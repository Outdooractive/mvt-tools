import ArgumentParser
import MVTTools

extension CLI {

    /// Options that toggle optional MLT encoder features.
    ///
    /// They only affect MLT output produced by the pure Swift encoder. The
    /// defaults match the library defaults: string and shared dictionaries plus
    /// FSST are enabled, FastPFOR and vertex dictionaries are disabled.
    struct MLTEncoderOptions: ParsableArguments {

        /// Names of the optional MLT encoder features.
        enum Feature: String, CaseIterable, Sendable {
            case dictionaries
            case sharedDictionaries = "shared-dictionaries"
            case fsst
            case fastpfor
            case vertexDictionaries = "vertex-dictionaries"
            case integerDeltaRLE = "integer-delta-rle"
        }

        /// A comma-separated list of MLT encoder feature names.
        struct FeatureList: ExpressibleByArgument {
            var features: [Feature]

            init?(argument: String) {
                let names = argument
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard !names.isEmpty else { return nil }

                var features: [Feature] = []
                for name in names {
                    guard let feature = Feature(rawValue: name) else { return nil }
                    features.append(feature)
                }
                self.features = features
            }

            static var allValueStrings: [String] {
                Feature.allCases.map(\.rawValue)
            }
        }

        @Flag(
            name: .customLong("mlt-plain"),
            help: "Disable all optional MLT encoder features for plain, deterministic output.")
        var plain = false

        @Option(
            name: .customLong("mlt-enable"),
            help: ArgumentHelp(
                "Enable MLT encoder features (comma-separated, repeatable).",
                valueName: "features"))
        var enable: [FeatureList] = []

        @Option(
            name: .customLong("mlt-disable"),
            help: ArgumentHelp(
                "Disable MLT encoder features (comma-separated, repeatable).",
                valueName: "features"))
        var disable: [FeatureList] = []

        func validate() throws {
            let enabled = Set(enable.flatMap(\.features))
            let disabled = Set(disable.flatMap(\.features))
            let conflicts = enabled.intersection(disabled)
            guard conflicts.isEmpty else {
                throw ValidationError(
                    "Features cannot be both enabled and disabled: "
                        + conflicts.map(\.rawValue).sorted().joined(separator: ", "))
            }
        }

        /// Applies the flags to the given export options.
        ///
        /// `--mlt-plain` is applied first so that individual features can be
        /// re-enabled on top of the plain preset.
        func apply(to options: inout VectorTile.ExportOptions) {
            if plain {
                options.mlt = .plain
            }
            for feature in enable.flatMap(\.features) {
                set(feature, enabled: true, in: &options.mlt)
            }
            for feature in disable.flatMap(\.features) {
                set(feature, enabled: false, in: &options.mlt)
            }
        }

        private func set(
            _ feature: Feature,
            enabled: Bool,
            in options: inout VectorTile.ExportOptions.MLTEncodingOptions
        ) {
            switch feature {
            case .dictionaries:
                options.useStringDictionaries = enabled
            case .sharedDictionaries:
                options.useSharedStringDictionaries = enabled
            case .fsst:
                options.useFSST = enabled
            case .fastpfor:
                options.useFastPFOR = enabled
            case .vertexDictionaries:
                options.useVertexDictionaries = enabled
            case .integerDeltaRLE:
                options.useIntegerDeltaRLE = enabled
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
