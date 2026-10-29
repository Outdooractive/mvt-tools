import Foundation

/// Morton/Z-order encoding for MLT vertex dictionaries.
enum MLTMortonEncoder {

    struct Settings {
        var coordinateShift: Int32
        var bits: Int
    }

    static func settings(for vertices: [MLTTileCoordinate]) -> Settings? {
        guard !vertices.isEmpty else { return nil }

        var minimum = min(vertices[0].x, vertices[0].y)
        var maximum = max(vertices[0].x, vertices[0].y)
        for vertex in vertices.dropFirst() {
            minimum = min(minimum, vertex.x, vertex.y)
            maximum = max(maximum, vertex.x, vertex.y)
        }

        guard minimum > Int32.min else { return nil }
        let shift = minimum < 0 ? Int32(-Int64(minimum)) : 0
        let extent = Int64(maximum) + Int64(shift)
        guard extent >= 0 else { return nil }

        var bits = 0
        var value: Int64 = 1
        while value <= extent, bits < 17 {
            value <<= 1
            bits += 1
        }
        guard bits <= 16 else { return nil }

        return Settings(coordinateShift: shift, bits: max(1, bits))
    }

    static func code(
        x: Int32,
        y: Int32,
        settings: Settings
    ) -> UInt32 {
        let shiftedX = UInt32(bitPattern: x &+ settings.coordinateShift)
        let shiftedY = UInt32(bitPattern: y &+ settings.coordinateShift)
        var result: UInt32 = 0
        for index in 0 ..< settings.bits {
            let mask = UInt32(1) << UInt32(index)
            result |= ((shiftedX & mask) << UInt32(index))
                | ((shiftedY & mask) << UInt32(index + 1))
        }
        return result
    }

}
