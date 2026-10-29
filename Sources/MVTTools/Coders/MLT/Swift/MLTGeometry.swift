#if EnableMLT
import Foundation

// Geometry topology rules follow the upstream `maplibre-tile-spec`
// specification and decoder (MIT OR Apache-2.0).
/// A coordinate in the tile's integer grid (before projection).
struct MLTTileCoordinate: Equatable, Sendable {
    var x: Int32
    var y: Int32

    init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }

}

/// An MLT geometry with coordinates still in the tile grid.
enum MLTGeometry: Equatable, Sendable {
    case point(MLTTileCoordinate)
    case multiPoint([MLTTileCoordinate])
    case lineString([MLTTileCoordinate])
    case multiLineString([[MLTTileCoordinate]])
    case polygon([[MLTTileCoordinate]])
    case multiPolygon([[[MLTTileCoordinate]]])
}

enum MLTGeometryType: UInt32 {
    case point = 0
    case lineString = 1
    case polygon = 2
    case multiPoint = 3
    case multiLineString = 4
    case multiPolygon = 5
}

/// Decodes a single MLT geometry column.
enum MLTGeometryDecoder {

    struct Result {
        var geometries: [MLTGeometry]
        var featureCount: Int
    }

    static func decode(
        from reader: inout MLTByteReader,
        numStreams: Int
    ) throws -> Result {
        guard numStreams >= 1 else {
            throw MLTError.invalidData("Geometry column has no streams")
        }

        let geometryTypeMetadata = try MLTStreamMetadata.decode(from: &reader)
        let rawTypes = try MLTIntegerDecoder.decodeUInt32(
            from: &reader,
            metadata: geometryTypeMetadata,
            signed: false)

        let types = try rawTypes.map { raw -> MLTGeometryType in
            guard let type = MLTGeometryType(rawValue: raw) else {
                throw MLTError.invalidData("Invalid geometry type \(raw)")
            }
            return type
        }
        guard types.count <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Geometry column has too many features")
        }

        var geometryLengths: [UInt32]?
        var partLengths: [UInt32]?
        var ringLengths: [UInt32]?
        var triangleLengths: [UInt32]?
        var vertexOffsets: [UInt32] = []
        var indexBuffer: [UInt32] = []
        var vertexBuffer: [Int32] = []
        var mortonCodes: [UInt32]?
        var mortonSettings: (numBits: Int, coordinateShift: Int32)?

        for _ in 1 ..< numStreams {
            let metadata = try MLTStreamMetadata.decode(from: &reader)

            switch metadata.physicalStreamType {
            case .length:
                guard case let .length(lengthType) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Length stream is missing its logical type")
                }
                switch lengthType {
                case .geometries:
                    geometryLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                case .parts:
                    partLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                case .rings:
                    ringLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                case .triangles:
                    triangleLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                case .varBinary, .symbol, .dictionary:
                    throw MLTError.unsupported("Length type \(lengthType) in a geometry column")
                }

            case .offset:
                guard case let .offset(offsetType) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Offset stream is missing its logical type")
                }
                switch offsetType {
                case .vertex:
                    vertexOffsets = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                case .index:
                    indexBuffer = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                case .string, .key:
                    throw MLTError.unsupported("Offset type \(offsetType) in a geometry column")
                }

