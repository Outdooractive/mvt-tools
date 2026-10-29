import Foundation

/// Parses a raw MLT tile into neutral layer models.
///
/// This type is the boundary between the format codec and `MVTTools`. It does
/// not depend on GISTools, projections or gzip.
package enum MLTDecoderCore {

    /// Decodes all tag `0x01` layers in a tile.
    package static func decode(_ data: Data) throws -> [MLTDecodedLayer] {
        var reader = MLTByteReader(data)
        var layers: [MLTDecodedLayer] = []

        while !reader.isAtEnd {
            let length = Int(try reader.readVarint32())
            guard length >= 0, length <= reader.remaining else {
                throw MLTError.unexpectedEnd(
                    offset: reader.offset,
                    needed: length,
                    available: reader.remaining)
            }

            var block = try reader.readSubReader(length)
            let tag = try block.readVarint32()
            switch tag {
            case MLTTileFraming.tag0x01:
                let layer = try MLTLayerDecoder.decode(from: &block)
                guard block.isAtEnd else {
                    throw MLTError.invalidData(
                        "\(block.remaining) trailing bytes in layer '\(layer.name)'")
                }
                layers.append(layer)

            case 2:
                throw MLTError.unsupported("MLT tag 0x02")

            default:
                continue
            }
        }

        return layers
    }

}
