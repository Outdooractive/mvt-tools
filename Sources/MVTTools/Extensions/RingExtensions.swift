#if !os(Linux)
    import CoreLocation
#endif
import GISTools

// MARK: Private

extension Ring {

    /// Note: Vector tiles have a flipped y axis, so
    /// clockwise/counterClockwise are reverted
    var isUnprojectedClockwise: Bool {
        !isClockwise
    }

    /// Note: Vector tiles have a flipped y axis, so
    /// clockwise/counterClockwise are reverted
    var isUnprojectedCounterClockwise: Bool {
        !isCounterClockwise
    }

}
