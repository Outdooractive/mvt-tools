import ArgumentParser
import MVTTools

extension CLI {

    /// Options that toggle optional MLT encoder features.
    ///
    /// They only affect MLT output produced by the pure Swift encoder. The
    /// defaults match the library defaults: string and shared dictionaries plus
    /// FSST are enabled, FastPFOR and vertex dictionaries are disabled.
    struct MLTEncoderOptions: ParsableArguments {

        @Flag(
            name: .customLong("mlt-plain"),
            help: "Disable all optional MLT encoder features for plain, deterministic output.")
        var plain = false

        @Flag(
            name: .customLong("mlt-no-dictionaries"),
            help: "Disable single and shared string dictionaries in MLT output.")
        var noDictionaries = false

        @Flag(
            name: .customLong("mlt-no-shared-dictionaries"),
            help: "Disable shared string dictionaries in MLT output.")
        var noSharedDictionaries = false

        @Flag(
            name: .customLong("mlt-no-fsst"),
            help: "Disable FSST compression of string dictionaries in MLT output.")
        var noFSST = false

        @Flag(
            name: .customLong("mlt-fastpfor"),
            help: "Enable FastPFOR for large 32-bit integer streams in MLT output.")
        var fastPFOR = false

        @Flag(
            name: .customLong("mlt-vertex-dictionaries"),
            help: "Enable Hilbert/Morton vertex dictionaries in MLT output.")
        var vertexDictionaries = false

        @Flag(
            name: .customLong("mlt-no-vertex-dictionaries"),
            help: "Disable Hilbert/Morton vertex dictionaries in MLT output.")
        var noVertexDictionaries = false

        @Flag(
            name: .customLong("mlt-no-integer-delta-rle"),
            help: "Disable delta, RLE and delta-RLE integer streams in MLT output.")
        var noIntegerDeltaRLE = false

        /// Applies the flags to the given export options.
        ///
        /// `--mlt-plain` is applied first so that individual features can be
        /// re-enabled on top of the plain preset.
        func apply(to options: inout VectorTile.ExportOptions) {
            if plain {
                options.mlt = .plain
            }
            if noDictionaries {
                options.mlt.useStringDictionaries = false
                options.mlt.useSharedStringDictionaries = false
            }
            if noSharedDictionaries {
                options.mlt.useSharedStringDictionaries = false
            }
            if noFSST {
                options.mlt.useFSST = false
            }
            if fastPFOR {
                options.mlt.useFastPFOR = true
            }
            if vertexDictionaries {
                options.mlt.useVertexDictionaries = true
            }
            if noVertexDictionaries {
                options.mlt.useVertexDictionaries = false
            }
            if noIntegerDeltaRLE {
                options.mlt.useIntegerDeltaRLE = false
            }
        }

        /// A compact summary of the effective switches for verbose output.
        ///
        /// - Parameter options: The MLT options after ``apply(to:)``.
        /// - Returns: A comma-separated list of enabled features, or `plain`.
        func summary(for options: VectorTile.ExportOptions.MLTEncodingOptions) -> String {
            var features: [String] = []
            if options.useStringDictionaries {
                features.append("dictionaries")
                if options.useSharedStringDictionaries {
                    features.append("shared-dictionaries")
                }
                if options.useFSST {
                    features.append("fsst")
                }
            }
            if options.useFastPFOR {
                features.append("fastpfor")
            }
            if options.useVertexDictionaries {
                features.append("vertex-dictionaries")
            }
            if options.useIntegerDeltaRLE {
                features.append("delta-rle")
            }
            return features.isEmpty ? "plain" : features.joined(separator: ", ")
        }

    }

}
