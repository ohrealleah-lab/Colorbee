import Synchronization

/// Set from the main thread to stop work running elsewhere, which checks it now and then.
final class CancelFlag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() {
        value.withLock { $0 = true }
    }
}
