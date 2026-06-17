import Foundation

nonisolated func submitToCoalescingMainActorValuePump<Value>(
    _ pump: CoalescingMainActorValuePump<Value>,
    value: Value
) {
    pump.submit(value)
}

final class CoalescingMainActorValuePump<Value>: @unchecked Sendable {
    typealias Deliver = @Sendable (Value) async -> Void
    typealias MergePendingValue = @Sendable (Value, Value) -> Value

    private let lock = NSLock()
    private let mergePendingValue: MergePendingValue?
    nonisolated(unsafe) private var deliver: Deliver?
    nonisolated(unsafe) private var pendingValue: Value?
    nonisolated(unsafe) private var isDraining = false

    nonisolated init(mergePendingValue: MergePendingValue? = nil) {
        self.mergePendingValue = mergePendingValue
    }

    nonisolated func installDeliver(_ deliver: @escaping Deliver) {
        withLock {
            self.deliver = deliver
        }
    }

    nonisolated func submit(_ value: Value) {
        let shouldStartDrain = withLock {
            if let pendingValue, let mergePendingValue {
                self.pendingValue = mergePendingValue(pendingValue, value)
            } else {
                pendingValue = value
            }
            guard isDraining == false else {
                return false
            }
            isDraining = true
            return true
        }
        guard shouldStartDrain else {
            return
        }

        Task {
            await drain()
        }
    }

    nonisolated func reset() {
        withLock {
            pendingValue = nil
        }
    }

    /// Waits until any submitted values have been delivered (for tests and action/observation ordering).
    nonisolated func flush() async {
        while true {
            let shouldWait = withLock {
                pendingValue != nil || isDraining
            }
            guard shouldWait else {
                return
            }
            await Task.yield()
        }
    }

    nonisolated private func drain() async {
        while let value = nextValueForDrain() {
            guard let deliver = currentDeliver() else {
                continue
            }
            await deliver(value)
        }
    }

    nonisolated private func currentDeliver() -> Deliver? {
        withLock { deliver }
    }

    nonisolated private func nextValueForDrain() -> Value? {
        withLock {
            guard let pendingValue else {
                isDraining = false
                return nil
            }
            self.pendingValue = nil
            return pendingValue
        }
    }

    nonisolated private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
