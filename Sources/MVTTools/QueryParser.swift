import Foundation

public struct QueryParser {

    public enum Expression: Equatable {
        // Comparisons
        public enum Comparison: Equatable {
            case equals
            case notEquals
            case greaterThan
            case greaterThanOrEqual
            case lessThan
            case lessThanOrEqual
            case regex
        }

        // Conditions
        public enum Condition: Equatable {
            case and
            case or
            case not
        }

        // Key or index
        public enum KeyOrIndex: Equatable {
            case key(String)
            case index(Int)
        }

        case comparison(Comparison)
        case condition(Condition)
        case literal(AnyHashable)
        case value([KeyOrIndex])
    }

    private let reader: Reader?
    private(set) var pipeline: [Expression]?

    public init?(string: String) {
        guard string.hasPrefix(".") else { return nil }

        self.reader = Reader(characters: Array(string.utf8))
        self.parseQuery()
    }

    public init(pipeline: [Expression]) {
        self.reader = nil
        self.pipeline = pipeline
    }

    // Works in a reverse polish notation
    public func evaluate(on properties: [String: AnyHashable]) -> Bool {
        guard let pipeline else { return false }

        var stack: [AnyHashable?] = []

        for expression in pipeline {
            switch expression {
            case let .literal(value):
                stack.insert(value, at: 0)

            case let .value(keys):
                var current: AnyHashable? = properties

                for keyOrIndex in keys {
                    switch keyOrIndex {
                    case let .key(key):
                        if let object = current as? [String: AnyHashable] {
                            current = object[key]
                        }
                        else {
                            current = nil
                            break
                        }

                    case let .index(index):
                        if let array = current as? [AnyHashable] {
                            current = array.get(at: index)
                        }
                        else {
                            current = nil
                            break
                        }
                    }
                }

                stack.insert(current, at: 0)

            case let .comparison(comparison):
                switch comparison {
                case .equals, .notEquals:
                    guard stack.count >= 2,
                          let second = stack.removeFirst(),
                          let first = stack.removeFirst()
                    else { return false }

                    if comparison == .equals {
                        stack.insert(first == second, at: 0)
                    }
                    else {
                        stack.insert(first != second, at: 0)
                    }

                case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
                    guard stack.count >= 2,
                          let second = stack.removeFirst(),
                          let first = stack.removeFirst()
                    else { return false }

                    stack.insert(compare(first: first, second: second, condition: comparison), at: 0)

                case .regex:
                    guard stack.count >= 2,
                          let regex = stack.removeFirst() as? String,
                          let value = stack.removeFirst() as? String
                    else { return false }

                    stack.insert(value.matches(regex), at: 0)
                }

            case let .condition(condition):
                switch condition {
                case .and, .or:
                    guard stack.count >= 2 else { return false }

                    let second = stack.removeFirst()
                    let first = stack.removeFirst()
                    let firstIsTrue = if let bool = first as? Bool { bool } else { first != nil }
                    let secondIsTrue = if let bool = second as? Bool { bool } else { second != nil }

                    if condition == .and {
                        stack.insert(firstIsTrue && secondIsTrue, at: 0)
                    }
                    else {
                        stack.insert(firstIsTrue || secondIsTrue, at: 0)
                    }

                case .not:
                    guard stack.isNotEmpty else { return false }

                    let value = stack.removeFirst()
                    let valueIsTrue = if let bool = value as? Bool { bool } else { value != nil }

                    stack.insert(!valueIsTrue, at: 0)
                }
            }
        }

        // The stack should contain the result now
        guard stack.count == 1,
              let result = stack.first
        else { return false }

        if let bool = result as? Bool {
            return bool
        }

        return result != nil
    }

