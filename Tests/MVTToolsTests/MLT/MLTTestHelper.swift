import Foundation
import Gzip

/// Test helper for inspecting raw MLT binary metadata.
///
/// This parser reads just enough of the MLT format to extract column type
/// codes from the layer metadata, allowing tests to verify that integer
/// properties are encoded as INT_32 (not INT_64) so that the JS/WASM decoder
/// produces JavaScript Numbers rather than BigInts.
enum MLTTestHelper {

    /// Reads the varint at `pos` and returns the decoded value and new position.
    private static func readVarint(_ data: Data, pos: Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var p = pos
        while p < data.count {
            let b = UInt64(data[p])
            p += 1
            result |= (b & 0x7F) << shift
            if (b & 0x80) == 0 {
                break
            }
            shift += 7
        }
        return (result, p)
    }

    /// Reads a length-prefixed UTF-8 string.
    private static func readString(_ data: Data, pos: Int) -> (String, Int) {
        let (length, p) = readVarint(data, pos: pos)
        let len = Int(length)
        let s = String(data: data.subdata(in: p ..< (p + len)), encoding: .utf8) ?? ""
        return (s, p + len)
    }

    /// MLT column type codes (from the spec's `type_map.hpp`).
    /// - 0–3: ID columns
    /// - 4: GEOMETRY
    /// - 10–29: scalar types (even = non-nullable, odd = nullable)
    /// - 30: STRUCT
    static let typeCodeNames: [Int: String] = [
        10: "BOOLEAN", 11: "BOOLEAN?",
        12: "INT_8", 13: "INT_8?",
        14: "UINT_8", 15: "UINT_8?",
        16: "INT_32", 17: "INT_32?",
        18: "UINT_32", 19: "UINT_32?",
        20: "INT_64", 21: "INT_64?",
        22: "UINT_64", 23: "UINT_64?",
        24: "FLOAT", 25: "FLOAT?",
        26: "DOUBLE", 27: "DOUBLE?",
        28: "STRING", 29: "STRING?",
    ]

    /// Extracts the column type codes for a named layer from raw (decompressed) MLT data.
    ///
    /// - Parameters:
    ///   - data: Raw MLT binary data (will be decompressed if gzipped).
    ///   - layerName: The layer to inspect.
    /// - Returns: An array of type codes for the layer's columns, or an empty array if the layer is not found.
    static func columnTypeCodes(in data: Data, layerName: String) -> [Int] {
        let rawData = data.isGzipped ? ((try? data.gunzipped()) ?? data) : data
        var pos = 0

        while pos < rawData.count {
            let (blockLen, p1) = readVarint(rawData, pos: pos)
            let blockStart = p1
            let blockEnd = blockStart + Int(blockLen)
            guard blockEnd <= rawData.count else { break }

            let (tag, p2) = readVarint(rawData, pos: blockStart)
            if tag != 1 {
                pos = blockEnd
                continue
            }

            let (name, p3) = readString(rawData, pos: p2)
            let (_, p4) = readVarint(rawData, pos: p3) // extent
            let (colCount, p5) = readVarint(rawData, pos: p4)

            if name == layerName {
                var typeCodes: [Int] = []
                var cp = p5
                for _ in 0 ..< Int(colCount) {
                    let (typeCode, np) = readVarint(rawData, pos: cp)
                    typeCodes.append(Int(typeCode))
                    cp = np
                    // Skip column name if typeCode >= 10
                    if typeCode >= 10 {
                        let (_, np2) = readString(rawData, pos: cp)
                        cp = np2
                    }
                    // Skip children if STRUCT (typeCode == 30)
                    if typeCode == 30 {
                        let (childCount, np3) = readVarint(rawData, pos: cp)
                        cp = np3
                        for _ in 0 ..< Int(childCount) {
                            let (childType, np4) = readVarint(rawData, pos: cp)
                            cp = np4
                            if childType >= 10 {
                                let (_, np5) = readString(rawData, pos: cp)
                                cp = np5
                            }
                        }
                    }
                }
                return typeCodes
            }
            else {
                // Skip to end of block
                pos = blockEnd
                continue
            }
        }

        return []
    }

}