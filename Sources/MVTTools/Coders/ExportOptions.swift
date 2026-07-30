#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools

@available(*, unavailable, renamed: "VectorTile.ExportOptions", message: "This struct has been moved to the VectorTile namespace")
public struct VectorTileExportOptions {}

extension VectorTile {

    /// Various export options.
    public struct ExportOptions {

        /// Options for the buffer around tiles.
        public enum BufferSizeOptions {
            /// No buffering.
            case no
            /// Use the same dimension as `ExportOptions.extent`.
            case extent(Int)
            /// Use pixels (see `ExportOptions.tileSize`).
            case pixel(Int)
        }

        /// Gzip options.
        public enum CompressionOptions: Equatable {
            /// Don't compress the vector tile data.
            case no
            /// The default compression level (*6*).
            case `default`
            /// A compression level, between *0* (no compression) and *9* (best compression).
            case level(Int)
        }

        /// Options for Feature simplification.
        public enum SimplifyFeaturesOptions {
            /// Don't simplify featutes.
            case no
            /// Use the same dimension as `ExportOptions.extent`.
            case extent(Int)
            /// Use meters.
            case meters(CLLocationDistance)
        }

        /// The grid width and height of one tile. Always 4096.
        public static let extent = 4096

        /// The tile size in pixels. Always 512.
        public static let tileSize = 512

        /// The buffer around the tile, either in pixels (see ``tileSize``) or in the same dimension as ``extent`` (default: **no**).
        public var bufferSize: BufferSizeOptions = .no

        /// Whether to enable compression or not (default: **no**)
        ///
        /// Uses Gzip.
        public var compression: CompressionOptions = .no

        /// Simplify features before encoding them (default: **no**).
        public var simplifyFeatures: SimplifyFeaturesOptions = .no

        /// Creates export options with the given buffer, compression, and simplification settings.
        ///
        /// - Parameters:
        ///   - bufferSize: The buffer size around the tile (default: `.no`).
        ///   - compression: The compression setting (default: `.no`).
        ///   - simplifyFeatures: The simplification setting (default: `.no`).
        public init(
            bufferSize: BufferSizeOptions = .no,
            compression: CompressionOptions = .no,
            simplifyFeatures: SimplifyFeaturesOptions = .no
        ) {
            self.bufferSize = bufferSize
            self.compression = compression
            self.simplifyFeatures = simplifyFeatures
        }

    }

    /// Process features according to the given export options (clipping,
    /// simplification, or both).
    ///
    /// When `options` is `nil` or no processing is needed, the original
    /// features are returned unchanged.
    ///
    /// - Parameters:
    ///   - features: The features to process.
    ///   - options: Export options controlling clipping and simplification.
    /// - Returns: The processed features, or the original array if no
    ///   processing was requested.
    func processFeatures(
        _ features: [Feature],
        options: VectorTile.ExportOptions? = nil
    ) -> [Feature] {
        guard let options else { return features }

        var bufferSize = 0
        switch options.bufferSize {
        case .no:
            bufferSize = 0
        case let .extent(extent):
            bufferSize = extent
        case let .pixel(pixel):
            bufferSize = Int((Double(pixel) / Double(VectorTile.ExportOptions.tileSize)) * Double(VectorTile.ExportOptions.extent))
        }

        var simplifyDistance: CLLocationDistance = 0.0
        switch options.simplifyFeatures {
        case .no:
            simplifyDistance = 0.0
        case let .extent(extent):
            let tileBoundsInMeters = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
            simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude)
                / Double(VectorTile.ExportOptions.extent) * Double(extent)
        case let .meters(meters):
            simplifyDistance = meters
        }

        var clipBoundingBox: BoundingBox?
        if bufferSize != 0 {
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4326)
            if let box = clipBoundingBox {
                let sqrt2 = 2.0.squareRoot()
                let diagonal = Double(VectorTile.ExportOptions.extent) * sqrt2
                let bufferDiagonal = Double(bufferSize) * sqrt2
                let factor = bufferDiagonal / diagonal
                let diagonalLength = box.southWest.distance(from: box.northEast)
                clipBoundingBox = box.expanded(byDistance: diagonalLength * factor)
            }
        }

        guard clipBoundingBox != nil || simplifyDistance > 0.0 else { return features }

        return features.compactMap { feature in
            let clipped: Feature
            if let clipBoundingBox {
                guard let c = feature.clipped(to: clipBoundingBox) else { return nil }
                clipped = c
            }
            else {
                clipped = feature
            }
            if simplifyDistance > 0.0 {
                return clipped.simplified(tolerance: simplifyDistance)
            }
            return clipped
        }
    }

}
