import Foundation

// MARK: Private

extension String {

    var isNotEmpty: Bool { !isEmpty }

    /// Trims white space and new line characters
    mutating func trim() {
        self = self.trimmed()
    }

    /// Trims white space and new line characters, returns a new string
    func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
