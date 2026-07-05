import Foundation
import GISTools
@testable import MVTTools
import Testing

struct VectorTileGPXTests {

    // MARK: - VectorTile+GPX convenience API

    private static let gpxWaypoints: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="test">
      <wpt lat="52.518611" lon="13.376111">
        <ele>35.0</ele>
        <name>Berlin</name>
        <sym>City</sym>
      </wpt>
      <wpt lat="48.8566" lon="2.3522">
        <ele>25.0</ele>
        <name>Paris</name>
        <sym>Landmark</sym>
      </wpt>
    </gpx>
    """

    @Test
    func gpxDataInit() throws {
        let data = try #require(Self.gpxWaypoints.data(using: .utf8))
        let tile = try #require(VectorTile(
            gpxData: data,
            indexed: nil))
        #expect(tile.origin == .gpx)
        #expect(tile.layers.keys.contains("wpt"),
                "GPX features should be in a 'wpt' layer")
        #expect(tile.layers["wpt"]?.features.count == 2)
    }

    @Test
    func gpxContentsOfAndWrite() throws {
        let data = try #require(Self.gpxWaypoints.data(using: .utf8))
        let tile = try #require(VectorTile(gpxData: data))

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpx_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        #expect(tile.writeGPX(to: tempUrl))
        #expect(FileManager.default.fileExists(atPath: tempUrl.path))

        let readTile = try #require(VectorTile(contentsOfGPX: tempUrl))
        #expect(readTile.origin == .gpx)
        #expect(readTile.layers.isEmpty == false)
    }

    @Test
    func gpxToGpxDataRoundtrip() throws {
        let data = try #require(Self.gpxWaypoints.data(using: .utf8))
        let tile = try #require(VectorTile(gpxData: data))

        let exported = try #require(tile.toGpxData())
        #expect(exported.isEmpty == false)

        let reimported = try #require(VectorTile(gpxData: exported))
        #expect(reimported.origin == .gpx)
        let reCount = reimported.layers.values.reduce(0) { $0 + $1.features.count }
        #expect(reCount == 2)
    }

}
