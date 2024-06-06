#if !os(Linux)
    import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
import XCTest

@testable import MVTTools

final class MVTDecoderTests: XCTestCase {

    func testFeatureGeometryDecoder() {
        // Point
        let geometry1: [UInt32] = [9, 50, 34]
        let coordinates1 = MVTDecoder.multiCoordinatesFrom(geometryIntegers: geometry1, ofType: .point, projectionFunction: MVTDecoder.passThroughFromTile).first?.first
        let result1 = Coordinate3D(x: 25.0, y: 17.0, projection: .noSRID)
        XCTAssertNotNil(coordinates1, "Failed to parse a POINT")
        XCTAssertEqual(coordinates1, result1)

        // MultiPoint
        let geometry2: [UInt32] = [17, 10, 14, 3, 9]
        let coordinates2 = MVTDecoder.multiCoordinatesFrom(geometryIntegers: geometry2, ofType: .point, projectionFunction: MVTDecoder.passThroughFromTile)
        let result2 = [
            [Coordinate3D(x: 5.0, y: 7.0, projection: .noSRID)],
            [Coordinate3D(x: 3.0, y: 2.0, projection: .noSRID)],
        ]
        XCTAssertNotNil(coordinates2, "Failed to parse a MULTIPOINT")
        XCTAssertEqual(coordinates2, result2)

        // Linestring
        let geometry3: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        let coordinates3 = MVTDecoder.multiCoordinatesFrom(geometryIntegers: geometry3, ofType: .linestring, projectionFunction: MVTDecoder.passThroughFromTile)
        let result3 = [[
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ]]
        XCTAssertNotNil(coordinates3, "Failed to parse a LINESTRING")
        XCTAssertEqual(coordinates3, result3)

        // MultiLinestring
        let geometry4: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        let coordinates4 = MVTDecoder.multiCoordinatesFrom(geometryIntegers: geometry4, ofType: .linestring, projectionFunction: MVTDecoder.passThroughFromTile)
        let result4 = [[
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 1.0, y: 1.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 5.0, projection: .noSRID),
        ]]
        XCTAssertNotNil(coordinates4, "Failed to parse a MULTILINESTRING")
        XCTAssertEqual(coordinates4, result4)

        // Polygon
        let geometry5: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        let coordinates5 = MVTDecoder.multiCoordinatesFrom(geometryIntegers: geometry5, ofType: .linestring, projectionFunction: MVTDecoder.passThroughFromTile)
        let result5 = [[
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
            Coordinate3D(x: 8.0, y: 12.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 34.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
        ]]
        XCTAssertNotNil(coordinates5, "Failed to parse a Polygon")
        XCTAssertEqual(coordinates5, result5)

        // MultiPolygon
        let geometry6: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        let coordinates6 = MVTDecoder.multiCoordinatesFrom(geometryIntegers: geometry6, ofType: .linestring, projectionFunction: MVTDecoder.passThroughFromTile)
        let result6 = [[
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 11.0, y: 11.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 11.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 20.0, projection: .noSRID),
            Coordinate3D(x: 11.0, y: 20.0, projection: .noSRID),
            Coordinate3D(x: 11.0, y: 11.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 13.0, y: 13.0, projection: .noSRID),
            Coordinate3D(x: 13.0, y: 17.0, projection: .noSRID),
            Coordinate3D(x: 17.0, y: 17.0, projection: .noSRID),
            Coordinate3D(x: 17.0, y: 13.0, projection: .noSRID),
            Coordinate3D(x: 13.0, y: 13.0, projection: .noSRID),
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
        let feature1 = MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry1,
            ofType: .point,
            projectionFunction: MVTDecoder.passThroughFromTile)
        XCTAssertNotNil(feature1, "Failed to parse a POINT")

        let point1: Point? = feature1?.geometry as? Point
        let boundingBox1: BoundingBox? = feature1?.boundingBox
        XCTAssertNotNil(point1, "Failed to parse a POINT")
        XCTAssertNotNil(boundingBox1, "FEATURE(POINT) without bounding box")

        let result1 = Point(Coordinate3D(x: 25.0, y: 17.0, projection: .noSRID))
        XCTAssertEqual(point1, result1)
        XCTAssertEqual(boundingBox1, result1.calculateBoundingBox())

        // MultiPoint
        let geometry2: [UInt32] = [17, 10, 14, 3, 9]
        let feature2 = MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry2,
            ofType: .point,
            projectionFunction: MVTDecoder.passThroughFromTile)
        XCTAssertNotNil(feature2, "Failed to parse a MULTIPOINT")

