import Foundation

/// Allocates process-unique SRIDs for tests that register custom projections.
///
/// `Synchronization.Mutex` would be the natural choice here, but it is only
/// available on iOS 18, macOS 15, tvOS 18 and watchOS 11. Because the package
/// supports older deployment targets, this helper uses `NSLock` instead.
final class SRIDCounter: @unchecked Sendable {

    private let lock = NSLock()
    private var value: Int

    /// Creates a counter starting at the given SRID.
    /// - Parameter initialValue: The first SRID that will be returned.
    init(_ initialValue: Int) {
        self.value = initialValue
    }

    /// Returns the next SRID and advances the counter.
    /// - Parameter count: How far to advance the counter after this call.
    /// - Returns: The SRID at the start of the reserved range.
    func next(_ count: Int = 1) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let start = value
        value += count
        return start
    }

}
