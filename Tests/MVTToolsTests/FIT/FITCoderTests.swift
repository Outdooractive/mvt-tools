import Foundation
import GISTools
import GISToolsFIT
@testable import MVTTools
import Testing

struct VectorTileFITTests {

    // MARK: - Helpers

    private static func makeSampleFitData() -> Data {
        let feature = sampleTrackFeature()
        var fc = FeatureCollection([feature])

        let device: [String: Sendable] = [
            "manufacturer": 1,
            "product": 0,
            "type": 4,
        ]
        fc.foreignMembers["fit_device"] = device

        let activity: [String: Sendable] = [
            "type": 0,
            "num_sessions": 1,
        ]
        fc.foreignMembers["fit_activity"] = activity

        return try! fc.fitData()
    }

    private static func sampleTrackFeature() -> Feature {
        let coords: [Coordinate3D] = [
            Coordinate3D(latitude: 10.0, longitude: 20.0, altitude: 100.0),
            Coordinate3D(latitude: 10.001, longitude: 20.001, altitude: 110.0),
            Coordinate3D(latitude: 10.002, longitude: 20.002, altitude: 120.0),
        ]
        let multiLine = MultiLineString(unchecked: [LineString(unchecked: coords)])

        var feature = Feature(multiLine)
        feature.properties["fit_type"] = "record"
        feature.properties["heart_rate"] = 120
        feature.properties["power"] = 250
        feature.properties["sport"] = "Cycling"
        feature.properties["total_distance"] = Double(1000.0)
        feature.properties["total_calories"] = Int(50)
        feature.properties["total_elapsed_time"] = Double(300.0)
        feature.properties["start_time"] = UInt32(1_000_000)

        feature.properties["fit_heart_rates"] = [120, 125, 130]
        feature.properties["fit_cadences"] = [80, 85, 90]
        feature.properties["fit_powers"] = [200, 250, 280]
        feature.properties["fit_speeds"] = [5.0, 5.5, 6.0]
        feature.properties["fit_temperatures"] = [22.0, 23.0, 24.0]

        return feature
    }

    // MARK: - VectorTile+FIT convenience API

    @Test
    func fitDataInit() throws {
        let data = Self.makeSampleFitData()
        let tile = try #require(VectorTile(
            fitData: data,
            indexed: nil))
        #expect(tile.origin == .fit)
        #expect(tile.layers.isEmpty == false)
    }

    @Test
    func fitContentsOfAndWrite() throws {
        let data = Self.makeSampleFitData()
        let tile = try #require(VectorTile(fitData: data))

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fit_\(UUID().uuidString).fit")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        #expect(tile.writeFIT(to: tempUrl))
        #expect(FileManager.default.fileExists(atPath: tempUrl.path))

        let readTile = try #require(VectorTile(contentsOfFIT: tempUrl))
        #expect(readTile.origin == .fit)
        #expect(readTile.layers.isEmpty == false)
    }

    @Test
    func fitToFitDataRoundtrip() throws {
        let data = Self.makeSampleFitData()
        let tile = try #require(VectorTile(fitData: data))

        let exported = try #require(tile.toFitData())
        #expect(exported.isEmpty == false)

        let reimported = try #require(VectorTile(fitData: exported))
        #expect(reimported.origin == .fit)
        let reCount = reimported.layers.values.reduce(0) { $0 + $1.features.count }
        #expect(reCount > 0)
    }

    // MARK: - Cross-format roundtrips

    @Test
    func fitToGeoJsonRoundtrip() throws {
        let data = Self.makeSampleFitData()
        let tile = try #require(VectorTile(fitData: data))

        let geojson = try #require(tile.toGeoJson())
        #expect(geojson.isEmpty == false)

        let reimported = try #require(VectorTile(geoJsonData: geojson, indexed: nil))
        #expect(reimported.layers.isEmpty == false)
    }

    @Test
    func fitToGpxRoundtrip() throws {
        let data = Self.makeSampleFitData()
        let tile = try #require(VectorTile(fitData: data))

        let gpx = try #require(tile.toGpxData())
        #expect(gpx.isEmpty == false)

        let reimported = try #require(VectorTile(gpxData: gpx, indexed: nil))
        #expect(reimported.layers.isEmpty == false)
    }

}
