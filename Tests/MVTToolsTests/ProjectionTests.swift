#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import XCTest

@testable import MVTTools

final class ProjectionTests: XCTestCase {

    func testProjectToEpsg3857() {
        let projection1 = Coordinate3D(latitude: 20.5, longitude: 10.5).projected(to: .epsg3857)
        XCTAssertEqual(projection1.latitude, 2332357.812619, accuracy: 0.00001)
        XCTAssertEqual(projection1.longitude, 1168854.653329, accuracy: 0.00001)

        let projection2 = Coordinate3D(latitude: 45.0, longitude: -180.0).projected(to: .epsg3857)
        XCTAssertEqual(projection2.latitude, 5621521.486192, accuracy: 0.00001)
        XCTAssertEqual(projection2.longitude, -20037508.342789, accuracy: 0.00001)

        let projection3 = Coordinate3D(latitude: -45.0, longitude: 45.0).projected(to: .epsg3857)
        XCTAssertEqual(projection3.latitude, -5621521.486192, accuracy: 0.00001)
        XCTAssertEqual(projection3.longitude, 5009377.085697, accuracy: 0.00001)
    }

    func testProjectToEpsg4326() {
        let projection1 = Coordinate3D(x: 1168854.653329, y: 2332357.812619).projected(to: .epsg4326)
        XCTAssertEqual(projection1.latitude, 20.5, accuracy: 0.00001)
        XCTAssertEqual(projection1.longitude, 10.5, accuracy: 0.00001)

        let projection2 = Coordinate3D(x: -20037508.342789, y: 5621521.486192).projected(to: .epsg4326)
        XCTAssertEqual(projection2.latitude, 45.0, accuracy: 0.00001)
        XCTAssertEqual(projection2.longitude, -180.0, accuracy: 0.00001)

        let projection3 = Coordinate3D(x: 5009377.09, y: -5621521.49).projected(to: .epsg4326)
        XCTAssertEqual(projection3.latitude, -45.0, accuracy: 0.00001)
        XCTAssertEqual(projection3.longitude, 45.0, accuracy: 0.00001)
    }

}
