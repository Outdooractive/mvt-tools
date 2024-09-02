import Foundation

extension Set {

    var isNotEmpty: Bool { !isEmpty }

    var asArray: [Element] { Array(self) }

}
