#if EnableMLT
import Foundation
import MVTTools

@main
struct MLTBenchmark {

    private static let usageMessage = """
        usage: mlt-benchmark <tile.mvt|tile.pbf|tile.mlt> <x> <y> <z> [iterations] \
        [--plain|--no-fsst|--fastpfor|--no-dictionaries|--vertex-dictionaries|\
        --no-vertex-dictionaries|--no-shared-dictionaries|--no-integer-delta-rle]
        """

    private enum BenchmarkError: Error, CustomStringConvertible {
        case usage
        case invalidCoordinate(String)
        case invalidIterations(String)
        case encodingFailed

        var description: String {
            switch self {
            case .usage:
                return MLTBenchmark.usageMessage
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
        var argumentIndex = 5
        var iterations = 10
        if argumentIndex < arguments.count, let value = Int(arguments[argumentIndex]) {
            iterations = value
            argumentIndex += 1
        }
        guard iterations > 0 else {
            throw BenchmarkError.invalidIterations(String(iterations))
        }

        var mltOptions = VectorTile.ExportOptions.MLTEncodingOptions()
        for argument in arguments.dropFirst(argumentIndex) {
            switch argument {
            case "--plain":
                mltOptions = .plain
            case "--no-fsst":
                mltOptions.useFSST = false
            case "--fastpfor":
                mltOptions.useFastPFOR = true
            case "--no-fastpfor":
                mltOptions.useFastPFOR = false
            case "--no-dictionaries":
                mltOptions.useStringDictionaries = false
                mltOptions.useSharedStringDictionaries = false
            case "--no-shared-dictionaries":
                mltOptions.useSharedStringDictionaries = false
            case "--vertex-dictionaries":
                mltOptions.useVertexDictionaries = true
            case "--no-vertex-dictionaries":
                mltOptions.useVertexDictionaries = false
            case "--no-integer-delta-rle":
                mltOptions.useIntegerDeltaRLE = false
            default:
                throw BenchmarkError.usage
            }
        }
        let exportOptions = VectorTile.ExportOptions(mlt: mltOptions)

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
            encoded = tile.mltData(options: exportOptions)
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
