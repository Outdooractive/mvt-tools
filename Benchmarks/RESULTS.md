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
| Pure Swift, default options | 15.18 ms/iteration | 50.2 ms/iteration | 230,637 bytes |
| Pure Swift, `--vertex-dictionaries` | 15.03 ms/iteration | 79.7 ms/iteration | 230,637 bytes |
| Pure Swift, `--fastpfor` | 14.58 ms/iteration | 49.1 ms/iteration | 230,637 bytes |
| Pure Swift, `--no-fsst` | 15.78 ms/iteration | 48.3 ms/iteration | 230,637 bytes |
| Pure Swift, `--plain` | 15.70 ms/iteration | 48.2 ms/iteration | 311,446 bytes |
| C++ | 14.34 ms/iteration | 54.1 ms/iteration | 244,263 bytes |

The pure Swift default enables dictionaries, shared dictionaries, FSST and
delta/RLE, and leaves FastPFOR and vertex dictionaries opt-in. It is now about
8% faster than C++ on this input and produces a 5.6% smaller tile. The optional
features can be enabled or disabled individually:

```bash
swift run -c release --traits EnableMLT mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt 8716 8015 14 30 --plain
```

`--no-fsst` saves about 2 ms on this input and does not change the tile size,
because FSST training does not find a profitable symbol table here.
`--vertex-dictionaries` costs about 30 ms and does not change the tile size on
this input; across 118 real-world OMT tiles they save 0.19% raw size in total
(median 0.12% on the 40% of tiles where they win) and do not reliably help after
gzip. `--fastpfor` does not change the tile size on this input either.
`--plain` produces a tile that is about 35% larger. With FSST training now
cheap, the remaining default-mode cost is mostly geometry and property
serialization plus the candidate construction per stream.

## MLT input

Input: `Tests/MLTCoreTests/Fixtures/0_0_0.mlt`
(66,727 bytes, 5 layers, 532 features).

| Backend | Decode | Encode | MLT output |
| --- | ---: | ---: | ---: |
| Pure Swift | 1.7 ms/iteration | 15.8 ms/iteration | 68,154 bytes |
| C++ | 2.63 ms/iteration | 5.43 ms/iteration | 68,262 bytes |

On this small tile the pure Swift default still spends about 9 ms of the 16 ms
in FSST training. With `--no-fsst` it encodes in roughly 6 ms and produces the
same tile, because no profitable symbol table exists for these small string
dictionaries. That makes `--no-fsst` (or
`VectorTile.ExportOptions.MLTEncodingOptions(useFSST: false)`) the first knob
when encode speed matters more than size on small tiles. Enabling
`--vertex-dictionaries` costs another 6 ms here and saves 112 bytes.

## Notes

- Decode timings include reading the MVT input where applicable.
- Encode timings include the full MLT encode path, including gzip settings
  used by the benchmark (none by default).
- Encode timings are dominated by dictionary construction, FSST training and
  candidate generation for every stream; the `.plain` preset shows the cost of
  the feature set on its own. FSST training is the largest single cost on small
  tiles where it does not pay off, so `--no-fsst` is the first flag to try.