            case .data:
                guard case let .dictionary(dictionaryType) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Data stream is missing its dictionary type")
                }
                switch dictionaryType {
                case .vertex:
                    vertexBuffer = try decodeVertexBuffer(
                        from: &reader, metadata: metadata)
                case .morton:
                    guard let numBits = metadata.mortonNumBits,
                          let coordinateShift = metadata.mortonCoordinateShift
                    else {
                        throw MLTError.invalidData("Morton stream is missing its metadata")
                    }
                    mortonCodes = try MLTIntegerDecoder.decodeMortonCodes(
                        from: &reader, metadata: metadata)
                    mortonSettings = (numBits, Int32(truncatingIfNeeded: coordinateShift))
                default:
                    throw MLTError.unsupported("Dictionary type \(dictionaryType) in a geometry column")
                }

            case .present:
                // Geometry present streams are not part of the current format.
                throw MLTError.unsupported("Present stream in a geometry column")
            }
        }

        _ = triangleLengths
        _ = indexBuffer

        if let codes = mortonCodes, vertexOffsets.isEmpty {
            vertexBuffer = try expandMortonCodes(
                codes,
                settings: mortonSettings)
            mortonCodes = nil
        }

        let geometryOffsets: [UInt32]?
        let partOffsets: [UInt32]?
        let ringOffsets: [UInt32]?

        if let geometryLengths {
            geometryOffsets = try buildRootOffsets(
                types: types,
                lengths: geometryLengths,
                threshold: MLTGeometryType.polygon.rawValue)
            if let partLengths, let ringLengths {
                partOffsets = try buildLevel1Offsets(
                    types: types,
                    rootOffsets: geometryOffsets ?? [],
                    lengths: partLengths,
                    isLineStringPresent: false)
                ringOffsets = try buildLevel2Offsets(
                    types: types,
                    rootOffsets: geometryOffsets ?? [],
                    level1Offsets: partOffsets ?? [],
                    lengths: ringLengths)
            }
            else if let partLengths {
                partOffsets = try buildLevel1WithoutRingBufferOffsets(
                    types: types,
                    rootOffsets: geometryOffsets ?? [],
                    lengths: partLengths)
                ringOffsets = nil
            }
            else {
                partOffsets = nil
                ringOffsets = nil
            }
        }
        else if let partLengths, let ringLengths {
            partOffsets = try buildRootOffsets(
                types: types,
                lengths: partLengths,
                threshold: MLTGeometryType.lineString.rawValue)
            ringOffsets = try buildLevel1Offsets(
                types: types,
                rootOffsets: partOffsets ?? [],
                lengths: ringLengths,
                isLineStringPresent: true)
            geometryOffsets = nil
        }
        else if let partLengths {
            partOffsets = try buildRootOffsets(
                types: types,
                lengths: partLengths,
                threshold: MLTGeometryType.point.rawValue)
            ringOffsets = nil
            geometryOffsets = nil
        }
        else {
            geometryOffsets = nil
            partOffsets = nil
            ringOffsets = nil
        }

        var vertexReader = MLTVertexReader(
            vertices: vertexBuffer,
            vertexOffsets: vertexOffsets,
            mortonCodes: mortonCodes,
            mortonSettings: mortonSettings)

        let geometries = try buildGeometries(
            types: types,
            geometryOffsets: geometryOffsets,
            partOffsets: partOffsets,
            ringOffsets: ringOffsets,
            vertexReader: &vertexReader)

        return Result(geometries: geometries, featureCount: types.count)
    }

    // MARK: - Vertex decoding

    private static func decodeVertexBuffer(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata
    ) throws -> [Int32] {
        if metadata.logicalTechnique1 == .componentwiseDelta {
            let values = try MLTIntegerDecoder.decodeUInt32(
                from: &reader, metadata: metadata, signed: true)
            return values.map { Int32(bitPattern: $0) }
        }

        let raw = try MLTIntegerDecoder.decodeUInt32(
            from: &reader, metadata: metadata, signed: false)
        var values = raw.map { Int32(bitPattern: $0) }
        applyComponentwiseDelta(&values)
        return values
    }

    private static func applyComponentwiseDelta(_ values: inout [Int32]) {
        guard values.count >= 2 else { return }
        values[0] = MLTZigZag.decode(UInt32(bitPattern: values[0]))
        values[1] = MLTZigZag.decode(UInt32(bitPattern: values[1]))
        var index = 2
        while index < values.count {
            let decoded = MLTZigZag.decode(UInt32(bitPattern: values[index]))
            values[index] = decoded &+ values[index - 2]
            index += 1
        }
    }

    private static func expandMortonCodes(
        _ codes: [UInt32],
        settings: (numBits: Int, coordinateShift: Int32)?
    ) throws -> [Int32] {
        guard let settings else {
            throw MLTError.invalidData("Morton codes without settings")
        }
        var result: [Int32] = []
        result.reserveCapacity(codes.count * 2)
        for code in codes {
            result.append(
                MLTMorton.decode(code, numBits: settings.numBits) &- settings.coordinateShift)
            result.append(
                MLTMorton.decode(code >> 1, numBits: settings.numBits) &- settings.coordinateShift)
        }
        return result
    }

    // MARK: - Topology offsets

    private static func buildRootOffsets(
        types: [MLTGeometryType],
        lengths: [UInt32],
        threshold: UInt32
    ) throws -> [UInt32] {
        guard types.count < MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Too many geometries")
        }
        var offsets: [UInt32] = [0]
        offsets.reserveCapacity(types.count + 1)
        var lengthIndex = 0
        for type in types {
            let count: UInt32
            if type.rawValue > threshold {
                guard lengthIndex < lengths.count else {
                    throw MLTError.invalidData("Root length stream is too short")
                }
                count = lengths[lengthIndex]
                lengthIndex += 1
            }
            else {
                count = 1
            }
            offsets.append(offsets[offsets.count - 1] &+ count)
        }
        guard lengthIndex == lengths.count else {
            throw MLTError.invalidData("Root length stream has trailing values")
        }
        return offsets
    }

    private static func buildLevel1Offsets(
        types: [MLTGeometryType],
        rootOffsets: [UInt32],
        lengths: [UInt32],
        isLineStringPresent: Bool
    ) throws -> [UInt32] {
        guard rootOffsets.count == types.count + 1 else {
            throw MLTError.invalidData("Root offset stream does not match the geometry types")
        }
        let size = Int(rootOffsets[rootOffsets.count - 1]) + 1
        guard size >= 1, size <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Too many parts")
        }
        var offsets = [UInt32](repeating: 0, count: size)
        var offsetIndex = 1
        var lengthIndex = 0
        var previous: UInt32 = 0

        for index in types.indices {
            let type = types[index]
            let count = Int(rootOffsets[index + 1] - rootOffsets[index])
            let hasLength = type == .multiPolygon
                || type == .polygon
                || (isLineStringPresent && (type == .multiLineString || type == .lineString))

            for _ in 0 ..< count {
                if hasLength {
                    guard lengthIndex < lengths.count else {
                        throw MLTError.invalidData("Part length stream is too short")
                    }
                    previous = previous &+ lengths[lengthIndex]
                    lengthIndex += 1
                }
                else {
                    previous = previous &+ 1
                }
                guard offsetIndex < offsets.count else {
                    throw MLTError.invalidData("Part offset stream overflow")
                }
                offsets[offsetIndex] = previous
                offsetIndex += 1
            }
        }
        guard offsetIndex == offsets.count, lengthIndex == lengths.count else {
            throw MLTError.invalidData("Part offset stream does not match the geometry types")
        }
        return offsets
    }

    private static func buildLevel1WithoutRingBufferOffsets(
        types: [MLTGeometryType],
        rootOffsets: [UInt32],
        lengths: [UInt32]
    ) throws -> [UInt32] {
        guard rootOffsets.count == types.count + 1 else {
            throw MLTError.invalidData("Root offset stream does not match the geometry types")
        }
        let size = Int(rootOffsets[rootOffsets.count - 1]) + 1
        guard size >= 1, size <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Too many parts")
        }
        var offsets = [UInt32](repeating: 0, count: size)
        var offsetIndex = 1
        var lengthIndex = 0
        var previous: UInt32 = 0

        for index in types.indices {
            let type = types[index]
            let count = Int(rootOffsets[index + 1] - rootOffsets[index])
            let hasLength = type == .multiLineString || type == .lineString

            for _ in 0 ..< count {
                if hasLength {
                    guard lengthIndex < lengths.count else {
                        throw MLTError.invalidData("Part length stream is too short")
                    }
                    previous = previous &+ lengths[lengthIndex]
                    lengthIndex += 1
                }
                else {
                    previous = previous &+ 1
                }
                guard offsetIndex < offsets.count else {
                    throw MLTError.invalidData("Part offset stream overflow")
                }
                offsets[offsetIndex] = previous
                offsetIndex += 1
            }
        }
        guard offsetIndex == offsets.count, lengthIndex == lengths.count else {
            throw MLTError.invalidData("Part offset stream does not match the geometry types")
        }
        return offsets
    }

    private static func buildLevel2Offsets(
        types: [MLTGeometryType],
        rootOffsets: [UInt32],
        level1Offsets: [UInt32],
        lengths: [UInt32]
    ) throws -> [UInt32] {
        guard rootOffsets.count == types.count + 1 else {
            throw MLTError.invalidData("Root offset stream does not match the geometry types")
        }
        let size = Int(level1Offsets[level1Offsets.count - 1]) + 1
        guard size >= 1, size <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Too many rings")
        }
        var offsets = [UInt32](repeating: 0, count: size)
        var level1Index = 1
        var offsetIndex = 1
        var lengthIndex = 0
        var previous: UInt32 = 0

        for index in types.indices {
            let type = types[index]
            let count = Int(rootOffsets[index + 1] - rootOffsets[index])
            let hasLength = type != .point && type != .multiPoint

            for _ in 0 ..< count {
                if hasLength {
                    guard level1Index < level1Offsets.count else {
                        throw MLTError.invalidData("Part offset stream is too short")
                    }
                    let parts = Int(level1Offsets[level1Index] - level1Offsets[level1Index - 1])
                    level1Index += 1
                    for _ in 0 ..< parts {
                        guard lengthIndex < lengths.count else {
                            throw MLTError.invalidData("Ring length stream is too short")
                        }
                        previous = previous &+ lengths[lengthIndex]
                        lengthIndex += 1
                        guard offsetIndex < offsets.count else {
                            throw MLTError.invalidData("Ring offset stream overflow")
                        }
                        offsets[offsetIndex] = previous
                        offsetIndex += 1
                    }
                }
                else {
                    level1Index += 1
                    previous = previous &+ 1
                    guard offsetIndex < offsets.count else {
                        throw MLTError.invalidData("Ring offset stream overflow")
                    }
                    offsets[offsetIndex] = previous
                    offsetIndex += 1
                }
            }
        }
        guard offsetIndex == offsets.count, lengthIndex == lengths.count else {
            throw MLTError.invalidData("Ring offset stream does not match the geometry types")
        }
        return offsets
    }

    // MARK: - Geometry assembly

    private static func buildGeometries(
        types: [MLTGeometryType],
        geometryOffsets: [UInt32]?,
        partOffsets: [UInt32]?,
        ringOffsets: [UInt32]?,
        vertexReader: inout MLTVertexReader
    ) throws -> [MLTGeometry] {
        let containsPolygon = types.contains { $0 == .polygon || $0 == .multiPolygon }
        var geometries: [MLTGeometry] = []
        geometries.reserveCapacity(types.count)

        var geometryOffsetCounter = 1
        var partOffsetCounter = 1
        var ringOffsetCounter = 1

        for type in types {
            switch type {
            case .point:
                let coordinates = try vertexReader.read(count: 1, closeRing: false)
                guard let coordinate = coordinates.first else {
                    throw MLTError.invalidData("Missing point coordinate")
                }
                geometries.append(.point(coordinate))
                if geometryOffsets != nil {
                    geometryOffsetCounter += 1
                }
                partOffsetCounter += 1
                ringOffsetCounter += 1

            case .multiPoint:
                let count = try span(
                    geometryOffsets, at: geometryOffsetCounter, name: "geometry")
                geometryOffsetCounter += 1
                let coordinates = try vertexReader.read(count: count, closeRing: false)
                geometries.append(.multiPoint(coordinates))
                partOffsetCounter += count
                ringOffsetCounter += count

            case .lineString:
                let count: Int
                if containsPolygon {
                    count = try span(ringOffsets, at: ringOffsetCounter, name: "ring")
                    ringOffsetCounter += 1
                }
                else {
                    count = try span(partOffsets, at: partOffsetCounter, name: "part")
                }
                partOffsetCounter += 1
                let coordinates = try vertexReader.read(count: count, closeRing: false)
                geometries.append(.lineString(coordinates))
                if geometryOffsets != nil {
                    geometryOffsetCounter += 1
                }

            case .multiLineString:
                let lineCount = try span(
                    geometryOffsets, at: geometryOffsetCounter, name: "geometry")
                geometryOffsetCounter += 1
                var lines: [[MLTTileCoordinate]] = []
                lines.reserveCapacity(lineCount)

                for _ in 0 ..< lineCount {
                    let count: Int
                    if containsPolygon {
                        count = try span(ringOffsets, at: ringOffsetCounter, name: "ring")
                        ringOffsetCounter += 1
                    }
                    else {
                        count = try span(partOffsets, at: partOffsetCounter, name: "part")
                    }
                    partOffsetCounter += 1
                    lines.append(try vertexReader.read(count: count, closeRing: false))
                }
                geometries.append(.multiLineString(lines))

            case .polygon:
                let ringCount = try span(
                    partOffsets, at: partOffsetCounter, name: "part")
                partOffsetCounter += 1
                var rings: [[MLTTileCoordinate]] = []
                rings.reserveCapacity(ringCount)

                for _ in 0 ..< ringCount {
                    let count = try span(ringOffsets, at: ringOffsetCounter, name: "ring")
                    ringOffsetCounter += 1
                    rings.append(try vertexReader.read(count: count, closeRing: true))
                }
                geometries.append(.polygon(rings))
                if geometryOffsets != nil {
                    geometryOffsetCounter += 1
                }

            case .multiPolygon:
                let polygonCount = try span(
                    geometryOffsets, at: geometryOffsetCounter, name: "geometry")
                geometryOffsetCounter += 1
                var polygons: [[[MLTTileCoordinate]]] = []
                polygons.reserveCapacity(polygonCount)

                for _ in 0 ..< polygonCount {
                    let ringCount = try span(
                        partOffsets, at: partOffsetCounter, name: "part")
                    partOffsetCounter += 1
                    var rings: [[MLTTileCoordinate]] = []
                    rings.reserveCapacity(ringCount)

                    for _ in 0 ..< ringCount {
                        let count = try span(ringOffsets, at: ringOffsetCounter, name: "ring")
                        ringOffsetCounter += 1
                        rings.append(try vertexReader.read(count: count, closeRing: true))
                    }
                    polygons.append(rings)
                }
                geometries.append(.multiPolygon(polygons))
            }
        }

        return geometries
    }

    private static func span(
        _ offsets: [UInt32]?,
        at index: Int,
        name: String
    ) throws -> Int {
        guard let offsets, index > 0, index < offsets.count else {
            throw MLTError.invalidData("Missing \(name) offsets")
        }
        let start = offsets[index - 1]
        let end = offsets[index]
        guard end >= start else {
            throw MLTError.invalidData("Invalid \(name) offsets")
        }
        let count = Int(end - start)
        guard count <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Too many \(name) values")
        }
        return count
    }

}

