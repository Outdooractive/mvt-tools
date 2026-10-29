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

See [RESULTS.md](RESULTS.md) for a recent release-mode benchmark run.
