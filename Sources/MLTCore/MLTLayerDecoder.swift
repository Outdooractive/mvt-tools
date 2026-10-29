import Foundation

/// A decoded MLT layer, still using tile-grid coordinates.
package struct MLTDecodedLayer {
    package var name: String
    package var extent: Int
    package var featureCount: Int
    package var ids: [UInt64?]
    package var geometries: [MLTGeometry]
    package var properties: [String: [MLTValue?]]
}

enum MLTLayerDecoder {

    static func decode(from reader: inout MLTByteReader) throws -> MLTDecodedLayer {
        let table = try MLTFeatureTable.decode(from: &reader)

        var ids: [UInt64?] = []
        var geometries: [MLTGeometry] = []
        var properties: [String: [MLTValue?]] = [:]
        var geometryFeatureCount: Int?
        var idFeatureCount: Int?
        var propertyFeatureCount: Int?

        for column in table.columns {
            let numStreams = try column.hasStreamCount
                ? Int(reader.readVarint32())
                : 1

            if column.isID {
                let decoded = try decodeIDs(
                    from: &reader,
                    column: column,
                    numStreams: numStreams)
                ids = decoded
                idFeatureCount = decoded.count
            }
            else if column.isGeometry {
                let decoded = try MLTGeometryDecoder.decode(
                    from: &reader,
                    numStreams: numStreams)
                geometries = decoded.geometries
                geometryFeatureCount = decoded.featureCount
            }
            else if column.isStructure {
                let decoded = try MLTPropertyDecoder.decodeSharedDictionary(
                    from: &reader,
                    column: column,
                    numStreams: numStreams)
                for (name, values) in decoded {
                    properties[name] = values
                    if !values.isEmpty {
                        propertyFeatureCount = values.count
                    }
                }
            }
            else {
                let decoded = try MLTPropertyDecoder.decode(
                    from: &reader,
                    column: column,
                    numStreams: numStreams)
                properties[decoded.name] = decoded.values
                propertyFeatureCount = decoded.featureCount
            }
        }

        let featureCount = try resolveFeatureCount(
            geometry: geometryFeatureCount,
            id: idFeatureCount,
            property: propertyFeatureCount,
            layer: table.name)

        guard geometries.count == featureCount else {
            throw MLTError.invalidData(
                "Layer '\(table.name)' has \(geometries.count) geometries for \(featureCount) features")
        }
        let emptyPropertyNames = properties.filter { $0.value.isEmpty }.map(\.key)
        for name in emptyPropertyNames {
            properties[name] = Array(repeating: nil, count: featureCount)
        }
        if !ids.isEmpty, ids.count != featureCount {
            throw MLTError.invalidData(
                "Layer '\(table.name)' has \(ids.count) ids for \(featureCount) features")
        }
        for (name, values) in properties where values.count != featureCount {
            throw MLTError.invalidData(
                "Layer '\(table.name)' column '\(name)' has \(values.count) values for \(featureCount) features")
        }

        return MLTDecodedLayer(
            name: table.name,
            extent: table.extent,
            featureCount: featureCount,
            ids: ids,
            geometries: geometries,
            properties: properties)
    }

    private static func resolveFeatureCount(
        geometry: Int?,
        id: Int?,
        property: Int?,
        layer: String
    ) throws -> Int {
        let counts = [geometry, id, property].compactMap { $0 }
        guard let first = counts.first else {
            throw MLTError.invalidData("Layer '\(layer)' has no geometry, id or property columns")
        }
        guard counts.allSatisfy({ $0 == first }) else {
            throw MLTError.invalidData(
                "Layer '\(layer)' has inconsistent feature counts: \(counts)")
        }
        return first
    }

    private static func decodeIDs(
        from reader: inout MLTByteReader,
        column: MLTColumn,
        numStreams: Int
    ) throws -> [UInt64?] {
        _ = numStreams

        var presentBits: [UInt8]?
        var presentCount = 0

        if column.nullable {
            let presentMetadata = try MLTStreamMetadata.decode(from: &reader)
            presentCount = presentMetadata.numValues
            presentBits = try MLTByteRLE.decodeBool(
                &reader,
                numValues: presentMetadata.numValues,
                byteLength: presentMetadata.byteLength)
        }

        let dataMetadata = try MLTStreamMetadata.decode(from: &reader)
        let values: [UInt64]
        if column.longID {
            values = try MLTIntegerDecoder.decodeUInt64(
                from: &reader, metadata: dataMetadata, signed: false)
        }
        else {
            values = try MLTIntegerDecoder.decodeUInt32(
                from: &reader, metadata: dataMetadata, signed: false
            ).map(UInt64.init)
        }

        guard let presentBits else {
            return values.map { Optional($0) }
        }

        guard presentCount >= 0, presentCount <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Invalid ID present count")
        }

        var result: [UInt64?] = Array(repeating: nil, count: presentCount)
        var valueIndex = 0
        for index in 0 ..< presentCount where MLTByteRLE.bit(presentBits, at: index) {
            guard valueIndex < values.count else {
                throw MLTError.invalidData("ID present stream has more values than the ID column")
            }
            result[index] = values[valueIndex]
            valueIndex += 1
        }
        guard valueIndex == values.count else {
            throw MLTError.invalidData("ID present stream has fewer values than the ID column")
        }
        return result
    }

}