// MARK: - Vertex reader

private struct MLTVertexReader {

    let vertices: [Int32]
    let vertexOffsets: [UInt32]
    let mortonCodes: [UInt32]?
    let mortonSettings: (numBits: Int, coordinateShift: Int32)?

    private var flatIndex = 0
    private var offsetIndex = 0

    init(
        vertices: [Int32],
        vertexOffsets: [UInt32],
        mortonCodes: [UInt32]?,
        mortonSettings: (numBits: Int, coordinateShift: Int32)?
    ) {
        self.vertices = vertices
        self.vertexOffsets = vertexOffsets
        self.mortonCodes = mortonCodes
        self.mortonSettings = mortonSettings
    }

    mutating func read(count: Int, closeRing: Bool) throws -> [MLTTileCoordinate] {
        guard count >= 0, count <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Invalid vertex count \(count)")
        }
        var result: [MLTTileCoordinate] = []
        result.reserveCapacity(closeRing ? count + 1 : count)

        if vertexOffsets.isEmpty {
            if let mortonCodes {
                guard let mortonSettings else {
                    throw MLTError.invalidData("Morton codes without settings")
                }
                for _ in 0 ..< count {
                    guard flatIndex < mortonCodes.count else {
                        throw MLTError.invalidData("Vertex buffer is too short")
                    }
                    result.append(Self.decodeMorton(
                        mortonCodes[flatIndex], settings: mortonSettings))
                    flatIndex += 1
                }
            }
            else {
                for _ in 0 ..< count {
                    guard flatIndex + 1 < vertices.count else {
                        throw MLTError.invalidData("Vertex buffer is too short")
                    }
                    result.append(MLTTileCoordinate(
                        x: vertices[flatIndex],
                        y: vertices[flatIndex + 1]))
                    flatIndex += 2
                }
            }
        }
        else {
            for _ in 0 ..< count {
                guard offsetIndex < vertexOffsets.count else {
                    throw MLTError.invalidData("Vertex offset stream is too short")
                }
                let index = Int(vertexOffsets[offsetIndex])
                offsetIndex += 1

                if let mortonCodes {
                    guard let mortonSettings else {
                        throw MLTError.invalidData("Morton codes without settings")
                    }
                    guard index < mortonCodes.count else {
                        throw MLTError.invalidData("Morton vertex index is out of bounds")
                    }
                    result.append(Self.decodeMorton(
                        mortonCodes[index], settings: mortonSettings))
                }
                else {
                    let offset = index * 2
                    guard offset + 1 < vertices.count else {
                        throw MLTError.invalidData("Vertex dictionary index is out of bounds")
                    }
                    result.append(MLTTileCoordinate(
                        x: vertices[offset],
                        y: vertices[offset + 1]))
                }
            }
        }

        if closeRing, let first = result.first, result.last != first {
            result.append(first)
        }
        return result
    }

    private static func decodeMorton(
        _ code: UInt32,
        settings: (numBits: Int, coordinateShift: Int32)
    ) -> MLTTileCoordinate {
        MLTTileCoordinate(
            x: MLTMorton.decode(code, numBits: settings.numBits) &- settings.coordinateShift,
            y: MLTMorton.decode(code >> 1, numBits: settings.numBits) &- settings.coordinateShift)
    }

}

#endif
