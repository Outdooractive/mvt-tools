import Foundation

/// Hilbert curve index for sorting MLT vertex dictionaries.
enum MLTHilbert {

    /// Number of bits needed to cover a coordinate range.
    static func bits(for range: Int64) -> Int {
        guard range > 0 else { return 1 }
        var bits = 0
        var value: Int64 = 1
        while value <= range, bits < 31 {
            value <<= 1
            bits += 1
        }
        return max(1, bits)
    }

    /// Returns the Hilbert index of a normalized coordinate.
    static func index(
        x: Int32,
        y: Int32,
        minX: Int32,
        minY: Int32,
        bits: Int
    ) -> UInt64 {
        let size = UInt64(1) << UInt64(bits)
        var xValue = UInt64(UInt32(bitPattern: x &- minX))
        var yValue = UInt64(UInt32(bitPattern: y &- minY))
        var result: UInt64 = 0
        var step = size / 2

        while step > 0 {
            let rx: UInt64 = (xValue & step) > 0 ? 1 : 0
            let ry: UInt64 = (yValue & step) > 0 ? 1 : 0
            result &+= step &* step &* ((3 &* rx) ^ ry)

            if ry == 0 {
                if rx == 1 {
                    xValue = size &- 1 &- xValue
                    yValue = size &- 1 &- yValue
                }
                swap(&xValue, &yValue)
            }
            step /= 2
        }

        return result
    }

}
