import Foundation

// MARK: Private

extension String {

    /// A Boolean value indicating whether the string is not empty.
    var isNotEmpty: Bool { !isEmpty }

    /// Trims white space and new line characters
    mutating func trim() {
        self = self.trimmed()
    }

    /// Trims white space and new line characters, returns a new string
    func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
