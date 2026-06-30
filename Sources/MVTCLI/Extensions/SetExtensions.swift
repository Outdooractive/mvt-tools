import Foundation

// MARK: Private

extension Set {

    /// A Boolean value indicating whether the set is not empty.
    var isNotEmpty: Bool { !isEmpty }

    /// Returns the elements of the set as an `Array`.
    var asArray: [Element] { Array(self) }

}
