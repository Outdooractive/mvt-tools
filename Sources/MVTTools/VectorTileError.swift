import Foundation
import GISTools

/// Errors thrown by ``VectorTile`` initializers when loading data or
/// validating tile coordinates.
public enum VectorTileError: Error, Equatable {

    /// One or more tile coordinates are negative or invalid.
    case invalidCoordinate(x: Int, y: Int, z: Int)

    /// The tile coordinate exceeds the valid range for the zoom level.
    case coordinateOutOfBounds(x: Int, y: Int, z: Int, maxBound: Int)

    /// The file at `url` could not be read.
    case fileReadFailed(url: URL, reason: String)

    /// The data could not be parsed in the expected format.
    case parseFailed(format: String, reason: String)

}

// MARK: - LocalizedError

extension VectorTileError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .invalidCoordinate(x, y, z):
            return "Invalid tile coordinate: z=\(z), x=\(x), y=\(y). "
                + "Coordinates must be >= 0 and z must be less than \(Int.bitWidth - 1)."
        case let .coordinateOutOfBounds(x, y, z, maxBound):
            let maximumCoordinate = maxBound > 0 ? maxBound - 1 : maxBound
            return "Tile coordinate out of bounds at zoom \(z): x=\(x), y=\(y). "
                + "Maximum is \(maximumCoordinate) (2^\(z) = \(maxBound))."
        case let .fileReadFailed(url, reason):
            return "Failed to read \(url.absoluteString): \(reason)"
        case let .parseFailed(format, reason):
            return "Failed to parse \(format) data: \(reason)"
        }
    }

}
