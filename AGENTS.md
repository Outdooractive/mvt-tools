# AGENTS.md

# mvt-tools — MVT (Vector Tile) CLI & Library

A Swift package for reading, writing, converting, and inspecting
[Mapbox Vector Tiles (MVT)](https://github.com/mapbox/vector-tile-spec/tree/master/2.1),
[MapLibre Tiles (MLT)](https://github.com/maplibre/maplibre-tile-spec),
[GeoJSON](https://geojson.org/),
[GPX](https://www.topografix.com/gpx.asp),
[FIT](https://developer.garmin.com/fit/overview/),
[CSV](https://en.wikipedia.org/wiki/Comma-separated_values),
[Shapefile](https://www.esri.com/content/dam/esrisites/sitecore-archive/Files/Pdfs/library/whitepapers/pdfs/shapefile.pdf),
and [GeoPackage](https://www.geopackage.org/) files.

Two products:
- **`mvt`** — CLI executable (`MVTCLI` target): dump, info, query, merge, import, export
- **`MVTTools`** — library target: `VectorTile` model, MVT/MLT encode/decode, GeoJSON/GPX/FIT/CSV/Shapefile/GeoPackage I/O, spatial queries

Key source areas:
- **`VectorTile.swift`** — Central model: holds `[String: LayerContainer]` (layer name → features),
  tile coordinates (z/x/y), projection, bounding box. All operations extend this type.
- **`Coders/MVT/MVTDecoder.swift`** — MVT protobuf → `[Feature]` per layer (zigzag decoding, projection)
- **`Coders/MVT/MVTEncoder.swift`** — `[Feature]` per layer → MVT protobuf (zigzag encoding, clipping, simplification)
- **`Coders/MLT/MLTDecoder.swift`** — MLT decoder (C++ bridge, zigzag decoding, projection)
- **`Coders/MLT/MLTEncoder.swift`** — MLT encoder (C++ bridge, zigzag encoding, clipping, simplification)
- **`Coders/Projections.swift`** — Shared forward/inverse projection helpers (tile-extent ↔ geographic)
- **`Coders/ExportOptions.swift`** — Buffer, compression, simplification options
- **`Coders/GeoJSON/VectorTile+GeoJSON.swift`** — VectorTile GeoJSON import/export init, `toGeoJson()`, `writeGeoJson()`
- **`Coders/GPX/VectorTile+GPX.swift`** — VectorTile GPX import/export init, `toGpxData()`, `writeGPX()`
- **`Coders/CSV/VectorTile+CSV.swift`** — VectorTile CSV import/export init, `toCsvData()`, `writeCSV()`
- **`Coders/FIT/VectorTile+FIT.swift`** — VectorTile FIT import/export init, `toFitData()`, `writeFIT()`
- **`Coders/Shapefile/VectorTile+Shapefile.swift`** — VectorTile Shapefile import/export init, `writeShapefile()`, `writeShapefiles()`
- **`Coders/GeoPackage/VectorTile+GeoPackage.swift`** — VectorTile GeoPackage import/export init, `writeGeoPackage()`
- **`Coders/MVT/VectorTile+MVT.swift`** — VectorTile MVT import/export init, `mvtData()`, `writeMVT()`
- **`Coders/MLT/VectorTile+MLT.swift`** — VectorTile MLT import/export init, `mltData()`, `writeMLT()`
- **`GeoJson.swift`** — VectorTile extension: `addGeoJson()`, `setGeoJson()`
- **`Query.swift`** — Spatial queries (R-Tree indexed or linear scan), text search, `queryMany`
- **`QueryParser.swift`** — Reverse Polish Notation query DSL parser/evaluator
- **`Merge.swift`** — `VectorTile.merge(_:)` — combine features from multiple tiles
- **`Info.swift`** — `tileInfo()` — per-layer feature counts, property histograms
- **`Extensions/`** — Shared helpers on Array, Dictionary, String, Int, Double, Ring
- **`MVTCLI/`** — CLI subcommands: `Dump`, `Info`, `Query`, `Merge`, `Import`, `Export` using `swift-argument-parser`

Key model: `VectorTile` holds `layers: [String: LayerContainer]` where each `LayerContainer`
has `features: [Feature]` (from `GISTools`), a bounding box, and an optional `RTree<Feature>` index.
All coordinate handling uses `GISTools` (`Coordinate3D`, `Projection`, `BoundingBox`, `MapTile`).

Projections: EPSG:4326 (WGS84), EPSG:3857 (Web Mercator), EPSG:4978 (ECEF), noSRID.

Dependencies:
- **GISTools** — geometry types, projections, R-Tree
- **GISToolsCSV** — CSV import/export
- **GISToolsGPX** — GPX import/export
- **GISToolsFIT** — FIT import/export
- **GISToolsShapefile** — Shapefile import/export
- **GISToolsGeoPackage** — GeoPackage import/export
- **GzipSwift** — gzip compression/decompression for MVT and GeoJSON
- **SwiftProtobuf** — protobuf serialization of `VectorTile_Tile`
- **swift-argument-parser** — CLI command/option parsing
- **swift-log** — logging

## Build & test

```bash
swift build           # build library + CLI
swift test            # run all tests (Swift Testing)
```

## Swift instructions

- DO USE idiomatic Swift 6, at least version 6.1
- DO write tests for everything you do, use Swift Testing (`import Testing`), not XCTest
- DO ASK if anything is unclear, or you need a decision
- DO add proper Swift DocC code documentation to your code
- DO NOT introduce third-party frameworks without asking first
- AVOID force unwraps and force `try` unless it is unrecoverable
- Assume strict Swift concurrency rules are being applied
- Use `#require(...)` (not `try #require(...)`) for Optional-returning expressions in tests

## C/C++ instructions (CMLT bridge)

- All `if`, `else`, `for`, `while` blocks MUST use braces `{}`, even for single-statement bodies
  - Correct: `if (x) { return; }`
  - Wrong: `if (x) return;`
- Use 4-space indentation (same as Swift)
- Use `// MARK: -` comments to organize sections (same pattern as Swift)
- C++ exceptions must be caught at the C bridge boundary via `TRY_BRIDGE`/`CATCH_BRIDGE_RET`/`CATCH_BRIDGE_VOID` macros
- Prefer C-style `/* ... */` for multi-line comments, `//` for single-line
- Function names use `snake_case` (MLT C API convention)

## Code style conventions

### Spacing

- 4-space indentation, no tabs
- Semicolons: A line with a semicolon is probably a two-liner.
- Commas: Left-hugging, space follows. `x, y`
- Generic parameters: Add spacing after the comma. `Type<T, U>`
- Braces: Always with a space on the inside. `{ get set }`
- Binary operators: add single-space padding before and after for all binary operators. `a + (b * c), a + b * c, or a + b * c`
    - Extra note: Use parenthesis in mathematical expressions to ease understanding even if not necessary. `a + (b * c)`
- Return arrow tokens: Spaces on both sides. `f() -> T`
- Ranges: prefer spaces on both sides. `1 ... 3, 1 ..< 4`
- Unterminated Ranges: Omit spacing. `1...`
- Empty constructs: No internal spaces. `[], [:], {}, f()`
- Trailing closure: Add a space before the opening brace. `function() { ... }`
- Functional closure: Trim spaces before opening parenthesis. `compactMap({ $0 })`
- Comments: Add single-space padding between comment delimiters and text. `// comment`, `/* comment */`
- Trailing whitespace: Never. Ever.
- Last file line: End each file with a single new line.

### General

- Multiple `if` conditions should be separated by `,`, not `&&`. Example: `if a==1, b==2 {}`.
- Use `x.isNotEmpty` (defined in local extensions) instead of `!x.isEmpty`.

### Colon style

Use left-hugging colons, with a space after the colon:
- `let dict = ["a": 1, "b": 2]`
- `let x: [String: String] = ["key": "value"]`
- `let y = foo(param1: value1, param2: value2)`
- `func bar<T: Hashable>(a: T) -> Void {}`
- `case a, b:`
- `class DerivedClass: ParentClass ...`

Don't use left-hugging colons in ternary expressions or in other places where they confuse the compiler:
- `let result = booleanCondition ? value1 : value2`

Skip spaces for empty constructors (see above):
- `[]`, `[:]`

### Ternary expressions

- Keep where short ternary expressions on one line:
`let result = booleanCondition ? value1 : value2`

- Split longer ternary expressions into three lines:
```swift
let result = booleanCondition
    ? value1
    : value2
```

Note that `?` and `:` are aligned.

### Attributes

Always place attributes (like `@objc`, `@discardableResult`) on their own line before the function declaration:
```swift
@discardableResult
func insert(...)
```

### Number Literals

- Use three-place underscore chunking for decimal numbers. `1_000_000`
- Use two-place underscore chunking for hex numbers. `FF_AB_01`
- Always add the fraction for floating-point numbers. `1.0`, not `1`

### Brace style

Put `else` on an extra line.

```swift
if let value = key {
    // ...do something
}
else {
    // ...do something else
}
```

### Code organization

- `// MARK:` and `// MARK: -` to organize type extensions into logical groups
- `PascalCase` for types and type aliases, `camelCase` for everything else (properties, methods, enum cases, constants)
- `struct` by default, `class` only when needed (reference semantics)
- `Sendable` conformance on all model types
- `guard let` / `if let` with early returns for failable initializers and optional handling
- Extensions to group related functionality per type (one extension per concern)
- One test struct per algorithm/type (e.g., `struct MVTDecoderTests`)
- Key path expressions (`\.property`) over closures where possible

### Argument wrapping

If a method has ≤3 parameters and no return value, or ≤2 parameters and a return value, put the entire signature on one line (exception: line exceeds 80 characters). Otherwise, split parameters one per line and put the opening brace `{` on its own line.

  ```swift
  // One line (≤2 params + return, ≤80 chars)
  public func isEmpty -> Bool { layers.isEmpty }

  // Multi-line (>2 params + return → one per line, brace on own line)
  public func removeFeatures(
      fromLayer layerName: String,
      where shouldBeRemoved: (Feature) -> Bool
  ) -> Bool {
  ```

When a function **call** is split across multiple lines, place each argument on its own line:

  ```swift
  // One line (fits ≤80 chars)
  let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14)

  // Multi-line → one argument per line
  tile.query(
      at: Coordinate3D(latitude: 3.87, longitude: 11.52),
      tolerance: 100.0,
      layerName: "road")
  ```

## General instructions

- DO NOT take any shortcuts while implementing an algorithm. Correctness is the highest priority
- DO NOT commit changes unless the user tells you to do so, ALWAYS let the user review your changes
- DO NOT create free functions (un-namespaced top-level functions). Always use a `private enum` namespace or extensions on existing types.
- Code MUST compile cleanly, with no warnings
- New algorithms and bug fixes MUST include tests for all projections (EPSG:4326, EPSG:3857, EPSG:4978, noSRID)
- Use written-out decimal numbers (e.g., `0.0000000001`) instead of scientific notation (`1e-10`)
- Always test both MVT and GeoJSON code paths when adding/changing I/O logic
- CLI changes should be reflected in the `MVTCLI` target; library changes in `MVTTools`
- New formats should be added as `Coders/<Format>/VectorTile+<Format>.swift` extensions
