import Foundation
import GISTools
@testable import MVTTools
import struct GISTools.Polygon
import Testing

struct MLTRoundtripGeometryTests {

    // MARK: - Geometry round-trips

    @Test
    func encodePointAndLine() throws {
        let point = Feature(Point(Coordinate3D(latitude: 5.0, longitude: 10.0)), id: .int(1))
        let line = Feature(MultiLineString([[
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ]])!, id: .int(2))
        let poly = Feature(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]])!, id: .int(3))

        guard let data = MLTEncoder.encode(
            layers: [
                "points": VectorTile.LayerContainer(features: [point], boundingBox: nil),
                "lines": VectorTile.LayerContainer(features: [line], boundingBox: nil),
                "polygons": VectorTile.LayerContainer(features: [poly], boundingBox: nil),
            ],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .epsg4326)
        #expect(decoded.keys.count == 3)
        #expect(decoded["points"]?.features.count == 1)
        #expect(decoded["lines"]?.features.count == 1)
        #expect(decoded["polygons"]?.features.count == 1)
    }

    @Test
    func multiLineStringRoundtrip() throws {
        let lines = MultiLineString([[
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ], [
            Coordinate3D(latitude: 5.0, longitude: 6.0),
            Coordinate3D(latitude: 7.0, longitude: 8.0),
        ]])!
        let feature = Feature(lines, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? MultiLineString)
        #expect(result.coordinates.count == 2)
        #expect(result.coordinates[0].count == 2)
        #expect(result.coordinates[1].count == 2)
        #expect(result.coordinates[0][0].x == 2.0)
        #expect(result.coordinates[0][1].x == 4.0)
        #expect(result.coordinates[1][0].x == 6.0)
        #expect(result.coordinates[1][1].x == 8.0)
    }

    @Test
    func polygonRoundtrip() throws {
        let ring = [
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 300.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
        ]
        let poly = try #require(Polygon([ring]))
        let feature = Feature(poly, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == ring.count)
        for (a, b) in zip(result.rings[0].coordinates, ring) {
            #expect(abs(a.x - b.x) < 1.0)
            #expect(abs(a.y - b.y) < 1.0)
        }
    }

    @Test
    func polygonWithHoleRoundtrip() throws {
        let outer: [Coordinate3D] = [
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]
        let inner: [Coordinate3D] = [
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 800.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 800.0, y: 800.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 800.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
        ]
        let poly = try #require(Polygon([outer, inner]))
        let feature = Feature(poly, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 2)
        #expect(result.rings[0].coordinates.count == outer.count)
        #expect(result.rings[1].coordinates.count == inner.count)
    }

    @Test
    func multiPolygonRoundtrip() throws {
        let poly1 = try #require(Polygon([[
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 250.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]]))
        let poly2 = try #require(Polygon([[
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 800.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
        ]]))
        let mpoly = try #require(MultiPolygon([poly1, poly2]))
        let feature = Feature(mpoly, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? MultiPolygon)
        #expect(result.coordinates.count == 2)
        #expect(result.coordinates[0].count == 1)
        #expect(result.coordinates[1].count == 1)
        #expect(result.coordinates[0][0].count == 4)
        #expect(result.coordinates[1][0].count == 4)
    }

    @Test
    func multiPointRoundtrip() throws {
        let coords = [
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ]
        let mp = try #require(MultiPoint(coords))
        let feature = Feature(mp, id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.geometry is MultiPoint)
    }

    @Test
    func altitudeIsDropped() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0, altitude: 500.0, m: 123.0)
        let feature = Feature(Point(coord), properties: [:] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)
        let pt = try #require(feat.geometry.allCoordinates.first)

        #expect(pt.latitude == 10.0)
        #expect(pt.longitude == 20.0)
        #expect(pt.altitude == nil)
    }

    // MARK: - MultiPolygon ring grouping

    /// A MultiPolygon with multiple polygons, some with holes, must preserve
    /// the ring grouping through an MLT encode → decode round-trip.
    ///
    /// This is a regression test for the triangular-artifact bug where
    /// interior rings (holes) were being separated from their parent polygons
    /// and turned into standalone filled polygons, causing overlapping
    /// triangles in maplibre-gl-js.
    @Test
    func multiPolygonWithHolesPreservesRingGrouping() throws {
        // Polygon 0: exterior + 1 hole
        let poly0 = try #require(Polygon([[
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 400.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 400.0, y: 400.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 400.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
        ]]))
        // Polygon 1: just exterior
        let poly1 = try #require(Polygon([[
            Coordinate3D(x: 2000.0, y: 2000.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 2000.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 3000.0, projection: .noSRID),
            Coordinate3D(x: 2000.0, y: 3000.0, projection: .noSRID),
            Coordinate3D(x: 2000.0, y: 2000.0, projection: .noSRID),
        ]]))
        // Polygon 2: exterior + 2 holes
        let poly2 = try #require(Polygon([[
            Coordinate3D(x: 4000.0, y: 4000.0, projection: .noSRID),
            Coordinate3D(x: 5000.0, y: 4000.0, projection: .noSRID),
            Coordinate3D(x: 5000.0, y: 5000.0, projection: .noSRID),
            Coordinate3D(x: 4000.0, y: 5000.0, projection: .noSRID),
            Coordinate3D(x: 4000.0, y: 4000.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 4200.0, y: 4200.0, projection: .noSRID),
            Coordinate3D(x: 4400.0, y: 4200.0, projection: .noSRID),
            Coordinate3D(x: 4400.0, y: 4400.0, projection: .noSRID),
            Coordinate3D(x: 4200.0, y: 4400.0, projection: .noSRID),
            Coordinate3D(x: 4200.0, y: 4200.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 4600.0, y: 4600.0, projection: .noSRID),
            Coordinate3D(x: 4800.0, y: 4600.0, projection: .noSRID),
            Coordinate3D(x: 4800.0, y: 4800.0, projection: .noSRID),
            Coordinate3D(x: 4600.0, y: 4800.0, projection: .noSRID),
            Coordinate3D(x: 4600.0, y: 4600.0, projection: .noSRID),
        ]]))

        let mpoly = try #require(MultiPolygon([poly0, poly1, poly2]))
        let feature = Feature(mpoly, id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let features = try #require(decoded["test"]?.features)
        #expect(features.count == 1)

        let decodedMpoly = try #require(features[0].geometry as? MultiPolygon)
        // Must have 3 polygons
        #expect(decodedMpoly.coordinates.count == 3)
        // Polygon 0: 2 rings (exterior + 1 hole)
        #expect(decodedMpoly.coordinates[0].count == 2)
        // Polygon 1: 1 ring (exterior only)
        #expect(decodedMpoly.coordinates[1].count == 1)
        // Polygon 2: 3 rings (exterior + 2 holes)
        #expect(decodedMpoly.coordinates[2].count == 3)
    }

    /// Multiple MultiPolygon features in the same layer, each with different
    /// ring counts, must all preserve their ring grouping.
    @Test
    func multipleMultiPolygonsWithHolesInSameLayer() throws {
        // Feature 1: MultiPolygon with 1 polygon that has 1 hole
        let poly1 = try #require(Polygon([[
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 400.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 400.0, y: 400.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 400.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
        ]]))
        let feat1 = Feature(try #require(MultiPolygon([poly1])), id: .int(1))

        // Feature 2: MultiPolygon with 2 polygons, one with a hole, one without
        let poly2a = try #require(Polygon([[
            Coordinate3D(x: 2000.0, y: 2000.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 2000.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 3000.0, projection: .noSRID),
            Coordinate3D(x: 2000.0, y: 3000.0, projection: .noSRID),
            Coordinate3D(x: 2000.0, y: 2000.0, projection: .noSRID),
        ], [
            Coordinate3D(x: 2200.0, y: 2200.0, projection: .noSRID),
            Coordinate3D(x: 2400.0, y: 2200.0, projection: .noSRID),
            Coordinate3D(x: 2400.0, y: 2400.0, projection: .noSRID),
            Coordinate3D(x: 2200.0, y: 2400.0, projection: .noSRID),
            Coordinate3D(x: 2200.0, y: 2200.0, projection: .noSRID),
        ]]))
        let poly2b = try #require(Polygon([[
            Coordinate3D(x: 4000.0, y: 4000.0, projection: .noSRID),
            Coordinate3D(x: 4500.0, y: 4000.0, projection: .noSRID),
            Coordinate3D(x: 4500.0, y: 4500.0, projection: .noSRID),
            Coordinate3D(x: 4000.0, y: 4500.0, projection: .noSRID),
            Coordinate3D(x: 4000.0, y: 4000.0, projection: .noSRID),
        ]]))
        let feat2 = Feature(try #require(MultiPolygon([poly2a, poly2b])), id: .int(2))

        // Feature 3: simple Polygon (no hole)
        let poly3 = try #require(Polygon([[
            Coordinate3D(x: 5000.0, y: 5000.0, projection: .noSRID),
            Coordinate3D(x: 6000.0, y: 5000.0, projection: .noSRID),
            Coordinate3D(x: 6000.0, y: 6000.0, projection: .noSRID),
            Coordinate3D(x: 5000.0, y: 6000.0, projection: .noSRID),
            Coordinate3D(x: 5000.0, y: 5000.0, projection: .noSRID),
        ]]))
        let feat3 = Feature(poly3, id: .int(3))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feat1, feat2, feat3], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let features = try #require(decoded["test"]?.features)
        #expect(features.count == 3)

        // Feature 1: MultiPolygon with 1 polygon, 2 rings
        let mp1 = try #require(features[0].geometry as? MultiPolygon)
        #expect(mp1.coordinates.count == 1)
        #expect(mp1.coordinates[0].count == 2)

        // Feature 2: MultiPolygon with 2 polygons, first has 2 rings, second has 1
        let mp2 = try #require(features[1].geometry as? MultiPolygon)
        #expect(mp2.coordinates.count == 2)
        #expect(mp2.coordinates[0].count == 2)
        #expect(mp2.coordinates[1].count == 1)

        // Feature 3: Polygon with 1 ring
        let p3 = try #require(features[2].geometry as? Polygon)
        #expect(p3.rings.count == 1)
    }

    /// Encode the same VectorTile to both MVT and MLT and verify that
    /// MultiPolygon ring grouping is preserved in both.
    /// This simulates what `MVTPostgis.data()` does: create one VectorTile
    /// and encode it to both formats.
    @Test
    func dualMvtMltEncodingPreservesRingGrouping() throws {
        // MultiPolygon with 2 polygons, first has a hole
        // Use realistic EPSG:3857 coordinates within tile 7/65/47
        // (lng [2.81, 5.62], lat [40.98, 43.07])
        // EPSG:3857: x = lng * 111319, y = lat(log) * ...
        let poly0 = try #require(Polygon([[
            Coordinate3D(x: 320000.0, y: 5160000.0, projection: .epsg3857),
            Coordinate3D(x: 420000.0, y: 5160000.0, projection: .epsg3857),
            Coordinate3D(x: 420000.0, y: 5300000.0, projection: .epsg3857),
            Coordinate3D(x: 320000.0, y: 5300000.0, projection: .epsg3857),
            Coordinate3D(x: 320000.0, y: 5160000.0, projection: .epsg3857),
        ], [
            Coordinate3D(x: 340000.0, y: 5200000.0, projection: .epsg3857),
            Coordinate3D(x: 360000.0, y: 5200000.0, projection: .epsg3857),
            Coordinate3D(x: 360000.0, y: 5220000.0, projection: .epsg3857),
            Coordinate3D(x: 340000.0, y: 5220000.0, projection: .epsg3857),
            Coordinate3D(x: 340000.0, y: 5200000.0, projection: .epsg3857),
        ]]))
        let poly1 = try #require(Polygon([[
            Coordinate3D(x: 500000.0, y: 5000000.0, projection: .epsg3857),
            Coordinate3D(x: 550000.0, y: 5000000.0, projection: .epsg3857),
            Coordinate3D(x: 550000.0, y: 5100000.0, projection: .epsg3857),
            Coordinate3D(x: 500000.0, y: 5100000.0, projection: .epsg3857),
            Coordinate3D(x: 500000.0, y: 5000000.0, projection: .epsg3857),
        ]]))
        let mpoly = try #require(MultiPolygon([poly0, poly1]))
        let feature = Feature(mpoly, id: .int(1))

        // Create a VectorTile at z7 with EPSG:3857 (same as PostGIS)
        var tile = try VectorTile(x: 65, y: 47, z: 7, projection: .epsg3857)
        tile.appendFeatures([feature], to: "landuse_a")

        let options = VectorTile.ExportOptions(
            bufferSize: .pixel(32),
            compression: .level(9),
            simplifyFeatures: .no)

        // Encode to both formats using the SAME tile
        let mvtData = try #require(tile.mvtData(options: options))
        let mltData = try #require(tile.mltData(options: options))

        // Decode MVT and check (MVT flattens rings, decoder uses winding order)
        let mvtTile = try VectorTile(mvtData: mvtData, x: 65, y: 47, z: 7, projection: .epsg4326)
        let mvtFeatures = mvtTile.features(for: "landuse_a")
        #expect(mvtFeatures.count == 1)

        // Decode MLT and check — MLT must preserve the explicit polygon grouping
        let mltLayers = try MLTDecoder.decode(from: mltData, x: 65, y: 47, z: 7, projection: .epsg4326)
        let mltFeatures = try #require(mltLayers["landuse_a"]?.features)
        #expect(mltFeatures.count == 1)
        let mltMpoly = try #require(mltFeatures[0].geometry as? MultiPolygon)
        #expect(mltMpoly.coordinates.count == 2)
        #expect(mltMpoly.coordinates[0].count == 2)  // exterior + hole
        #expect(mltMpoly.coordinates[1].count == 1)  // exterior only
    }

}
