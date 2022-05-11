import Foundation

public struct VectorTileExportOptions {

    /// The grid width and height of one tile. Always 4096.
    public let extent: Int = 4096

    /// The buffer around the tile, in the same dimension as ``extent``.
    public var bufferSize: Int = 0

    ///
    public var simplifyDistance: Int = 0

    /// Whether to enable compression or not (default: **false**)
    ///
    /// Uses Gzip.
    public var compression: Bool = false

    /// The compression level, between *0* (no compression) and *9* (best compression). (default: **6**)
    ///
    /// Only relevant when ``compression`` is enabled.
    public var compressionLevel: Int = 6 {
        didSet {
            compressionLevel = max(0, min(9, compressionLevel))
        }
    }

}
