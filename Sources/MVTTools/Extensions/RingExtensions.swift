#if canImport(CoreLocation)
import CoreLocation
#endif
import GISTools

// MARK: Private

extension Ring {

    /// A Boolean value indicating whether the ring appears clockwise in unprojected tile space.
    ///
    /// Vector tiles have a flipped y axis, so clockwise/counterClockwise are reverted.
    var isUnprojectedClockwise: Bool {
        !isClockwise
    }

    /// A Boolean value indicating whether the ring appears counter-clockwise in unprojected tile space.
    ///
    /// Vector tiles have a flipped y axis, so clockwise/counterClockwise are reverted.
    var isUnprojectedCounterClockwise: Bool {
        !isCounterClockwise
    }

}
