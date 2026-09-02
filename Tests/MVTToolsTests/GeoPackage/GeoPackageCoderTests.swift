#if EnableGeoPackage
import Foundation
import GISTools
import GISToolsGeoPackage
@testable import MVTTools
import Testing

struct VectorTileGeoPackageTests {

    // MARK: - VectorTile+GeoPackage convenience API

    @Test
    func geopackageInitTable() async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        tile.setFeatures([point], for: "test_table")
        try await tile.writeGeoPackage(to: tempUrl, table: "test_table")

        let imported = try await VectorTile(geopackage: tempUrl, table: "test_table")
        #expect(imported.origin == .geopackage)
        #expect(imported.layerNames == ["test_table"])
        #expect(imported.features(for: "test_table").count == 1)
    }

    @Test
    func geopackageInitAll() async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")
        try await tile.writeGeoPackage(to: tempUrl)

        let imported = try await VectorTile(geopackage: tempUrl)
        #expect(imported.origin == .geopackage)
        #expect(imported.layerNames.contains("points"))
        #expect(imported.layerNames.contains("lines"))
    }

    @Test
    func geopackageWritePerLayer() async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")
        try await tile.writeGeoPackage(to: tempUrl)

        let conn = try GeoPackageConnection(url: tempUrl)
        let contents = try await conn.readContents()
        await conn.close()
        let tables = contents.filter { $0.dataType == "features" }.map(\.tableName)
        #expect(tables.contains("points"))
        #expect(tables.contains("lines"))
    }

    @Test
    func geopackageRoundtripWithGpkgLayer() async throws {
        // Export two layers merged into one table, then import and verify
        // the "gpkg_layer" property restores the original layer structure.
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")

        // Export merged to a single table.
        try await tile.writeGeoPackage(to: tempUrl, table: "merged")

        // Import back — "gpkg_layer" should split into the original layers.
        let imported = try await VectorTile(geopackage: tempUrl, table: "merged")
        #expect(imported.origin == .geopackage)
        #expect(imported.layerNames.contains("points"))
        #expect(imported.layerNames.contains("lines"))
        #expect(imported.features(for: "points").count == 1)
        #expect(imported.features(for: "lines").count == 1)
        // The "gpkg_layer" property should be stripped from the features.
        for feat in imported.features(for: "points") {
            #expect(feat.properties["gpkg_layer"] == nil)
        }
        for feat in imported.features(for: "lines") {
            #expect(feat.properties["gpkg_layer"] == nil)
        }
    }

}

#endif
