#if EnableMLT
import Foundation
import GISTools
@testable import MVTTools
import Testing

struct MLTRoundtripConvenienceTests {

    // MARK: - VectorTile+MLT convenience API

    @Test
    func mltDataInitAndExport() throws {
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 48.8566, longitude: 2.3522),
            Coordinate3D(latitude: 52.5200, longitude: 13.4050),
        ])!, id: .int(2))

        guard let originalData = MLTEncoder.encode(
            layers: [
                "points": VectorTile.LayerContainer(features: [point], boundingBox: nil),
                "lines": VectorTile.LayerContainer(features: [line], boundingBox: nil),
            ],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }

        let tile = try VectorTile(
            mltData: originalData,
            x: 0, y: 0, z: 0,
            projection: .epsg4326)
        #expect(tile.origin == .mlt)
        #expect(tile.layerNames.count == 2)
        #expect(tile.layerNames.contains("points"))
        #expect(tile.layerNames.contains("lines"))

        let reencoded = try #require(tile.mltData())
        #expect(reencoded.isEmpty == false)

        let decoded = try MLTDecoder.decode(
            from: reencoded, x: 0, y: 0, z: 0, projection: .epsg4326)
        #expect(decoded["points"]?.features.count == 1)
        #expect(decoded["lines"]?.features.count == 1)
    }

    @Test
    func mltContentsOfAndWrite() throws {
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [point], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let writeTile = try VectorTile(
            mltData: data,
            x: 0, y: 0, z: 0,
            projection: .epsg4326)
        #expect(writeTile.writeMLT(to: tempUrl))

        let readTile = try VectorTile(
            contentsOfMLT: tempUrl,
            x: 0, y: 0, z: 0,
            projection: .epsg4326)
        #expect(readTile.origin == .mlt)
        #expect(readTile.layerNames == ["test"])
    }

    @Test
    func mltContentsOfWithTile() throws {
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [point], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let tile = try VectorTile(
            mltData: data,
            x: 0, y: 0, z: 0,
            projection: .epsg4326)
        #expect(tile.writeMLT(to: tempUrl))

        let mapTile = MapTile(x: 0, y: 0, z: 0)
        let readTile = try VectorTile(
            contentsOfMLT: tempUrl,
            tile: mapTile,
            projection: .epsg4326)
        #expect(readTile.origin == .mlt)
        #expect(readTile.layerNames == ["test"])
        #expect(readTile.x == 0)
        #expect(readTile.y == 0)
        #expect(readTile.z == 0)
    }

    // MARK: - Cross-format roundtrip (MVT ↔ MLT)

    @Test
    func mvtToMltRoundtrip() throws {
        let mvtData = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")

        let mvtTile = try VectorTile(
            mvtData: mvtData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        #expect(mvtTile.origin == .mvt)
        #expect(mvtTile.layers.isEmpty == false)

        guard let mltData = MLTEncoder.encode(
            layers: mvtTile.layers,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        else { return }

        let mltTile = try VectorTile(
            mltData: mltData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        #expect(mltTile.origin == .mlt)
        #expect(mltTile.layers.isEmpty == false)

        let mvt2Data = try #require(mltTile.mvtData())
        let mvt2Tile = try VectorTile(
            mvtData: mvt2Data,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        #expect(mvt2Tile.origin == .mvt)
        #expect(mvt2Tile.layers.isEmpty == false)
    }

    @Test
    func mltToMvtRoundtrip() throws {
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 48.8566, longitude: 2.3522),
            Coordinate3D(latitude: 52.5200, longitude: 13.4050),
        ])!, id: .int(2))

        guard let mltData = MLTEncoder.encode(
            layers: [
                "points": VectorTile.LayerContainer(features: [point], boundingBox: nil),
                "lines": VectorTile.LayerContainer(features: [line], boundingBox: nil),
            ],
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        else { return }

        let mltTile = try VectorTile(
            mltData: mltData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)

        let mvtData = try #require(mltTile.mvtData())

        let mvtTile = try VectorTile(
            mvtData: mvtData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        #expect(mvtTile.origin == .mvt)
        #expect(mvtTile.layers.keys == mltTile.layers.keys)

        for (name, container) in mvtTile.layers {
            let originalContainer = try #require(mltTile.layers[name])
            #expect(container.features.count == originalContainer.features.count,
                    "Layer '\(name)' feature count mismatch")
        }
    }

}

#endif
