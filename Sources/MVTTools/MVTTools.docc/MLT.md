# MapLibre Tiles (MLT)

Using the C++-backed MLT decoder and encoder.

## Availability

MLT support is gated behind the `EnableMLT` package trait. The target links a
C++ bridge that bundles the MapLibre Tile specification implementation,
FastPFOR, and FSST. Builds with `EnableMLT` require Swift C++ interoperability
and a C++20 toolchain.

```bash
swift build --enable-all-traits
```

Reading or writing an MLT file without the trait throws a CLI error (or
fails to compile the `mltData`/`mltDecoder` API at the library level).

## Reading

```swift
let tile = try VectorTile(
    mltData: data,
    x: 8657,
    y: 5725,
    z: 14,
    indexed: .hilbert)
```

The decoder supports gzipped input, extracts typed properties (string,
integer, double, boolean), numeric feature IDs, and all geometry types. Ring
order is normalized and the closing vertex is reconstructed when omitted by
the encoder.

## Writing

```swift
let options = VectorTile.ExportOptions(
    bufferSize: .extent(512),
    simplifyFeatures: .meters(1.0))

try tile.writeMLT(to: outputURL, options: options)
```

The encoder:

- normalizes polygon winding in tile space so MapLibre's `classifyRings`
  sees exterior rings and holes correctly,
- stores polygon rings without the redundant closing vertex,
- disables FSST and Morton/Hilbert vertex encoding for interoperability with
  the JavaScript/WASM decoder,
- only writes numeric feature IDs.

## Known limitations

MLT is an evolving format. String feature IDs and altitude are not preserved.
The encoder targets interoperability with `maplibre-gl-js`; enable
`EnableMLT` only when the C++ toolchain is available on every build platform.
