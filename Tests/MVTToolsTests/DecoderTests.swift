#if !os(Linux)
import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
import XCTest

@testable import MVTTools

final class DecoderTests: XCTestCase {

    func testFeatureGeometryDecoder() {
        // Point
        let geometry1: [UInt32] = [9, 50, 34]
        let coordinates1 = VectorTile.multiCoordinatesFrom(geometryIntegers: geometry1, ofType: .point, projectionFunction: VectorTile.passThroughFromTile).first?.first
        let result1 = Coordinate3D(latitude: 17.0, longitude: 25.0)
        XCTAssertNotNil(coordinates1, "Failed to parse a POINT")
        XCTAssertEqual(coordinates1, result1)

        // MultiPoint
        let geometry2: [UInt32] = [17, 10, 14, 3, 9]
        let coordinates2 = VectorTile.multiCoordinatesFrom(geometryIntegers: geometry2, ofType: .point, projectionFunction: VectorTile.passThroughFromTile)
        let result2 = [
            [Coordinate3D(latitude: 7.0, longitude: 5.0)],
            [Coordinate3D(latitude: 2.0, longitude: 3.0)]
        ]
        XCTAssertNotNil(coordinates2, "Failed to parse a MULTIPOINT")
        XCTAssertEqual(coordinates2, result2)

        // Linestring
        let geometry3: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        let coordinates3 = VectorTile.multiCoordinatesFrom(geometryIntegers: geometry3, ofType: .linestring, projectionFunction: VectorTile.passThroughFromTile)
        let result3 = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ]]
        XCTAssertNotNil(coordinates3, "Failed to parse a LINESTRING")
        XCTAssertEqual(coordinates3, result3)

        // MultiLinestring
        let geometry4: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        let coordinates4 = VectorTile.multiCoordinatesFrom(geometryIntegers: geometry4, ofType: .linestring, projectionFunction: VectorTile.passThroughFromTile)
        let result4 = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0)
        ], [
            Coordinate3D(latitude: 1.0, longitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 3.0),
        ]]
        XCTAssertNotNil(coordinates4, "Failed to parse a MULTILINESTRING")
        XCTAssertEqual(coordinates4, result4)

        // Polygon
        let geometry5: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        let coordinates5 = VectorTile.multiCoordinatesFrom(geometryIntegers: geometry5, ofType: .linestring, projectionFunction: VectorTile.passThroughFromTile)
        let result5 = [[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
        ]]
        XCTAssertNotNil(coordinates5, "Failed to parse a Polygon")
        XCTAssertEqual(coordinates5, result5)

        // MultiPolygon
        let geometry6: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        let coordinates6 = VectorTile.multiCoordinatesFrom(geometryIntegers: geometry6, ofType: .linestring, projectionFunction: VectorTile.passThroughFromTile)
        let result6 = [[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ], [
            Coordinate3D(latitude: 11.0, longitude: 11.0),
            Coordinate3D(latitude: 11.0, longitude: 20.0),
            Coordinate3D(latitude: 20.0, longitude: 20.0),
            Coordinate3D(latitude: 20.0, longitude: 11.0),
            Coordinate3D(latitude: 11.0, longitude: 11.0),
        ], [
            Coordinate3D(latitude: 13.0, longitude: 13.0),
            Coordinate3D(latitude: 17.0, longitude: 13.0),
            Coordinate3D(latitude: 17.0, longitude: 17.0),
            Coordinate3D(latitude: 13.0, longitude: 17.0),
            Coordinate3D(latitude: 13.0, longitude: 13.0),
        ]]
        XCTAssertNotNil(coordinates6, "Failed to parse a MULTIPOLYGON")
        XCTAssertEqual(coordinates6, result6)

        let rings: [Ring] = coordinates6.map { Ring($0)! }
        XCTAssertTrue(rings[0].isUnprojectedClockwise, "First polygon ring is not oriented clockwise")
        XCTAssertTrue(rings[1].isUnprojectedClockwise, "Second polygon ring is not oriented clockwise")
        XCTAssertTrue(rings[2].isUnprojectedCounterClockwise, "Third polygon ring is not oriented counter-clockwise")
    }

    func testFeatureConversion() {
        // Point
        let geometry1: [UInt32] = [9, 50, 34]
        let feature1 = VectorTile.convertToLayerFeature(
            geometryIntegers: geometry1,
            ofType: .point,
            projectionFunction: VectorTile.passThroughFromTile)
        XCTAssertNotNil(feature1, "Failed to parse a POINT")

        let point1: Point? = feature1?.geometry as? Point
        let boundingBox1: BoundingBox? = feature1?.boundingBox
        XCTAssertNotNil(point1, "Failed to parse a POINT")
        XCTAssertNotNil(boundingBox1, "FEATURE(POINT) without bounding box")

        let result1: Point = Point(Coordinate3D(latitude: 17.0, longitude: 25.0))
        XCTAssertEqual(point1, result1)
        XCTAssertEqual(boundingBox1, result1.calculateBoundingBox())

        // MultiPoint
        let geometry2: [UInt32] = [17, 10, 14, 3, 9]
        let feature2 = VectorTile.convertToLayerFeature(
            geometryIntegers: geometry2,
            ofType: .point,
            projectionFunction: VectorTile.passThroughFromTile)
        XCTAssertNotNil(feature2, "Failed to parse a MULTIPOINT")

        let multiPoint2: MultiPoint? = feature2?.geometry as? MultiPoint
        let boundingBox2: BoundingBox? = feature2?.boundingBox
        XCTAssertNotNil(multiPoint2, "Failed to parse a MULTIPOINT")
        XCTAssertNotNil(boundingBox2, "FEATURE(MULTIPOINT) without bounding box")

        let result2: MultiPoint = MultiPoint([
            Coordinate3D(latitude: 7.0, longitude: 5.0),
            Coordinate3D(latitude: 2.0, longitude: 3.0)
        ])!
        XCTAssertEqual(multiPoint2, result2)
        XCTAssertEqual(boundingBox2, result2.calculateBoundingBox())

        // Linestring
        let geometry3: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        let feature3 = VectorTile.convertToLayerFeature(
            geometryIntegers: geometry3,
            ofType: .linestring,
            projectionFunction: VectorTile.passThroughFromTile)
        XCTAssertNotNil(feature3, "Failed to parse a LINESTRING")

        let lineString3: LineString? = feature3?.geometry as? LineString
        let boundingBox3: BoundingBox? = feature3?.boundingBox
        XCTAssertNotNil(lineString3, "Failed to parse a LINESTRING")
        XCTAssertNotNil(boundingBox3, "FEATURE(LINESTRING) without bounding box")

        let result3: LineString = LineString([
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ])!
        XCTAssertEqual(lineString3, result3)
        XCTAssertEqual(boundingBox3, result3.calculateBoundingBox())

        // MultiLinestring
        let geometry4: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        let feature4 = VectorTile.convertToLayerFeature(
            geometryIntegers: geometry4,
            ofType: .linestring,
            projectionFunction: VectorTile.passThroughFromTile)
        XCTAssertNotNil(feature4, "Failed to parse a MULTILINESTRING")

        let multiLineString4: MultiLineString? = feature4?.geometry as? MultiLineString
        let boundingBox4: BoundingBox? = feature4?.boundingBox
        XCTAssertNotNil(multiLineString4, "Failed to parse a MULTILINESTRING")
        XCTAssertNotNil(boundingBox4, "FEATURE(MULTILINESTRING) without bounding box")

        let result4: MultiLineString = MultiLineString([[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0)
        ], [
            Coordinate3D(latitude: 1.0, longitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 3.0),
        ]])!
        XCTAssertEqual(multiLineString4, result4)
        XCTAssertEqual(boundingBox4, result4.calculateBoundingBox())

        // Polygon
        let geometry5: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        let feature5 = VectorTile.convertToLayerFeature(
            geometryIntegers: geometry5,
            ofType: .polygon,
            projectionFunction: VectorTile.passThroughFromTile)
        XCTAssertNotNil(feature5, "Failed to parse a POLYGON")

        let polygon5: Polygon? = feature5?.geometry as? Polygon
        let boundingBox5: BoundingBox? = feature5?.boundingBox
        XCTAssertNotNil(polygon5, "Failed to parse a POLYGON")
        XCTAssertNotNil(boundingBox5, "FEATURE(POLYGON) without bounding box")

        let result5: Polygon? = Polygon([[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
        ]])
        XCTAssertNotNil(result5)
        XCTAssertEqual(polygon5, result5)
        XCTAssertEqual(boundingBox5, result5?.calculateBoundingBox())

        // MultiPolygon
        let geometry6: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        let feature6 = VectorTile.convertToLayerFeature(
            geometryIntegers: geometry6,
            ofType: .polygon,
            projectionFunction: VectorTile.passThroughFromTile)
        XCTAssertNotNil(feature6, "Failed to parse a MULTIPOLYGON")

        let multiPolygon6: MultiPolygon? = feature6?.geometry as? MultiPolygon
        let boundingBox6: BoundingBox? = feature6?.boundingBox
        XCTAssertNotNil(multiPolygon6, "Failed to parse a MULTIPOLYGON")
        XCTAssertNotNil(boundingBox6, "FEATURE(MULTIPOLYGON) without bounding box")

        let result6: MultiPolygon = MultiPolygon([[[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]], [[
            Coordinate3D(latitude: 11.0, longitude: 11.0),
            Coordinate3D(latitude: 11.0, longitude: 20.0),
            Coordinate3D(latitude: 20.0, longitude: 20.0),
            Coordinate3D(latitude: 20.0, longitude: 11.0),
            Coordinate3D(latitude: 11.0, longitude: 11.0),
        ], [
            Coordinate3D(latitude: 13.0, longitude: 13.0),
            Coordinate3D(latitude: 17.0, longitude: 13.0),
            Coordinate3D(latitude: 17.0, longitude: 17.0),
            Coordinate3D(latitude: 13.0, longitude: 17.0),
            Coordinate3D(latitude: 13.0, longitude: 13.0),
        ]]])!
        XCTAssertEqual(multiPolygon6, result6)
        XCTAssertEqual(boundingBox6, result6.calculateBoundingBox())
    }

}
