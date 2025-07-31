#if !os(Linux)
    import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

struct MVTEncoderTests {

    @Test
    func featureGeometryEncoder() {
        // Point
        let point = Coordinate3D(latitude: 17.0, longitude: 25.0)
        let pointGeometryIntegers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: [[point]],
            ofType: .point,
            projectionFunction: MVTEncoder.passThroughToTile())
        let pointResult: [UInt32] = [9, 50, 34]
        #expect(pointGeometryIntegers == pointResult)

        // MultiPoint
        let multiPoint = [
            [Coordinate3D(latitude: 7.0, longitude: 5.0)],
            [Coordinate3D(latitude: 2.0, longitude: 3.0)],
        ]
        let multiPointGeometryIntegers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: multiPoint,
            ofType: .point,
            projectionFunction: MVTEncoder.passThroughToTile())
        let multiPointResult: [UInt32] = [17, 10, 14, 3, 9]
        #expect(multiPointGeometryIntegers == multiPointResult)

        // Linestring
        let lineString = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ]]
        let lineStringGeometryIntegers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: lineString,
            ofType: .linestring,
            projectionFunction: MVTEncoder.passThroughToTile())
        let lineStringResult: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        #expect(lineStringGeometryIntegers == lineStringResult)

        // MultiLinestring
        let multiLineString = [[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ], [
            Coordinate3D(latitude: 1.0, longitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 3.0),
        ]]
        let multiLineStringGeometryIntegers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: multiLineString,
            ofType: .linestring,
            projectionFunction: MVTEncoder.passThroughToTile())
        let multiLineStringResult: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        #expect(multiLineStringGeometryIntegers == multiLineStringResult)

        // Polygon
        let polygon = [[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
        ]]
        let polygonGeometryIntegers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: polygon,
            ofType: .polygon,
            projectionFunction: MVTEncoder.passThroughToTile())
        let polygonResult: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        #expect(polygonGeometryIntegers == polygonResult)

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
        let multiPolygonGeometryIntegers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: multiPolygon,
            ofType: .polygon,
            projectionFunction: MVTEncoder.passThroughToTile())
        let multiPolygonResult: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        #expect(multiPolygonGeometryIntegers == multiPolygonResult)
    }

    @Test
    func featureConversion() async throws {
        // Point
        let point = Feature(Point(Coordinate3D(latitude: 17.0, longitude: 25.0)), id: .int(500))
        let pointFeature = try #require(MVTEncoder.vectorTileFeature(
            from: point,
            projectionFunction: MVTEncoder.passThroughToTile()))
        let pointGeometry: [UInt32] = [9, 50, 34]
        #expect(pointFeature.geometry == pointGeometry)
        #expect(pointFeature.type == VectorTile_Tile.GeomType.point)
        #expect(pointFeature.id == 500)

        // MultiPoint
        let multiPoint = Feature(MultiPoint([
            Coordinate3D(latitude: 7.0, longitude: 5.0),
            Coordinate3D(latitude: 2.0, longitude: 3.0),
        ])!, id: .int(501))
        let multiPointFeature = try #require(MVTEncoder.vectorTileFeature(
            from: multiPoint,
            projectionFunction: MVTEncoder.passThroughToTile()))
        let multiPointGeometry: [UInt32] = [17, 10, 14, 3, 9]
        #expect(multiPointFeature.geometry == multiPointGeometry)
        #expect(multiPointFeature.type == VectorTile_Tile.GeomType.point)
        #expect(multiPointFeature.id == 501)

        // Linestring
        let lineString = Feature(LineString([
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ])!, id: .int(502))
        let lineStringFeature = try #require(MVTEncoder.vectorTileFeature(
            from: lineString,
            projectionFunction: MVTEncoder.passThroughToTile()))
        let lineStringGeometry: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0]
        #expect(lineStringFeature.geometry == lineStringGeometry)
        #expect(lineStringFeature.type == VectorTile_Tile.GeomType.linestring)
        #expect(lineStringFeature.id == 502)

        // MultiLinestring
        let multiLineString = Feature(MultiLineString([[
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 2.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ], [
            Coordinate3D(latitude: 1.0, longitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 3.0),
        ]])!, id: .int(503))
        let multiLineStringFeature = try #require(MVTEncoder.vectorTileFeature(
            from: multiLineString,
            projectionFunction: MVTEncoder.passThroughToTile()))
        let multiLineStringGeometry: [UInt32] = [9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8]
        #expect(multiLineStringFeature.geometry == multiLineStringGeometry)
        #expect(multiLineStringFeature.type == VectorTile_Tile.GeomType.linestring)
        #expect(multiLineStringFeature.id == 503)

        // Polygon
        let polygon = Feature(Polygon([[
            Coordinate3D(latitude: 6.0, longitude: 3.0),
            Coordinate3D(latitude: 12.0, longitude: 8.0),
            Coordinate3D(latitude: 34.0, longitude: 20.0),
            Coordinate3D(latitude: 6.0, longitude: 3.0),
        ]])!, id: .int(504))
        let polygonFeature = try #require(MVTEncoder.vectorTileFeature(
            from: polygon,
            projectionFunction: MVTEncoder.passThroughToTile()))
        let polygonGeometry: [UInt32] = [9, 6, 12, 18, 10, 12, 24, 44, 15]
        #expect(polygonFeature.geometry == polygonGeometry)
        #expect(polygonFeature.type == VectorTile_Tile.GeomType.polygon)
        #expect(polygonFeature.id == 504)

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
        let multiPolygonFeature = try #require(MVTEncoder.vectorTileFeature(
            from: multiPolygon,
            projectionFunction: MVTEncoder.passThroughToTile()))
        let multiPolygonGeometry: [UInt32] = [9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18, 0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15]
        #expect(multiPolygonFeature.geometry == multiPolygonGeometry)
        #expect(multiPolygonFeature.type == VectorTile_Tile.GeomType.polygon)
        #expect(multiPolygonFeature.id == 505)
    }

    @Test
    func encodeDecode() async throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326))
        let point = Feature(Point(Coordinate3D(latitude: 25.0, longitude: 25.0)), id: .int(600))
        tile.addGeoJson(geoJson: point, layerName: "test")

        let features = tile.features(for: "test")
        #expect(features.count == 1)
        #expect(features[0].geometry as! Point == point.geometry as! Point)
        #expect(features[0].id == .int(600))

        let tileData = try #require(tile.data())
        let decodedTile = try #require(VectorTile(data: tileData, x: 0, y: 0, z: 0))

        let decodedTileFeatures = decodedTile.features(for: "test")
        #expect(decodedTileFeatures.count == 1)
        #expect(abs((decodedTileFeatures[0].geometry as! Point).coordinate.latitude - 25) < 0.1)
        #expect(abs((decodedTileFeatures[0].geometry as! Point).coordinate.longitude - 25) < 0.1)
        #expect(decodedTileFeatures[0].id == .int(600))
    }

    @Test
    func compressOption() async throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))
        let compressed = try #require(tile.data(options: .init(compression: .default)))

        #expect(compressed.isGzipped)
        #expect(compressed.count < mvt.count, "Compressed tile should be smaller")
    }

    @Test
    func bufferSizeOption() async throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14, layerWhitelist: ["building_label"]))

        let bufferedTileData = try #require(tile.data(options: .init(bufferSize: .extent(0))))
        let bufferedTile = try #require(VectorTile(data: bufferedTileData, x: 8716, y: 8015, z: 14))

        let features: [Point] = bufferedTile.features(for: "building_label").compactMap({ $0.geometry as? Point })
        let bounds = MapTile(x: 8716, y: 8015, z: 14).boundingBox(projection: .epsg4326)

        #expect(features.count > 0)
        #expect(features.allSatisfy({ bounds.contains($0.coordinate) }))
    }

    @Test
    func simplifyOption() async throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14, layerWhitelist: ["road"]))

        let simplifiedTileData = try #require(tile.data(options: .init(bufferSize: .extent(4096), simplifyFeatures: .extent(1024))))
        let simplifiedTile = try #require(VectorTile(data: simplifiedTileData, x: 8716, y: 8015, z: 14))
        #expect(tile.features(for: "road").count == simplifiedTile.features(for: "road").count)
    }

}

extension Data {

    private func utf8EncodedString() -> String? {
        String(data: self, encoding: .utf8)
    }

}
