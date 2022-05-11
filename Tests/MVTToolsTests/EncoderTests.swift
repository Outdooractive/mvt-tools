#if !os(Linux)
import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
import XCTest

@testable import MVTTools

final class EncoderTests: XCTestCase {

    func testFeatureGeometryEncoder() {
        // Point
        let point = Coordinate3D(latitude: 17.0, longitude: 25.0)
        let pointGeometryIntegers = VectorTile.geometryIntegers(fromMultiCoordinates: [[point]], ofType: .point, projectionFunction: VectorTile.passThroughToTile())
        let pointResult: [UInt32] = [9, 50, 34]
        XCTAssertEqual(pointGeometryIntegers, pointResult)

        // MultiPoint
        let multiPoint = [
            [Coordinate3D(latitude: 7.0, longitude: 5.0)],
            [Coordinate3D(latitude: 2.0, longitude: 3.0)]
        ]
        let multiPointGeometryIntegers = VectorTile.geometryIntegers(fromMultiCoordinates: multiPoint, ofType: .point, projectionFunction: VectorTile.passThroughToTile())
        let multiPointResult: [UInt32] = [17, 10, 14, 3, 9]
        XCTAssertEqual(multiPointGeometryIntegers, multiPointResult)

        // Linestring
        let lineString = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            ]]
        let lineStringGeometryIntegers = VectorTile.geometryIntegers(fromMultiCoordinates: lineString, ofType: .linestring, projectionFunction: VectorTile.passThroughToTile())
        let lineStringResult: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        XCTAssertEqual(lineStringGeometryIntegers, lineStringResult)

        // MultiLinestring
        let multiLineString = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0)
            ], [
                Coordinate3D(latitude: 1.0, longitude: 1.0),
                Coordinate3D(latitude: 5.0, longitude: 3.0),
            ]]
        let multiLineStringGeometryIntegers = VectorTile.geometryIntegers(fromMultiCoordinates: multiLineString, ofType: .linestring, projectionFunction: VectorTile.passThroughToTile())
        let multiLineStringResult: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        XCTAssertEqual(multiLineStringGeometryIntegers, multiLineStringResult)

        // Polygon
        let polygon = [[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            ]]
        let polygonGeometryIntegers = VectorTile.geometryIntegers(fromMultiCoordinates: polygon, ofType: .polygon, projectionFunction: VectorTile.passThroughToTile())
        let polygonResult: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        XCTAssertEqual(polygonGeometryIntegers, polygonResult)

        // MultiPolygon
        let multiPolygon = [[
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
        let multiPolygonGeometryIntegers = VectorTile.geometryIntegers(fromMultiCoordinates: multiPolygon, ofType: .polygon, projectionFunction: VectorTile.passThroughToTile())
        let multiPolygonResult: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        XCTAssertEqual(multiPolygonGeometryIntegers, multiPolygonResult)
    }

    func testFeatureConversion() {
        // Point
        let point = Feature(Point(Coordinate3D(latitude: 17.0, longitude: 25.0)))
        let pointFeature = VectorTile.vectorTileFeature(from: point, projectionFunction: VectorTile.passThroughToTile())
        XCTAssertNotNil(pointFeature, "Failed to encode a POINT")

        let pointGeometry: [UInt32] = [9, 50, 34]
        XCTAssertEqual(pointFeature?.geometry, pointGeometry)
        XCTAssertEqual(pointFeature?.type, VectorTile_Tile.GeomType.point)

        // MultiPoint
        let multiPoint = Feature(MultiPoint([
            Coordinate3D(latitude: 7.0, longitude: 5.0),
            Coordinate3D(latitude: 2.0, longitude: 3.0)
        ])!)
        let multiPointFeature = VectorTile.vectorTileFeature(from: multiPoint, projectionFunction: VectorTile.passThroughToTile())
        XCTAssertNotNil(multiPointFeature, "Failed to encode a MULTIPOINT")

        let multiPointGeometry: [UInt32] = [17, 10, 14, 3, 9]
        XCTAssertEqual(multiPointFeature?.geometry, multiPointGeometry)
        XCTAssertEqual(multiPointFeature?.type, VectorTile_Tile.GeomType.point)

        // Linestring
        let lineString = Feature(LineString([
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ])!)
        let lineStringFeature = VectorTile.vectorTileFeature(from: lineString, projectionFunction: VectorTile.passThroughToTile())
        XCTAssertNotNil(lineStringFeature, "Failed to encode a LINESTRING")

        let lineStringGeometry: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        XCTAssertEqual(lineStringFeature?.geometry, lineStringGeometry)
        XCTAssertEqual(lineStringFeature?.type, VectorTile_Tile.GeomType.linestring)

        // MultiLinestring
        let multiLineString = Feature(MultiLineString([[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0)
            ], [
                Coordinate3D(latitude: 1.0, longitude: 1.0),
                Coordinate3D(latitude: 5.0, longitude: 3.0),
            ]])!)
        let multiLineStringFeature = VectorTile.vectorTileFeature(from: multiLineString, projectionFunction: VectorTile.passThroughToTile())
        XCTAssertNotNil(multiLineStringFeature, "Failed to encode a MULTILINESTRING")

        let multiLineStringGeometry: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        XCTAssertEqual(multiLineStringFeature?.geometry, multiLineStringGeometry)
        XCTAssertEqual(multiLineStringFeature?.type, VectorTile_Tile.GeomType.linestring)

        // Polygon
        let polygon = Feature(Polygon([[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            ]])!)
        let polygonFeature = VectorTile.vectorTileFeature(from: polygon, projectionFunction: VectorTile.passThroughToTile())
        XCTAssertNotNil(polygonFeature, "Failed to encode a POLYGON")

        let polygonGeometry: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        XCTAssertEqual(polygonFeature?.geometry, polygonGeometry)
        XCTAssertEqual(polygonFeature?.type, VectorTile_Tile.GeomType.polygon)

        // MultiPolygon
        let multiPolygon = Feature(MultiPolygon([[[
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
                ]]])!)
        let multiPolygonFeature = VectorTile.vectorTileFeature(from: multiPolygon, projectionFunction: VectorTile.passThroughToTile())
        XCTAssertNotNil(polygonFeature, "Failed to encode a MULTIPOLYGON")

        let multiPolygonGeometry: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        XCTAssertEqual(multiPolygonFeature?.geometry, multiPolygonGeometry)
        XCTAssertEqual(multiPolygonFeature?.type, VectorTile_Tile.GeomType.polygon)
    }

    func testEncodeDecode() {
        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Point(Coordinate3D(latitude: 25.0, longitude: 25.0))
        tile.addGeoJson(geoJson: point, layerName: "test")

        let features = tile.features(for: "test")!
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].geometry as! Point, point)

        let tileData = tile.data()!
        let decodedTile = VectorTile(data: tileData, x: 0, y: 0, z: 0)!

        let decodedTileFeatures = decodedTile.features(for: "test")!
        XCTAssertEqual(decodedTileFeatures.count, 1)
        XCTAssertEqual((decodedTileFeatures[0].geometry as! Point).coordinate.latitude, 25, accuracy: 0.1)
        XCTAssertEqual((decodedTileFeatures[0].geometry as! Point).coordinate.longitude, 25, accuracy: 0.1)
    }

    func testCompressOption() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }
        guard let compressed = tile.data(options: VectorTileExportOptions(compression: true)) else {
            XCTAssert(false, "Unable to get compressed tile data")
            return
        }

        XCTAssertTrue(compressed.isGzipped)
        XCTAssertLessThan(compressed.count, mvt.count, "Compressed tile should be smaller")
    }

    func testBufferSizeOption() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14, layerWhitelist: ["building_label"]) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        let bufferedTileData = tile.data(options: VectorTileExportOptions(bufferSize: 0))!
        let bufferedTile = VectorTile(data: bufferedTileData, x: 8716, y: 8015, z: 14)!

        let features: [Point] = bufferedTile.features(for: "building_label")!.compactMap({ $0.geometry as? Point })
        let bounds = Projection.epsg4236TileBounds(x: 8716, y: 8015, z: 14)

        XCTAssertGreaterThan(features.count, 0)
        XCTAssertTrue(features.allSatisfy({ bounds.contains($0.coordinate) }))
    }

    func testSimplifyOption() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

    }

    static var allTests = [
        ("testFeatureGeometryEncoder", testFeatureGeometryEncoder),
        ("testFeatureConversion", testFeatureConversion),
        ("testCompressOption", testCompressOption),
        ("testBufferSizeOption", testBufferSizeOption),
        ("testSimplifyOption", testSimplifyOption),
    ]

}

fileprivate extension Data {

    func utf8EncodedString() -> String? {
        String(data: self, encoding: .utf8)
    }

}
