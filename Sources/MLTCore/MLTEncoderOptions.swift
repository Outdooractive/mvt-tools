import Foundation

/// Feature switches for the pure Swift MLT encoder.
package struct MLTEncoderOptions: Sendable, Equatable {

    package var useStringDictionaries: Bool
    package var useSharedStringDictionaries: Bool
    package var useFSST: Bool
    package var useFastPFOR: Bool
    package var useVertexDictionaries: Bool
    package var useIntegerDeltaRLE: Bool

    package init(
        useStringDictionaries: Bool = true,
        useSharedStringDictionaries: Bool = true,
        useFSST: Bool = true,
        useFastPFOR: Bool = false,
        useVertexDictionaries: Bool = true,
        useIntegerDeltaRLE: Bool = true
    ) {
        self.useStringDictionaries = useStringDictionaries
        self.useSharedStringDictionaries = useSharedStringDictionaries
        self.useFSST = useFSST
        self.useFastPFOR = useFastPFOR
        self.useVertexDictionaries = useVertexDictionaries
        self.useIntegerDeltaRLE = useIntegerDeltaRLE
    }

    package static let plain = MLTEncoderOptions(
        useStringDictionaries: false,
        useSharedStringDictionaries: false,
        useFSST: false,
        useFastPFOR: false,
        useVertexDictionaries: false,
        useIntegerDeltaRLE: false)

}
