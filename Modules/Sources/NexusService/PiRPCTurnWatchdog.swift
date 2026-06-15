#if os(macOS)
    import Foundation

    enum PiRPCTurnWatchdogAction: Equatable {
        case none
        case pollProviderState
        case declareProviderStall(idleSeconds: Int)
    }

    enum PiRPCTurnWatchdog {
        static let defaultStallThresholdNanoseconds: UInt64 = 90 * 1_000_000_000
        static let defaultPollIntervalNanoseconds: UInt64 = 15 * 1_000_000_000
        static let defaultWatchdogTickNanoseconds: UInt64 = 5 * 1_000_000_000

        static func configuredStallThresholdNanoseconds() -> UInt64 {
            configuredNanoseconds(environmentKey: "NEXUS_PI_RPC_TURN_STALL_SEC", default: defaultStallThresholdNanoseconds)
        }

        static func configuredPollIntervalNanoseconds() -> UInt64 {
            configuredNanoseconds(environmentKey: "NEXUS_PI_RPC_TURN_POLL_SEC", default: defaultPollIntervalNanoseconds)
        }

        static func configuredWatchdogTickNanoseconds() -> UInt64 {
            configuredNanoseconds(environmentKey: "NEXUS_PI_RPC_TURN_WATCHDOG_TICK_SEC", default: defaultWatchdogTickNanoseconds)
        }

        private static func configuredNanoseconds(environmentKey: String, default defaultValue: UInt64) -> UInt64 {
            guard let raw = ProcessInfo.processInfo.environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
                let seconds = Double(raw),
                seconds > 0
            else {
                return defaultValue
            }
            return UInt64(seconds * 1_000_000_000)
        }

        /// After `stallThreshold`, poll Pi at most every `pollInterval`. Declare a provider stall once after at least one poll if the turn is still open.
        static func evaluate(
            promptTurnCommitted: Bool,
            providerStallDeclared: Bool,
            lastStdoutActivityUptimeNanoseconds: UInt64?,
            lastProviderPollUptimeNanoseconds: UInt64?,
            watchdogPollsSinceIdleThreshold: Int,
            nowUptimeNanoseconds: UInt64,
            pollIntervalNanoseconds: UInt64,
            stallThresholdNanoseconds: UInt64
        ) -> PiRPCTurnWatchdogAction {
            guard promptTurnCommitted, providerStallDeclared == false else {
                return .none
            }
            guard let lastActivity = lastStdoutActivityUptimeNanoseconds else {
                return .none
            }

            let idleNanoseconds = nowUptimeNanoseconds >= lastActivity
                ? nowUptimeNanoseconds - lastActivity
                : 0

            guard idleNanoseconds >= stallThresholdNanoseconds else {
                return .none
            }

            let lastPoll = lastProviderPollUptimeNanoseconds ?? 0
            let sincePoll = nowUptimeNanoseconds >= lastPoll ? nowUptimeNanoseconds - lastPoll : 0
            guard sincePoll >= pollIntervalNanoseconds else {
                return .none
            }

            let idleSeconds = max(1, Int(idleNanoseconds / 1_000_000_000))
            if watchdogPollsSinceIdleThreshold >= 1 {
                return .declareProviderStall(idleSeconds: idleSeconds)
            }
            return .pollProviderState
        }
    }
#endif