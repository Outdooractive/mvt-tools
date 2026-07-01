#if canImport(CoreLocation)
import CoreLocation
#endif
import CMLT
import Foundation
import GISTools
import Gzip

/// Encodes GISTools features into the MapLibre Tile (MLT) binary format.
enum MLTEncoder {

    /// Encodes layers into MLT binary data, with optional projection, clipping,
    /// simplification, and compression.
    ///
    /// - Parameters:
    ///   - layers: A dictionary of layer names to their ``VectorTile.LayerContainer``.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The source projection of the input coordinates (default: ``Projection/epsg4326``).
    ///   - options: Export options controlling buffer size, simplification, and compression.
    /// - Returns: The encoded MLT binary data, or `nil` on failure.
    static func encode(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTile.ExportOptions = .init()
    ) -> Data? {
        let encoder = mlt_encoder_create()
        defer { mlt_encoder_destroy(encoder) }

        let extent = UInt32(VectorTile.ExportOptions.extent)
        let projectionFunction = Projections.inverseProjection(
            for: projection, x: x, y: y, z: z, extent: Int(extent))

        // Determine the clipping bounding box.
        // z=0 tiles cover the whole world and are skipped (GISTools clipLine
        // has edge-case behaviour with full-span bounding boxes).
        var clipBoundingBox: BoundingBox?
        if z > 0  {
            switch projection {
            case .noSRID:
                break
            case .epsg3857:
                clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
            case .epsg4326:
                clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4326)
            case .epsg4978:
                clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4978)
            }
        }

        // Buffer size
        var bufferSize = 0
        switch options.bufferSize {
        case .no:
            bufferSize = 0
        case let .extent(bufferExtent):
            bufferSize = bufferExtent
        case let .pixel(pixel):
            bufferSize = Int((Double(pixel) / Double(VectorTile.ExportOptions.tileSize)) * Double(VectorTile.ExportOptions.extent))
        }

        // Simplify distance
        var simplifyDistance: CLLocationDistance = 0.0
        switch options.simplifyFeatures {
        case .no:
            simplifyDistance = 0.0
        case let .extent(simplifyExtent):
            let tileBoundsInMeters = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
            simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude) / Double(VectorTile.ExportOptions.extent) * Double(simplifyExtent)
        case let .meters(meters):
            simplifyDistance = meters
        }

        if bufferSize != 0,
           let boundingBoxToExpand = clipBoundingBox
        {
            let sqrt2 = 2.0.squareRoot()
            let diagonal = Double(extent) * sqrt2
            let bufferDiagonal = Double(bufferSize) * sqrt2
            let factor = bufferDiagonal / diagonal

            let diagonalLength = boundingBoxToExpand.southWest.distance(from: boundingBoxToExpand.northEast)
            let distance = diagonalLength * factor

            clipBoundingBox = boundingBoxToExpand.expanded(byDistance: distance)
        }

        for (layerName, container) in layers {
            guard container.features.isNotEmpty else { continue }

            let layerFeatures: [Feature] = if let clippedToBoundingBox = clipBoundingBox {
                if simplifyDistance > 0.0 {
                    container.features.compactMap({ $0.clipped(to: clippedToBoundingBox)?.simplified(tolerance: simplifyDistance) })
                }
                else {
                    container.features.compactMap({ $0.clipped(to: clippedToBoundingBox) })
                }
            }
            else {
                container.features
            }

            guard layerFeatures.isNotEmpty else { continue }
            mlt_encoder_begin_layer(encoder, layerName, extent)

            for feature in layerFeatures {
                // MLT only supports numeric IDs; skip non-integer IDs.
                let numericId = feature.id?.uint64Value
                let hasId = numericId != nil
                let featureId = numericId ?? 0

                // Map GISTools geometry type → MLT constant.
                let geomType: Int32
                switch feature.geometry.type {
                case .point:             geomType = Int32(kMLTGeometryPoint)
                case .multiPoint:        geomType = Int32(kMLTGeometryMultiPoint)
                case .lineString:        geomType = Int32(kMLTGeometryLineString)
                case .multiLineString:   geomType = Int32(kMLTGeometryMultiLineString)
                case .polygon:           geomType = Int32(kMLTGeometryPolygon)
                case .multiPolygon:      geomType = Int32(kMLTGeometryMultiPolygon)
                default:                 continue
                }

                // Project coordinates from geographic space to tile-extent space.
                // For multi-part geometries we collect part/ring sizes so the C++
                // encoder can reconstruct the structure.
                var partSizes: [UInt32] = []
                var polygonRingCounts: [UInt32] = []
                var projectedCoords: [(Int, Int)] = []

                let collectRing: ([Coordinate3D]) -> Void = { ring in
                    let projected = ring.map(projectionFunction)
                    partSizes.append(UInt32(projected.count))
                    projectedCoords.append(contentsOf: projected)
                }

                switch feature.geometry.type {
                case .multiLineString:
                    let mls = feature.geometry as! MultiLineString
                    for line in mls.coordinates { collectRing(line) }

                case .polygon:
                    let poly = feature.geometry as! Polygon
                    for ring in poly.rings { collectRing(ring.coordinates) }

                case .multiPolygon:
                    let mpoly = feature.geometry as! MultiPolygon
                    for poly in mpoly.coordinates {
                        polygonRingCounts.append(UInt32(poly.count))
                        for ring in poly { collectRing(ring) }
                    }

                default:
                    projectedCoords = feature.geometry.allCoordinates.map(projectionFunction)
                }

                var xs = projectedCoords.map { Float($0.0) }
                var ys = projectedCoords.map { Float($0.1) }

                // Build typed property list.
                var mltProps: [MLTProperty] = []
                for (key, value) in feature.properties {
                    let (type, strValue): (Int32, String)
                    if value is String {
                        type = Int32(kMLTPropString)
                        strValue = value as! String
                    }
                    else if let i = value as? Int {
                        type = Int32(kMLTPropInt)
                        strValue = String(i)
                    }
                    else if let i = value as? Int64 {
                        type = Int32(kMLTPropInt)
                        strValue = String(i)
                    }
                    else if let u = value as? UInt {
                        type = Int32(kMLTPropUInt)
                        strValue = String(u)
                    }
                    else if let d = value as? Double {
                        type = Int32(kMLTPropDouble)
                        strValue = String(d)
                    }
                    else if let f = value as? Float {
                        type = Int32(kMLTPropFloat)
                        strValue = String(f)
                    }
                    else if let b = value as? Bool {
                        type = Int32(kMLTPropBool)
                        strValue = b ? "true" : "false"
                    }
                    else {
                        type = Int32(kMLTPropString)
                        strValue = String(describing: value)
                    }
                    guard let k = strdup(key), let v = strdup(strValue) else { continue }
                    var prop = MLTProperty()
                    prop.key = UnsafePointer(k)
                    prop.type = type
                    prop.value = UnsafePointer(v)
                    mltProps.append(prop)
                }
                defer {
                    for prop in mltProps {
                        if let k = prop.key {
                            free(UnsafeMutablePointer(mutating: k))
                        }
                        if let v = prop.value {
                            free(UnsafeMutablePointer(mutating: v))
                        }
                    }
                }

                if partSizes.isEmpty {
                    mlt_encoder_add_feature(
                        encoder, featureId, hasId,
                        geomType,
                        &xs, &ys, xs.count,
                        nil, 0,
                        nil, 0,
                        &mltProps, mltProps.count)
                }
                else if polygonRingCounts.isEmpty {
                    mlt_encoder_add_feature(
                        encoder, featureId, hasId,
                        geomType,
                        &xs, &ys, xs.count,
                        &partSizes, partSizes.count,
                        nil, 0,
                        &mltProps, mltProps.count)
                }
                else {
                    mlt_encoder_add_feature(
                        encoder, featureId, hasId,
                        geomType,
                        &xs, &ys, xs.count,
                        &partSizes, partSizes.count,
                        &polygonRingCounts, polygonRingCounts.count,
                        &mltProps, mltProps.count)
                }
            }
        }

        // Finalize and optionally compress.
        var outLength: Int = 0
        guard let buffer = mlt_encoder_finish(encoder, &outLength) else {
            return nil
        }
        defer { mlt_buffer_free(buffer) }

        let serializedData = Data(bytes: buffer, count: outLength)
        if options.compression != .no {
            var value = 6 // default
            if case let .level(compressionLevel) = options.compression {
                value = max(0, min(9, compressionLevel))
            }
            let level = CompressionLevel(rawValue: Int32(value))
            return (try? serializedData.gzipped(level: level)) ?? serializedData
        }
        else {
            return serializedData
        }
    }

}
