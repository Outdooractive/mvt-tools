#if EnableMLT
#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import Gzip
import MLTCore
import struct GISTools.Polygon

/// Pure Swift MLT encoder.
///
/// Converts `VectorTile` features into neutral ``MLTEncodableLayer`` values and
/// delegates the wire format to ``MLTEncoderCore``. For every stream it chooses
/// the smallest of the enabled layouts: plain/delta/RLE/delta-RLE (plus FastPFOR
/// when enabled) for integers, componentwise delta or a Hilbert/Morton vertex
/// dictionary for geometry, and plain/dictionary/shared/FSST for strings. The
/// feature switches come from ``VectorTile/ExportOptions/mlt``.
enum MLTEncoderSwift {

    static func encode(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTile.ExportOptions = .init()
    ) -> Data? {
        do {
            let data = try encodeTile(
                layers: layers,
                x: x,
                y: y,
                z: z,
                projection: projection,
                options: options)
            return try compress(data, options: options.compression)
        }
        catch {
            return nil
        }
    }

    private static func compress(
        _ data: Data,
        options: VectorTile.ExportOptions.CompressionOptions
    ) throws -> Data {
        switch options {
        case .no:
            return data
        case .default:
            return try data.gzipped(level: .defaultCompression)
        case let .level(level):
            let clamped = max(0, min(9, level))
            return try data.gzipped(level: CompressionLevel(rawValue: Int32(clamped)))
        }
    }

    private static func encodeTile(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection,
        options: VectorTile.ExportOptions
    ) throws -> Data {
        let extent = VectorTile.ExportOptions.extent
        let projectionFunction = Projections.inverseProjection(
            for: projection, x: x, y: y, z: z, extent: extent)

        var clipBoundingBox: BoundingBox?
        if projection.hasSRID {
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: projection)
        }

        var bufferSize = 0
        switch options.bufferSize {
        case .no:
            bufferSize = 0
        case let .extent(value):
            bufferSize = value
        case let .pixel(pixel):
            bufferSize = Int(
                (Double(pixel) / Double(VectorTile.ExportOptions.tileSize))
                    * Double(VectorTile.ExportOptions.extent))
        }

        var simplifyDistance: Double = 0.0
        switch options.simplifyFeatures {
        case .no:
            simplifyDistance = 0.0
        case let .extent(value):
            let tileBoundsInMeters = MapTile(x: x, y: y, z: z)
                .boundingBox(projection: .epsg3857)
            simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude)
                / Double(VectorTile.ExportOptions.extent) * Double(value)
        case let .meters(meters):
            simplifyDistance = meters
        }

        if bufferSize != 0, let boundingBox = clipBoundingBox {
            clipBoundingBox = VectorTile.expanded(boundingBox, byBufferSize: bufferSize)
        }

        var encodableLayers: [MLTEncodableLayer] = []

        for (layerName, container) in layers.sorted(by: { $0.key < $1.key }) {
            guard !layerName.isEmpty, container.features.isNotEmpty else { continue }

            let processed = VectorTile.processedFeatures(
                container.features,
                clipBoundingBox: clipBoundingBox,
                simplifyDistance: simplifyDistance)

            let features = processed.compactMap { feature -> MLTEncodableFeature? in
                guard let geometry = feature.geometry,
                      let encoded = encodeGeometry(geometry, project: projectionFunction)
                else {
                    return nil
                }
                return MLTEncodableFeature(
                    id: feature.id?.uint64Value,
                    hasNumericID: feature.id?.uint64Value != nil,
                    geometry: encoded,
                    properties: feature.properties)
            }

            guard features.isNotEmpty else { continue }

            encodableLayers.append(MLTEncodableLayer(
                name: layerName,
                extent: extent,
                features: features))
        }

        return try MLTEncoderCore.encode(
            layers: encodableLayers,
            options: MLTEncoderOptions(
                useStringDictionaries: options.mlt.useStringDictionaries,
                useSharedStringDictionaries: options.mlt.useSharedStringDictionaries,
                useFSST: options.mlt.useFSST,
                useFastPFOR: options.mlt.useFastPFOR,
                useVertexDictionaries: options.mlt.useVertexDictionaries,
                useIntegerDeltaRLE: options.mlt.useIntegerDeltaRLE))
    }

}

// MARK: - Geometry conversion

extension MLTEncoderSwift {

    fileprivate static func encodeGeometry(
        _ geometry: GeoJsonGeometry,
        project: (Coordinate3D) -> (Int, Int)
    ) -> MLTGeometry? {
        switch geometry.type {
        case .point:
            guard let point = geometry as? Point else { return nil }
            return .point(tileCoordinate(point.coordinate, project: project))

        case .multiPoint:
            guard let multiPoint = geometry as? MultiPoint else { return nil }
            return .multiPoint(multiPoint.coordinates.map { tileCoordinate($0, project: project) })

        case .lineString:
            guard let line = geometry as? LineString else { return nil }
            return .lineString(line.coordinates.map { tileCoordinate($0, project: project) })

        case .multiLineString:
            guard let multiLine = geometry as? MultiLineString else { return nil }
            return .multiLineString(
                multiLine.coordinates.map { line in
                    line.map { tileCoordinate($0, project: project) }
                })

        case .polygon:
            guard let polygon = geometry as? Polygon else { return nil }
            let rings = polygon.rings.map { ring -> [MLTTileCoordinate] in
                var coordinates = ring.coordinates.map { tileCoordinate($0, project: project) }
                if coordinates.count > 1, coordinates.first == coordinates.last {
                    coordinates.removeLast()
                }
                return coordinates
            }
            return .polygon(normalizePolygonWinding(rings))

        case .multiPolygon:
            guard let multiPolygon = geometry as? MultiPolygon else { return nil }
            let polygons = multiPolygon.coordinates.map { polygon -> [[MLTTileCoordinate]] in
                let rings = polygon.map { ring -> [MLTTileCoordinate] in
                    var coordinates = ring.map { tileCoordinate($0, project: project) }
                    if coordinates.count > 1, coordinates.first == coordinates.last {
                        coordinates.removeLast()
                    }
                    return coordinates
                }
                return normalizePolygonWinding(rings)
            }
            return .multiPolygon(polygons)

        default:
            return nil
        }
    }

    private static func tileCoordinate(
        _ coordinate: Coordinate3D,
        project: (Coordinate3D) -> (Int, Int)
    ) -> MLTTileCoordinate {
        let projected = project(coordinate)
        return MLTTileCoordinate(
            x: Int32(clamping: projected.0),
            y: Int32(clamping: projected.1))
    }

    private static func tileArea(_ ring: [MLTTileCoordinate]) -> Double {
        guard ring.count > 2 else { return 0.0 }
        var sum = 0.0
        for index in ring.indices {
            let current = ring[index]
            let next = ring[(index + 1) % ring.count]
            sum += Double(next.x - current.x) * Double(current.y + next.y)
        }
        return sum
    }

    private static func normalizePolygonWinding(
        _ rings: [[MLTTileCoordinate]]
    ) -> [[MLTTileCoordinate]] {
        guard var exterior = rings.first else { return rings }
        if tileArea(exterior) > 0 {
            exterior.reverse()
        }
        var result: [[MLTTileCoordinate]] = [exterior]
        for hole in rings.dropFirst() {
            var value = hole
            if tileArea(value) < 0 {
                value.reverse()
            }
            result.append(value)
        }
        return result
    }

}

#endif
