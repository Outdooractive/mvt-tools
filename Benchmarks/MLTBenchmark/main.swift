#if EnableMLT
import Foundation
import MVTTools

@main
struct MLTBenchmark {

    private enum BenchmarkError: Error, CustomStringConvertible {
        case usage
        case invalidCoordinate(String)
        case invalidIterations(String)
        case encodingFailed

        var description: String {
            switch self {
            case .usage:
                return "usage: mlt-benchmark <tile.mvt|tile.pbf|tile.mlt> <x> <y> <z> [iterations]"
            case let .invalidCoordinate(value):
                return "invalid tile coordinate: \(value)"
            case let .invalidIterations(value):
                return "invalid iteration count: \(value)"
            case .encodingFailed:
                return "failed to encode MLT"
            }
        }
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 5 else {
            throw BenchmarkError.usage
        }

        let url = URL(fileURLWithPath: arguments[1])
        guard let x = Int(arguments[2]) else {
            throw BenchmarkError.invalidCoordinate(arguments[2])
        }
        guard let y = Int(arguments[3]) else {
            throw BenchmarkError.invalidCoordinate(arguments[3])
        }
        guard let z = Int(arguments[4]) else {
            throw BenchmarkError.invalidCoordinate(arguments[4])
        }
        let iterations = arguments.count > 5
            ? (Int(arguments[5]) ?? 10)
            : 10
        guard iterations > 0 else {
            throw BenchmarkError.invalidIterations(String(iterations))
        }

        let data = try Data(contentsOf: url)
        let extensionName = url.pathExtension.lowercased()
        let isMVT = extensionName == "mvt" || extensionName == "pbf"

        var tile: VectorTile?
        var decodeSeconds = 0.0
        for _ in 0 ..< iterations {
            let start = Date()
            let decoded = try isMVT
                ? VectorTile(mvtData: data, x: x, y: y, z: z)
                : VectorTile(mltData: data, x: x, y: y, z: z)
            decodeSeconds += Date().timeIntervalSince(start)
            tile = decoded
        }

        guard let tile else {
            throw BenchmarkError.encodingFailed
        }

        var encodeSeconds = 0.0
        var encoded: Data?
        for _ in 0 ..< iterations {
            let start = Date()
            encoded = tile.mltData()
            encodeSeconds += Date().timeIntervalSince(start)
        }

        guard let encoded else {
            throw BenchmarkError.encodingFailed
        }

        let featureCount = tile.layerNames.reduce(0) { $0 + tile.features(for: $1).count }
        print("input:  \(data.count) bytes, \(tile.layerNames.count) layers, \(featureCount) features")
        print("decode: \(String(format: "%.2f", decodeSeconds * 1000.0 / Double(iterations))) ms/iteration")
        print("encode: \(String(format: "%.2f", encodeSeconds * 1000.0 / Double(iterations))) ms/iteration")
        print("output: \(encoded.count) bytes")
    }

}
#else
import Foundation

@main
struct MLTBenchmark {
    static func main() {
        print("Build with --traits EnableMLT to run the MLT benchmark.")
    }
}
#endif
