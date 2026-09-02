#if EnableCSV
import Foundation
import GISTools
import GISToolsCSV
@testable import MVTTools
import Testing

struct VectorTileCSVTests {

    // MARK: - VectorTile+CSV convenience API

    private static let csvPoints: String = """
    id,longitude,latitude,altitude,name
    1,11.518585,48.135125,520.0,Marienplatz
    2,13.376111,52.518611,35.0,Reichstag
    """

    @Test
    func csvDataInit() throws {
        let data = try #require(Self.csvPoints.data(using: .utf8))
        let tile = try VectorTile(
            csvData: data,
            indexed: nil)
        #expect(tile.origin == .csv)
        #expect(tile.layers.keys.contains("Layer-0"),
                "CSV features should be in a default layer")
        #expect(tile.layers["Layer-0"]?.features.count == 2)
    }

    @Test
    func csvContentsOfAndWrite() throws {
        let data = try #require(Self.csvPoints.data(using: .utf8))
        let tile = try VectorTile(csvData: data)

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("csv_\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        #expect(tile.writeCSV(to: tempUrl))
        #expect(FileManager.default.fileExists(atPath: tempUrl.path))

        let readTile = try VectorTile(contentsOfCSV: tempUrl)
        #expect(readTile.origin == .csv)
        #expect(readTile.layers.isEmpty == false)
    }

    @Test
    func csvToCsvDataRoundtrip() throws {
        let data = try #require(Self.csvPoints.data(using: .utf8))
        let tile = try VectorTile(csvData: data)

        let exported = try #require(tile.toCsvData())
        #expect(exported.isEmpty == false)

        let reimported = try VectorTile(csvData: exported)
        #expect(reimported.origin == .csv)
        let reCount = reimported.layers.values.reduce(0) { $0 + $1.features.count }
        #expect(reCount == 2)
    }

    @Test
    func csvLayerPropertySplitsLayers() throws {
        let csv = """
        id,longitude,latitude,vt_layer
        1,11.518585,48.135125,alpha
        2,13.376111,52.518611,beta
        """
        let data = try #require(csv.data(using: .utf8))
        let tile = try VectorTile(
            csvData: data,
            layerProperty: "vt_layer")
        #expect(tile.layers.keys.contains("alpha"))
        #expect(tile.layers.keys.contains("beta"))
        #expect(tile.layers["alpha"]?.features.count == 1)
        #expect(tile.layers["beta"]?.features.count == 1)
        // The layer property is stripped after routing.
        #expect(tile.layers["alpha"]?.features.first?.properties["vt_layer"] == nil)
    }

    @Test
    func csvSemicolonDelimiter() throws {
        let csv = """
        id;longitude;latitude;name
        1;11.518585;48.135125;Marienplatz
        """
        let data = try #require(csv.data(using: .utf8))
        let tile = try VectorTile(
            csvData: data,
            readOptions: CSVReadOptions(delimiter: ";"))
        #expect(tile.layers["Layer-0"]?.features.count == 1)
    }

    @Test
    func csvReadAndWriteOptions() throws {
        let csv = """
        id,longitude,latitude,name
        1,11.518585,48.135125,NULL
        """
        let data = try #require(csv.data(using: .utf8))
        let tile = try VectorTile(
            csvData: data,
            readOptions: CSVReadOptions(nullHandling: .omit))
        let feature = try #require(tile.layers["Layer-0"]?.features.first)
        #expect(feature.properties["name"] == nil)

        let exported = try #require(tile.toCsvData(
            writeOptions: CSVWriteOptions(delimiter: ";", lineEnding: .crlf)))
        #expect(String(decoding: exported, as: UTF8.self).contains(";"))
        #expect(String(decoding: exported, as: UTF8.self).contains("\r\n"))
    }

}

#endif
