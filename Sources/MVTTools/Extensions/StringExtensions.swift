import Foundation

extension String {

    public func matches(_ regex: String) -> Bool {
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
