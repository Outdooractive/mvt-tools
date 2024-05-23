import Foundation

extension String: Error {}

extension String {

    func extractingGroupsUsingPattern(
        _ pattern: String,
        caseInsensitive: Bool = false,
        treatAsOneLine: Bool = false)
        -> [String]
    {
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
