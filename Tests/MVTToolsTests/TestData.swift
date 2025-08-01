import Foundation
import XCTest

struct TestData {

    static func stringFromFile(name: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestData")
            .appendingPathComponent(name)

        return try String(contentsOf: path, encoding: .utf8)
    }

    static func dataFromFile(name: String) throws -> Data {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestData")
            .appendingPathComponent(name)

        return try Data(contentsOf: path)
    }

}
