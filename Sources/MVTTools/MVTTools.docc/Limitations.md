# Limitations

Intentional trade-offs and format restrictions.

## Vector tile formats are lossy

MVT and MLT store geometry on a 4096 × 4096 grid per tile. Coordinates are
quantized to that grid, so a decode/encode round trip is accurate to about
one extent cell (tile width / 4096).

Neither format preserves:

- altitude (`Coordinate3D/altitude`)
- the GeoJSON `m` value
- string feature IDs (MVT and MLT IDs are numeric)
- foreign members on geometries and features

## Property encoding in MVT

MVT property values are typed (string, float, double, int, uint, sint, bool).
`MVTTools` adds two conventions on top:

- Arrays and dictionaries are encoded as JSON strings.
- On decode, any string that starts with `[` or `{` and parses as JSON is
  converted back to an array or dictionary.

This makes array/dictionary round trips work, but a plain string that happens
to look like JSON (for example `"[1,2]"`) cannot be distinguished from a real
array. Use a different representation when the distinction matters.

Feature IDs without a numeric `id` are represented as random UUID strings.
They are not written to MVT/MLT and do not survive a round trip.

## Polygon winding

GeoJSON allows either winding order, while MVT interpreters rely on ring
orientation. `MVTTools` normalizes polygon winding for MVT and MLT exports so
that exterior rings and holes are classified correctly. The decoded polygon
may be a `Polygon` instead of a `MultiPolygon` (or vice versa) when a
single-part multi-geometry was encoded.

## Clipping and buffers

Features are clipped to the tile bounding box at export time for projections
with an SRID. Buffers are measured in tile-extent units (1/4096 of the tile
width) or pixels (1/512 of the tile). Features fully inside the clip box are
passed through unchanged to preserve their geometry type.

`noSRID` tiles skip clipping because there is no geographic tile bound.

## Empty and malformed input

- Empty protobuf data is a valid empty MVT tile.
- Invalid or truncated protobuf payloads throw
  VectorTileError.
- Unknown MVT layer versions are ignored; duplicate layer names are merged.
- A layer extent of zero is treated as the default extent (4096).
- Degenerate polygon rings and malformed geometry commands are dropped rather
  than decoded into invalid geometry.
- Empty GeoJSON/CSV/Shapefile collections cannot derive a tile coordinate and
  throw VectorTileError.

## Concurrency

``VectorTile`` is a `Sendable` value type and does not contain internal locks.
Concurrent reads of separate tile values are safe. Sharing and mutating a single
tile instance from multiple tasks requires external synchronization, for
example with an actor or a lock-backed wrapper. See <doc:Concurrency> for
examples and the full list of mutating APIs.

Shared mutable state is otherwise limited to the optional global logger
(``VectorTile/logger``) and the process-wide projection registry in `GISTools`.
