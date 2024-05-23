import Foundation

extension Array {

    /// Adds a new element at the end of the array if it's not *nil*.
    mutating func append(ifNotNil element: Element?) {
        guard let element else { return }

        append(element)
    }

    // MARK: -

    /// Returns the array's elements pairwise. For arrays with uneven length, the last element will be skipped.
    func pairs() -> [(first: Element, second: Element)] {
        guard !isEmpty else { return [] }

        return (0 ..< (count / 2)).compactMap { (index) in
            let i = index * 2
            return (first: self[i], second: self[i + 1])
        }
    }

    // MARK: -

    /// Fetches an element from the array, or returns *nil* if the index is out of bounds.
    ///
    /// - parameter index: The index in the array. May be negative. In this case, -1 will be the last element, -2 the second-to-last, and so on.
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
