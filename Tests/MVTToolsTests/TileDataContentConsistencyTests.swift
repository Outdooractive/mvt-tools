import Foundation
import GISTools
@testable import MVTTools
import Testing

struct TileDataContentConsistencyTests {

    /// Expand multi-geometry features into individual single-geometry features.
    private func flattenedFeatures(_ features: [Feature]) -> [Feature] {
        FeatureCollection(features).flattened?.features ?? features
    }

    // MARK: - Layer structure: all three formats

    @Test
    func mvtAndMltHaveSameLayers() throws {
        let mvtData = try TestData.dataFromFile(name: "14_8657_5725.pbf")
        let mltData = try TestData.dataFromFile(name: "14_8657_5725.mlt")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let mltTile = try #require(VectorTile(mltData: mltData, x: 8657, y: 5725, z: 14))

        #expect(mvtTile.layerNames.sorted() == mltTile.layerNames.sorted())

        for layerName in mvtTile.layerNames {
            #expect(mvtTile.features(for: layerName).count == mltTile.features(for: layerName).count,
                    "Feature count mismatch in layer '\(layerName)'")
        }
    }

    // MARK: - Total feature counts (accounting for multi-geometry flattening)

    @Test
    func rawCountsMatchBetweenMvtAndMlt() throws {
        let mvtData = try TestData.dataFromFile(name: "14_8657_5725.pbf")
        let mltData = try TestData.dataFromFile(name: "14_8657_5725.mlt")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let mltTile = try #require(VectorTile(mltData: mltData, x: 8657, y: 5725, z: 14))

        let mvtTotal = mvtTile.layers.values.reduce(0) { $0 + $1.features.count }
        let mltTotal = mltTile.layers.values.reduce(0) { $0 + $1.features.count }

        #expect(mvtTotal == mltTotal,
                "MVT (\(mvtTotal)) vs MLT (\(mltTotal)) raw counts differ")
    }

    @Test
    func flattenedCountsMatchBetweenMvtAndGeoJson() throws {
        let mvtData = try TestData.dataFromFile(name: "14_8657_5725.pbf")
        let geoJsonData = try TestData.dataFromFile(name: "14_8657_5725.geojson")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let geoJsonTile = try #require(VectorTile(geoJsonData: geoJsonData, layerProperty: "vt_layer"))

        let mvtRaw = mvtTile.layers.values.reduce(0) { $0 + $1.features.count }
        let mvtFlat = mvtTile.layerNames.reduce(0) { $0 + flattenedFeatures(mvtTile.features(for: $1)).count }
        let geoJsonTotal = geoJsonTile.layers.values.reduce(0) { $0 + $1.features.count }

        // GeoJSON init flattens multi-geometries, so compare with flattened MVT
        #expect(mvtFlat == geoJsonTotal,
                "MVT raw=\(mvtRaw), MVT flattened=\(mvtFlat), GeoJSON=\(geoJsonTotal)")
    }

}
