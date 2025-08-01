#if !os(Linux)
    import CoreLocation
#endif
import Foundation
import GISTools
@testable import MVTTools
import Testing

struct ProjectionTests {

    @Test
    func projectToEpsg3857() async throws {
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

    @Test
    func projectToEpsg4326() async throws {
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

}
