import Foundation

// MARK: Private

extension Array {

    /// Returns the array if it is not empty, or `nil` otherwise.
    var nonempty: Self? { isEmpty ? nil : self }

    /// A Boolean value indicating whether the collection is not empty.
    var isNotEmpty: Bool { !isEmpty }

    /// Returns the element at the given index, supporting negative indices
    /// that count backward from the end of the array.
    ///
    /// For example, `get(at: -1)` returns the last element.
    ///
    /// - Parameter index: The index of the element to retrieve. Negative
    ///   values count from the end of the array.
    /// - Returns: The element at the given index, or `nil` if the index is
    ///   out of bounds.
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

    /// Returns the elements of the array as a `Set`.
    var asSet: Set<Element> { Set(self) }

    /// Returns an array with duplicate elements removed, preserving an
    /// arbitrary ordering of the remaining elements.
    var uniqued: Self { Array(Set(self)) }

}

extension Array where Element: OptionalProtocol {

    /// Removes `nil` and empty elements from the array, returning an array
    /// of unwrapped values.
    /// - Returns: An array containing only non-`nil` elements.
    func trimmed() -> [Element.Wrapped] {
        self.compactMap({ $0.optional == nil ? nil : $0.optional })
    }

}
