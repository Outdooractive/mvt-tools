import Foundation

struct FixtureInfo: Codable {

    struct Validity: Codable {
        var v1: Bool
        var v2: Bool
    }

    var description: String
    var specificationReference: String
    var validity: Validity
    var proto: String

    enum CodingKeys: String, CodingKey {
        case description
        case specificationReference = "specification_reference"
        case validity
        case proto
    }

}
