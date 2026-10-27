# Concurrency

How to share and mutate ``VectorTile`` values safely across tasks.

## Value semantics

``VectorTile`` is a `Sendable` value type. It has no internal locks and no
shared mutable storage. Every tile value owns its own layers, features,
bounding boxes, and optional R-tree index.

Concurrent reads of separate tile values are safe. Copying a tile produces an
independent value, and mutating one copy does not modify another.

```swift
var first = try VectorTile(mvtData: data, x: 8716, y: 8015, z: 14)
let second = first

first.removeLayer("road")

// `second` still contains the road layer.
print(second.hasLayer("road"))  // true
```

## Mutating operations

The following APIs mutate the tile value they are called on:

- `clear()`
- `setFeatures(_:for:)`
- `appendFeatures(_:to:)`
- `removeFeatures(fromLayer:where:)`
- `removeLayer(_:)`
- `createIndex(sortOption:)`
- `merge(_:ignoreTileCoordinateMismatch:)`
- `addGeoJson(geoJson:layerName:layerProperty:layerAllowlist:)`
- `setGeoJson(geoJson:layerName:layerProperty:layerAllowlist:)`

These methods are not internally synchronized. The Swift compiler can prevent
many accidental sharing mistakes because ``VectorTile`` is `Sendable`, but it
cannot make a shared mutable variable safe. If more than one task can access
the same tile instance while any task mutates it, the caller must provide
synchronization.

## Actor ownership

An actor is the preferred solution when callers can use async APIs. The actor
owns the tile and serializes every read and mutation.

```swift
actor TileStore {

    private var tile: VectorTile

    init(_ tile: VectorTile) {
        self.tile = tile
    }

    func snapshot() -> VectorTile {
        tile
    }

    func setFeatures(_ features: [Feature], for layerName: String) {
        tile.setFeatures(features, for: layerName)
    }

    func removeLayer(_ layerName: String) -> [Feature]? {
        tile.removeLayer(layerName)
    }

    func createIndex() {
        tile.createIndex()
    }

}
```

Callers can read a consistent copy with `await store.snapshot()` or perform a
mutation without exposing the underlying value.

## Lock-backed wrapper

Use a lock when callers need synchronous access. `NSLock` is available on every
supported platform and is the same primitive used internally by the GISTools
projection registry.

```swift
import Foundation

final class LockedTile: @unchecked Sendable {

    private let lock = NSLock()
    private var tile: VectorTile

    init(_ tile: VectorTile) {
        self.tile = tile
    }

    func snapshot() -> VectorTile {
        lock.lock()
        defer { lock.unlock() }
        return tile
    }

    func withTile<T>(_ body: (inout VectorTile) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&tile)
    }

}
```

`LockedTile` is `@unchecked Sendable` because every access to `tile` is
protected by `lock`. Keep critical sections short. Do not call `withTile`
recursively, because `NSLock` is not recursive, and do not hold the lock while
awaiting another task or running a long user callback.

## Process-wide state

The only mutable process-wide state in MVTTools is the optional global logger
(``VectorTile/logger``). Configure it once during application startup and do
not change it while other tasks are using MVTTools.

Projection registration is handled by the GISTools projection registry, which
is internally synchronized.
