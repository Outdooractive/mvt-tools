import GISTools
@testable import MVTTools
import Testing

struct RingExtensionsTests {

    @Test
    func isUnprojectedClockwise() throws {
        // In MVT (y-flipped), a visually clockwise ring is counter-clockwise in unprojected coords
        let cwRing = try #require(Ring([
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]))
        // In regular (non-flipped) coords this ring is counter-clockwise
        #expect(cwRing.isClockwise == false)
        #expect(cwRing.isCounterClockwise)
        // But in MVT's flipped y-axis space, clockwise is inverted
        #expect(cwRing.isUnprojectedClockwise)
        #expect(cwRing.isUnprojectedCounterClockwise == false)
    }

    @Test
    func isUnprojectedCounterClockwise() throws {
        // A ring that goes counter-clockwise in regular coords
        let ccwRing = try #require(Ring([
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]))
        // In regular (non-flipped) coords this ring is clockwise
        #expect(ccwRing.isClockwise)
        #expect(ccwRing.isCounterClockwise == false)
        #expect(ccwRing.isUnprojectedClockwise == false)
        #expect(ccwRing.isUnprojectedCounterClockwise)
    }

}
