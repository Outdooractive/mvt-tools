import Foundation
import GISTools
@testable import MVTTools
import Testing

/// Consistency tests comparing the same tile encoded as MVT (`.pbf`), MLT
/// (`.mlt`), and GeoJSON (`.geojson`).
///
/// All three fixtures derive from the same source data but were produced by
/// different pipelines, so the tests are intentionally tolerant of:
/// - Feature ordering within a layer (MVT and MLT may sort differently).
/// - Polygon-vs-MultiPolygon distinctions (MVT collapses both to `polygon` and
///   uses winding-order heuristics to reconstruct; MLT preserves the original
///   database geometry type).
/// - Ring ordering within a polygon (MVT decodes rings in file order; the
///   database may store them in a different order).
/// - Feature IDs (MVT supports string UUIDs; MLT only supports numeric IDs).
struct TileDataContentConsistencyTests {

    // MARK: - Helpers

    /// Expand multi-geometry features into individual single-geometry features.
    private func flattenedFeatures(_ features: [Feature]) -> [Feature] {
        FeatureCollection(features).flattened?.features ?? features
    }

    /// A hashable, comparable representation of a rounded coordinate.
    private struct RoundedCoord: Hashable, Comparable {
        let x: Int64
        let y: Int64

        static func < (lhs: RoundedCoord, rhs: RoundedCoord) -> Bool {
            lhs.x < rhs.x || (lhs.x == rhs.x && lhs.y < rhs.y)
        }
    }

    /// A hashable representation of a normalized ring (sorted vertex set).
    private struct RingSignature: Hashable {
        let vertices: Set<RoundedCoord>
    }

    /// Normalize a geometry into a set of ring signatures, tolerant of
    /// Polygon-vs-MultiPolygon and ring-order differences.
    ///
    /// Each ring is stripped of its closing vertex, rounded, sorted by
    /// coordinate, and collected into a set of ring signatures.
    private func normalizedRings(
        of geometry: GeoJsonGeometry,
        precision: Double = 0.0000001
    ) -> Set<RingSignature> {
        let scale = 1.0 / precision
        var rings: [[Coordinate3D]] = []

        switch geometry {
        case let point as Point:
            rings = [[point.coordinate]]

        case let multiPoint as MultiPoint:
            rings = [multiPoint.coordinates]

        case let lineString as LineString:
            rings = [lineString.coordinates]

        case let multiLineString as MultiLineString:
            rings = multiLineString.coordinates

        case let polygon as Polygon:
            rings = polygon.rings.map(\.coordinates)

        case let multiPolygon as MultiPolygon:
            rings = multiPolygon.polygons.flatMap(\.rings).map(\.coordinates)

        default:
            return []
        }

        var result: Set<RingSignature> = []
        for ring in rings {
            var coords = ring
            if coords.count > 1, coords.first == coords.last {
                coords.removeLast()
            }
            let rounded = Set(coords.map {
                RoundedCoord(x: Int64(round($0.x * scale)), y: Int64(round($0.y * scale)))
            })
            result.insert(RingSignature(vertices: rounded))
        }

        return result
    }

    /// A sortable, hashable representation of a feature's properties for set
    /// comparison (order-independent).
    ///
    /// Boolean-like values are normalized so that MVT (`0`/`1` as Int), MLT
    /// (`true`/`false` as Bool), and GeoJSON (`true`/`false` as Bool) all
    /// compare equal.
    private func propertySignature(_ feature: Feature) -> String {
        let sorted = feature.properties.sorted { $0.key < $1.key }
        return sorted.map { key, value -> String in
            let normalized: String
            switch value {
            case let b as Bool:
                normalized = b ? "true" : "false"
            case let i as Int:
                // MVT encodes booleans as 0/1 integers; normalize to true/false.
                if i == 0 { normalized = "false" }
                else if i == 1 { normalized = "true" }
                else { normalized = String(i) }
            case let i as Int64:
                if i == 0 { normalized = "false" }
                else if i == 1 { normalized = "true" }
                else { normalized = String(i) }
            case let u as UInt:
                if u == 0 { normalized = "false" }
                else if u == 1 { normalized = "true" }
                else { normalized = String(u) }
            case let u as UInt64:
                if u == 0 { normalized = "false" }
                else if u == 1 { normalized = "true" }
                else { normalized = String(u) }
            case let d as Double:
                // MVT may store booleans as 0.0/1.0 doubles.
                if d == 0.0 { normalized = "false" }
                else if d == 1.0 { normalized = "true" }
                else { normalized = String(d) }
            case let f as Float:
                if f == 0.0 { normalized = "false" }
                else if f == 1.0 { normalized = "true" }
                else { normalized = String(f) }
            case let s as String:
                // String "0"/"1" that look boolean-like are left as-is; they
                // represent actual string values, not encoded booleans.
                normalized = s
            default:
                normalized = String(describing: value)
            }
            return "\(key)=\(normalized)"
        }.joined(separator: ";")
    }

    // MARK: - Layer structure: all three formats

