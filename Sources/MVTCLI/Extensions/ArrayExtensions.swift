import Foundation

extension Array {

    var nonempty: Self? { isEmpty ? nil : self }

    var isNotEmpty: Bool { !isEmpty }

    func get(at index: Int) -> Element? {
        guard index >= -count,
              index < count
        else { return nil }

        if index >= 0 {
            return self[index]
        }
        else {
            return self[count - abs(index)]
        }
    }

}

extension Array  where Element: Hashable {

    var asSet: Set<Element> { Set(self) }

    var uniqued: Self { Array(Set(self)) }

}

extension Array where Element: OptionalProtocol {

    /// Removes nil and empty elements.
    public func trimmed() -> [Element.Wrapped] {
        self.compactMap({ $0.optional == nil ? nil : $0.optional })
    }

}
