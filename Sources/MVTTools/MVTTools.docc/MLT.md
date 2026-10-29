# MapLibre Tiles (MLT)

Reading and writing [MapLibre Tiles](https://maplibre.org/maplibre-tile-spec/).

## Availability

MLT support is gated behind the `EnableMLT` package trait. The default
implementation is pure Swift and does not require Swift/C++ interoperability,
a C++ toolchain, or the `maplibre-tile-spec` submodule. The format codec lives
in the Foundation-only `MLTCore` target; `MVTTools` contains the `VectorTile`
adapters.

```bash
swift build --traits EnableMLT
swift test --traits EnableMLT
```

Building the `mvt` executable or the `MVTTools` product does not build the
optional CMLT target even when the `maplibre-tile-spec` submodule is checked
out. Running a package-wide `swift build` also compiles unused root targets, so
use `swift build --product mvt` (or omit the submodule) for a strict pure
Swift build.

An optional C++ backend is available behind the `EnableMLTCXX` trait. It
implies `EnableMLT` and links the upstream `maplibre-tile-spec` C++
implementation (including FastPFOR and FSST). Enable it only when you want to
compare implementations or need the C++ encoder:

```bash
swift build --traits EnableMLTCXX
```

When both traits are enabled, the public API uses the C++ backend. Both
implementations remain compiled, so tests can compare them. The C++ backend is
deprecated and will be removed in the next major release; `EnableMLT` is the
supported path.

Reading or writing an MLT file without the `EnableMLT` trait is unavailable at
compile time (library) or throws a CLI error.

## Reading

```swift
let tile = try VectorTile(
    mltData: data,
    x: 8657,
    y: 5725,
    z: 14,
    indexed: .hilbert)
```

The pure Swift decoder supports the tag `0x01` tile format, including:

- gzipped and uncompressed input,
- multiple layers and mixed geometry types,
- point, multi-point, line string, multi-line string, polygon and
  multi-polygon geometries,
- plain, delta, componentwise-delta, RLE and Morton topology/vertex streams,
- Hilbert vertex dictionaries,
- integer streams encoded as plain varints, fixed-width values or FastPFOR,
- scalar properties: boolean, 8/32/64-bit signed and unsigned integers, float,
  double and string,
- plain, single-dictionary, shared-dictionary and FSST string columns,
- nullable columns and numeric feature IDs,
- UTF-8 BOM removal and gzip auto-detection.

It follows the C++ implementation for property value types: 8/32-bit integers
are exposed as `Int64`, unsigned 8/32-bit integers as `UInt64`, and `Float` as
`Double`.

Experimental columns that `VectorTile` cannot represent (for example RangeMap,
binary or deeply nested structs) are rejected with an error rather than
silently corrupted.

## Writing

```swift
let options = VectorTile.ExportOptions(
    bufferSize: .extent(512),
    simplifyFeatures: .meters(1.0))

try tile.writeMLT(to: outputURL, options: options)
```

The pure Swift encoder writes a conservative, deterministic subset:

- plain, delta, RLE, delta-RLE or bit-packed FastPFOR for integer and length streams, choosing the smallest,
- componentwise-delta varints for vertices, with an optional Hilbert-sorted or Morton vertex dictionary when smaller,
- plain, single-dictionary, shared-dictionary or FSST strings, including FSST-compressed shared dictionaries, choosing the smallest layout,
- boolean RLE for nullable/present streams,
- gzip compression through `ExportOptions.compression`,
- numeric feature IDs only.

It normalizes polygon winding in tile space so MapLibre's `classifyRings`
sees exterior rings and holes correctly, and stores rings without the
redundant closing vertex. Its output is validated against both the pure Swift
and C++ decoders.

Hilbert and Morton vertex dictionaries, and FSST string dictionaries, are used
when they reduce the encoded size. They can be added as encoder optimizations later without
changing the public API.

## Backend differences

The two backends are semantically compatible but not byte-identical. The C++
encoder enables its own topology heuristics and may sort points/line strings by
Hilbert order. The pure Swift encoder preserves feature order and emits plain
encodings, trading size for predictability and interoperability.

## Known limitations

- Only the tag `0x01` tile format is decoded; tag `0x02` and external tileset
  metadata are not supported yet.
- String feature IDs and altitude are not preserved.
- Experimental MLT types (nested structs beyond shared string dictionaries,
  vertex-scoped properties, RangeMap, tessellation, `GEOMETRY_Z`, 128-bit
  integers) are not fully supported.
- The first pure Swift encoder release does not implement compression
  optimizations beyond gzip.
