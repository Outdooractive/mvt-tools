import Foundation

// MARK: Private

extension Dictionary {

    /// Returns a Boolean value indicating whether the dictionary contains the given key.
    ///
    /// - Parameter key: The key to look up in the dictionary.
    /// - Returns: `true` if the key exists in the dictionary, `false` otherwise.
    func hasKey(_ key: Key) -> Bool {
        self[key] != nil
    }

}
