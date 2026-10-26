# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning.

## Unreleased

### Changed

- Updated `gis-tools`, `gis-tools-csv`, `gis-tools-fit`,
  `gis-tools-geopackage`, `gis-tools-gpx`, and `gis-tools-shapefile` to
  `3.0.0-beta.5`. `GzipSwift`, `swift-argument-parser`, `swift-log`, and
  `swift-protobuf` remain at their latest compatible releases.
- `VectorTile.layerNames` is now sorted, and MVT/MLT/GeoJSON encoding uses
  sorted layer order so repeated runs produce deterministic output.
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
