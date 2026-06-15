#if os(macOS)
    import Foundation

    /// Limits Pi `text_delta` observation churn so the macOS structured feed is not rebuilt on every token.
    final class PiRPCStreamingObservationThrottle: @unchecked Sendable {
        private let minimumInterval: TimeInterval
        private let now: @Sendable () -> Date
        private let lock = NSLock()
        nonisolated(unsafe) private var lastNotifiedAt: Date?
        nonisolated(unsafe) private var pendingNotify = false

        init(minimumInterval: TimeInterval = 0.05, now: @escaping @Sendable () -> Date = Date.init) {
            self.minimumInterval = minimumInterval
            self.now = now
        }

        /// Returns whether the caller should invoke `notifyChange()` immediately for this streaming delta.
        func shouldNotifyImmediatelyForStreamingDelta() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let current = now()
            if let lastNotifiedAt, current.timeIntervalSince(lastNotifiedAt) < minimumInterval {
                pendingNotify = true
                return false
            }
            lastNotifiedAt = current
            pendingNotify = false
            return true
        }

        /// Flush a deferred streaming notification (call from a delayed task).
        func consumePendingNotify() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard pendingNotify else {
                return false
            }
            pendingNotify = false
            lastNotifiedAt = now()
            return true
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            lastNotifiedAt = nil
            pendingNotify = false
        }
    }
#endif