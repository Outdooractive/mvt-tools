import Foundation
import XCTest

class TestData {

    class func stringFromFile(name: String) -> String {
        let path = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("TestData")
            .appendingPathComponent(name)

        do {
            if try !(path.checkResourceIsReachable()) {
                XCTAssert(false, "Fixture \(name) not found.")
                return ""
            }
            return try String(contentsOf: path, encoding: .utf8)
        }
        catch {
            XCTAssert(false, "Unable to decode fixture at \(path): \(error).")
            return ""
        }
    }

    class func dataFromFile(name: String) -> Data {
        let path = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("TestData")
            .appendingPathComponent(name)

        do {
            if try !(path.checkResourceIsReachable()) {
                XCTAssert(false, "Fixture \(name) not found.")
                return Data()
            }
            return try Data(contentsOf: path)
        }
        catch {
            XCTAssert(false, "Unable to decode fixture at \(path): \(error).")
            return Data()
        }
    }

}
