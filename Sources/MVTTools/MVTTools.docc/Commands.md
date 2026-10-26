# Command line tool

The `mvt` executable wraps the library for file inspection and conversion.

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

Tile coordinates are needed for MVT/MLT. They can be passed with `--x`,
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

## Output formats

The output format is inferred from `--output` (`.mvt`, `.pbf`, `.mlt`,
`.geojson`, `.json`, `.gpx`, `.fit`, `.csv`, `.shp`, `.gpkg`) or set with
`--output-format`. Without an output file the result is written as GeoJSON to
stdout.

## Exit behaviour

The CLI reports argument, format, and I/O errors with a non-zero exit code.
`mvt load` treats individual download failures as soft failures and reports
them in its summary; it does not abort the remaining downloads.
