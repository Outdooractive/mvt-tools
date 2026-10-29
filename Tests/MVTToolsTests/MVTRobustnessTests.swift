#if EnableMVT
#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

/// Regression tests for malformed input, numeric edge cases, and
/// geometry/property round-trip fidelity.
struct MVTRobustnessTests {

    // MARK: - Helpers

    private func makeTileData(
        layers: [VectorTile_Tile.Layer]
    ) throws -> Data {
        var tile = VectorTile_Tile()
        tile.layers = layers
        return try tile.serializedData()
    }

    private func makePointLayer(
        name: String = "test",
        version: UInt32 = 2,
        extent: UInt32 = 4096,
        geometry: [UInt32] = [9, 100, 100]
    ) -> VectorTile_Tile.Layer {
        var layer = VectorTile_Tile.Layer()
        layer.name = name
        layer.version = version
        layer.extent = extent

        var feature = VectorTile_Tile.Feature()
        feature.type = .point
        feature.geometry = geometry
        layer.features = [feature]

        return layer
    }

    // MARK: - Zigzag / integer range

    @Test
    func zigZagBoundaries() throws {
        let cases: [(value: Int, encoded: UInt32)] = [
            (Int(Int32.min), 4_294_967_295),
            (-1, 1),
            (0, 0),
            (1, 2),
            (Int(Int32.max), 4_294_967_294),
        ]

        for testCase in cases {
            let integers = MVTEncoder.geometryIntegers(
                fromMultiCoordinates: [[
                    Coordinate3D(x: Double(testCase.value), y: 0.0, projection: .noSRID),
                ]],
                ofType: .point,
                projectionFunction: Projections.passThroughToTile())

            let result = try #require(integers)
            #expect(result.count == 3)
            #expect(result[0] == 9)
            #expect(result[1] == testCase.encoded)
            #expect(result[2] == 0)
        }
    }

