# MLT benchmark results

Local run on Linux aarch64, Swift 6.4.1, release configuration, 20 iterations.
These numbers are indicative; rerun on your target hardware before making
capacity decisions.

## MVT input

Input: `Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt`
(412,300 bytes, 23 layers, 11,238 features).

```bash
swift run -c release --traits EnableMLT mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt 8716 8015 14 20
swift run -c release --traits EnableMLTCXX mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt 8716 8015 14 20
```

| Backend | Decode | Encode | MLT output |
| --- | ---: | ---: | ---: |
| Pure Swift | 15.91 ms/iteration | 131.74 ms/iteration | 230,637 bytes |
| C++ | 15.42 ms/iteration | 65.39 ms/iteration | 244,263 bytes |

The pure Swift encoder is slower, mainly because it trains string dictionaries
and FSST symbols per layer. It produces a smaller tile on this input.

## MLT input

Input: `Tests/MLTCoreTests/Fixtures/0_0_0.mlt`
(66,727 bytes, 5 layers, 532 features).

| Backend | Decode | Encode | MLT output |
| --- | ---: | ---: | ---: |
| Pure Swift | 1.81 ms/iteration | 51.68 ms/iteration | 68,042 bytes |
| C++ | 3.36 ms/iteration | 6.05 ms/iteration | 68,262 bytes |

## Notes

- Decode timings include reading the MVT input where applicable.
- Encode timings include the full MLT encode path, including gzip settings
  used by the benchmark (none by default).
- The pure Swift encoder's encode cost is a candidate for further profiling;
  FSST training and dictionary construction dominate.
