# Development

Local setup, build, test, coverage and documentation instructions for
`mvt-tools`.

## Dependencies

Install the development tools:

```bash
brew install protobuf swift-protobuf swiftlint
```

The MLT format uses a git submodule. After cloning, initialize it with:

```bash
git submodule update --init --recursive
```

## Build and test

```bash
swift build                       # MVT, MLT (trait), GeoJSON, and the CLI
swift build --enable-all-traits   # every format coder
swift test                        # default trait set
swift test --enable-all-traits    # all format coders
```

## Coverage

Coverage is measured with LLVM's `llvm-cov` and excludes test sources,
generated protobuf code, and the C++ MLT bridge:

```bash
swift test --enable-all-traits --enable-code-coverage
llvm-cov report .build/debug/MVTToolsTests.so .build/debug/MVTCLITests.so \
    -instr-profile="$(find .build -name '*.profdata' -print -quit)" \
    -ignore-filename-regex='(Tests/|\.build/|Dependencies/|CMLT/|VectorTile_Tile\.swift)'
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

CI runs the macOS and Linux all-traits test suites, the coverage gate, and
the DocC validation job.

## Releasing

See [RELEASING.md](RELEASING.md) for the CLI release and Homebrew update flow.
