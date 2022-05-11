#if !os(Linux)
import CoreLocation
#endif
import GISTools

// MARK: - Ring

extension Ring {

    /// Note: Vector tiles have a flipped y axis, so
    /// clockwise/counterClockwise are reverted
    var isUnprojectedClockwise: Bool {
        return !isClockwise
    }

    var isUnprojectedCounterClockwise: Bool {
        return !isCounterClockwise
    }

}