    @Test
    func mvtAndMltHaveSameLayers() throws {
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let mltData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.mlt")

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
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let mltData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.mlt")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let mltTile = try #require(VectorTile(mltData: mltData, x: 8657, y: 5725, z: 14))

        let mvtTotal = mvtTile.layers.values.reduce(0) { $0 + $1.features.count }
        let mltTotal = mltTile.layers.values.reduce(0) { $0 + $1.features.count }

        #expect(mvtTotal == mltTotal,
                "MVT (\(mvtTotal)) vs MLT (\(mltTotal)) raw counts differ")
    }

    @Test
    func flattenedCountsMatchBetweenMvtAndGeoJson() throws {
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let geoJsonData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.geojson")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let geoJsonTile = try #require(VectorTile(geoJsonData: geoJsonData, layerProperty: "vt_layer"))

        let mvtRaw = mvtTile.layers.values.reduce(0) { $0 + $1.features.count }
        let mvtFlat = mvtTile.layerNames.reduce(0) { $0 + flattenedFeatures(mvtTile.features(for: $1)).count }
        let geoJsonTotal = geoJsonTile.layers.values.reduce(0) { $0 + $1.features.count }

        // GeoJSON init flattens multi-geometries, so compare with flattened MVT
        #expect(mvtFlat == geoJsonTotal,
                "MVT raw=\(mvtRaw), MVT flattened=\(mvtFlat), GeoJSON=\(geoJsonTotal)")
    }

    // MARK: - Per-layer property consistency (MVT vs MLT)

    @Test
    func mvtAndMltHaveSamePropertiesPerLayer() throws {
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let mltData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.mlt")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let mltTile = try #require(VectorTile(mltData: mltData, x: 8657, y: 5725, z: 14))

        for layerName in mvtTile.layerNames {
            let mvtFeatures = mvtTile.features(for: layerName)
            let mltFeatures = mltTile.features(for: layerName)

            // Compare properties as multisets (order-independent, tolerant of
            // boolean encoding differences between MVT and MLT).
            let mvtProps = mvtFeatures.map(propertySignature)
            let mltProps = mltFeatures.map(propertySignature)

            #expect(mvtProps.sorted() == mltProps.sorted(),
                    "Property mismatch in layer '\(layerName)'")
        }
    }

    // MARK: - Per-layer geometry consistency (MVT vs MLT)

    @Test
    func mvtAndMltHaveSameGeometriesPerLayer() throws {
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let mltData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.mlt")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let mltTile = try #require(VectorTile(mltData: mltData, x: 8657, y: 5725, z: 14))

        for layerName in mvtTile.layerNames {
            let mvtFeatures = mvtTile.features(for: layerName)
            let mltFeatures = mltTile.features(for: layerName)

            // Compare normalized geometry signatures as sets (order-independent,
            // tolerant of Polygon-vs-MultiPolygon and ring-order differences).
            let mvtGeoms = Set(mvtFeatures.map { normalizedRings(of: $0.geometry) })
            let mltGeoms = Set(mltFeatures.map { normalizedRings(of: $0.geometry) })

            // The MVT (`.pbf`) and MLT (`.mlt`) were produced by different
            // pipelines from the same database.  A small number of features near
            // tile boundaries may differ due to clipping/rounding differences.
            // Allow up to 1% mismatch (minimum 1) for large layers.
            let totalCount = mvtFeatures.count
            let mismatchCount = mvtGeoms.symmetricDifference(mltGeoms).count / 2
            let tolerance = max(1, totalCount / 100)

            #expect(mismatchCount <= tolerance,
                    "Geometry mismatch in layer '\(layerName)' (\(mismatchCount) differences, tolerance \(tolerance))")
        }
    }

    // MARK: - Per-layer property consistency (MVT vs GeoJSON)

    @Test
    func mvtAndGeoJsonHaveSamePropertiesPerLayer() throws {
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let geoJsonData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.geojson")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let geoJsonTile = try #require(VectorTile(geoJsonData: geoJsonData, layerProperty: "vt_layer"))

        for layerName in mvtTile.layerNames {
            let mvtFeatures = flattenedFeatures(mvtTile.features(for: layerName))
            let geoJsonFeatures = geoJsonTile.features(for: layerName)

            // GeoJSON init flattens multi-geometries, so compare with flattened MVT.
            let mvtProps = mvtFeatures.map(propertySignature)
            let geoJsonProps = geoJsonFeatures.map(propertySignature)

            #expect(mvtProps.sorted() == geoJsonProps.sorted(),
                    "Property mismatch in layer '\(layerName)' (MVT vs GeoJSON)")
        }
    }

    // MARK: - Per-layer geometry consistency (MVT vs GeoJSON)

    @Test
    func mvtAndGeoJsonHaveSameGeometriesPerLayer() throws {
        let mvtData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.pbf")
        let geoJsonData = try TestData.dataFromFile(name: "immenstadt_14_8657_5725.geojson")

        let mvtTile = try #require(VectorTile(mvtData: mvtData, x: 8657, y: 5725, z: 14))
        let geoJsonTile = try #require(VectorTile(geoJsonData: geoJsonData, layerProperty: "vt_layer"))

        for layerName in mvtTile.layerNames {
            let mvtFeatures = flattenedFeatures(mvtTile.features(for: layerName))
            let geoJsonFeatures = geoJsonTile.features(for: layerName)

            let mvtGeoms = Set(mvtFeatures.map { normalizedRings(of: $0.geometry) })
            let geoJsonGeoms = Set(geoJsonFeatures.map { normalizedRings(of: $0.geometry) })

            // The GeoJSON has full-precision coordinates while the MVT has
            // tile-extent integer rounding, so a small number of features may
            // differ.  Allow up to 5% mismatch (minimum 1) for large layers.
            let totalCount = mvtFeatures.count
            let mismatchCount = mvtGeoms.symmetricDifference(geoJsonGeoms).count / 2
            let tolerance = max(1, totalCount / 20)

            #expect(mismatchCount <= tolerance,
                    "Geometry mismatch in layer '\(layerName)' (MVT vs GeoJSON, \(mismatchCount) differences, tolerance \(tolerance))")
        }
    }

}