        let multiPoint2: MultiPoint? = feature2?.geometry as? MultiPoint
        let boundingBox2: BoundingBox? = feature2?.boundingBox
        XCTAssertNotNil(multiPoint2, "Failed to parse a MULTIPOINT")
        XCTAssertNotNil(boundingBox2, "FEATURE(MULTIPOINT) without bounding box")

        let result2 = MultiPoint([
            Coordinate3D(x: 5.0, y: 7.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 2.0, projection: .noSRID),
        ])!
        XCTAssertEqual(multiPoint2, result2)
        XCTAssertEqual(boundingBox2, result2.calculateBoundingBox())

        // Linestring
        let geometry3: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        let feature3 = MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry3,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile)
        XCTAssertNotNil(feature3, "Failed to parse a LINESTRING")

        let lineString3: LineString? = feature3?.geometry as? LineString
        let boundingBox3: BoundingBox? = feature3?.boundingBox
        XCTAssertNotNil(lineString3, "Failed to parse a LINESTRING")
        XCTAssertNotNil(boundingBox3, "FEATURE(LINESTRING) without bounding box")

        let result3 = LineString([
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ])!
        XCTAssertEqual(lineString3, result3)
        XCTAssertEqual(boundingBox3, result3.calculateBoundingBox())

        // MultiLinestring
        let geometry4: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        let feature4 = MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry4,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile)
        XCTAssertNotNil(feature4, "Failed to parse a MULTILINESTRING")

        let multiLineString4: MultiLineString? = feature4?.geometry as? MultiLineString
        let boundingBox4: BoundingBox? = feature4?.boundingBox
        XCTAssertNotNil(multiLineString4, "Failed to parse a MULTILINESTRING")
        XCTAssertNotNil(boundingBox4, "FEATURE(MULTILINESTRING) without bounding box")

        let result4 = MultiLineString([[
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 1.0, y: 1.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 5.0, projection: .noSRID),
        ]])!
        XCTAssertEqual(multiLineString4, result4)
        XCTAssertEqual(boundingBox4, result4.calculateBoundingBox())

        // Polygon
        let geometry5: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        let feature5 = MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry5,
            ofType: .polygon,
            projectionFunction: MVTDecoder.passThroughFromTile)
        XCTAssertNotNil(feature5, "Failed to parse a POLYGON")

        let polygon5: Polygon? = feature5?.geometry as? Polygon
        let boundingBox5: BoundingBox? = feature5?.boundingBox
        XCTAssertNotNil(polygon5, "Failed to parse a POLYGON")
        XCTAssertNotNil(boundingBox5, "FEATURE(POLYGON) without bounding box")

        let result5: Polygon? = Polygon([[
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
            Coordinate3D(x: 8.0, y: 12.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 34.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
        ]])
        XCTAssertNotNil(result5)
        XCTAssertEqual(polygon5, result5)
        XCTAssertEqual(boundingBox5, result5?.calculateBoundingBox())

        // MultiPolygon
        let geometry6: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        let feature6 = MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry6,
            ofType: .polygon,
            projectionFunction: MVTDecoder.passThroughFromTile)
        XCTAssertNotNil(feature6, "Failed to parse a MULTIPOLYGON")

        let multiPolygon6: MultiPolygon? = feature6?.geometry as? MultiPolygon
        let boundingBox6: BoundingBox? = feature6?.boundingBox
        XCTAssertNotNil(multiPolygon6, "Failed to parse a MULTIPOLYGON")
        XCTAssertNotNil(boundingBox6, "FEATURE(MULTIPOLYGON) without bounding box")

        let result6 = MultiPolygon([[[
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]], [[
            Coordinate3D(x: 11.0, y: 11.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 11.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 20.0, projection: .noSRID),
            Coordinate3D(x: 11.0, y: 20.0, projection: .noSRID),
            Coordinate3D(x: 11.0, y: 11.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 13.0, y: 13.0, projection: .noSRID),
            Coordinate3D(x: 13.0, y: 17.0, projection: .noSRID),
            Coordinate3D(x: 17.0, y: 17.0, projection: .noSRID),
            Coordinate3D(x: 17.0, y: 13.0, projection: .noSRID),
            Coordinate3D(x: 13.0, y: 13.0, projection: .noSRID),
        ]]])!
        XCTAssertEqual(multiPolygon6, result6)
        XCTAssertEqual(boundingBox6, result6.calculateBoundingBox())
    }

}
