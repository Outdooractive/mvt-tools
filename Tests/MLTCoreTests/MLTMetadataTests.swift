#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

struct MLTMetadataTests {

    @Test
    func scalarColumnTypeCodes() throws {
        for type in allScalarTypes {
            for nullable in [false, true] {
                let column = MLTColumn(
                    name: "value",
                    nullable: nullable,
                    scope: .feature,
                    kind: .scalar(type),
                    children: [])

                var writer = MLTByteWriter()
                try column.encode(to: &writer)
                var reader = MLTByteReader(writer.bytes)
                let decoded = try MLTColumn.decode(from: &reader)

                #expect(decoded.name == "value")
                #expect(decoded.nullable == nullable)
                #expect(decoded.scalarType == type)
                #expect(decoded.hasStreamCount == (type == .string))
                #expect(reader.isAtEnd)
            }
        }
    }

    @Test
    func idColumnTypeCodes() throws {
        for longID in [false, true] {
            for nullable in [false, true] {
                let column = MLTColumn(
                    name: "id",
                    nullable: nullable,
                    scope: .feature,
                    kind: .id(longID: longID),
                    children: [])

                var writer = MLTByteWriter()
                try column.encode(to: &writer)
                var reader = MLTByteReader(writer.bytes)
                let decoded = try MLTColumn.decode(from: &reader)

                #expect(decoded.isID)
                #expect(decoded.longID == longID)
                #expect(decoded.nullable == nullable)
                #expect(decoded.name == "id")
            }
        }
    }

    @Test
    func geometryAndStructColumns() throws {
        let geometry = MLTColumn(
            name: "geometry",
            nullable: false,
            scope: .feature,
            kind: .geometry,
            children: [])
        let structColumn = MLTColumn(
            name: "name",
            nullable: false,
            scope: .feature,
            kind: .structure,
            children: [
                MLTColumn(
                    name: ":en",
                    nullable: true,
                    scope: .feature,
                    kind: .scalar(.string),
                    children: []),
            ])

        var writer = MLTByteWriter()
        try geometry.encode(to: &writer)
        try structColumn.encode(to: &writer)

        var reader = MLTByteReader(writer.bytes)
        let decodedGeometry = try MLTColumn.decode(from: &reader)
        let decodedStruct = try MLTColumn.decode(from: &reader)

        #expect(decodedGeometry.isGeometry)
        #expect(decodedGeometry.name == "geometry")
        #expect(decodedStruct.isStructure)
        #expect(decodedStruct.children.count == 1)
        #expect(decodedStruct.children[0].name == ":en")
        #expect(decodedStruct.children[0].nullable)
    }

    @Test
    func featureTableRoundTrip() throws {
        let table = MLTFeatureTable(
            name: "layer",
            extent: 4096,
            columns: [
                MLTColumn(
                    name: "id",
                    nullable: true,
                    scope: .feature,
                    kind: .id(longID: true),
                    children: []),
                MLTColumn(
                    name: "geometry",
                    nullable: false,
                    scope: .feature,
                    kind: .geometry,
                    children: []),
                MLTColumn(
                    name: "value",
                    nullable: true,
                    scope: .feature,
                    kind: .scalar(.double),
                    children: []),
            ])

        var writer = MLTByteWriter()
        try table.encode(to: &writer)
        var reader = MLTByteReader(writer.bytes)
        let decoded = try MLTFeatureTable.decode(from: &reader)

        #expect(decoded.name == table.name)
        #expect(decoded.extent == table.extent)
        #expect(decoded.columns.count == table.columns.count)
        #expect(reader.isAtEnd)
    }

    @Test
    func unknownColumnTypeCodeIsRejected() {
        var writer = MLTByteWriter()
        writer.writeVarint32(31)
        var reader = MLTByteReader(writer.bytes)

        #expect(throws: MLTError.unsupported("column type code 31")) {
            _ = try MLTColumn.decode(from: &reader)
        }
    }

    @Test
    func emptyLayerNameIsRejected() {
        let table = MLTFeatureTable(name: "", extent: 4096, columns: [])
        #expect(throws: (any Error).self) {
            var writer = MLTByteWriter()
            try table.encode(to: &writer)
        }
    }

    @Test
    func tileFramingRoundTrip() throws {
        var writer = MLTByteWriter()
        MLTTileFraming.writeBlock(tag: 1, payload: [1, 2, 3], to: &writer)
        MLTTileFraming.writeBlock(tag: 2, payload: [4, 5], to: &writer)

        var reader = MLTByteReader(writer.bytes)
        let blocks = try MLTTileFraming.readBlocks(from: &reader)

        #expect(blocks.count == 2)
        #expect(blocks[0].tag == 1)
        #expect(blocks[0].payload == [1, 2, 3])
        #expect(blocks[1].tag == 2)
        #expect(blocks[1].payload == [4, 5])
        #expect(reader.isAtEnd)
    }

    @Test
    func streamMetadataRoundTrip() throws {
        let metadata = MLTStreamMetadata(
            physicalStreamType: .data,
            logicalStreamType: .dictionary(.vertex),
            logicalTechnique1: .componentwiseDelta,
            logicalTechnique2: .none,
            physicalTechnique: .varint,
            numValues: 1234,
            byteLength: 5678)

        var writer = MLTByteWriter()
        metadata.encode(to: &writer)
        writer.write(contentsOf: repeatElement(0, count: metadata.byteLength))
        var reader = MLTByteReader(writer.bytes)
        let decoded = try MLTStreamMetadata.decode(from: &reader)

        #expect(decoded.physicalStreamType == .data)
        #expect(decoded.logicalStreamType == .dictionary(.vertex))
        #expect(decoded.logicalTechnique1 == .componentwiseDelta)
        #expect(decoded.logicalTechnique2 == .none)
        #expect(decoded.physicalTechnique == .varint)
        #expect(decoded.numValues == 1234)
        #expect(decoded.byteLength == 5678)
    }

    @Test
    func streamMetadataRejectsOversizedPayload() {
        var writer = MLTByteWriter()
        writer.write(MLTPhysicalStreamType.data.rawValue << 4)
        writer.write(MLTPhysicalTechnique.varint.rawValue)
        writer.writeVarint32(1)
        writer.writeVarint32(100) // byteLength larger than the input
        let reader = MLTByteReader(writer.bytes)

        #expect(throws: (any Error).self) {
            var reader = reader
            _ = try MLTStreamMetadata.decode(from: &reader)
        }
    }

    private var allScalarTypes: [MLTScalarType] {
        [
            .boolean, .int8, .uint8, .int32, .uint32,
            .int64, .uint64, .float, .double, .string,
        ]
    }

}

#endif
