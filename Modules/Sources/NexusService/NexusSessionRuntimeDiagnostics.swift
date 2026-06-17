#if os(macOS)
    import Foundation
    import NexusDomain
    import os

    /// Unified logging for correlating Nexus (host) and provider child PIDs during Pi RPC sessions.
    /// Stream in Console.app: subsystem `com.chundla.nexus`, category `SessionRuntime`.
    /// CLI: `log stream --predicate 'subsystem == "com.chundla.nexus" AND category == "SessionRuntime"' --level debug`
    enum NexusSessionRuntimeDiagnostics {
        private static let logger = Logger(
            subsystem: "com.chundla.nexus",
            category: "SessionRuntime"
        )

        static var nexusHostPID: Int32 {
            ProcessInfo.processInfo.processIdentifier
        }

        static func logRuntimeRegistered(
            sessionID: UUID,
            providerID: ProviderID,
            hadExistingRuntime: Bool
        ) {
            logger.info(
                """
                runtimeRegistered nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                provider=\(providerID.rawValue, privacy: .public) \
                replacedExisting=\(hadExistingRuntime, privacy: .public)
                """
            )
        }

        static func logRuntimeRemoved(sessionID: UUID, providerID: ProviderID?) {
            let provider = providerID?.rawValue ?? "unknown"
            logger.info(
                """
                runtimeRemoved nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                provider=\(provider, privacy: .public)
                """
            )
        }

        static func logPiProcessStarted(
            sessionID: UUID,
            childPID: Int32,
            executable: String,
            arguments: [String]
        ) {
            logger.notice(
                """
                piProcessStarted nexusHostPID=\(nexusHostPID, privacy: .public) \
                piChildPID=\(childPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                executable=\(executable, privacy: .public) \
                arguments=\(arguments.joined(separator: " "), privacy: .public)
                """
            )
        }

        static func logPiProcessTerminated(
            sessionID: UUID?,
            childPID: Int32?,
            exitStatus: Int32
        ) {
            let session = sessionID?.uuidString ?? "unknown"
            let pidText = childPID.map { "\($0)" } ?? "unknown"
            logger.notice(
                """
                piProcessTerminated nexusHostPID=\(nexusHostPID, privacy: .public) \
                piChildPID=\(pidText, privacy: .public) \
                sessionID=\(session, privacy: .public) \
                exitStatus=\(exitStatus, privacy: .public)
                """
            )
        }

        static func logInteractiveReadyBootstrap(
            sessionID: UUID,
            providerID: ProviderID,
            hadRuntimeBefore: Bool,
            relaunchedPersistedSession: Bool
        ) {
            logger.info(
                """
                interactiveReadyBootstrap nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                provider=\(providerID.rawValue, privacy: .public) \
                hadRuntimeBefore=\(hadRuntimeBefore, privacy: .public) \
                relaunchedPersistedSession=\(relaunchedPersistedSession, privacy: .public)
                """
            )
        }

        static func logSessionPromptSubmitted(
            sessionID: UUID,
            providerID: ProviderID,
            hasRuntime: Bool,
            promptPreview: String
        ) {
            let preview = String(promptPreview.prefix(120))
            logger.notice(
                """
                sessionPromptSubmitted nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                provider=\(providerID.rawValue, privacy: .public) \
                hasRuntime=\(hasRuntime, privacy: .public) \
                promptPreview=\(preview, privacy: .public)
                """
            )
        }

        static func logPiPromptDispatch(sessionID: UUID, startedNewTurn: Bool) {
            logger.notice(
                """
                piPromptDispatch nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                startedNewTurn=\(startedNewTurn, privacy: .public)
                """
            )
        }

        static func logPiPromptAccepted(sessionID: UUID) {
            logger.notice(
                """
                piPromptAccepted nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public)
                """
            )
        }

        static func logPiAgentEnd(sessionID: UUID, willRetry: Bool) {
            logger.notice(
                """
                piAgentEnd nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                willRetry=\(willRetry, privacy: .public)
                """
            )
        }

        static func logPiTurnWatchdogStarted(sessionID: UUID, stallThresholdSeconds: Int) {
            logger.notice(
                """
                piTurnWatchdogStarted nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                stallThresholdSec=\(stallThresholdSeconds, privacy: .public)
                """
            )
        }

        static func logPiTurnWatchdogPoll(
            sessionID: UUID,
            idleThresholdSeconds: Int,
            piSessionFile: String?
        ) {
            let file = piSessionFile ?? "unknown"
            logger.notice(
                """
                piTurnWatchdogPoll nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                idleThresholdSec=\(idleThresholdSeconds, privacy: .public) \
                piSessionFile=\(file, privacy: .public)
                """
            )
        }

        static func logPiTurnWatchdogStallDeclared(
            sessionID: UUID,
            idleSeconds: Int,
            piSessionFile: String?
        ) {
            let file = piSessionFile ?? "unknown"
            logger.notice(
                """
                piTurnWatchdogStallDeclared nexusHostPID=\(nexusHostPID, privacy: .public) \
                sessionID=\(sessionID.uuidString, privacy: .public) \
                idleSeconds=\(idleSeconds, privacy: .public) \
                piSessionFile=\(file, privacy: .public)
                """
            )
        }
    }
#endif
