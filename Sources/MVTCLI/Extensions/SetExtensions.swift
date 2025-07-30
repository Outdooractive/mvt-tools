import Foundation

// MARK: Private

extension Set {

    var isNotEmpty: Bool { !isEmpty }

    var asArray: [Element] { Array(self) }

}
