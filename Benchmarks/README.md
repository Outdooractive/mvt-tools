# Benchmarks

`mlt-benchmark` measures MLT decode/encode time and encoded size for a tile.

```bash
swift run --traits EnableMLT mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt \
    8716 8015 14 20
```

Arguments:

- path to an MVT (`mvt`/`pbf`) or MLT (`mlt`) tile
- tile x, y and z
- optional iteration count (default: 10)

The benchmark prints decode and encode time per iteration plus the resulting
MLT size. It uses the public `VectorTile` API and therefore exercises the same
path as library consumers.

Optional encoder switches can be passed after the iteration count:

```bash
swift run -c release --traits EnableMLT mlt-benchmark <tile> <x> <y> <z> 20 --no-fsst
```

Available flags: `--plain`, `--no-fsst`, `--fastpfor`, `--no-fastpfor`,
`--no-dictionaries`, `--no-shared-dictionaries`, `--vertex-dictionaries`,
`--no-vertex-dictionaries`, `--no-integer-delta-rle`. FastPFOR and vertex
dictionaries are opt-in features, so they are off unless their flags are
passed.

See [RESULTS.md](RESULTS.md) for a recent release-mode benchmark run.
