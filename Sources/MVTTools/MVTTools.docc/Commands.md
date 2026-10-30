# Command line tool

The `mvt` executable wraps the library for file inspection and conversion.
Despite its name, it is not limited to vector tiles: every command accepts any
supported format, and `merge`, `import` and `export` convert between MVT, MLT,
GeoJSON, GPX, FIT, CSV, Shapefile and GeoPackage.

## Installation

```bash
brew install Outdooractive/homebrew-tap/mvt-tools
# or
./install_mvt.sh
```

## Subcommands

| Command | Purpose |
| --- | --- |
| `mvt dump` | Print any supported input as pretty GeoJSON (default subcommand) |
| `mvt info` | Print per-layer feature/property tables |
| `mvt query` | Filter features by text, query DSL, or coordinate |
| `mvt merge` | Merge any number of inputs into any supported output |
| `mvt import` | Alias for `merge` |
| `mvt export` | Alias for `merge` |
| `mvt load` | Download a bounding-box tile cover from a URL template |
| `mvt rezoom` | Overzoom/underzoom source tiles into one target tile |
| `mvt reproject` | Reproject any supported input to a target CRS |

MVT and MLT require their package traits at build time. Tile coordinates are
needed for MVT/MLT. They can be passed with `--x`,
`--y`, `--z`, or parsed from a path such as `14/8716/8015.pbf` or
`14_8716_8015.mvt`. Other formats derive a tile coordinate from their bounding
box.

## Examples

```bash
mvt info Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
mvt query -p input.pbf ".class == 'motorway'"
mvt export input.pbf --output output.geojson
mvt merge --output out.mvt --force-overwrite input.geojson input.gpx
mvt rezoom --output 15_17432_16030.mvt 14_8716_8015.mvt
```

## Loading remote tiles

```bash
mvt load --bbox "11.0,3.0,12.0,4.0" --output-dir ./tiles \
    https://example.com/tiles/14/{x}/{y}.pbf
```

`--zoom` overrides a literal zoom in the template. A bounding box whose
minimum longitude is greater than its maximum crosses the antimeridian, for
example `170,-10,-170,10`. Use `--layout tree` for `z/x/y.ext` output and
`--overwrite-existing` to replace existing files.

## Projections

All file-conversion commands accept separate input and output CRS options:

| Option | Short | Description |
|---|---|---|
| `--input-projection` | `-ip` | Input CRS: `auto`, SRID, `EPSG:n`, `noSRID`, or registered WKT. |
| `--output-projection` | `-op` | Output CRS: `auto`, SRID, `EPSG:n`, `noSRID`, or registered WKT. |

MVT/MLT, CSV, GeoJSON, GPX and FIT default to EPSG:4326. Shapefile and GeoPackage use their embedded CRS. An explicit input projection overrides the format default; for Shapefile/GeoPackage this reinterprets the raw coordinates, which is useful when file metadata is wrong. Use `--output-projection` or `mvt reproject` for an actual coordinate transformation.

GeoJSON input projection reinterprets raw coordinates in the selected CRS, not from 4326. CSV also accepts `projection`/`crs`/`srid` columns.

```bash
mvt reproject -ip 3857 -op 4326 --output out.geojson 14/8716/8015.mvt
mvt reproject -op 3857 --output out.mvt input.geojson
```

`reproject` accepts the same layer filters (`--layer`, `--drop-layer`), simplification, buffering, compression and CSV options as `merge`.

## Output formats

The output format is inferred from `--output` (`.mvt`, `.pbf`, `.mlt`,
`.geojson`, `.json`, `.gpx`, `.fit`, `.csv`, `.shp`, `.gpkg`) or set with
`--output-format`. Without an output file the result is written as GeoJSON to
stdout.

## Exit behaviour

The CLI reports argument, format, and I/O errors with a non-zero exit code.
`mvt load` reports individual tile download failures in its summary and exits
non-zero if any download failed; the remaining downloads still complete.
