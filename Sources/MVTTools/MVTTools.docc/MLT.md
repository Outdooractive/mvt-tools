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

- plain, delta, RLE, delta-RLE or bit-packed FastPFOR with optional one-bit exceptions for integer and length streams, choosing the smallest,
- componentwise-delta varints for vertices, with an optional Hilbert-sorted or Morton vertex dictionary when smaller,
- plain, single-dictionary, shared-dictionary or FSST strings, including FSST-compressed shared dictionaries, choosing the smallest layout,
- boolean RLE for nullable/present streams,
- gzip compression through `ExportOptions.compression`,
- numeric feature IDs only.

It normalizes polygon winding in tile space so MapLibre's `classifyRings`
sees exterior rings and holes correctly, and stores rings without the
redundant closing vertex. Its output is validated against both the pure Swift
and C++ decoders.

Hilbert and Morton vertex dictionaries, and FSST string dictionaries, are only
used when they reduce the encoded size. They cost encode time but never change
the decoded content, so they can be disabled individually when that trade-off is
not wanted.

### Encoder feature switches

`VectorTile.ExportOptions.mlt` controls optional encoder features:

```swift
var options = VectorTile.ExportOptions()
options.mlt.useVertexDictionaries = true
options.mlt.useFastPFOR = true

let data = tile.mltData(options: options)
```

The defaults are conservative: string and shared dictionaries plus FSST are
enabled, FastPFOR and vertex dictionaries are disabled. Vertex dictionaries
rarely reduce the gzip-compressed size of real-world tiles, while building and
testing both candidates costs a noticeable share of encode time; enable them
for layers with many repeated vertices. Enable FastPFOR when a tile has large
32-bit integer streams.

The available switches are:

| Option | Default | Effect |
| --- | --- | --- |
| `useStringDictionaries` | `true` | Single and shared string dictionaries. |
| `useSharedStringDictionaries` | `true` | Group related string columns into a shared dictionary. |
| `useFSST` | `true` | FSST compression of string dictionaries. |
| `useFastPFOR` | `false` | FastPFOR for large 32-bit integer streams. |
| `useVertexDictionaries` | `false` | Hilbert/Morton vertex dictionaries for repeated vertices. |
| `useIntegerDeltaRLE` | `true` | Delta, RLE and delta-RLE integer streams. |

`VectorTile.ExportOptions.MLTEncodingOptions.plain` disables all optional
encodings for the most conservative, deterministic output. `useFSST` requires
`useStringDictionaries`, and `useSharedStringDictionaries` requires
`useStringDictionaries` as well.

Disabling a switch only trades encoded size for encode time or compatibility; it
never changes the decoded content. For example, `useFSST = false` skips FSST
training, which costs time even when no profitable symbol table exists, and
`useVertexDictionaries = false` (the default) skips the Hilbert/Morton candidate
construction unless a layer has enough repeated vertices to benefit.

The switches apply to the pure Swift encoder. The optional C++ backend uses its
own configuration.

The CLI exposes the same controls on `merge`, `export`, `import`, `rezoom` and
`reproject`:

```bash
# Skip FSST training on a small tile
mvt export input.mvt -O mlt -o out.mlt --mlt-disable fsst

# Opt in to the expensive encodings, or start from the plain preset
mvt export input.mvt -O mlt -o out.mlt --mlt-enable fastpfor,vertex-dictionaries
mvt export input.mvt -O mlt -o out.mlt --mlt-plain --mlt-enable fsst
```

The feature lists are comma-separated and repeatable. `--verbose` prints the
effective set.

## Backend differences

The two backends are semantically compatible but not byte-identical. The C++
encoder enables its own topology heuristics and may sort points/line strings by
Hilbert order. The pure Swift encoder preserves feature order and emits plain
encodings, trading size for predictability and interoperability.

## Experimental feature policy

Experimental MLT v1 features are intentionally not implemented yet. The
current behavior is conservative and explicit:

| Feature | Behavior |
| --- | --- |
| Nested/struct properties | Shared string dictionaries are supported. Other struct shapes are rejected with an unsupported-feature error. |
| Vertex-scoped properties / M-values | Not supported. The tag `0x01` decoder has no vertex-scope path; do not use vertex-scoped columns with this codec. |
| RangeMap and binary columns | Rejected by the metadata decoder. |
| Tessellation streams | Triangle and index streams are parsed but ignored. Geometry must still be decodable from the normal topology streams. |
| `GEOMETRY_Z` | Rejected as an unsupported geometry type. |
| 128-bit integers | Rejected as unsupported scalar types. |
| Logical date/timestamp/JSON types | Rejected as unsupported logical scalar types. |
| External tileset metadata | Not supported. Only embedded tag `0x01` metadata is read. |
| MLT v2 (`0x02`) | Rejected with an unsupported-feature error until the upstream format stabilizes. |

## Known limitations

- Only the tag `0x01` tile format is decoded.
- String feature IDs and altitude are not preserved.
- The encoder uses gzip plus the implemented adaptive encodings; it does not
  implement MLT v2 encodings.
