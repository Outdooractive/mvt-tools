#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
@testable import MVTTools
import Testing

struct ProjectionTests {

    /// Tests converting EPSG:4326 (lat/lon) coordinates to EPSG:3857 (Web Mercator).
    @Test
    func projectToEpsg3857() {
        let projection1 = Coordinate3D(latitude: 20.5, longitude: 10.5).projected(to: .epsg3857)
        #expect(abs(projection1.latitude - 2_332_357.812619) < 0.00001)
        #expect(abs(projection1.longitude - 1_168_854.653329) < 0.00001)

        let projection2 = Coordinate3D(latitude: 45.0, longitude: -180.0).projected(to: .epsg3857)
        #expect(abs(projection2.latitude - 5_621_521.486192) < 0.00001)
        #expect(abs(projection2.longitude - -20_037_508.342789) < 0.00001)

        let projection3 = Coordinate3D(latitude: -45.0, longitude: 45.0).projected(to: .epsg3857)
        #expect(abs(projection3.latitude - -5_621_521.486192) < 0.00001)
        #expect(abs(projection3.longitude - 5_009_377.085697) < 0.00001)
    }

    /// Tests converting EPSG:3857 (Web Mercator) coordinates back to EPSG:4326 (lat/lon).
    @Test
    func projectToEpsg4326() {
        let projection1 = Coordinate3D(x: 1_168_854.653329, y: 2_332_357.812619).projected(to: .epsg4326)
        #expect(abs(projection1.latitude - 20.5) < 0.00001)
        #expect(abs(projection1.longitude - 10.5) < 0.00001)

        let projection2 = Coordinate3D(x: -20_037_508.342789, y: 5_621_521.486192).projected(to: .epsg4326)
        #expect(abs(projection2.latitude - 45.0) < 0.00001)
        #expect(abs(projection2.longitude - -180.0) < 0.00001)

        let projection3 = Coordinate3D(x: 5_009_377.09, y: -5_621_521.49).projected(to: .epsg4326)
        #expect(abs(projection3.latitude - -45.0) < 0.00001)
        #expect(abs(projection3.longitude - 45.0) < 0.00001)
    }

    /// Tests that `.noSRID` passes coordinates through without transformation.
    @Test
    func noProjection() {
        let coordinate = Coordinate3D(x: 123.456, y: 789.012, projection: .noSRID)
        let projected = coordinate.projected(to: .noSRID)
        #expect(projected.x == 123.456)
        #expect(projected.y == 789.012)
        #expect(projected.projection == .noSRID)
    }

    /// Tests that EPSG:4326 coordinates round-trip correctly through EPSG:4978 (ECEF).
    @Test
    func projectToEpsg4978() {
        let coordinate = Coordinate3D(latitude: 45.0, longitude: 0.0)
        let ecef = coordinate.projected(to: .epsg4978)

        #expect(abs(ecef.x - 4_510_691.0) < 10_000.0)
        #expect(abs(ecef.y) < 10_000.0)
        let zValue = ecef.z ?? 0.0
        #expect(abs(zValue - 4_486_765.0) < 10_000.0)

        let roundtrip = ecef.projected(to: .epsg4326)
        #expect(abs(roundtrip.latitude - 45.0) < 0.001)
        #expect(abs(roundtrip.longitude - 0.0) < 0.001)
    }

}
