#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

struct OverzoomTests {

    // MARK: - Helpers

    /// Creates a tile at the given coordinates with two point features:
    /// one in the NW quadrant of the tile, one in the SE quadrant.
    private func makeSourceTile(
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326
    ) -> VectorTile {
        var tile = VectorTile(x: x, y: y, z: z, projection: projection)!
        let bbox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4326)
        let centerLon = (bbox.southWest.longitude + bbox.northEast.longitude) / 2.0
        let centerLat = (bbox.southWest.latitude + bbox.northEast.latitude) / 2.0
        let quarterLon = (bbox.southWest.longitude + centerLon) / 2.0
        let quarterLat = (bbox.southWest.latitude + centerLat) / 2.0
        let threeQuarterLon = (centerLon + bbox.northEast.longitude) / 2.0
        let threeQuarterLat = (centerLat + bbox.northEast.latitude) / 2.0

        let nwPoint = Feature(
            Point(Coordinate3D(latitude: threeQuarterLat, longitude: quarterLon)),
            properties: ["name": "nw"])

        let sePoint = Feature(
            Point(Coordinate3D(latitude: quarterLat, longitude: threeQuarterLon)),
            properties: ["name": "se"])

        tile.setFeatures([nwPoint, sePoint], for: "test")
        return tile
    }

    // MARK: - Ancestry (delegates to MapTile.isRelated)

    @Test
    func isRelatedSameZoom() {
        let tile = MapTile(x: 1, y: 1, z: 2)
        #expect(tile.isRelated(to: tile))
        #expect(!tile.isRelated(to: MapTile(x: 2, y: 2, z: 2)))
    }

    @Test
    func isRelatedOverzoom() {
        let source = MapTile(x: 1, y: 1, z: 2)
        // Children of 2/1/1 at z=3: (2,2), (3,2), (2,3), (3,3)
        #expect(source.isRelated(to: MapTile(x: 2, y: 2, z: 3)))
        #expect(source.isRelated(to: MapTile(x: 3, y: 3, z: 3)))
        // Grandchild at z=4 (4,4 is child of 3,2 which is child of 2,1)
        #expect(source.isRelated(to: MapTile(x: 4, y: 4, z: 4)))
        // 7,7 at z=4 is also a grandchild: 7>>1=3, 3>>1=1 → child of 2/1/1
        #expect(source.isRelated(to: MapTile(x: 7, y: 7, z: 4)))
        // Not a descendant
        #expect(!source.isRelated(to: MapTile(x: 0, y: 0, z: 3)))
        #expect(!source.isRelated(to: MapTile(x: 0, y: 0, z: 4)))
    }

    @Test
    func isRelatedUnderzoom() {
        let source = MapTile(x: 2, y: 2, z: 3)
        let target = MapTile(x: 1, y: 1, z: 2)
        #expect(source.isRelated(to: target))

        // Source at z=4, target at z=2
        let sourceDeep = MapTile(x: 4, y: 4, z: 4)
        #expect(sourceDeep.isRelated(to: target))

        // Not an ancestor
        #expect(!MapTile(x: 0, y: 0, z: 3).isRelated(to: target))
    }

    // MARK: - Overzoom

    @Test
    func overzoomByOne() throws {
        let source = makeSourceTile(x: 1, y: 1, z: 2)
        // Overzoom to NW child: z=3, x=2, y=2
        let result = try #require(source.rezoom(toTargetX: 2, targetY: 2, targetZ: 3))

        #expect(result.z == 3)
        #expect(result.x == 2)
        #expect(result.y == 2)
        #expect(result.projection == source.projection)

        // Encode to MVT (which clips) and decode to check features
        let data = try #require(result.mvtData(options: .init(bufferSize: .extent(512))))
        let decoded = try #require(VectorTile(mvtData: data, x: 2, y: 2, z: 3))

        let features = decoded.features(for: "test")
        // The NW point should be in this child, the SE point should be clipped
        let names = Set(features.compactMap { $0.properties["name"] as? String })
        #expect(names.contains("nw"))
        #expect(!names.contains("se"))
    }

    @Test
    func overzoomByTwo() throws {
        let source = makeSourceTile(x: 1, y: 1, z: 2)
        // Overzoom to a grandchild at z=4
        // Children of 2/1/1: z=3 → (2,2), (3,2), (2,3), (3,3)
        // Children of 3/2/2: z=4 → (4,4), (5,4), (4,5), (5,5)
        let result = try #require(source.rezoom(toTargetX: 4, targetY: 4, targetZ: 4))

        #expect(result.z == 4)
        #expect(result.x == 4)
        #expect(result.y == 4)

        let data = try #require(result.mvtData(options: .init(bufferSize: .extent(512))))
        let decoded = try #require(VectorTile(mvtData: data, x: 4, y: 4, z: 4))

        let features = decoded.features(for: "test")
        // The NW point might be in this grandchild, depending on exact position
        // The important thing is the SE point is definitely not here
        let names = Set(features.compactMap { $0.properties["name"] as? String })
        #expect(!names.contains("se"))
    }

    @Test
    func overzoomNonAncestorReturnsNil() {
        let source = makeSourceTile(x: 1, y: 1, z: 2)
        // z=3/x=0/y=0 is NOT a child of z=2/x=1/y=1
        let result = source.rezoom(toTargetX: 0, targetY: 0, targetZ: 3)
        #expect(result == nil)
    }

    // MARK: - Underzoom

    @Test
    func underzoomByOne() throws {
        // Source at z=3/x=2/y=2 (a child of z=2/x=1/y=1)
        let source = makeSourceTile(x: 2, y: 2, z: 3)
        let result = try #require(source.rezoom(toTargetX: 1, targetY: 1, targetZ: 2))

        #expect(result.z == 2)
        #expect(result.x == 1)
        #expect(result.y == 1)

        // Encode and decode — all features from the child should be in the parent
        let data = try #require(result.mvtData(options: .init(bufferSize: .extent(512))))
        let decoded = try #require(VectorTile(mvtData: data, x: 1, y: 1, z: 2))

        let features = decoded.features(for: "test")
        let names = Set(features.compactMap { $0.properties["name"] as? String })
        // Both features should be retained (they're within the parent tile)
        #expect(names.contains("nw"))
        #expect(names.contains("se"))
    }

    @Test
    func underzoomMultipleChildren() throws {
        // Create all 4 children of z=2/x=1/y=1 at z=3
        let children: [VectorTile] = [
            makeSourceTile(x: 2, y: 2, z: 3),
            makeSourceTile(x: 3, y: 2, z: 3),
            makeSourceTile(x: 2, y: 3, z: 3),
            makeSourceTile(x: 3, y: 3, z: 3),
        ]

        // Underzoom all 4 into their parent at z=2/x=1/y=1
        let result = VectorTile.rezoom(children, toTargetX: 1, targetY: 1, targetZ: 2)

        #expect(result.z == 2)
        #expect(result.x == 1)
        #expect(result.y == 1)

        let data = try #require(result.mvtData(options: .init(bufferSize: .extent(512))))
        let decoded = try #require(VectorTile(mvtData: data, x: 1, y: 1, z: 2))

        let features = decoded.features(for: "test")
        // Each child contributed 2 features → 8 total
        #expect(features.count == 8)
    }

    @Test
    func underzoomNonAncestorReturnsNil() {
        let source = makeSourceTile(x: 0, y: 0, z: 3)
        // z=2/x=1/y=1 is NOT the parent of z=3/x=0/y=0
        let result = source.rezoom(toTargetX: 1, targetY: 1, targetZ: 2)
        #expect(result == nil)
    }

    // MARK: - Same zoom (identity)

    @Test
    func rezoomSameZoom() throws {
        let source = makeSourceTile(x: 1, y: 1, z: 2)
        let result = try #require(source.rezoom(toTargetX: 1, targetY: 1, targetZ: 2))

        #expect(result.z == 2)
        #expect(result.x == 1)
        #expect(result.y == 1)

        let features = result.features(for: "test")
        #expect(features.count == 2)
    }

    @Test
    func rezoomSameZoomDifferentTileReturnsNil() {
        let source = makeSourceTile(x: 1, y: 1, z: 2)
        let result = source.rezoom(toTargetX: 2, targetY: 2, targetZ: 2)
        #expect(result == nil)
    }

    // MARK: - All projections

    @Test
    func overzoomAllProjections() throws {
        for projection in [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID] {
            let source = makeSourceTile(x: 1, y: 1, z: 2, projection: projection)
            let result = try #require(source.rezoom(toTargetX: 2, targetY: 2, targetZ: 3))

            #expect(result.projection == projection)
            #expect(result.z == 3)
            #expect(result.x == 2)
            #expect(result.y == 2)

            // Features should be present (pre-encoding)
            let features = result.features(for: "test")
            #expect(features.count == 2, "projection \(projection) should have 2 features")
        }
    }

    @Test
    func underzoomAllProjections() throws {
        for projection in [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID] {
            let source = makeSourceTile(x: 2, y: 2, z: 3, projection: projection)
            let result = try #require(source.rezoom(toTargetX: 1, targetY: 1, targetZ: 2))

            #expect(result.projection == projection)
            #expect(result.z == 2)

            let features = result.features(for: "test")
            #expect(features.count == 2, "projection \(projection) should have 2 features")
        }
    }

    // MARK: - Round-trip MVT

    @Test
    func overzoomMvtRoundTrip() throws {
        // Use the real test data tile
        let mvtData = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let source = try #require(VectorTile(mvtData: mvtData, x: 8716, y: 8015, z: 14))

        // Overzoom to z=15, NW child (x=17432, y=16030)
        let result = try #require(source.rezoom(toTargetX: 17432, targetY: 16030, targetZ: 15))

        let data = try #require(result.mvtData(options: .init(bufferSize: .extent(512))))
        let decoded = try #require(VectorTile(mvtData: data, x: 17432, y: 16030, z: 15))

        // Should have some layers with features (the NW quadrant of the original tile)
        #expect(decoded.layerNames.isNotEmpty)
        let totalFeatures = decoded.layerNames.reduce(0) { $0 + decoded.features(for: $1).count }
        #expect(totalFeatures > 0)
    }

    @Test
    func underzoomMvtRoundTrip() throws {
        let mvtData = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let source = try #require(VectorTile(mvtData: mvtData, x: 8716, y: 8015, z: 14))

        // Underzoom to z=13, parent (x=4358, y=4007)
        let result = try #require(source.rezoom(toTargetX: 4358, targetY: 4007, targetZ: 13))

        let data = try #require(result.mvtData(options: .init(bufferSize: .extent(512))))
        let decoded = try #require(VectorTile(mvtData: data, x: 4358, y: 4007, z: 13))

        // All features should be retained (the source is within the parent)
        #expect(decoded.layerNames.isNotEmpty)
        let totalFeatures = decoded.layerNames.reduce(0) { $0 + decoded.features(for: $1).count }
        #expect(totalFeatures > 0)
    }

    // MARK: - Round-trip GeoJSON

    @Test
    func overzoomGeoJsonRoundTrip() throws {
        let source = makeSourceTile(x: 1, y: 1, z: 2)
        let result = try #require(source.rezoom(toTargetX: 2, targetY: 2, targetZ: 3))

        let data = try #require(result.toGeoJson(options: .init(bufferSize: .extent(0))))

        let fc = try #require(FeatureCollection(jsonData: data))
        // Only the NW point should be in this child tile
        #expect(fc.features.isNotEmpty)
    }

    @Test
    func underzoomGeoJsonRoundTrip() throws {
        let source = makeSourceTile(x: 2, y: 2, z: 3)
        let result = try #require(source.rezoom(toTargetX: 1, targetY: 1, targetZ: 2))

        let data = try #require(result.toGeoJson(options: .init(bufferSize: .extent(0))))

        let fc = try #require(FeatureCollection(jsonData: data))
        // Both features should be retained
        #expect(fc.features.count == 2)
    }

    // MARK: - Static rezoom with mixed sources

    @Test
    func rezoomMixedSources() throws {
        // Source at z=2 (ancestor of target z=3)
        let sourceA = makeSourceTile(x: 1, y: 1, z: 2)
        // Source at z=3 (same zoom as target, same tile → identity)
        let sourceB = makeSourceTile(x: 2, y: 2, z: 3)
        // Source at z=4 (descendant of target z=3)
        let sourceC = makeSourceTile(x: 4, y: 4, z: 4)

        let result = VectorTile.rezoom(
            [sourceA, sourceB, sourceC],
            toTargetX: 2,
            targetY: 2,
            targetZ: 3)

        #expect(result.z == 3)
        #expect(result.x == 2)
        #expect(result.y == 2)

        // All three sources are valid ancestors/descendants of z=3/x=2/y=2
        // Each contributes 2 features → 6 total
        let features = result.features(for: "test")
        #expect(features.count == 6)
    }

    @Test
    func rezoomSkipsInvalidSources() throws {
        let validSource = makeSourceTile(x: 1, y: 1, z: 2)
        let invalidSource = makeSourceTile(x: 0, y: 0, z: 2) // not an ancestor of 3/2/2

        let result = VectorTile.rezoom(
            [validSource, invalidSource],
            toTargetX: 2,
            targetY: 2,
            targetZ: 3)

        // Only the valid source contributes
        let features = result.features(for: "test")
        #expect(features.count == 2)
    }

}