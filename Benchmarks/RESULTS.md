# MLT benchmark results

Local run on Linux aarch64, Swift 6.4.1, release configuration, 30 iterations.
These numbers are indicative; rerun on your target hardware before making
capacity decisions.

## MVT input

Input: `Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt`
(412,300 bytes, 23 layers, 11,238 features).

```bash
swift run -c release --traits EnableMLT mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt 8716 8015 14 30
swift run -c release --traits EnableMLTCXX mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt 8716 8015 14 30
```

| Backend | Decode | Encode | MLT output |
| --- | ---: | ---: | ---: |
| Pure Swift, default options | 15.85 ms/iteration | 80.63 ms/iteration | 230,637 bytes |
| Pure Swift, `--fastpfor` | 14.38 ms/iteration | 77.42 ms/iteration | 230,637 bytes |
| Pure Swift, `--no-fsst` | 14.81 ms/iteration | 68.54 ms/iteration | 230,637 bytes |
| Pure Swift, `--no-vertex-dictionaries` | 14.84 ms/iteration | 56.57 ms/iteration | 230,637 bytes |
| Pure Swift, `--plain` | 15.69 ms/iteration | 48.31 ms/iteration | 311,446 bytes |
| C++ | 14.34 ms/iteration | 54.12 ms/iteration | 244,263 bytes |

The pure Swift default uses the same feature set as the C++ `EncoderConfig`
(dictionaries, shared dictionaries, FSST and vertex dictionaries on, FastPFOR
off). It is roughly 1.5x slower and produces a 5.6% smaller tile; disabling
vertex dictionaries brings encode time to parity with C++ on this input.
The optional features can be disabled individually:

```bash
swift run -c release --traits EnableMLT mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt 8716 8015 14 30 --plain
```

`--no-fsst` saves about 12 ms on this input but does not change the tile size,
because FSST training does not find a profitable symbol table here.
`--no-vertex-dictionaries` saves about 24 ms without a size change on this
input as well; the vertex dictionaries only pay off on layers with many
repeated vertices. `--fastpfor` does not change the tile size on this input.
`--plain` is roughly 2× faster than the default but produces a tile that is
about 35% larger. The remaining default-mode cost is dominated by building
string dictionaries (including FSST training) and by constructing and
serializing several candidate encodings per stream before choosing the
smallest one.

## MLT input

Input: `Tests/MLTCoreTests/Fixtures/0_0_0.mlt`
(66,727 bytes, 5 layers, 532 features).

| Backend | Decode | Encode | MLT output |
| --- | ---: | ---: | ---: |
| Pure Swift | 1.53 ms/iteration | 33.72 ms/iteration | 68,042 bytes |
| C++ | 2.63 ms/iteration | 5.43 ms/iteration | 68,262 bytes |

On this small tile the pure Swift default spends about 26 ms of the 34 ms in
FSST training. With `--no-fsst` it encodes in roughly 7 ms and produces the same
68,042-byte tile, because no profitable symbol table exists for these small
string dictionaries. That makes `--no-fsst` (or
`VectorTile.ExportOptions.MLTEncodingOptions(useFSST: false)`) the first knob
when encode speed matters more than size on small tiles.

## Notes

- Decode timings include reading the MVT input where applicable.
- Encode timings include the full MLT encode path, including gzip settings
  used by the benchmark (none by default).
- Encode timings are dominated by dictionary construction, FSST training and
  candidate generation for every stream; the `.plain` preset shows the cost of
  the feature set on its own. FSST training is the largest single cost on small
  tiles where it does not pay off, so `--no-fsst` is the first flag to try.
