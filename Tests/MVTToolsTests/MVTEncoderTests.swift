#if !os(Linux)
    import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
import XCTest

@testable import MVTTools

final class MVTEncoderTests: XCTestCase {

    func testFeatureGeometryEncoder() {
        // Point
        let point = Coordinate3D(latitude: 17.0, longitude: 25.0)
        let pointGeometryIntegers = MVTEncoder.geometryIntegers(fromMultiCoordinates: [[point]], ofType: .point, projectionFunction: MVTEncoder.passThroughToTile())
        let pointResult: [UInt32] = [9, 50, 34]
        XCTAssertEqual(pointGeometryIntegers, pointResult)

        // MultiPoint
        let multiPoint = [
            [Coordinate3D(latitude: 7.0, longitude: 5.0)],
            [Coordinate3D(latitude: 2.0, longitude: 3.0)],
        ]
        let multiPointGeometryIntegers = MVTEncoder.geometryIntegers(fromMultiCoordinates: multiPoint, ofType: .point, projectionFunction: MVTEncoder.passThroughToTile())
        let multiPointResult: [UInt32] = [17, 10, 14, 3, 9]
        XCTAssertEqual(multiPointGeometryIntegers, multiPointResult)

        // Linestring
        let lineString = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ]]
        let lineStringGeometryIntegers = MVTEncoder.geometryIntegers(fromMultiCoordinates: lineString, ofType: .linestring, projectionFunction: MVTEncoder.passThroughToTile())
        let lineStringResult: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        XCTAssertEqual(lineStringGeometryIntegers, lineStringResult)

        // MultiLinestring
        let multiLineString = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ], [
            Coordinate3D(latitude: 1.0, longitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 3.0),
        ]]
        let multiLineStringGeometryIntegers = MVTEncoder.geometryIntegers(fromMultiCoordinates: multiLineString, ofType: .linestring, projectionFunction: MVTEncoder.passThroughToTile())
        let multiLineStringResult: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        XCTAssertEqual(multiLineStringGeometryIntegers, multiLineStringResult)

        // Polygon
        let polygon = [[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
        ]]
        let polygonGeometryIntegers = MVTEncoder.geometryIntegers(fromMultiCoordinates: polygon, ofType: .polygon, projectionFunction: MVTEncoder.passThroughToTile())
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
        let multiPolygonGeometryIntegers = MVTEncoder.geometryIntegers(fromMultiCoordinates: multiPolygon, ofType: .polygon, projectionFunction: MVTEncoder.passThroughToTile())
        let multiPolygonResult: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        XCTAssertEqual(multiPolygonGeometryIntegers, multiPolygonResult)
    }

    func testFeatureConversion() {
        // Point
        let point = Feature(Point(Coordinate3D(latitude: 17.0, longitude: 25.0)), id: .int(500))
        let pointFeature = MVTEncoder.vectorTileFeature(from: point, projectionFunction: MVTEncoder.passThroughToTile())
        XCTAssertNotNil(pointFeature, "Failed to encode a POINT")

        let pointGeometry: [UInt32] = [9, 50, 34]
        XCTAssertEqual(pointFeature?.geometry, pointGeometry)
        XCTAssertEqual(pointFeature?.type, VectorTile_Tile.GeomType.point)
        XCTAssertEqual(pointFeature?.id, 500)

        // MultiPoint
        let multiPoint = Feature(MultiPoint([
            Coordinate3D(latitude: 7.0, longitude: 5.0),
            Coordinate3D(latitude: 2.0, longitude: 3.0),
        ])!, id: .int(501))
        let multiPointFeature = MVTEncoder.vectorTileFeature(from: multiPoint, projectionFunction: MVTEncoder.passThroughToTile())
        XCTAssertNotNil(multiPointFeature, "Failed to encode a MULTIPOINT")

        let multiPointGeometry: [UInt32] = [17, 10, 14, 3, 9]
        XCTAssertEqual(multiPointFeature?.geometry, multiPointGeometry)
        XCTAssertEqual(multiPointFeature?.type, VectorTile_Tile.GeomType.point)
        XCTAssertEqual(multiPointFeature?.id, 501)

        // Linestring
        let lineString = Feature(LineString([
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ])!, id: .int(502))
        let lineStringFeature = MVTEncoder.vectorTileFeature(from: lineString, projectionFunction: MVTEncoder.passThroughToTile())
        XCTAssertNotNil(lineStringFeature, "Failed to encode a LINESTRING")

        let lineStringGeometry: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        XCTAssertEqual(lineStringFeature?.geometry, lineStringGeometry)
        XCTAssertEqual(lineStringFeature?.type, VectorTile_Tile.GeomType.linestring)
        XCTAssertEqual(lineStringFeature?.id, 502)

        // MultiLinestring
        let multiLineString = Feature(MultiLineString([[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ], [
            Coordinate3D(latitude: 1.0, longitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 3.0),
        ]])!, id: .int(503))
        let multiLineStringFeature = MVTEncoder.vectorTileFeature(from: multiLineString, projectionFunction: MVTEncoder.passThroughToTile())
        XCTAssertNotNil(multiLineStringFeature, "Failed to encode a MULTILINESTRING")

        let multiLineStringGeometry: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        XCTAssertEqual(multiLineStringFeature?.geometry, multiLineStringGeometry)
        XCTAssertEqual(multiLineStringFeature?.type, VectorTile_Tile.GeomType.linestring)
        XCTAssertEqual(multiLineStringFeature?.id, 503)

        // Polygon
        let polygon = Feature(Polygon([[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
        ]])!, id: .int(504))
        let polygonFeature = MVTEncoder.vectorTileFeature(from: polygon, projectionFunction: MVTEncoder.passThroughToTile())
        XCTAssertNotNil(polygonFeature, "Failed to encode a POLYGON")

        let polygonGeometry: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        XCTAssertEqual(polygonFeature?.geometry, polygonGeometry)
        XCTAssertEqual(polygonFeature?.type, VectorTile_Tile.GeomType.polygon)
        XCTAssertEqual(polygonFeature?.id, 504)

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
        ]]])!, id: .int(505))
        let multiPolygonFeature = MVTEncoder.vectorTileFeature(from: multiPolygon, projectionFunction: MVTEncoder.passThroughToTile())
        XCTAssertNotNil(polygonFeature, "Failed to encode a MULTIPOLYGON")

        let multiPolygonGeometry: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        XCTAssertEqual(multiPolygonFeature?.geometry, multiPolygonGeometry)
        XCTAssertEqual(multiPolygonFeature?.type, VectorTile_Tile.GeomType.polygon)
        XCTAssertEqual(multiPolygonFeature?.id, 505)
    }

    func testEncodeDecode() {
        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 25.0, longitude: 25.0)), id: .int(600))
        tile.addGeoJson(geoJson: point, layerName: "test")

        let features = tile.features(for: "test")!
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].geometry as! Point, point.geometry as! Point)
        XCTAssertEqual(features[0].id, .int(600))

        let tileData = tile.data()!
        let decodedTile = VectorTile(data: tileData, x: 0, y: 0, z: 0)!

        let decodedTileFeatures = decodedTile.features(for: "test")!
        XCTAssertEqual(decodedTileFeatures.count, 1)
        XCTAssertEqual((decodedTileFeatures[0].geometry as! Point).coordinate.latitude, 25, accuracy: 0.1)
        XCTAssertEqual((decodedTileFeatures[0].geometry as! Point).coordinate.longitude, 25, accuracy: 0.1)
        XCTAssertEqual(decodedTileFeatures[0].id, .int(600))
    }

    func testCompressOption() {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }
        guard let compressed = tile.data(options: .init(compression: .default)) else {
            XCTAssert(false, "Unable to get compressed tile data")
            return
        }

        XCTAssertTrue(compressed.isGzipped)
        XCTAssertLessThan(compressed.count, mvt.count, "Compressed tile should be smaller")
    }

    func testBufferSizeOption() {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14, layerWhitelist: ["building_label"]) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        let bufferedTileData = tile.data(options: .init(bufferSize: .extent(0)))!
        let bufferedTile = VectorTile(data: bufferedTileData, x: 8716, y: 8015, z: 14)!

        let features: [Point] = bufferedTile.features(for: "building_label")!.compactMap({ $0.geometry as? Point })
        let bounds = MapTile(x: 8716, y: 8015, z: 14).boundingBox(projection: .epsg4326)

        XCTAssertGreaterThan(features.count, 0)
        XCTAssertTrue(features.allSatisfy({ bounds.contains($0.coordinate) }))
    }

    func testSimplifyOption() {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14, layerWhitelist: ["road"]) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        let simplifiedTileData = tile.data(options: .init(bufferSize: .extent(4096), simplifyFeatures: .extent(1024)))!
        let simplifiedTile = VectorTile(data: simplifiedTileData, x: 8716, y: 8015, z: 14)!

        XCTAssertEqual(tile.features(for: "road")!.count, simplifiedTile.features(for: "road")!.count)

//        print(simplifiedTile.toGeoJson(prettyPrinted: true)!.utf8EncodedString() ?? "")
    }

}

extension Data {

    private func utf8EncodedString() -> String? {
        String(data: self, encoding: .utf8)
    }

}
