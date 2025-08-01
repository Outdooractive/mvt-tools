#if !os(Linux)
    import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

struct VectorTileTests {

    @Test
    func loadMvt() async throws {
        let tileLayerNames: [String] = ["landuse", "waterway", "water", "aeroway", "barrier_line", "building", "landuse_overlay", "tunnel", "road", "bridge", "admin", "country_label_line", "country_label", "marine_label", "state_label", "place_label", "water_label", "area_label", "rail_station_label", "airport_label", "road_label", "waterway_label", "building_label"].sorted()

        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let layerNames = VectorTile.layerNames(from: mvt)?.sorted()
        #expect(layerNames == tileLayerNames)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))
        #expect(tile.layerNames.sorted() == tileLayerNames)

        let _ = try #require(tile.toGeoJson(prettyPrinted: true))

        let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        let resultLayerNames: [String] = Set(result.map({ $0.layerName })).sorted()
        #expect(resultLayerNames == ["barrier_line", "building", "building_label", "landuse", "road", "road_label"])
    }

    @Test
    func writeMvt() async throws {
        var tile = try #require(VectorTile(x: 8716, y: 8015, z: 14))

        var feature = Feature(Point(Coordinate3D(latitude: 3.870163, longitude: 11.518585)))
        feature.properties = [
            "test": 1,
            "test2": 5.567,
            "test3": [1, 2, 3],
            "test4": [
                "sub1": 1,
                "sub2": 2,
            ],
        ]

        tile.setFeatures([feature], for: "test")
        let _ = try #require(tile.data())
    }

    @Test
    func tileInfo() async throws {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = try TestData.dataFromFile(name: tileName)
        #expect(mvt.isEmpty == false)

        let layers = try #require(VectorTile.tileInfo(from: mvt))
        #expect(layers.count == 23)
    }

    @Test
    func merge() async throws {
        var tile1 = try #require(VectorTile(x: 0, y: 0, z: 0))
        var tile2 = try #require(VectorTile(x: 0, y: 0, z: 0))
        var tile3 = try #require(VectorTile(x: 0, y: 0, z: 0))

        #expect(tile1.features(for: "test1").count == 0)
        #expect(tile1.features(for: "test2").count == 0)

        let feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        let feature2 = Feature(Point(Coordinate3D(latitude: -10.0, longitude: -10.0)))

        tile1.appendFeatures([feature1], to: "test1")
        tile2.appendFeatures([feature2], to: "test1")
        tile3.appendFeatures([feature2], to: "test2")

        #expect(tile1.features(for: "test1").count == 1)
        let tile1and2mergeResult = tile1.merge(tile2)
        #expect(tile1and2mergeResult)
        #expect(tile1.features(for: "test1").count == 2)

        #expect(tile1.features(for: "test2").count == 0)
        let tile1and3mergeResult = tile1.merge(tile3)
        #expect(tile1and3mergeResult)
        #expect(tile1.features(for: "test1").count == 2)
        #expect(tile1.features(for: "test2").count == 1)
    }

    @Test
    func encodeDecodeBigInt() async throws {
        let feature = try #require(Feature(jsonData: TestData.dataFromFile(name: "bigint_id.geojson")))
        #expect(feature.id == .uint(18_446_744_073_638_380_036))

        var tile = try #require(VectorTile(x: 10, y: 25, z: 6))
        tile.setFeatures([feature], for: "test")
        let tileData = try #require(tile.data())
        #expect(tileData.isEmpty == false)

        let tile2 = try #require(VectorTile(data: tileData, x: 10, y: 25, z: 6))
        let feature2: Feature = try #require(tile2.features(for: "test").first)

        #expect(feature.id == feature2.id)
    }

}
