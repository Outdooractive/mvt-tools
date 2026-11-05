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

    /// A Boolean value indicating whether the ring is an MVT exterior ring.
    ///
    /// MVT defines exterior rings as having a positive signed area in tile
    /// coordinates. `.noSRID` coordinates are already in tile space; all
    /// projections with an SRID use a Y-up coordinate system in which the same
    /// ring is clockwise.
    var isMVTExterior: Bool {
        projection.hasSRID ? isClockwise : isUnprojectedClockwise
    }

}
