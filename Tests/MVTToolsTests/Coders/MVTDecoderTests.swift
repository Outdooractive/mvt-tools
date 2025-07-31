#if !os(Linux)
    import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

struct MVTDecoderTests {

    @Test
    func featureGeometryDecoder() async throws {
        // Point
        let geometry1: [UInt32] = [9, 50, 34]
        let coordinates1 = try #require(MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: geometry1,
            ofType: .point,
            projectionFunction: MVTDecoder.passThroughFromTile
        ).first?.first)
        let result1 = Coordinate3D(x: 25.0, y: 17.0, projection: .noSRID)
        #expect(coordinates1 == result1)

        // MultiPoint
        let geometry2: [UInt32] = [17, 10, 14, 3, 9]
        let coordinates2 = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: geometry2,
            ofType: .point,
            projectionFunction: MVTDecoder.passThroughFromTile)
        let result2 = [
            [Coordinate3D(x: 5.0, y: 7.0, projection: .noSRID)],
            [Coordinate3D(x: 3.0, y: 2.0, projection: .noSRID)],
        ]
        #expect(coordinates2 == result2)

        // Linestring
        let geometry3: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        let coordinates3 = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: geometry3,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile)
        let result3 = [[
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ]]
        #expect(coordinates3 == result3)

        // MultiLinestring
        let geometry4: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        let coordinates4 = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: geometry4,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile)
        let result4 = [[
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 1.0, y: 1.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 5.0, projection: .noSRID),
        ]]
        #expect(coordinates4 == result4)

        // Polygon
        let geometry5: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        let coordinates5 = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: geometry5,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile)
        let result5 = [[
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
            Coordinate3D(x: 8.0, y: 12.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 34.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
        ]]
        #expect(coordinates5 == result5)

        // MultiPolygon
        let geometry6: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        let coordinates6 = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: geometry6,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile)
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
        #expect(coordinates6 == result6)

        let rings: [Ring] = coordinates6.map { Ring($0)! }
        #expect(rings[0].isUnprojectedClockwise, "First polygon ring is not oriented clockwise")
        #expect(rings[1].isUnprojectedClockwise, "Second polygon ring is not oriented clockwise")
        #expect(rings[2].isUnprojectedCounterClockwise, "Third polygon ring is not oriented counter-clockwise")
    }

    @Test
    func featureConversion() async throws {
        // Point
        let geometry1: [UInt32] = [9, 50, 34]
        let feature1 = try #require(MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry1,
            ofType: .point,
            projectionFunction: MVTDecoder.passThroughFromTile))
        let point1: Point = try #require(feature1.geometry as? Point)
        let boundingBox1: BoundingBox = try #require(feature1.boundingBox)
        let result1 = Point(Coordinate3D(x: 25.0, y: 17.0, projection: .noSRID))
        #expect(point1 == result1)
        #expect(boundingBox1 == result1.calculateBoundingBox())

        // MultiPoint
        let geometry2: [UInt32] = [17, 10, 14, 3, 9]
        let feature2 = try #require(MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry2,
            ofType: .point,
            projectionFunction: MVTDecoder.passThroughFromTile))
        let multiPoint2: MultiPoint = try #require(feature2.geometry as? MultiPoint)
        let boundingBox2: BoundingBox = try #require(feature2.boundingBox)
        let result2 = try #require(MultiPoint([
            Coordinate3D(x: 5.0, y: 7.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 2.0, projection: .noSRID),
        ]))
        #expect(multiPoint2 == result2)
        #expect(boundingBox2 == result2.calculateBoundingBox())

        // Linestring
        let geometry3: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        let feature3 = try #require(MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry3,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile))
        let lineString3: LineString = try #require(feature3.geometry as? LineString)
        let boundingBox3: BoundingBox = try #require(feature3.boundingBox)
        let result3 = try #require(LineString([
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ]))
        #expect(lineString3 == result3)
        #expect(boundingBox3 == result3.calculateBoundingBox())

        // MultiLinestring
        let geometry4: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        let feature4 = try #require(MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry4,
            ofType: .linestring,
            projectionFunction: MVTDecoder.passThroughFromTile))
        let multiLineString4: MultiLineString = try #require(feature4.geometry as? MultiLineString)
        let boundingBox4: BoundingBox = try #require(feature4.boundingBox)
        let result4 = try #require(MultiLineString([[
            Coordinate3D(x: 2.0, y: 2.0, projection: .noSRID),
            Coordinate3D(x: 2.0, y: 10.0, projection: .noSRID),
            Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 1.0, y: 1.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 5.0, projection: .noSRID),
        ]]))
        #expect(multiLineString4 == result4)
        #expect(boundingBox4 == result4.calculateBoundingBox())

        // Polygon
        let geometry5: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        let feature5 = try #require(MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry5,
            ofType: .polygon,
            projectionFunction: MVTDecoder.passThroughFromTile))
        let polygon5: Polygon = try #require(feature5.geometry as? Polygon)
        let boundingBox5: BoundingBox = try #require(feature5.boundingBox)
        let result5 = try #require(Polygon([[
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
            Coordinate3D(x: 8.0, y: 12.0, projection: .noSRID),
            Coordinate3D(x: 20.0, y: 34.0, projection: .noSRID),
            Coordinate3D(x: 3.0, y: 6.0, projection: .noSRID),
        ]]))
        #expect(polygon5 == result5)
        #expect(boundingBox5 == result5.calculateBoundingBox())

        // MultiPolygon
        let geometry6: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        let feature6 = try #require(MVTDecoder.convertToLayerFeature(
            geometryIntegers: geometry6,
            ofType: .polygon,
            projectionFunction: MVTDecoder.passThroughFromTile))
        let multiPolygon6: MultiPolygon = try #require(feature6.geometry as? MultiPolygon)
        let boundingBox6: BoundingBox = try #require(feature6.boundingBox)
        let result6 = try #require(MultiPolygon([[[
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
        ]]]))
        #expect(multiPolygon6 == result6)
        #expect(boundingBox6 == result6.calculateBoundingBox())
    }

}
