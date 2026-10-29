# MLT test fixtures

These tiles are copied from the upstream
[`maplibre-tile-spec`](https://github.com/maplibre/maplibre-tile-spec)
conformance corpus:

- Upstream revision: `71f20ee897a285f54bc461974c07713af04aeb7b`
- Path: `test/expected/0x01/omt`
- Files: `0_0_0.mlt`, `7_66_84.mlt`, `9_264_342.mlt`

They cover multiple layers, FastPFOR integer streams, FSST and shared string
dictionaries, Morton vertex dictionaries, mixed geometry types and numeric
feature IDs. Keeping a small curated copy here means the regular decoder tests
do not need the `maplibre-tile-spec` submodule.

The upstream code and test data are dual-licensed under the MIT and Apache
License 2.0. See the upstream repository for the full license texts.

The complete upstream `0x01` corpus is still exercised by
`MLTCorpusTests` when the submodule is present.
