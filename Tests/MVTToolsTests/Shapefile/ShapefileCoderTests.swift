import Foundation
import GISTools
import GISToolsShapefile
@testable import MVTTools
import Testing

struct VectorTileShapefileTests {

    // MARK: - VectorTile+Shapefile convenience API

    @Test
    func shapefileInit() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shapefileUrl = tempDir.appendingPathComponent("test_points")
        let points = [
            Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1)),
            Feature(Point(Coordinate3D(latitude: 30.0, longitude: 40.0)), id: .int(2)),
        ]
        let fc = FeatureCollection(points)
        try ShapefileCoder.write(fc, to: shapefileUrl)

        let tile = try #require(VectorTile(
            shapefile: shapefileUrl.appendingPathExtension("shp")))
        #expect(tile.origin == .shapefile)
        #expect(tile.layerNames == ["test_points"])
        #expect(tile.features(for: "test_points").count == 2)
    }

    @Test
    func shapefileWriteSingle() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        tile.setFeatures([point], for: "test_layer")

        let outputUrl = tempDir.appendingPathComponent("output")
        try tile.writeShapefile(to: outputUrl, layerName: "test_layer")
        #expect(FileManager.default.fileExists(atPath: outputUrl.appendingPathExtension("shp").path))
        #expect(FileManager.default.fileExists(atPath: outputUrl.appendingPathExtension("dbf").path))

        let readTile = try #require(VectorTile(shapefile: outputUrl.appendingPathExtension("shp")))
        #expect(readTile.origin == .shapefile)
        #expect(readTile.layers.values.reduce(0) { $0 + $1.features.count } == 1)
    }

    @Test
    func shapefileWritePerLayer() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")

        let outDir = tempDir.appendingPathComponent("layers")
        try tile.writeShapefiles(to: outDir)
        #expect(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("points.shp").path))
        #expect(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("lines.shp").path))
    }

    @Test
    func shapefileMixedGeometryError() throws {
        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)_mixed")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        #expect(throws: ShapefileError.mixedGeometry(types: [.point, .lineString])) {
            try tile.writeShapefile(to: tempUrl)
        }
    }

}
