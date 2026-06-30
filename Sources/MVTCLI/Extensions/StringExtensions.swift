import Foundation

// MARK: Private

extension String {

    /// Extracts capture groups from the string using the given regular
    /// expression pattern.
    ///
    /// - Parameters:
    ///   - pattern: A regular expression pattern to match against the string.
    ///   - caseInsensitive: If `true`, the pattern matching is case-insensitive.
    ///   - treatAsOneLine: If `true`, the `.` metacharacter matches line
    ///     separators as well.
    /// - Returns: An array of strings representing the captured groups from
    ///   all matches. Returns an empty array if the pattern is invalid or no
    ///   matches are found.
    func extractingGroupsUsingPattern(
        _ pattern: String,
        caseInsensitive: Bool = false,
        treatAsOneLine: Bool = false
    ) -> [String] {
        var options = NSRegularExpression.Options()

        if caseInsensitive { options.insert(.caseInsensitive) }
        if treatAsOneLine { options.insert(.dotMatchesLineSeparators) }

        do {
            var groups: [String] = []
            let regexp = try NSRegularExpression(pattern: pattern, options: options)

            regexp.enumerateMatches(
                in: self,
                options: NSRegularExpression.MatchingOptions(),
                range: NSRange(startIndex..., in: self),
                using: { (matchResult, flags, stop) in
                    guard let matchResult else { return }

                    for i in 1 ..< matchResult.numberOfRanges {
                        if let range = Range(matchResult.range(at: i), in: self) {
                            groups.append(String(self[range]))
                        }
                    }
                })

            return groups
        }
        catch let error as NSError {
            print("invalid regex: \(error.description)")
            return []
        }
    }

}
