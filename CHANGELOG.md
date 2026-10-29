# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning.

## Unreleased

### Added

- Pure Swift MLT decoder and encoder behind `EnableMLT`. The trait no longer
  requires Swift/C++ interoperability, a C++20 toolchain, or the
  `maplibre-tile-spec` submodule. The decoder supports plain, delta,
  componentwise-delta, RLE, Morton, Hilbert dictionary, FastPFOR, FSST and
  shared-dictionary streams for the tag `0x01` format.
- `EnableMLTCXX` keeps the existing C++ MLT bridge available as an optional
  backend. It implies `EnableMLT`; when both traits are enabled the public API
  uses C++, while tests can compare both implementations.
- Cross-backend MLT tests, upstream `0x01` corpus conformance tests, binary/RLE/
  metadata unit tests, and truncated/mutated-input robustness tests.
- Updated the `maplibre-tile-spec` submodule to the current `main` revision
  (`71f20ee8`) for the optional C++ backend and conformance fixtures.
- Added an `mlt-benchmark` executable for MLT decode/encode timing and size
  measurements, plus an AddressSanitizer CI job for the pure Swift codec.
- Recorded release-mode benchmark results and added a manifest with checksums
  and expected layer/feature counts for the curated MLT fixtures. The full
  upstream corpus is opt-in via `MLT_FULL_CORPUS=1`.
- Documented the supported/rejected experimental MLT v1 feature matrix.
- The pure Swift MLT encoder now uses a Hilbert-sorted or Morton vertex
  dictionary when repeated vertices make it smaller than the plain
  componentwise-delta buffer.
- Large 32-bit integer streams can use a bit-packed FastPFOR encoding when it
  is smaller than the plain, delta, RLE or delta-RLE layouts. FastPFOR blocks
  can use one-bit exception streams for outliers.
- String dictionaries can use FSST compression when it reduces the encoded
  size, including shared dictionaries across related string columns.
- Added `ExportOptions.mlt` feature switches for string dictionaries, shared
  dictionaries, FSST, FastPFOR, vertex dictionaries and delta/RLE integer
  streams, plus a conservative `.plain` preset. FastPFOR and vertex
  dictionaries are disabled by default: on 118 real-world OMT tiles the vertex
  dictionaries save 0.19% raw size in total (median 0.12% where they win, no
  reliable gzip benefit) while costing a noticeable share of encode time.
- Added `--mlt-plain`, `--mlt-no-dictionaries`, `--mlt-no-shared-dictionaries`,
  `--mlt-no-fsst`, `--mlt-fastpfor`, `--mlt-vertex-dictionaries`,
  `--mlt-no-vertex-dictionaries` and `--mlt-no-integer-delta-rle` to `merge`,
  `export`, `import`, `rezoom` and `reproject`. `--verbose` prints the effective
  MLT encoder features.

### Changed

- The pure Swift MLT encoder builds the vertex index map once per geometry
  column and precomputes Hilbert codes for sorting, instead of hashing the
  vertices for each dictionary candidate and recomputing codes in the
  comparator. Default-mode encoding of the benchmark MVT tile is roughly 30%
  faster with unchanged output.
- FSST symbol training now uses allocation-free fixed-size substring keys
  instead of one byte array per candidate. Encoding the benchmark MLT fixture
  is about 35% faster with byte-identical output; FSST training remains the
  dominant encoder cost on small tiles, which is why `useFSST` can be disabled.
- MLT v2 (`0x02`) tiles are explicitly rejected with an unsupported-feature
  error instead of being silently treated as empty tiles.
- `EnableMLTCXX` is deprecated in favour of the pure Swift backend and will be
  removed in the next major release.
- The pure Swift MLT encoder now chooses single dictionary encoding for string
  columns when it reduces the encoded size. Related string columns such as
  `name`, `name_de` and `name_en` are grouped into shared dictionaries. Plain
  strings remain the fallback for unique values.
- Geometry topology, string length/offset, feature ID and numeric property
  streams now choose between plain, delta, RLE and delta-RLE encodings based on
  the smallest encoded size. This includes `INT_32`, `INT_64`, `UINT_32` and
  `UINT_64` property columns.
- Moved development setup, build, test, coverage and DocC instructions from
  `README.md` to `DEVELOPMENT.md`.