    @Test
    func outOfRangeCoordinatesAreRejectedInsteadOfCrashing() throws {
        let farAway = Coordinate3D(x: 5_000_000_000.0, y: 0.0, projection: .noSRID)
        let integers = MVTEncoder.geometryIntegers(
            fromMultiCoordinates: [[farAway]],
            ofType: .point,
            projectionFunction: Projections.passThroughToTile())
        #expect(integers == nil)

        let feature = Feature(Point(farAway))
        #expect(MVTEncoder.vectorTileFeature(
            from: feature,
            projectionFunction: Projections.passThroughToTile()) == nil)
    }

    @Test
    func unrepresentableFeatureIsSkippedDuringEncoding() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .noSRID)
        tile.appendFeatures([
            Feature(Point(Coordinate3D(x: 5_000_000_000.0, y: 0.0, projection: .noSRID))),
            Feature(Point(Coordinate3D(x: 10.0, y: 20.0, projection: .noSRID))),
        ], to: "test")

        let data = try #require(tile.mvtData())
        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded.features(for: "test").count == 1)
    }

    // MARK: - Malformed geometry command streams

    @Test
    func closePathDoesNotDuplicateTheClosingVertex() {
        // MoveTo (0,0), LineTo (2,0) (0,2) (0,0), ClosePath.
        let coordinates = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: [9, 0, 0, 26, 4, 0, 3, 4, 0, 3, 15],
            ofType: .polygon,
            projectionFunction: Projections.passThroughFromTile(x: 0, y: 0))

        #expect(coordinates.count == 1)
        #expect(coordinates[0].count == 4)
        #expect(coordinates[0].first == coordinates[0].last)
    }

    @Test
    func unknownCommandStopsDecoding() {
        // Valid MoveTo followed by an unknown command id (3).
        let coordinates = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: [9, 0, 0, 3, 9, 10, 10],
            ofType: .linestring,
            projectionFunction: Projections.passThroughFromTile(x: 0, y: 0))

        #expect(coordinates.count == 1)
        #expect(coordinates[0].count == 1)
    }

    @Test
    func truncatedGeometryStopsDecoding() {
        // MoveTo count 1, but only one of the two required parameters.
        let coordinates = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: [9, 4],
            ofType: .linestring,
            projectionFunction: Projections.passThroughFromTile(x: 0, y: 0))
        #expect(coordinates.isEmpty)

        // MoveTo is complete, LineTo is truncated.
        let partial = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: [9, 4, 4, 18, 0],
            ofType: .linestring,
            projectionFunction: Projections.passThroughFromTile(x: 0, y: 0))
        #expect(partial.count == 1)
        #expect(partial[0].count == 1)
    }

    @Test
    func closePathWithoutEnoughVerticesIsRejected() {
        // MoveTo (0,0), LineTo (2,0), ClosePath. A ring needs at least three
        // distinct vertices before the implicit closing vertex.
        let coordinates = MVTDecoder.multiCoordinatesFrom(
            geometryIntegers: [9, 0, 0, 10, 4, 0, 15],
            ofType: .polygon,
            projectionFunction: Projections.passThroughFromTile(x: 0, y: 0))
        #expect(coordinates.isEmpty)
    }

    // MARK: - Layer metadata robustness

    @Test
    func extentZeroFallsBackToDefaultExtent() throws {
        let data = try makeTileData(layers: [makePointLayer(extent: 0)])
        let tile = try VectorTile(mvtData: data, x: 0, y: 0, z: 0, projection: .epsg4326)

        let point = try #require(tile.features(for: "test").first?.geometry as? Point)
        #expect(point.coordinate.projection == .epsg4326)
        #expect(abs(point.coordinate.longitude) <= 180.0)
        #expect(abs(point.coordinate.latitude) <= 90.0)
        // A pass-through extent of zero would leave the raw tile coordinates
        // (50, 50) unprojected; the fallback extent must project them.
        #expect(point.coordinate.longitude != 50.0)
    }

    @Test
    func versionOneLayersAreDecoded() throws {
        let data = try makeTileData(layers: [makePointLayer(version: 1)])
        let tile = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        #expect(tile.features(for: "test").count == 1)
    }

    @Test
    func unknownVersionIsIgnored() throws {
        let data = try makeTileData(layers: [makePointLayer(version: 99)])
        let tile = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        #expect(tile.isEmpty)
    }

    @Test
    func duplicateLayerNamesAreMerged() throws {
        let data = try makeTileData(layers: [
            makePointLayer(name: "duplicate", geometry: [9, 2, 2]),
            makePointLayer(name: "duplicate", geometry: [9, 10, 10]),
        ])

        let tile = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        #expect(tile.layerNames == ["duplicate"])
        #expect(tile.features(for: "duplicate").count == 2)
    }

    @Test
    func malformedTileDataThrowsParseError() {
        #expect(throws: VectorTileError.parseFailed(
            format: "MVT",
            reason: "protobuf deserialization failed")) {
            try VectorTile(mvtData: Data([0xFF, 0xFF, 0xFF]), x: 0, y: 0, z: 0)
        }
    }

    @Test
    func gzippedDataIsDecodedAutomatically() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.appendFeatures([Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)))], to: "test")

        let data = try #require(tile.mvtData(options: .init(compression: .level(9))))
        #expect(data.isGzipped)

        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        #expect(decoded.features(for: "test").count == 1)
    }

    @Test
    func emptyTileRoundTrip() throws {
        let tile = try VectorTile(x: 0, y: 0, z: 0)
        let data = try #require(tile.mvtData())
        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        #expect(decoded.isEmpty)
        #expect(decoded.origin == .mvt)
    }

    @Test
    func gzippedGeoJsonIsDecodedAutomatically() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.appendFeatures([Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)))], to: "test")

        let data = try #require(tile.toGeoJson(
            layerProperty: nil,
            options: .init(compression: .level(9))))
        #expect(data.isGzipped)

        let decoded = try VectorTile(geoJsonData: data, layerProperty: nil)
        #expect(decoded.features(for: "Layer-0").count == 1)
    }

    // MARK: - Property fidelity

    @Test
    func propertyTypesSurviveRoundTrip() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)))
        feature.properties = [
            "string": "hello",
            "int": 42,
            "int32": Int32(123),
            "int64": Int64(9_000_000_000),
            "uint32": UInt32(456),
            "uint64": UInt64(9_000_000_000),
            "double": 1.25,
            "bool": true,
            "float": Float(2.5),
            "array": [1, 2, 3] as [Sendable],
            "dictionary": ["a": 1] as [String: Sendable],
        ]

        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.setFeatures([feature], for: "test")

        let data = try #require(tile.mvtData())
        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        let properties = try #require(decoded.features(for: "test").first?.properties)

        #expect(properties["string"] as? String == "hello")
        #expect(properties["int"] as? Int64 == 42)
        #expect(properties["int32"] as? Int64 == 123)
        #expect(properties["int64"] as? Int64 == 9_000_000_000)
        #expect(properties["uint32"] as? UInt64 == 456)
        #expect(properties["uint64"] as? UInt64 == 9_000_000_000)
        #expect(properties["double"] as? Double == 1.25)
        #expect(properties["bool"] as? Bool == true)
        #expect(properties["float"] as? Double == 2.5)
        #expect((properties["array"] as? [Sendable])?.count == 3)
        #expect((properties["dictionary"] as? [String: Sendable])?["a"] as? Int == 1)
    }

    @Test
    func jsonShapedStringsAreDecodedAsStructuredValues() throws {
        // This is a documented limitation of MVT property encoding: arrays and
        // dictionaries are stored as JSON strings, so a plain string that looks
        // like JSON cannot be distinguished from a structured value.
        var feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)))
        feature.properties = [
            "array": "[1,2]",
            "dictionary": "{\"a\":1}",
            "plain": "[not json]",
        ]

        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.setFeatures([feature], for: "test")

        let data = try #require(tile.mvtData())
        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        let properties = try #require(decoded.features(for: "test").first?.properties)

        #expect((properties["array"] as? [Sendable])?.count == 2)
        #expect((properties["dictionary"] as? [String: Sendable])?["a"] as? Int == 1)
        #expect(properties["plain"] as? String == "[not json]")
    }

    // MARK: - Polygon winding

    /// Creates a coordinate in the tile's projection. Geographic coordinates
    /// are used as the source, except for noSRID where the raw tile values are
    /// used directly.
    private func tileCoordinate(
        _ x: Double,
        _ y: Double,
        projection: Projection
    ) -> Coordinate3D {
        if projection == .noSRID {
            return Coordinate3D(x: x, y: y, projection: .noSRID)
        }
        return Coordinate3D(latitude: y, longitude: x).projected(to: projection)
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func polygonWindingIsNormalizedForMVT(projection: Projection) throws {
        // Deliberately wrong GeoJSON winding: clockwise exterior, CCW hole.
        let outer = [
            tileCoordinate(0.0, 0.0, projection: projection),
            tileCoordinate(0.0, 10.0, projection: projection),
            tileCoordinate(10.0, 10.0, projection: projection),
            tileCoordinate(10.0, 0.0, projection: projection),
            tileCoordinate(0.0, 0.0, projection: projection),
        ]
        let hole = [
            tileCoordinate(2.0, 2.0, projection: projection),
            tileCoordinate(8.0, 2.0, projection: projection),
            tileCoordinate(8.0, 8.0, projection: projection),
            tileCoordinate(2.0, 8.0, projection: projection),
            tileCoordinate(2.0, 2.0, projection: projection),
        ]

        let polygon = try #require(Polygon([outer, hole]))
        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        tile.setFeatures([Feature(polygon)], for: "test")

        let data = try #require(tile.mvtData())
        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0, projection: projection)
        let decodedPolygon = try #require(decoded.features(for: "test").first?.geometry as? Polygon)

        #expect(decodedPolygon.rings.count == 2)
        #expect(decodedPolygon.rings[0].isUnprojectedClockwise)
        #expect(decodedPolygon.rings[1].isUnprojectedCounterClockwise)
    }

    @Test
    func multipolygonWindingIsNormalizedForMVT() throws {
        let first = [
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]
        let second = [
            Coordinate3D(latitude: 20.0, longitude: 20.0),
            Coordinate3D(latitude: 20.0, longitude: 30.0),
            Coordinate3D(latitude: 30.0, longitude: 30.0),
            Coordinate3D(latitude: 30.0, longitude: 20.0),
            Coordinate3D(latitude: 20.0, longitude: 20.0),
        ]

        let firstPolygon = try #require(Polygon([first]))
        let secondPolygon = try #require(Polygon([second]))
        let multiPolygon = try #require(MultiPolygon([firstPolygon, secondPolygon]))

        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.setFeatures([Feature(multiPolygon)], for: "test")

        let data = try #require(tile.mvtData())
        let decoded = try VectorTile(mvtData: data, x: 0, y: 0, z: 0)
        let decodedMultiPolygon = try #require(decoded.features(for: "test").first?.geometry as? MultiPolygon)

        #expect(decodedMultiPolygon.polygons.count == 2)
        #expect(decodedMultiPolygon.polygons.allSatisfy({ $0.rings[0].isUnprojectedClockwise }))
    }

    // MARK: - Clipping and buffers

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func clippingDoesNotPromoteSingleGeometries(projection: Projection) throws {
        // ECEF tile bounding boxes are corner-derived; use an anchor that is
        // known to be inside the z=0 ECEF clip box.
        let baseX: Double = projection == .epsg4978 ? 90.0 : 1.0
        let baseY: Double = projection == .epsg4978 ? -40.0 : 1.0

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        let line = try #require(LineString([
            tileCoordinate(baseX, baseY, projection: projection),
            tileCoordinate(baseX + 0.01, baseY + 0.01, projection: projection),
        ]))
        let polygon = try #require(Polygon([[
            tileCoordinate(baseX, baseY, projection: projection),
            tileCoordinate(baseX + 0.01, baseY, projection: projection),
            tileCoordinate(baseX + 0.01, baseY + 0.01, projection: projection),
            tileCoordinate(baseX, baseY + 0.01, projection: projection),
            tileCoordinate(baseX, baseY, projection: projection),
        ]]))
        tile.setFeatures([Feature(line, id: .int(1)), Feature(polygon, id: .int(2))], for: "test")

        let data = try #require(tile.toGeoJson(options: .init(bufferSize: .extent(512))))
        let collection = try #require(FeatureCollection(jsonData: data))

        let byId = Dictionary(uniqueKeysWithValues: collection.features.compactMap({ feature in
            feature.id.map({ ($0, feature) })
        }))
        #expect(byId[.int(1)]?.geometry is LineString)
        #expect(byId[.int(2)]?.geometry is Polygon)
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857])
    func bufferSizeIsMeasuredInTileExtentUnits(projection: Projection) throws {
        let mapTile = MapTile(x: 8716, y: 8015, z: 14)
        let bounds = mapTile.boundingBox(projection: projection)
        let width = bounds.northEast.x - bounds.southWest.x
        let centerY = (bounds.southWest.y + bounds.northEast.y) / 2.0
        let centerX = (bounds.southWest.x + bounds.northEast.x) / 2.0

        let center = Feature(
            Point(Coordinate3D(x: centerX, y: centerY, projection: projection)),
            id: .int(1))
        let nearby = Feature(
            Point(Coordinate3D(
                x: bounds.northEast.x + (width * 0.5),
                y: centerY,
                projection: projection)),
            id: .int(2))
        let farAway = Feature(
            Point(Coordinate3D(
                x: bounds.northEast.x + (width * 1.2),
                y: centerY,
                projection: projection)),
            id: .int(3))

        var tile = try VectorTile(tile: mapTile, projection: projection)
        tile.setFeatures([center, nearby, farAway], for: "test")

        // One full tile width of buffer keeps the 1.5-width feature but drops
        // the 2.2-width feature. The old diagonal-based formula produced a
        // ~1.41× larger buffer and would also keep the far-away feature.
        let data = try #require(tile.toGeoJson(options: .init(bufferSize: .extent(4096))))
        let collection = try #require(FeatureCollection(jsonData: data))
        #expect(Set(collection.features.compactMap(\.id)) == [.int(1), .int(2)])

        // A negative buffer must not shrink the clip box below the tile.
        let negativeData = try #require(tile.toGeoJson(options: .init(bufferSize: .extent(-100))))
        let negativeCollection = try #require(FeatureCollection(jsonData: negativeData))
        #expect(Set(negativeCollection.features.compactMap(\.id)) == [.int(1)])
    }

    // MARK: - Indexed queries

    @Test
    func indexedQueryDoesNotReturnBoundingBoxFalsePositives() throws {
        let line = try #require(LineString([
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
        ]))
        let feature = Feature(line, id: .int(1))

        var plainTile = try VectorTile(x: 0, y: 0, z: 0, projection: .noSRID)
        plainTile.setFeatures([feature], for: "test")

        var indexedTile = plainTile
        indexedTile.createIndex(sortOption: .hilbert)

        let queryBox = BoundingBox(
            southWest: Coordinate3D(x: 40.0, y: 80.0, projection: .noSRID),
            northEast: Coordinate3D(x: 60.0, y: 100.0, projection: .noSRID))

        // The line's bounding box intersects the query box, but no part of the
        // line itself does.
        #expect(plainTile.query(in: queryBox).isEmpty)
        #expect(indexedTile.query(in: queryBox).isEmpty)

        let (plainFeatures, plainResults) = plainTile.queryMany(at: [queryBox.center], tolerance: 10.0)
        let (indexedFeatures, indexedResults) = indexedTile.queryMany(at: [queryBox.center], tolerance: 10.0)
        #expect(plainFeatures.isEmpty)
        #expect(plainResults.isEmpty)
        #expect(indexedFeatures.isEmpty)
        #expect(indexedResults.isEmpty)
    }

    @Test
    func queryManyRespectsFeatureFilterAndDuplicates() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .noSRID)
        tile.setFeatures([
            Feature(Point(Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID)), id: .int(1)),
        ], for: "test")

        let coordinate = Coordinate3D(x: 10.0, y: 10.0, projection: .noSRID)

        let (filteredFeatures, filteredResults) = tile.queryMany(
            at: [coordinate],
            tolerance: 5.0,
            featureFilter: { _ in false })
        #expect(filteredFeatures.isEmpty)
        #expect(filteredResults.isEmpty)

        // Two overlapping query boxes must report the feature only once when
        // includeDuplicates is false.
        let nearby = Coordinate3D(x: 11.0, y: 10.0, projection: .noSRID)
        let (uniqueFeatures, uniqueResults) = tile.queryMany(
            at: [coordinate, nearby],
            tolerance: 5.0,
            includeDuplicates: false)
        #expect(uniqueFeatures.count == 1)
        #expect(uniqueResults.count == 1)
        #expect(uniqueResults[0].results.count == 1)

        let (duplicateFeatures, duplicateResults) = tile.queryMany(
            at: [coordinate, nearby],
            tolerance: 5.0,
            includeDuplicates: true)
        #expect(duplicateFeatures.count == 1)
        #expect(duplicateResults.count == 2)
        #expect(duplicateResults.allSatisfy({ $0.results.count == 1 }))
    }

    // MARK: - API/error behaviour

    @Test
    func errorDescriptionsAreLocalized() throws {
        let errors: [VectorTileError] = [
            .invalidCoordinate(x: -1, y: 0, z: 0),
            .coordinateOutOfBounds(x: 4, y: 2, z: 2, maxBound: 4),
            .fileReadFailed(url: URL(fileURLWithPath: "/tmp/missing"), reason: "nope"),
            .parseFailed(format: "MVT", reason: "bad"),
        ]

        for error in errors {
            let description = try #require(error.errorDescription)
            #expect(description.isEmpty == false)
        }
    }

    @Test
    func extremeZoomDoesNotOverflow() {
        #expect(throws: VectorTileError.invalidCoordinate(x: 0, y: 0, z: 63)) {
            try VectorTile(x: 0, y: 0, z: 63)
        }

        // Constructing a malformed error value must not trap when its
        // description is generated.
        let error = VectorTileError.coordinateOutOfBounds(
            x: 0, y: 0, z: 63, maxBound: Int.min)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test
    func layerNamesAtMissingFileThrows() {
        let url = URL(fileURLWithPath: "/tmp/mvt-tools-does-not-exist-\(UUID().uuidString).mvt")
        #expect(throws: VectorTileError.self) {
            try VectorTile.layerNames(at: url)
        }
    }

    @Test
    func mergeWithMismatchedCoordinatesFails() throws {
        var first = try VectorTile(x: 0, y: 0, z: 0)
        var second = try VectorTile(x: 1, y: 1, z: 1)
        first.appendFeatures([Feature(Point(Coordinate3D(latitude: 1.0, longitude: 1.0)))], to: "test")
        second.appendFeatures([Feature(Point(Coordinate3D(latitude: 2.0, longitude: 2.0)))], to: "test")

        #expect(first.merge(second) == false)
        #expect(first.features(for: "test").count == 1)
    }

    @Test
    func layerNamesAreSortedAndEncodingIsDeterministic() throws {
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))

        var tileA = try VectorTile(x: 0, y: 0, z: 0)
        tileA.setFeatures([point], for: "b")
        tileA.setFeatures([point], for: "a")

        var tileB = try VectorTile(x: 0, y: 0, z: 0)
        tileB.setFeatures([point], for: "a")
        tileB.setFeatures([point], for: "b")

        #expect(tileA.layerNames == ["a", "b"])
        #expect(tileB.layerNames == ["a", "b"])

        let dataA = try #require(tileA.mvtData())
        let dataB = try #require(tileB.mvtData())
        #expect(dataA == dataB)
    }

    @Test
    func unlocatedFeaturesAreNotEncoded() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.layers["test"] = VectorTile.LayerContainer(
            features: [Feature(properties: ["name": "no geometry"])],
            boundingBox: nil)

        let data = tile.mvtData()
        #expect(data != nil)

        let decoded = try VectorTile(mvtData: try #require(data), x: 0, y: 0, z: 0)
        #expect(decoded.isEmpty)
    }

    @Test
    func compressionLevelsAreClamped() throws {
        var tile = try VectorTile(x: 0, y: 0, z: 0)
        tile.appendFeatures([Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)))], to: "test")

        let tooHigh = try #require(tile.mvtData(options: .init(compression: .level(100))))
        let tooLow = try #require(tile.mvtData(options: .init(compression: .level(-5))))

        #expect(tooHigh.isGzipped)
        #expect(tooLow.isGzipped)
        let decodedHigh = try VectorTile(mvtData: tooHigh, x: 0, y: 0, z: 0)
        let decodedLow = try VectorTile(mvtData: tooLow, x: 0, y: 0, z: 0)
        #expect(decodedHigh.features(for: "test").count == 1)
        #expect(decodedLow.features(for: "test").count == 1)
    }

    @Test
    func tileInfoCountsPropertiesAndVersions() throws {
        let data = try makeTileData(layers: [makePointLayer(version: 2)])
        let info = try #require(VectorTile.tileInfo(from: data))

        #expect(info.count == 1)
        #expect(info[0].name == "test")
        #expect(info[0].features == 1)
        #expect(info[0].pointFeatures == 1)
        #expect(info[0].version == 2)
    }

}
#endif
