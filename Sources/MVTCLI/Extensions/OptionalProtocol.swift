import Foundation

// MARK: Private

/// A protocol that abstracts over the `Optional` type, allowing extensions
/// that work with both `.some` and `.none` cases generically.
protocol OptionalProtocol {

    /// The type of the wrapped value.
    associatedtype Wrapped

    /// The wrapped value, or `nil` if the instance represents `.none`.
    var optional: Wrapped? { get }

}

extension Optional: OptionalProtocol {

    /// The wrapped value, or `nil` if the instance is `.none`.
    var optional: Wrapped? { self }

}