- Documented that `VectorTile` is a value type without internal locking, with
  guidance for actor- and lock-based synchronization of shared mutable tiles
  (#5).
- Updated `gis-tools`, `gis-tools-fit`, `gis-tools-geopackage`,
  `gis-tools-gpx`, and `gis-tools-shapefile` to `3.0.0-beta.5`, and
  `gis-tools-csv` to `3.0.0-beta.6`. `GzipSwift`, `swift-argument-parser`,
  `swift-log`, and `swift-protobuf` remain at their latest compatible releases.
- `VectorTile.layerNames` is now sorted, and MVT/MLT/GeoJSON encoding uses
  sorted layer order so repeated runs produce deterministic output.
- MLT encoding now defaults to the pure Swift implementation. Its first
  release uses conservative deterministic encodings (plain varints, plain
  strings, componentwise-delta vertices and gzip) and normalizes polygon
  winding in tile space.
- MVT geometry command encoding uses a correct signed 32-bit zigzag encoder.
  Coordinates or deltas outside the signed 32-bit range are rejected instead
  of trapping in `UInt32` conversion.
- MVT polygon and multi-polygon winding is normalized to the orientation
  required by MVT decoders before encoding.
- Export clipping passes through features that are fully inside the clip
  bounding box, preserving `LineString`/`Polygon` instead of promoting them
  to multi-geometries.
- Buffer sizes are now measured correctly in tile-extent units. The previous
  diagonal-based calculation made buffers about 41% larger than requested.
- Coordinate quantization rounds to the nearest extent cell instead of
  truncating towards the tile origin.
- MVT decoding treats layer extent `0` as the default extent, decodes version
  1 layers, and merges duplicate layer names instead of dropping data.
- A single polygon with holes now decodes back to `Polygon` rather than a
  one-element `MultiPolygon`.
- MLT property encoding now handles `Int8`/`Int16`/`Int32`, `UInt8`/`UInt16`/`UInt32`,
  and `UInt64` values instead of falling back to strings.
- MVT property value tables are deduplicated with type-tagged keys, so `Int`,
  `Int64`, `UInt64`, `Float`, and `Double` values no longer collapse into one
  another.
- Indexed queries apply a precise geometry intersection check after the R-Tree
  candidate search and return the same results as non-indexed queries.
- `queryMany` applies `featureFilter` before collecting feature IDs.
- Gzipped GeoJSON produced by `toGeoJson(options:)` can be read back by the
  GeoJSON importer and the CLI.
- `mvt load` now returns a non-zero exit status when any tile download fails,
  after printing its summary and completing the remaining downloads (#60).
- `mvt load` honours `--zoom` over URL-inferred zooms, prioritizes the tile
  template over unrelated numeric path segments, and accepts antimeridian
  crossing bounding boxes.
- `mvt query` accepts negative latitude/longitude coordinates (use `--` before
  a leading negative positional argument).
- `mvt merge` resolves the output format from `--output` even when there are no
  input files, and reports MVT write failures.
- `mvt info` accepts whitespace in `--info-tables` and labels the property-value
  table column `Property`.

### Added

- Published releases now build and upload the `mvt` archive automatically and
  open a validated Homebrew formula pull request. Manual dispatch remains
  available for backfills (#4).
- Separate `--input-projection` (`-ip`) and `--output-projection` (`-op`)
  CLI options, plus a new `mvt reproject` command.
- `VectorTile.projected(to:)` for real CRS transformations and
  `VectorTile.retagged(to:)` for intentionally reinterpreting coordinates.
- `--input-projection` support for GeoJSON, CSV, MVT, MLT, Shapefile and
  GeoPackage. GeoJSON and CSV input projection reinterprets raw coordinates.
- Projection options are threaded through `dump`, `merge`, `import`,
  `export`, `query`, `rezoom` and `reproject`.
- CSV `projection`/`crs`/`srid` columns and the gis-tools-csv 3.0.0-beta.6
  dependency.
- DocC catalog (`Sources/MVTTools/MVTTools.docc`) with getting-started, tile
  model, command line, querying, import/export, MLT, and limitations articles.
- `contentsOfGeoPackage` and `contentsOfShapefile` initializer aliases to match
  the `contentsOf…` naming used by the other format coders.
- Regression tests for malformed/truncated geometry, zigzag boundaries,
  integer overflow, extent fallback, version-1 layers, duplicate layers,
  gzipped input, property type fidelity, polygon winding, clipping, buffer
  sizes, indexed queries, `queryMany` filtering, and convenience initializer
  error paths.
- Coverage reporting and a 90% line-coverage gate, plus a DocC validation job
  in CI.

### Fixed

- GeoPackage import/export now close the `GeoPackageConnection` on every error
  path, preventing leaked SQLite handles and file locks (#61).
- `MVTEncoder` no longer traps when encoding coordinates that do not fit into
  the MVT 32-bit command parameter range.
- `MVTDecoder` no longer duplicates an explicitly closed ring when a
  `ClosePath` command follows the repeated first vertex.
- `MVTDecoder` rejects malformed `ClosePath` commands and unknown geometry
  commands instead of emitting partial or invalid geometry.
- Empty layers caused by features without geometry are no longer emitted by
  the MVT and MLT encoders.
- MLT features without a numeric ID no longer decode with the synthetic ID
  `0`; the C++ bridge now clears the encoder's default ID.
- MLT unsigned integer properties keep their `UInt32`/`UInt64` type instead of
  being returned as signed integers by the bridge.

### Documentation

- Updated README examples to the current API (`mvtData`, `writeMVT`,
  `tileInfo()` return type, CSV read options), documented package traits,
  gzip behaviour, antimeridian loading, development commands, coverage, and
  DocC validation.
