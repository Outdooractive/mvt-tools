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

    /// Returns a Boolean value indicating whether the string matches the given regular expression.
    ///
    /// Supports optional `/i` suffix for case-insensitive matching, similar to JavaScript.
    /// - Parameter regex: A regular expression pattern, optionally wrapped in `/` delimiters
    ///   with `/i` for case-insensitive matching.
    /// - Returns: `true` if the string matches the pattern, `false` otherwise.
    func matches(_ regex: String) -> Bool {
        var options: String.CompareOptions = .regularExpression

        var regex = regex
        if regex.hasPrefix("/") {
            regex.removeFirst()

            if regex.hasSuffix("/i") {
                options.insert(.caseInsensitive)
                regex.removeLast(2)
            }
            else if regex.hasSuffix("/") {
                regex.removeLast()
            }
        }

        return self.range(of: regex, options: options) != nil
    }

}
