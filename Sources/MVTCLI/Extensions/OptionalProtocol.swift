import Foundation

// MARK: Private

protocol OptionalProtocol {

    associatedtype Wrapped
    var optional: Wrapped? { get }

}

extension Optional: OptionalProtocol {

    var optional: Wrapped? { self }

}
