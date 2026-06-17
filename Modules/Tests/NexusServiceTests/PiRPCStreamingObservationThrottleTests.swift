#if os(macOS)
    import Foundation
    import Testing

    @testable import NexusService

    private final class PiRPCStreamingObservationThrottleTestClock: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var times: [TimeInterval]

        init(times: [TimeInterval]) {
            self.times = times
        }

        func next() -> Date {
            lock.lock()
            defer { lock.unlock() }
            let value = times.isEmpty ? 0 : times.removeFirst()
            return Date(timeIntervalSince1970: value)
        }
    }

    struct PiRPCStreamingObservationThrottleTests {
        @Test func defersNotifyWithinMinimumInterval() {
            let clock = PiRPCStreamingObservationThrottleTestClock(times: [0, 0.01, 0.06, 0.12])
            let throttle = PiRPCStreamingObservationThrottle(minimumInterval: 0.05) {
                clock.next()
            }

            #expect(throttle.shouldNotifyImmediatelyForStreamingDelta())
            #expect(throttle.shouldNotifyImmediatelyForStreamingDelta() == false)
            guard let generation = throttle.beginScheduledFlushIfNeeded() else {
                Issue.record("Expected scheduled flush generation")
                return
            }
            #expect(throttle.consumePendingNotify(forScheduledFlushGeneration: generation))
            #expect(throttle.consumePendingNotify(forScheduledFlushGeneration: generation) == false)
            #expect(throttle.shouldNotifyImmediatelyForStreamingDelta())
        }

        @Test func resetClearsPendingNotify() {
            let throttle = PiRPCStreamingObservationThrottle(minimumInterval: 1.0) {
                Date(timeIntervalSince1970: 0)
            }
            #expect(throttle.shouldNotifyImmediatelyForStreamingDelta())
            #expect(throttle.shouldNotifyImmediatelyForStreamingDelta() == false)
            throttle.reset()
            #expect(throttle.beginScheduledFlushIfNeeded() == nil)
            #expect(throttle.shouldNotifyImmediatelyForStreamingDelta())
        }
    }
#endif
