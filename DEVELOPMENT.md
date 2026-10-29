# Development

Local setup, build, test, coverage and documentation instructions for
`mvt-tools`.

## Dependencies

Install the development tools:

```bash
brew install protobuf swift-protobuf swiftlint
```

The optional C++ MLT backend uses a git submodule. After cloning, initialize it
with:

```bash
git submodule update --init --recursive
```

The pure Swift MLT implementation (`EnableMLT`) does not need the submodule or
a C++ toolchain.

## Build and test

```bash
swift build                       # MVT, GeoJSON, and the CLI
swift build --traits EnableMLT    # pure Swift MLT (no C++ interop)
swift build --traits EnableMLTCXX # optional C++ MLT backend
swift build --enable-all-traits   # every format coder
swift test                        # default trait set
swift test --traits EnableMLT     # pure Swift MLT
swift test --traits EnableMLTCXX  # C++ MLT backend + cross-backend tests
swift test --enable-all-traits    # all format coders
```

## Coverage

Coverage is measured with LLVM's `llvm-cov` and excludes test sources,
generated protobuf code, and the C++ MLT bridge:

```bash
swift test --traits EnableMLT,EnableCSV,EnableFIT,EnableGPX,EnableShapefile,EnableGeoPackage --enable-code-coverage
python3 scripts/coverage.py --minimum 90
```

## Documentation

The DocC catalog is in `Sources/MVTTools/MVTTools.docc`. To validate it locally:

```bash
swift build --target MVTTools \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc .build/symbol-graphs
mkdir -p .build/mvttools-symbols
cp .build/symbol-graphs/MVTTools.symbols.json .build/mvttools-symbols/
docc convert Sources/MVTTools/MVTTools.docc \
    --additional-symbol-graph-dir .build/mvttools-symbols \
    --output-path .build/docs \
    --warnings-as-errors
```

CI runs the macOS and Linux all-traits test suites, pure Swift and C++ MLT
jobs, the coverage gate, an AddressSanitizer job, and the DocC validation job.

## Benchmarks

Measure MLT decode/encode time and output size with the benchmark executable:

```bash
swift run --traits EnableMLT mlt-benchmark \
    Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt \
    8716 8015 14 20
```

## Releasing

See [RELEASING.md](RELEASING.md) for the CLI release and Homebrew update flow.
