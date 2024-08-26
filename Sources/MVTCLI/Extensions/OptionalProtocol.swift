import Foundation

// MARK: OptionalProtocol

public protocol OptionalProtocol {

    associatedtype Wrapped
    var optional: Wrapped? { get }

}

// MARK: - Optional + OptionalProtocol

extension Optional: OptionalProtocol {

    public var optional: Wrapped? {
        self
    }

}
