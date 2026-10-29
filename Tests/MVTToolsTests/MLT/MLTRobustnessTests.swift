#if EnableMLT
import Foundation
@testable import MVTTools
import Testing

struct MLTRobustnessTests {

    private static var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestData")
            .appendingPathComponent("gruenten_14_8661_5725.mlt")
    }

    @Test
    func truncatedTilesThrowWithoutCrashing() throws {
        let data = try Data(contentsOf: Self.fixture)
        #expect(data.isEmpty == false)

        var index = 0
        var failures = 0
        while index < data.count {
            let truncated = Data(data.prefix(index))
            do {
                _ = try MLTDecoderSwift.decode(
                    from: truncated,
                    x: 8661,
                    y: 5725,
                    z: 14)
            }
            catch {
                failures += 1
            }
            index += 257
        }
        #expect(failures > 0)
    }

    @Test
    func mutatedTilesDoNotCrash() throws {
        let data = try Data(contentsOf: Self.fixture)
        var generator = SeededGenerator(seed: 0x5EED)

        for _ in 0 ..< 200 {
            var mutated = Array(data)
            let position = Int.random(in: 0 ..< mutated.count, using: &generator)
            mutated[position] ^= UInt8.random(in: 1 ... 255, using: &generator)

            // Either decoding succeeds or it throws; neither path may trap.
            _ = try? MLTDecoderSwift.decode(
                from: Data(mutated),
                x: 8661,
                y: 5725,
                z: 14)
        }
    }

    @Test
    func randomDataDoesNotCrash() {
        var generator = SeededGenerator(seed: 0xC0FFEE)
        for length in [0, 1, 2, 3, 4, 8, 32, 256] {
            let bytes = (0 ..< length).map { _ in
                UInt8.random(in: 0 ... 255, using: &generator)
            }
            _ = try? MLTDecoderSwift.decode(
                from: Data(bytes),
                x: 0, y: 0, z: 0)
        }
    }

}

/// Small deterministic random number generator for fuzz-style tests.
private struct SeededGenerator: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

}

#endif
