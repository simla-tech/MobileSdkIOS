import Foundation

/// Generic helper for `AsyncStream` fan-out.
///
/// Stores active stream continuations, optionally emits an initial value to new subscribers,
/// broadcasts subsequent values to every subscriber, removes continuations on termination, and
/// finishes all streams when requested.
package final class AsyncBroadcaster<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    package init() {}

    /// Creates a stream and optionally yields the current value immediately.
    package func stream(initialValue: Value? = nil) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            if let initialValue {
                continuation.yield(initialValue)
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    /// Broadcasts a value to all active streams.
    package func yield(_ value: Value) {
        currentContinuations().forEach { $0.yield(value) }
    }

    /// Finishes all active streams and clears stored continuations.
    package func finish() {
        let currentContinuations = currentContinuations(removingAll: true)
        currentContinuations.forEach { $0.finish() }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }

    private func currentContinuations(
        removingAll shouldRemoveAll: Bool = false
    ) -> [AsyncStream<Value>.Continuation] {
        lock.lock()
        let currentContinuations = Array(continuations.values)
        if shouldRemoveAll {
            continuations.removeAll()
        }
        lock.unlock()
        return currentContinuations
    }
}
