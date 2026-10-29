#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
@testable import MVTTools
import Testing

/// Tests for file-based convenience initializers and their error paths.
struct FormatConvenienceTests {

    private var missingURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing_\(UUID().uuidString)")
    }

    private func writeTemporary(_ data: Data, extension ext: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("convenience_\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }

    // MARK: - MVT

    #if EnableMVT
    @Test
    func mvtContentsOfMissingFileThrows() {
        let url = missingURL.appendingPathExtension("mvt")
        #expect(throws: VectorTileError.self) {
            try VectorTile(contentsOfMVT: url, x: 0, y: 0, z: 0)
        }
    }
    #endif

    #if EnableMVT
    @Test
    func mvtContentsOfInvalidDataThrows() throws {
        let url = try writeTemporary(Data([0xFF, 0xFF]), extension: "mvt")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: VectorTileError.self) {
            try VectorTile(contentsOfMVT: url, x: 0, y: 0, z: 0)
        }
    }
    #endif

    #if EnableMVT
    @Test
    func mvtTileOverloadsAndAllowlist() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.setFeatures([
            Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0))),
        ], for: "one")
        tile.setFeatures([
            Feature(Point(Coordinate3D(latitude: 11.0, longitude: 21.0))),
        ], for: "two")

        let url = try writeTemporary(try #require(tile.mvtData()), extension: "mvt")
        defer { try? FileManager.default.removeItem(at: url) }

        let mapTile = MapTile(x: 0, y: 0, z: 0)
        let loaded = try VectorTile(
            contentsOfMVT: url,
            tile: mapTile,
            indexed: .hilbert,
            layerAllowlist: ["one"])

        #expect(loaded.x == 0)
        #expect(loaded.y == 0)
        #expect(loaded.z == 0)
        #expect(loaded.isIndexed)
        #expect(loaded.layerNames == ["one"])
        #expect(loaded.features(for: "one").count == 1)
    }
    #endif

    #if EnableMVT
    @Test
    func mvtDataInitWithTileAndAllowlist() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.setFeatures([
            Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0))),
        ], for: "one")
        tile.setFeatures([
            Feature(Point(Coordinate3D(latitude: 11.0, longitude: 21.0))),
        ], for: "two")

        let data = try #require(tile.mvtData())
        let loaded = try VectorTile(
            mvtData: data,
            tile: MapTile(x: 0, y: 0, z: 0),
            indexed: .hilbert,
            layerAllowlist: ["two"])

        #expect(loaded.isIndexed)
        #expect(loaded.layerNames == ["two"])
    }
    #endif

    #if EnableMVT
    @Test
    func writeMVTToDirectoryFails() throws {
        let tile = try VectorTile(x: 0, y: 0, z: 0)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_write_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(tile.writeMVT(to: directory) == false)
    }
    #endif

    // MARK: - MLT

    #if EnableMLT
    @Test
    func mltContentsOfMissingFileThrows() {
        let url = missingURL.appendingPathExtension("mlt")
        #expect(throws: VectorTileError.self) {
            try VectorTile(contentsOfMLT: url, x: 0, y: 0, z: 0)
        }
    }

    @Test
    func mltContentsOfInvalidDataThrows() throws {
        let url = try writeTemporary(Data([0x00, 0x01, 0x02]), extension: "mlt")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: VectorTileError.self) {
            try VectorTile(contentsOfMLT: url, x: 0, y: 0, z: 0)
        }
    }

    @Test
    func mltDataInitWithTileAndAllowlist() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.setFeatures([
            Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0))),
        ], for: "one")
        tile.setFeatures([
            Feature(Point(Coordinate3D(latitude: 11.0, longitude: 21.0))),
        ], for: "two")

        let data = try #require(tile.mltData())
        let loaded = try VectorTile(
            mltData: data,
            tile: MapTile(x: 0, y: 0, z: 0),
            indexed: .hilbert,
            layerAllowlist: ["two"])

        #expect(loaded.isIndexed)
        #expect(loaded.layerNames == ["two"])
    }

    @Test
    func writeMLTToDirectoryFails() throws {
        let tile = try VectorTile(x: 0, y: 0, z: 0)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_write_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(tile.writeMLT(to: directory) == false)
    }
    #endif

    // MARK: - GeoJSON

    @Test
    func geoJsonContentsOfMissingFileThrows() {
        let url = missingURL.appendingPathExtension("geojson")
        #expect(throws: VectorTileError.self) {
            try VectorTile(contentsOfGeoJson: url)
        }
    }

    @Test
    func geoJsonInvalidDataThrows() throws {
        let url = try writeTemporary(Data("not json".utf8), extension: "geojson")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: VectorTileError.self) {
            try VectorTile(contentsOfGeoJson: url)
        }
    }

    @Test
    func geoJsonEmptyCollectionThrows() {
        let data = Data(#"{"type":"FeatureCollection","features":[]}"#.utf8)
        #expect(throws: VectorTileError.self) {
            try VectorTile(geoJsonData: data)
        }
    }
}
