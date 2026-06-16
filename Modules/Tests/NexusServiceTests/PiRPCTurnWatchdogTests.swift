#if os(macOS)
    import Foundation
    @testable import NexusService
    import Testing

    @Suite struct PiRPCTurnWatchdogTests {
        private let stall: UInt64 = 90_000_000_000
        private let poll: UInt64 = 15_000_000_000

        @Test func noActionWhenTurnNotCommitted() {
            let action = PiRPCTurnWatchdog.evaluate(
                promptTurnCommitted: false,
                providerStallDeclared: false,
                lastStdoutActivityUptimeNanoseconds: 0,
                lastProviderPollUptimeNanoseconds: nil,
                watchdogPollsSinceIdleThreshold: 0,
                nowUptimeNanoseconds: stall + 1,
                pollIntervalNanoseconds: poll,
                stallThresholdNanoseconds: stall
            )
            #expect(action == .none)
        }

        @Test func noActionBeforeStallThreshold() {
            let action = PiRPCTurnWatchdog.evaluate(
                promptTurnCommitted: true,
                providerStallDeclared: false,
                lastStdoutActivityUptimeNanoseconds: 100,
                lastProviderPollUptimeNanoseconds: nil,
                watchdogPollsSinceIdleThreshold: 0,
                nowUptimeNanoseconds: 100 + stall - 1,
                pollIntervalNanoseconds: poll,
                stallThresholdNanoseconds: stall
            )
            #expect(action == .none)
        }

        @Test func pollsProviderAfterIdleThreshold() {
            let lastActivity: UInt64 = 1_000
            let now = lastActivity + stall + poll
            let action = PiRPCTurnWatchdog.evaluate(
                promptTurnCommitted: true,
                providerStallDeclared: false,
                lastStdoutActivityUptimeNanoseconds: lastActivity,
                lastProviderPollUptimeNanoseconds: nil,
                watchdogPollsSinceIdleThreshold: 0,
                nowUptimeNanoseconds: now,
                pollIntervalNanoseconds: poll,
                stallThresholdNanoseconds: stall
            )
            #expect(action == .pollProviderState)
        }

        @Test func declaresStallAfterPollWhenTurnStillOpen() {
            let lastActivity: UInt64 = 1_000
            let lastPoll = lastActivity + stall
            let now = lastPoll + poll
            let action = PiRPCTurnWatchdog.evaluate(
                promptTurnCommitted: true,
                providerStallDeclared: false,
                lastStdoutActivityUptimeNanoseconds: lastActivity,
                lastProviderPollUptimeNanoseconds: lastPoll,
                watchdogPollsSinceIdleThreshold: 1,
                nowUptimeNanoseconds: now,
                pollIntervalNanoseconds: poll,
                stallThresholdNanoseconds: stall
            )
            #expect(action == .declareProviderStall(idleSeconds: Int((now - lastActivity) / 1_000_000_000)))
        }
    }
#endif
