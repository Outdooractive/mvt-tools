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

        /// MLT encoder feature switches.
        ///
        /// Disable individual optimizations when they cause interoperability,
        /// size or performance problems. Disabling an option can increase the
        /// encoded tile size but never changes the decoded content.
        ///
        /// The defaults are conservative: string and shared dictionaries plus
        /// FSST are enabled, FastPFOR and vertex dictionaries are disabled.
        /// They only affect the pure Swift encoder; the optional C++ backend
        /// uses its own configuration.
        public struct MLTEncodingOptions: Sendable, Equatable {

            /// Use single and shared string dictionaries.
            public var useStringDictionaries: Bool

            /// Group related string columns into a shared dictionary.
            public var useSharedStringDictionaries: Bool

            /// Compress string dictionaries with FSST.
            ///
            /// Only applies when ``useStringDictionaries`` is enabled.
            public var useFSST: Bool

            /// Use FastPFOR for large 32-bit integer streams (default: disabled).
            ///
            /// Disabled by default because bit-packing rarely beats the plain,
            /// delta or RLE layouts for typical tile data.
            public var useFastPFOR: Bool

            /// Use Hilbert/Morton vertex dictionaries for repeated vertices
            /// (default: disabled).
            ///
            /// Disabled by default: on real-world tiles the dictionaries rarely
            /// reduce the gzip-compressed size, while building and testing them
            /// costs a noticeable share of encode time.
            public var useVertexDictionaries: Bool

            /// Use delta/RLE/delta-RLE integer stream encodings.
            public var useIntegerDeltaRLE: Bool

            /// Creates MLT encoder options with the default optimization set.
            public init(
                useStringDictionaries: Bool = true,
                useSharedStringDictionaries: Bool = true,
                useFSST: Bool = true,
                useFastPFOR: Bool = false,
                useVertexDictionaries: Bool = false,
                useIntegerDeltaRLE: Bool = true
            ) {
                self.useStringDictionaries = useStringDictionaries
                self.useSharedStringDictionaries = useSharedStringDictionaries
                self.useFSST = useFSST
                self.useFastPFOR = useFastPFOR
                self.useVertexDictionaries = useVertexDictionaries
                self.useIntegerDeltaRLE = useIntegerDeltaRLE
            }

            /// Plain, deterministic encoding without optional optimizations.
            public static let plain = MLTEncodingOptions(
                useStringDictionaries: false,
                useSharedStringDictionaries: false,
                useFSST: false,
                useFastPFOR: false,
                useVertexDictionaries: false,
                useIntegerDeltaRLE: false)

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

        /// MLT-specific encoder feature switches.
        public var mlt: MLTEncodingOptions = .init()

        /// Creates export options with the given buffer, compression, and simplification settings.
        ///
        /// - Parameters:
        ///   - bufferSize: The buffer size around the tile (default: `.no`).
        ///   - compression: The compression setting (default: `.no`).
        ///   - simplifyFeatures: The simplification setting (default: `.no`).
        ///   - mlt: MLT encoder feature switches.
        public init(
            bufferSize: BufferSizeOptions = .no,
            compression: CompressionOptions = .no,
            simplifyFeatures: SimplifyFeaturesOptions = .no,
            mlt: MLTEncodingOptions = .init()
        ) {
            self.bufferSize = bufferSize
            self.compression = compression
            self.simplifyFeatures = simplifyFeatures
            self.mlt = mlt
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
        if bufferSize != 0, projection.hasSRID {
            clipBoundingBox = VectorTile.expanded(
                MapTile(x: x, y: y, z: z).boundingBox(projection: projection),
                byBufferSize: bufferSize)
        }

        return VectorTile.processedFeatures(
            features,
            clipBoundingBox: clipBoundingBox,
            simplifyDistance: simplifyDistance)
    }

    /// Expand a tile bounding box by a buffer measured in tile-extent units.
    ///
    /// One extent unit corresponds to one 4096th of the tile width, so a
    /// buffer of `bufferSize` extent units is `bufferSize / 4096` of the tile
    /// width. The previous implementation multiplied the box diagonal
    /// (width × √2) by that fraction, which made every buffer roughly 41%
    /// larger than requested.
    ///
    /// - Parameters:
    ///   - boundingBox: The tile bounding box in the target projection.
    ///   - bufferSize: The buffer size in tile-extent units.
    /// - Returns: The expanded bounding box.
    static func expanded(
        _ boundingBox: BoundingBox,
        byBufferSize bufferSize: Int
    ) -> BoundingBox {
        guard bufferSize > 0 else { return boundingBox }

        // Use the tile's horizontal edge length in meters (or projection
        // units). `expanded(byDistance:)` interprets the value in meters for
        // geographic projections and native units for planar ones.
        let tileWidth = boundingBox.southWest.distance(from: boundingBox.southEast)
        let distance = (Double(bufferSize) / Double(VectorTile.ExportOptions.extent)) * tileWidth

        return boundingBox.expanded(byDistance: distance)
    }

    /// Clip and optionally simplify a list of features.
    ///
    /// Features that lie completely inside `clipBoundingBox` are passed
    /// through unchanged. This preserves their exact geometry type:
    /// `Feature.clipped(to:)` always returns multi-geometries, so
    /// clipping an already-contained `LineString` or `Polygon` would
    /// silently promote it to `multi-line string` or `MultiPolygon`.
    ///
    /// - Parameters:
    ///   - features: The features to process.
    ///   - clipBoundingBox: The clipping box, or `nil` to skip clipping.
    ///   - simplifyDistance: The simplification tolerance in projection
    ///     units, or `0.0` to skip simplification.
    /// - Returns: The processed features. Features outside the clip box are
    ///   dropped.
    static func processedFeatures(
        _ features: [Feature],
        clipBoundingBox: BoundingBox?,
        simplifyDistance: CLLocationDistance = 0.0
    ) -> [Feature] {
        guard clipBoundingBox != nil || simplifyDistance > 0.0 else { return features }

        return features.compactMap { feature in
            let clipped: Feature
            if let clipBoundingBox, !feature.isFullyContained(in: clipBoundingBox) {
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

extension Feature {

    /// A Boolean value indicating whether the feature's bounding box is
    /// completely inside `box`.
    ///
    /// - Parameter box: The bounding box to test against.
    /// - Returns: `true` when the feature has a geometry and its bounding box
    ///   is contained in `box`.
    func isFullyContained(in box: BoundingBox) -> Bool {
        let coordinates = allCoordinates
        guard coordinates.isNotEmpty else { return false }
        return coordinates.allSatisfy({ box.contains($0) })
    }

}
