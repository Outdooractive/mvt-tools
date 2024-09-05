import Foundation

public struct QueryParser {

    public enum Expression {
        // Comparisons
        public enum Comparison {
            case equals
            case notEquals
            case greaterThan
            case greaterThanOrEqual
            case lessThan
            case lessThanOrEqual
            case regex
        }

        // Conditions
        public enum Condition {
            case and
            case or
            case not
        }

        case comparison(Comparison)
        case condition(Condition)
        case literal(Sendable)
        case valueAt(Int)
        case valueFor([String])
    }

    private let reader: Reader?
    private var pipeline: [Expression]?

    public init(string: String) {
        self.reader = Reader(characters: Array(string.utf8))
        self.parseQuery()
    }

    public init(pipeline: [Expression]) {
        self.reader = nil
        self.pipeline = pipeline
    }

    public func evaluate(on properties: [String: Sendable]) -> Bool {
        guard let pipeline else { return false }

        var stack: [Sendable?] = []

        for expression in pipeline {
            switch expression {
            case let .comparison(condition):
                switch condition {
                case .equals, .notEquals:
                    guard stack.count >= 2,
                          let second = stack.removeFirst() as? AnyHashable,
                          let first = stack.removeFirst() as? AnyHashable
                    else { return false }

                    if condition == .equals {
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

                    stack.insert(compare(first: first, second: second, condition: condition), at: 0)

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

            case let .literal(value):
                stack.insert(value, at: 0)

            case let .valueAt(index):
                guard stack.isNotEmpty,
                      let array = stack.removeFirst() as? [Sendable]
                else { return false}
                
                stack.insert(array.get(at: index), at: 0)

            case let .valueFor(keys):
                var current: Sendable? = properties

                for key in keys {
                    if let object = current as? [String: Sendable] {
                        current = object[key]
                    }
                    else {
                        current = nil
                        break
                    }
                }

                stack.insert(current, at: 0)
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
    private func compare(first: Sendable, second: Sendable, condition: QueryParser.Expression.Comparison) -> Bool {
        if let left = (first as? Int) ?? (first as? Int8)?.asInt ?? (first as? Int16)?.asInt ?? (first as? Int32)?.asInt ?? (first as? Int64)?.asInt {
            if let right = (second as? Int) ?? (second as? Int8)?.asInt ?? (second as? Int16)?.asInt ?? (second as? Int32)?.asInt ?? (second as? Int64)?.asInt {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = (second as? UInt)?.asInt ?? (second as? UInt8)?.asInt ?? (second as? UInt16)?.asInt ?? (second as? UInt32)?.asInt ?? (second as? UInt64)?.asInt {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = (second as? Double) ?? (second as? Float)?.asDouble {
                return compare(left: Double(left), right: right, condition: condition)
            }
        }
        else if let left = (first as? Double) ?? (first as? Float)?.asDouble {
            if let right = (second as? Double) ?? (second as? Float)?.asDouble {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = (second as? Int) ?? (second as? Int8)?.asInt ?? (second as? Int16)?.asInt ?? (second as? Int32)?.asInt ?? (second as? Int64)?.asInt {
                return compare(left: left, right: Double(right), condition: condition)
            }
        }
        if let left = (first as? UInt) ?? (first as? UInt8)?.asUInt ?? (first as? UInt16)?.asUInt ?? (first as? UInt32)?.asUInt ?? (first as? UInt64)?.asUInt {
            if let right = (second as? UInt) ?? (second as? UInt8)?.asUInt ?? (second as? UInt16)?.asUInt ?? (second as? UInt32)?.asUInt ?? (second as? UInt64)?.asUInt {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = (second as? Int)?.asUInt ?? (second as? Int8)?.asUInt ?? (second as? Int16)?.asUInt ?? (second as? Int32)?.asUInt ?? (second as? Int64)?.asUInt {
                return compare(left: left, right: right, condition: condition)
            }
            else if let right = (second as? Double) ?? (second as? Float)?.asDouble {
                return compare(left: Double(left), right: right, condition: condition)
            }
        }
        else if let left = first as? String, let right = second as? String {
            return compare(left: left, right: right, condition: condition)
        }

        return false
    }

    private func compare<T: Comparable>(left: T, right: T, condition: QueryParser.Expression.Comparison) -> Bool {
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

        func peek(withOffset offset: Int = 0) -> UInt8? {
            guard index + offset < characters.endIndex else { return nil }

            return characters[index + offset]
        }

        mutating func moveIndex(by offset: Int) {
            index += offset
        }

    }

}