    // This needs improvement - can this be done in a more generic way?
    // Only the most common cases covered for now
    private func compare(
        first: AnyHashable,
        second: AnyHashable,
        condition: QueryParser.Expression.Comparison)
        -> Bool
    {
        if let left = first as? Int {
            if let right = second as? Int {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = second as? UInt {
                return compare(left: UInt(left), right: right, condition: condition)
            }
            else if let right = second as? Double {
                return compare(left: Double(left), right: right, condition: condition)
            }
        }
        else if let left = first as? Double {
            if let right = second as? Double {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = second as? Int {
                return compare(left: left, right: Double(right), condition: condition)
            }
            else if let right = second as? UInt {
                return compare(left: left, right: Double(right), condition: condition)
            }
        }
        else if let left = first as? UInt {
            if let right = second as? UInt {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = second as? Int {
                return compare(left: left, right: UInt(right), condition: condition)
            }
            else if let right = second as? Double {
                return compare(left: Double(left), right: right, condition: condition)
            }
        }
        else if let left = first as? String, let right = second as? String {
            return compare(left: left, right: right, condition: condition)
        }

        return false
    }

    private func compare<T: Comparable>(
        left: T,
        right: T,
        condition: QueryParser.Expression.Comparison)
        -> Bool
    {
        switch condition {
        case .equals:
            return left == right
        case .notEquals:
            return left != right
        case .greaterThan:
            return left > right
        case .greaterThanOrEqual:
            return left >= right
        case .lessThan:
            return left < right
        case .lessThanOrEqual:
            return left <= right
        case .regex:
            guard let value = left as? String, let regex = right as? String else { return false }
            return value.matches(regex)
        }
    }

    private mutating func parseQuery() {
        // skipWhitespace returns the first non-whitespace character,
        // which must be a '.'
        guard var reader,
              let firstCharacter = reader.skipWhitespace(),
              firstCharacter == UInt8(ascii: ".")
        else { return }

        pipeline = []

        var terms: [Expression] = []
        var comparison: Expression?
        var condition: Expression?
        var isBeginningOfTerm = false

        outer: while let char = reader.peek() {
            // Check for:
            // - and, or, not
            // - ==, !=, >, >=, <, <=, =~
            if isBeginningOfTerm {
                let hasAnd = reader.peekString("and", caseInsensitive: true)
                let hasOr = reader.peekString("or", caseInsensitive: true)
                let hasNot = reader.peekString("not", caseInsensitive: true)

                if hasAnd || hasOr || hasNot {
                    pipeline?.append(contentsOf: terms)
                    if let comparison {
                        pipeline?.append(comparison)
                    }
                    if let condition {
                        pipeline?.append(condition)
                    }
                    terms = []
                    comparison = nil
                    condition = nil
                    isBeginningOfTerm = false

                    if hasAnd {
                        condition = .condition(.and)
                        reader.moveIndex(by: 3)
                    }
                    else if hasOr {
                        condition = .condition(.or)
                        reader.moveIndex(by: 2)
                    }
                    else {
                        pipeline?.append(.condition(.not))
                        reader.moveIndex(by: 3)
                    }

                    continue
                }

                // Must be in the middle, otherwise it's just some literal value
                if terms.count == 1,
                   let term = reader.readComparisonExpression()
                {
                    isBeginningOfTerm = false
                    comparison = term
                    continue
                }
            }

            switch char {
            case UInt8(ascii: " "):
                reader.skipWhitespace()
                isBeginningOfTerm = true
                continue

            case UInt8(ascii: "."):
                guard let term = reader.readValueExpression() else { return }
                isBeginningOfTerm = false
                terms.append(term)

            default:
                guard let term = reader.readLiteralExpression() else { return }
                isBeginningOfTerm = false
                terms.append(term)
            }
        }

        pipeline?.append(contentsOf: terms)
        if let comparison {
            pipeline?.append(comparison)
        }
        if let condition {
            pipeline?.append(condition)
        }
    }

    // MARK: - Reader

    struct Reader {

        let characters: [UInt8]

        private var index: Int = 0

        init(characters: [UInt8]) {
            self.characters = characters
        }

        mutating func readNextCharacter() -> UInt8? {
            guard index < characters.endIndex else {
                index = characters.endIndex
                return nil
            }

            defer { index += 1 }

            return characters[index]
        }

        mutating func moveIndex(by offset: Int) {
            index += offset
        }

        func peek(withOffset offset: Int = 0) -> UInt8? {
            guard index + offset < characters.endIndex else { return nil }

            return characters[index + offset]
        }

        func peekString(_ string: String, caseInsensitive: Bool) -> Bool {
            guard index + string.count <= characters.endIndex else { return false }

            let peekString = caseInsensitive ? string.lowercased() : string

            for (offset, char) in peekString.utf8.enumerated() {
                var c = characters[index + offset]
                if caseInsensitive, c >= 65, c <= 90 {
                    c += 32
                }

                if c != char { return false }
            }

            return true
        }

        @discardableResult
        mutating func skipWhitespace() -> UInt8? {
            var offset = 0

            while let char = peek(withOffset: offset) {
                if char == UInt8(ascii: " ") {
                    offset += 1
                    continue
                }

                moveIndex(by: offset)
                return char
            }

            return nil
        }

        mutating func readValueExpression() -> Expression? {
            guard readNextCharacter() == UInt8(ascii: ".") else { return nil }

            var startIndex = index
            var offset = 0
            var parts: [QueryParser.Expression.KeyOrIndex] = []

            outer: while let char = peek(withOffset: offset) {
                switch char {
                case UInt8(ascii: " "):
                    break outer

                case UInt8(ascii: "."):
                    if let current = String(bytes: characters[startIndex ..< startIndex + offset], encoding: .utf8),
                       current.isNotEmpty
                    {
                        if let index = Int(current) {
                            parts.append(.index(index))
                        }
                        else {
                            parts.append(.key(current))
                        }
                    }

                    moveIndex(by: offset + 1)

                    startIndex = index
                    offset = 0

                case UInt8(ascii: "\""):
                    guard let quotedString = readQuotedString(UInt8(ascii: "\"")) else { return nil }

                    parts.append(.key(quotedString))
                    startIndex = index
                    offset = 0

                case UInt8(ascii: "'"):
                    guard let quotedString = readQuotedString(UInt8(ascii: "'")) else { return nil }

                    parts.append(.key(quotedString))
                    startIndex = index
                    offset = 0

                case UInt8(ascii: "["):
                    guard let arrayIndex = readArrayIndex() else { return nil }

                    parts.append(.index(arrayIndex))
                    startIndex = index
                    offset = 0

                default:
                    offset += 1
                }
            }

            moveIndex(by: offset)

            if let current = String(bytes: characters[startIndex ..< startIndex + offset], encoding: .utf8),
               current.isNotEmpty
            {
                if let index = Int(current) {
                    parts.append(.index(index))
                }
                else {
                    parts.append(.key(current))
                }
            }

            return .value(parts)
        }

        mutating func readLiteralExpression() -> Expression? {
            var startIndex = index
            var offset = 0
            var result = ""

            outer: while let char = peek(withOffset: offset) {
                switch char {
                case UInt8(ascii: " "):
                    break outer

                case UInt8(ascii: "\""):
                    guard let quotedString = readQuotedString(UInt8(ascii: "\"")) else { return nil }

                    result += quotedString
                    startIndex = index
                    offset = 0

                case UInt8(ascii: "'"):
                    guard let quotedString = readQuotedString(UInt8(ascii: "'")) else { return nil }

                    result += quotedString
                    startIndex = index
                    offset = 0

                default:
                    offset += 1
                }
            }

            moveIndex(by: offset)

            if let current = String(bytes: characters[startIndex ..< startIndex + offset], encoding: .utf8) {
                result += current
            }

            guard result.isNotEmpty else { return nil }

            if let int = Int(result) {
                return .literal(int)
            }
            else if let double = Double(result) {
                return .literal(double)
            }

            return .literal(result)
        }

        mutating func readComparisonExpression() -> Expression? {
            let firstChar = peek()

            guard firstChar == UInt8(ascii: "=")
                    || firstChar == UInt8(ascii: "!")
                    || firstChar == UInt8(ascii: ">")
                    || firstChar == UInt8(ascii: "<")
            else { return nil }

            if let secondChar = peek(withOffset: 1),
               secondChar != UInt8(ascii: " ")
            {
                if secondChar == UInt8(ascii: "=") {
                    if firstChar == UInt8(ascii: "=") {
                        moveIndex(by: 2)
                        return .comparison(.equals)
                    }
                    else if firstChar == UInt8(ascii: "!") {
                        moveIndex(by: 2)
                        return .comparison(.notEquals)
                    }
                    else if firstChar == UInt8(ascii: ">") {
                        moveIndex(by: 2)
                        return .comparison(.greaterThanOrEqual)
                    }
                    else if firstChar == UInt8(ascii: "<") {
                        moveIndex(by: 2)
                        return .comparison(.lessThanOrEqual)
                    }
                }
                else if secondChar == UInt8(ascii: "~") {
                    moveIndex(by: 2)
                    return .comparison(.regex)
                }
            }
            else {
                if firstChar == UInt8(ascii: ">") {
                    moveIndex(by: 1)
                    return .comparison(.greaterThan)
                }
                else if firstChar == UInt8(ascii: "<") {
                    moveIndex(by: 1)
                    return .comparison(.lessThan)
                }
            }

            return nil
        }

        mutating func readQuotedString(_ quotationCharacter: UInt8) -> String? {
            guard readNextCharacter() == quotationCharacter else { return nil }

            var startIndex = index
            var offset = 0
            var result = ""

            while let char = peek(withOffset: offset) {
                switch char {
                case quotationCharacter:
                    moveIndex(by: offset + 1)

                    guard let current = String(bytes: characters[startIndex ..< startIndex + offset], encoding: .utf8) else { return nil }

                    result += current
                    return result

                case UInt8(ascii: "\\"):
                    moveIndex(by: offset)

                    guard let current = String(bytes: characters[startIndex ..< startIndex + offset], encoding: .utf8),
                          readNextCharacter() == UInt8(ascii: "\\")
                    else { return nil }

                    result += current

                    guard let escaped = readNextCharacter() else { return nil }

                    result += String(cString: [escaped, 0])

                    startIndex = index
                    offset = 0

                default:
                    offset += 1
                }
            }

            return nil
        }

        private mutating func readArrayIndex() -> Int? {
            guard readNextCharacter() == UInt8(ascii: "[") else { return nil }

            let startIndex = index
            var offset = 0

            while let char = peek(withOffset: offset) {
                switch char {
                case UInt8(ascii: "]"):
                    moveIndex(by: offset + 1)

                    guard let current = String(bytes: characters[startIndex ..< startIndex + offset], encoding: .utf8) else {
                        return nil
                    }

                    return Int(current)

                default:
                    offset += 1
                }
            }

            return nil
        }

    }

}
