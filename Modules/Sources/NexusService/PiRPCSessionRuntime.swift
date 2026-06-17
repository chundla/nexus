#if os(macOS)
    import Foundation
    import NexusDomain

    // Pi RPC protocol: docs/pi-rpc.md (links to @earendil-works/pi-coding-agent docs/rpc.md).

    private let piBasicThinkingLevels = ["off", "minimal", "low", "medium", "high"]
    private let piExtendedThinkingLevels = piBasicThinkingLevels + ["xhigh"]

    private struct PiRPCModelDescriptor: Equatable {
        let provider: String
        let id: String
        let name: String?
        let availableThinkingLevels: [String]
    }

    protocol PiRPCTransporting: AnyObject {
        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?)
        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?)
        func start() throws
        func sendLine(_ line: String) throws
        func terminate() throws
    }

    enum PiRPCSessionRuntimeError: LocalizedError {
        case startupTimedOut
        case startupFailed(String)
        case busy
        case approvalRequestNotFound
        case extensionDialogNotFound

        var errorDescription: String? {
            switch self {
            case .startupTimedOut:
                return "Pi RPC mode did not finish startup in time."
            case .startupFailed(let message):
                return message
            case .busy:
                return
                    "Pi is already handling a prompt. Wait for the current turn to finish before sending another one."
            case .approvalRequestNotFound:
                return "Approval Request was not found for this Session."
            case .extensionDialogNotFound:
                return "Extension UI dialog was not found for this Session."
            }
        }
    }

    final class PiRPCSessionRuntime: SessionRuntime, @unchecked Sendable {
        typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws
            -> any PiRPCTransporting

        var state: Session.State {
            lock.lock()
            defer { lock.unlock() }
            return runtimeState
        }

        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
            lock.lock()
            defer { lock.unlock() }
            return SessionRecordAdapterMetadata.pi(
                linkage: sessionLinkage,
                activityItems: activityItems,
                approvalRequests: approvalRequests,
                extensionUIState: extensionUIStateLocked(),
                providerEvents: providerEvents
            )
        }

        func consumeStructuredHistoryOverflow() -> StructuredSessionPersistedHistoryOverflow {
            lock.lock()
            defer { lock.unlock() }
            let overflow = StructuredSessionPersistedHistoryOverflow(
                activityItems: persistedActivityItemOverflow,
                providerEvents: persistedProviderEventOverflow
            )
            persistedActivityItemOverflow.removeAll(keepingCapacity: true)
            persistedProviderEventOverflow.removeAll(keepingCapacity: true)
            return overflow
        }

        func consumeSessionTransition() -> SessionRuntimeSessionTransition? {
            lock.lock()
            defer { lock.unlock() }
            guard pendingSessionTransitions.isEmpty == false else {
                return nil
            }
            return pendingSessionTransitions.removeFirst()
        }

        private let lock = NSLock()
        private let transport: any PiRPCTransporting
        private let stopHandler: (() throws -> Void)?
        private let terminationStatusMessageBuilder: (Int32) -> String
        private let unexpectedTerminationState: Session.State
        private let unexpectedTerminationMessageBuilder: (Int32) -> String
        private let startupStateResponseID = "nexus-pi-startup-state"
        private let startupCommandsResponseID = "nexus-pi-startup-commands"
        private let startupAvailableModelsResponseID = "nexus-pi-startup-available-models"
        private let currentModelStatusPrefix = "Current Model:"
        private var currentModel: PiRPCModelDescriptor?
        private var currentThinkingLevel: String?
        private var steeringMode = "one-at-a-time"
        private var followUpMode = "one-at-a-time"
        private var queuedSteeringMessages: [String] = []
        private var queuedFollowUpMessages: [String] = []
        private var currentSessionName: String?
        private var runtimeState: Session.State = .ready
        private var transcriptEntries: [String] = []
        private var interruptedFailureMessage: String?
        private var draft = ""
        private var activityItems: [SessionActivityItem] = []
        private var persistedActivityItemOverflow: [SessionActivityItem] = []
        private var approvalRequests: [SessionApprovalRequest] = []
        private var pendingExtensionDialogs: [SessionExtensionUIDialog] = []
        private var extensionNotifications: [SessionExtensionUINotification] = []
        private var extensionStatuses: [SessionExtensionUIStatus] = []
        private var extensionWidgets: [SessionExtensionUIWidget] = []
        private var extensionTitle: String?
        private var extensionEditorText: String?
        private var providerEvents: [SessionProviderEvent] = []
        private var providerFacts: StructuredSessionProviderFacts = .empty
        private var finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic?
        private var persistedProviderEventOverflow: [SessionProviderEvent] = []
        private var nextProviderEventSequence = 0
        private var providerSlashCommands: [SessionSlashCommand]?
        private var availableModelCommands: [SessionSlashCommand]?
        private var terminalColumns = 80
        private var terminalRows = 24
        private var sessionLinkage: PiSessionLinkage?
        private var pendingSessionTransitions: [SessionRuntimeSessionTransition] = []
        private var changeHandler: (@Sendable () -> Void)?
        private var isStreaming = false
        /// True after a user `prompt` is accepted until `agent_end` (or error/aborted `message_end` / process exit).
        private var promptTurnCommitted = false
        /// Set when a new-turn `prompt` is sent until Pi returns `response` for that command.
        private var awaitingPromptAcceptance = false
        private var assistantTranscriptIndex: Int?
        private var currentAssistantText = ""
        /// Full assistant body accumulated from `text_delta` for the active turn (not subject to transcript trimming).
        private var liveStreamedAssistantText = ""
        private var lastAssistantStopReason: String?
        private var toolOutputByCallID: [String: String] = [:]
        private var toolNamesByCallID: [String: String] = [:]
        private var toolActivityItemIDByCallID: [String: UUID] = [:]
        private var toolAgentsByCallID: [String: String] = [:]
        private var streamingObservationThrottle = PiRPCStreamingObservationThrottle()
        private var didRequestStop = false
        private var pendingSlashCommandsRequestID: String?
        private var pendingAvailableModelsRequestID: String?
        private var pendingSetModelTargetsByRequestID: [String: String] = [:]
        private var pendingSetThinkingLevelsByRequestID: [String: String] = [:]
        private var pendingSetSteeringModesByRequestID: [String: String] = [:]
        private var pendingSetFollowUpModesByRequestID: [String: String] = [:]
        private var pendingSetSessionNamesByRequestID: [String: String] = [:]
        private var pendingAutoCompactionSettingsByRequestID: [String: Bool] = [:]
        private var pendingAutoRetrySettingsByRequestID: [String: Bool] = [:]
        private var pendingBashCommandsByRequestID: [String: String] = [:]
        private var pendingExportHTMLPathsByRequestID: [String: String] = [:]
        private var pendingSessionTransitionStateRequestIDs: Set<String> = []
        private var nextSlashCommandsRequestSequence = 0
        private var nextAvailableModelsRequestSequence = 0
        private var nextSetThinkingRequestSequence = 0
        private var nextSetSteeringModeRequestSequence = 0
        private var nextSetFollowUpModeRequestSequence = 0
        private var nextBashRequestSequence = 0
        private var nextExportHTMLRequestSequence = 0
        private let nexusSessionID: UUID?
        private var lastStdoutActivityUptimeNanoseconds: UInt64?
        private var lastProviderPollUptimeNanoseconds: UInt64?
        private var watchdogPollsSinceIdleThreshold = 0
        private var providerStallDeclared = false
        private var turnWatchdogTask: Task<Void, Never>?

        convenience init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: PiSessionLinkage? = nil,
            restoredMetadata: SessionRecordAdapterMetadata? = nil,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State = .exited,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
            stopHandler: (() throws -> Void)? = nil,
            processEnvironment: [String: String]? = nil,
            nexusSessionID: UUID? = nil,
            transportFactory: TransportFactory? = nil
        ) throws {
            let sessionID = nexusSessionID
            let resolvedTransportFactory =
                transportFactory ?? { executable, arguments, workingDirectory in
                    try ProcessPiRPCTransport(
                        executable: executable,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: processEnvironment,
                        nexusSessionID: sessionID
                    )
                }

            try self.init(
                executable: executable,
                workingDirectory: workingDirectory,
                sessionLinkage: sessionLinkage,
                restoredMetadata: restoredMetadata,
                terminationStatusMessageBuilder: terminationStatusMessageBuilder,
                unexpectedTerminationState: unexpectedTerminationState,
                unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder,
                stopHandler: stopHandler,
                nexusSessionID: nexusSessionID,
                transportFactory: resolvedTransportFactory,
                performStartup: false
            )
            try AsyncOperationSupport.blocking { try await self.completeStartup() }
        }

        convenience init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: PiSessionLinkage? = nil,
            restoredMetadata: SessionRecordAdapterMetadata? = nil,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State = .exited,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
            stopHandler: (() throws -> Void)? = nil,
            processEnvironment: [String: String]? = nil,
            nexusSessionID: UUID? = nil,
            transportFactory: TransportFactory? = nil
        ) async throws {
            let sessionID = nexusSessionID
            let resolvedTransportFactory =
                transportFactory ?? { executable, arguments, workingDirectory in
                    try ProcessPiRPCTransport(
                        executable: executable,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: processEnvironment,
                        nexusSessionID: sessionID
                    )
                }

            try self.init(
                executable: executable,
                workingDirectory: workingDirectory,
                sessionLinkage: sessionLinkage,
                restoredMetadata: restoredMetadata,
                terminationStatusMessageBuilder: terminationStatusMessageBuilder,
                unexpectedTerminationState: unexpectedTerminationState,
                unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder,
                stopHandler: stopHandler,
                nexusSessionID: nexusSessionID,
                transportFactory: resolvedTransportFactory,
                performStartup: false
            )
            try await self.completeStartup()
        }

        private init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: PiSessionLinkage?,
            restoredMetadata: SessionRecordAdapterMetadata?,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)?,
            stopHandler: (() throws -> Void)?,
            nexusSessionID: UUID?,
            transportFactory: TransportFactory,
            performStartup: Bool
        ) throws {
            self.nexusSessionID = nexusSessionID
            self.stopHandler = stopHandler
            self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
            self.unexpectedTerminationState = unexpectedTerminationState
            self.unexpectedTerminationMessageBuilder =
                unexpectedTerminationMessageBuilder ?? terminationStatusMessageBuilder
            self.sessionLinkage = sessionLinkage ?? restoredMetadata?.piSessionLinkage
            self.transport = try transportFactory(
                executable, Self.transportArguments(sessionLinkage: self.sessionLinkage), workingDirectory)
            restorePersistedState(from: restoredMetadata)
        }

        private func restorePersistedState(from metadata: SessionRecordAdapterMetadata?) {
            guard let metadata, metadata.providerID == .pi else {
                return
            }

            activityItems = StructuredSessionLiveHistoryRetention.retainedActivityItems(
                metadata.piPersistedActivityItems ?? [])
            transcriptEntries = StructuredSessionLiveHistoryRetention.retainedTranscriptEntries(
                Self.transcriptEntries(from: activityItems))
            approvalRequests = metadata.piPersistedApprovalRequests ?? []
            if let extensionUIState = metadata.piPersistedExtensionUIState {
                extensionTitle = extensionUIState.title
                pendingExtensionDialogs = extensionUIState.pendingDialogs
                extensionNotifications = extensionUIState.notifications
                extensionStatuses = extensionUIState.statuses.map { status in
                    SessionExtensionUIStatus(
                        key: status.key,
                        text: TerminalEscapeSequences.stripForPlainDisplay(status.text))
                }
                extensionWidgets = extensionUIState.widgets
                extensionEditorText = extensionUIState.editorText
            }
            providerEvents = StructuredSessionLiveHistoryRetention.retainedProviderEvents(
                PiStructuredSessionProviderEventCompaction.compacted(
                    events: metadata.piPersistedProviderEvents ?? [], providerID: .pi)
            )
            providerFacts = StructuredSessionProviderFacts.summarizing(providerEvents: providerEvents)
            nextProviderEventSequence = (providerEvents.last?.sequence ?? -1) + 1
        }

        private func completeStartup() async throws {
            let startupState = StartupState()
            let startupWaiter = AsyncResultWaiter<Void>()

            transport.setStdoutLineHandler { [weak self] line in
                guard let self,
                    let object = self.responseObject(from: line),
                    let type = self.string(for: "type", in: object)
                else {
                    return
                }

                self.recordProviderEvent(rawPayload: line, object: object, type: type)

                if type == "response" {
                    self.handleResponse(object, startupState: startupState, startupWaiter: startupWaiter)
                    self.notifyChange()
                    return
                }

                self.handleOutputEvent(object, type: type)
            }
            transport.setTerminationHandler { [weak self] status in
                if status != 0, startupState.error == nil {
                    let startupError = PiRPCSessionRuntimeError.startupFailed(
                        "Pi RPC mode exited before startup completed.")
                    startupState.record(error: startupError)
                    startupWaiter.fail(startupError)
                }
                self?.handleTermination(status: status)
            }

            try transport.start()
            try transport.sendLine(Self.jsonLine(["id": startupStateResponseID, "type": "get_state"]))

            do {
                try await startupWaiter.wait(
                    timeoutNanoseconds: 5_000_000_000,
                    timeoutError: { PiRPCSessionRuntimeError.startupTimedOut }
                )
            } catch {
                try? transport.terminate()
                throw startupState.error ?? error
            }

            if let startupError = startupState.error {
                try? transport.terminate()
                throw startupError
            }

            if ProcessInfo.processInfo.environment["NEXUS_PI_RPC_STARTUP_SESSION_STATS"] == "1" {
                requestSessionStats()
            }
            startTurnWatchdogIfNeeded()
            if let nexusSessionID {
                NexusSessionRuntimeDiagnostics.logPiTurnWatchdogStarted(
                    sessionID: nexusSessionID,
                    stallThresholdSeconds: Int(
                        PiRPCTurnWatchdog.configuredStallThresholdNanoseconds() / 1_000_000_000)
                )
            }
        }

        deinit {
            turnWatchdogTask?.cancel()
            try? transport.terminate()
        }

        func sessionScreen(for session: Session) -> SessionScreen {
            lock.lock()
            defer { lock.unlock() }
            let currentSession =
                currentSessionName.map {
                    Session(
                        id: session.id,
                        workspaceID: session.workspaceID,
                        providerID: session.providerID,
                        name: $0,
                        isDefault: session.isDefault,
                        state: session.state,
                        failureMessage: session.failureMessage
                    )
                } ?? session
            return SessionScreen(
                session: currentSession,
                primarySurface: .structuredActivityFeed,
                transcript: runtimeState == .interrupted
                    ? (interruptedFailureMessage ?? renderedTranscriptLocked()) : renderedTranscriptLocked(),
                terminalColumns: terminalColumns,
                terminalRows: terminalRows,
                activityItems: activityItems,
                approvalRequests: approvalRequests,
                extensionUI: extensionUIStateLocked(),
                slashCommands: mergedSlashCommandsLocked(),
                providerEvents: providerEvents,
                providerFacts: providerFacts,
                finalOutputDiagnostic: finalOutputDiagnostic,
                isAgentTurnInProgress: isStreaming || promptTurnCommitted
            )
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
            lock.lock()
            changeHandler = handler
            lock.unlock()
        }

        func stop() throws {
            lock.lock()
            didRequestStop = true
            runtimeState = .exited
            lock.unlock()
            try stopHandler?()
            try transport.terminate()
            notifyChange()
        }

        func sendInput(_ text: String) throws {
            try sendInput(SessionPrompt(text: text))
        }

        func sendInput(_ prompt: SessionPrompt) throws {
            try submitPrompt(prompt)
        }

        func sendText(_ text: String) throws {
            guard text.isEmpty == false else {
                return
            }

            lock.lock()
            draft += text
            lock.unlock()
            notifyChange()
        }

        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {
            switch key {
            case .enter:
                let prompt: String
                lock.lock()
                prompt = draft
                lock.unlock()
                try submitPrompt(SessionPrompt(text: prompt))
            case .backspace, .deleteForward:
                lock.lock()
                if draft.isEmpty == false {
                    draft.removeLast()
                }
                lock.unlock()
                notifyChange()
            case .tab:
                try sendText("\t")
            default:
                return
            }
        }

        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {
            lock.lock()
            guard let index = approvalRequests.firstIndex(where: { $0.id == approvalRequestID && $0.state == .pending })
            else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.approvalRequestNotFound
            }

            let request = approvalRequests[index]
            approvalRequests[index] = SessionApprovalRequest(
                id: request.id,
                title: request.title,
                text: request.text,
                state: decision == .approve ? .approved : .denied
            )
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: .approvalDecision,
                    text: "\(decision == .approve ? "Approved" : "Denied"): \(request.title)"
                )
            )
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "type": "approval_response",
                    "id": approvalRequestID.uuidString,
                    "decision": decision.rawValue,
                ])
            )
        }

        func respondToExtensionDialog(_ dialogID: String, response: SessionExtensionUIDialogResponse) throws {
            lock.lock()
            guard pendingExtensionDialogs.contains(where: { $0.id == dialogID }) else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.extensionDialogNotFound
            }

            pendingExtensionDialogs.removeAll { $0.id == dialogID }
            lock.unlock()
            notifyChange()

            var payload: [String: Any] = [
                "type": "extension_ui_response",
                "id": dialogID,
            ]
            if let confirmed = response.confirmed {
                payload["confirmed"] = confirmed
            } else if response.cancelled {
                payload["cancelled"] = true
            } else {
                payload["value"] = response.value ?? ""
            }

            try transport.sendLine(Self.jsonLine(payload))
        }

        func resize(columns: Int, rows: Int) throws {
            lock.lock()
            terminalColumns = max(1, columns)
            terminalRows = max(1, rows)
            lock.unlock()
            notifyChange()
        }

        private func submitPrompt(_ prompt: SessionPrompt) throws {
            let trimmed = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedPrompt = SessionPrompt(text: trimmed, images: prompt.images)
            guard trimmed.isEmpty == false || prompt.images.isEmpty == false else {
                lock.lock()
                draft = ""
                lock.unlock()
                notifyChange()
                return
            }

            if trimmed == "/model" || trimmed.hasPrefix("/model ") {
                try submitModelCommand(trimmed)
                return
            }

            if trimmed == "/cycle-model" || trimmed == "/cycle_model" {
                try submitCycleModelCommand(trimmed)
                return
            }

            if trimmed == "/cycle-thinking-level" || trimmed == "/cycle_thinking_level" {
                try submitCycleThinkingLevelCommand(trimmed)
                return
            }

            if trimmed == "/thinking" || trimmed.hasPrefix("/thinking ") {
                try submitThinkingCommand(trimmed)
                return
            }

            if trimmed == "/compact" || trimmed.hasPrefix("/compact ") {
                try submitCompactCommand(trimmed)
                return
            }

            if trimmed == "/auto-compaction" || trimmed.hasPrefix("/auto-compaction ") || trimmed == "/auto_compaction"
                || trimmed.hasPrefix("/auto_compaction ") || trimmed == "/set-auto-compaction"
                || trimmed.hasPrefix("/set-auto-compaction ") || trimmed == "/set_auto_compaction"
                || trimmed.hasPrefix("/set_auto_compaction ")
            {
                try submitAutoCompactionCommand(trimmed)
                return
            }

            if trimmed == "/auto-retry" || trimmed.hasPrefix("/auto-retry ") || trimmed == "/auto_retry"
                || trimmed.hasPrefix("/auto_retry ") || trimmed == "/set-auto-retry"
                || trimmed.hasPrefix("/set-auto-retry ") || trimmed == "/set_auto_retry"
                || trimmed.hasPrefix("/set_auto_retry ")
            {
                try submitAutoRetryCommand(trimmed)
                return
            }

            if trimmed == "/abort-retry" || trimmed == "/abort_retry" {
                try submitAbortRetryCommand(trimmed)
                return
            }

            if trimmed == "/abort" {
                try submitAbortCommand()
                return
            }

            if trimmed == "/bash" || trimmed.hasPrefix("/bash ") {
                try submitBashCommand(trimmed)
                return
            }

            if trimmed == "/abort-bash" || trimmed == "/abort_bash" {
                try submitAbortBashCommand()
                return
            }

            if trimmed == "/export-html" || trimmed.hasPrefix("/export-html ") || trimmed == "/export_html"
                || trimmed.hasPrefix("/export_html ")
            {
                try submitExportHTMLCommand(trimmed)
                return
            }

            if trimmed == "/messages" || trimmed == "/get-messages" || trimmed == "/get_messages" {
                try submitGetMessagesCommand(commandText: trimmed)
                return
            }

            if trimmed == "/session-stats" || trimmed == "/session_stats" || trimmed == "/get-session-stats"
                || trimmed == "/get_session_stats"
            {
                try submitGetSessionStatsCommand(commandText: trimmed)
                return
            }

            if trimmed == "/last-assistant-text" || trimmed == "/last_assistant_text"
                || trimmed == "/get-last-assistant-text" || trimmed == "/get_last_assistant_text"
            {
                try submitGetLastAssistantTextCommand(commandText: trimmed)
                return
            }

            if trimmed == "/steering-mode" || trimmed.hasPrefix("/steering-mode ") || trimmed == "/steering_mode"
                || trimmed.hasPrefix("/steering_mode ")
            {
                try submitSteeringModeCommand(trimmed)
                return
            }

            if trimmed == "/follow-up-mode" || trimmed.hasPrefix("/follow-up-mode ") || trimmed == "/follow_up_mode"
                || trimmed.hasPrefix("/follow_up_mode ")
            {
                try submitFollowUpModeCommand(trimmed)
                return
            }

            if trimmed == "/steer" || trimmed.hasPrefix("/steer ") {
                try submitSteeringCommand(resolvedPrompt)
                return
            }

            if trimmed == "/follow-up" || trimmed.hasPrefix("/follow-up ") || trimmed == "/follow_up"
                || trimmed.hasPrefix("/follow_up ")
            {
                try submitFollowUpCommand(resolvedPrompt)
                return
            }

            if trimmed == "/fork-messages" || trimmed == "/fork_messages" {
                try submitGetForkMessagesCommand(trimmed)
                return
            }

            if trimmed == "/fork" || trimmed.hasPrefix("/fork ") {
                try submitForkCommand(trimmed)
                return
            }

            if trimmed == "/clone" {
                try submitCloneCommand()
                return
            }

            if trimmed == "/session-name" || trimmed.hasPrefix("/session-name ") || trimmed == "/session_name"
                || trimmed.hasPrefix("/session_name ")
            {
                try submitSetSessionNameCommand(trimmed)
                return
            }

            lock.lock()
            let isCurrentlyStreaming = isStreaming
            let startedNewTurn = isCurrentlyStreaming == false
            if startedNewTurn {
                isStreaming = true
                promptTurnCommitted = true
                awaitingPromptAcceptance = true
                resetTurnWatchdogLocked()
                if let nexusSessionID {
                    NexusSessionRuntimeDiagnostics.logPiPromptDispatch(
                        sessionID: nexusSessionID,
                        startedNewTurn: true
                    )
                }
                assistantTranscriptIndex = nil
                currentAssistantText = ""
                liveStreamedAssistantText = ""
                lastAssistantStopReason = nil
            }
            draft = ""
            appendTranscriptEntryLocked("> \(promptSummaryText(for: resolvedPrompt))")
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: .message,
                    text: isCurrentlyStreaming
                        ? "Queued steering: \(promptSummaryText(for: resolvedPrompt))"
                        : "You: \(promptSummaryText(for: resolvedPrompt))",
                    prompt: resolvedPrompt
                )
            )
            lock.unlock()
            notifyChange()

            var payload = promptPayload(type: "prompt", prompt: resolvedPrompt)
            if isCurrentlyStreaming {
                payload["streamingBehavior"] = piStreamingBehavior(for: resolvedPrompt)
            }
            try transport.sendLine(Self.jsonLine(payload))
        }

        private func submitSteeringCommand(_ prompt: SessionPrompt) throws {
            let message = String(prompt.text.dropFirst("/steer".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let queuedPrompt = SessionPrompt(text: message, images: prompt.images)
            try submitQueuedCommand(
                prompt: queuedPrompt,
                usageText: "Usage: /steer <message>",
                activityPrefix: "Queued steering",
                payload: promptPayload(type: "steer", prompt: queuedPrompt)
            )
        }

        private func submitFollowUpCommand(_ prompt: SessionPrompt) throws {
            let trimmed = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if trimmed.hasPrefix("/follow_up") {
                message = String(trimmed.dropFirst("/follow_up".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = String(trimmed.dropFirst("/follow-up".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let queuedPrompt = SessionPrompt(text: message, images: prompt.images)

            try submitQueuedCommand(
                prompt: queuedPrompt,
                usageText: "Usage: /follow-up <message>",
                activityPrefix: "Queued follow-up",
                payload: promptPayload(type: "follow_up", prompt: queuedPrompt)
            )
        }

        private func submitCompactCommand(_ commandText: String) throws {
            let instructions = String(commandText.dropFirst("/compact".count)).trimmingCharacters(
                in: .whitespacesAndNewlines)

            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: .command, text: instructions.isEmpty ? "/compact" : "/compact \(instructions)"))
            lock.unlock()
            notifyChange()

            var payload: [String: Any] = [
                "id": "nexus-pi-compact-\(UUID().uuidString)",
                "type": "compact",
            ]
            if instructions.isEmpty == false {
                payload["customInstructions"] = instructions
            }
            try transport.sendLine(Self.jsonLine(payload))
        }

        private func submitAutoCompactionCommand(_ commandText: String) throws {
            guard
                let enabled = parseEnabledSelection(
                    from: commandText,
                    preferredPrefixes: [
                        "/auto_compaction", "/auto-compaction", "/set_auto_compaction", "/set-auto-compaction",
                    ])
            else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /auto-compaction <on|off>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            draft = ""
            requestID = "nexus-pi-auto-compaction-\(UUID().uuidString)"
            pendingAutoCompactionSettingsByRequestID[requestID] = enabled
            appendActivityItemLocked(
                SessionActivityItem(kind: .command, text: "/auto-compaction \(enabled ? "on" : "off")"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_auto_compaction",
                    "enabled": enabled,
                ]))
        }

        private func submitAutoRetryCommand(_ commandText: String) throws {
            guard
                let enabled = parseEnabledSelection(
                    from: commandText,
                    preferredPrefixes: ["/auto_retry", "/auto-retry", "/set_auto_retry", "/set-auto-retry"])
            else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /auto-retry <on|off>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            draft = ""
            requestID = "nexus-pi-auto-retry-\(UUID().uuidString)"
            pendingAutoRetrySettingsByRequestID[requestID] = enabled
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/auto-retry \(enabled ? "on" : "off")"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_auto_retry",
                    "enabled": enabled,
                ]))
        }

        private func submitAbortRetryCommand(_ commandText: String) throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(
                SessionActivityItem(kind: .command, text: commandText == "/abort_retry" ? "/abort-retry" : commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-abort-retry-\(UUID().uuidString)",
                    "type": "abort_retry",
                ]))
        }

        private func submitAbortCommand() throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/abort"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(Self.jsonLine(["type": "abort"]))
        }

        private func submitGetForkMessagesCommand(_ commandText: String) throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-fork-messages-\(UUID().uuidString)",
                    "type": "get_fork_messages",
                ]))
        }

        private func submitBashCommand(_ commandText: String) throws {
            let bashCommand = String(commandText.dropFirst("/bash".count)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard bashCommand.isEmpty == false else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /bash <command>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            draft = ""
            requestID = "nexus-pi-bash-\(nextBashRequestSequence)"
            nextBashRequestSequence += 1
            pendingBashCommandsByRequestID[requestID] = bashCommand
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/bash \(bashCommand)"))
            appendActivityItemLocked(SessionActivityItem(kind: .progress, text: "Running bash: \(bashCommand)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "bash",
                    "command": bashCommand,
                ])
            )
        }

        private func submitAbortBashCommand() throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/abort-bash"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(Self.jsonLine(["type": "abort_bash"]))
        }

        private func submitExportHTMLCommand(_ commandText: String) throws {
            let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            let outputPath: String
            if trimmed.hasPrefix("/export_html") {
                outputPath = String(trimmed.dropFirst("/export_html".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            } else {
                outputPath = String(trimmed.dropFirst("/export-html".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }

            let requestID: String
            lock.lock()
            draft = ""
            requestID = "nexus-pi-export-html-\(nextExportHTMLRequestSequence)"
            nextExportHTMLRequestSequence += 1
            if outputPath.isEmpty == false {
                pendingExportHTMLPathsByRequestID[requestID] = outputPath
            }
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: .command, text: outputPath.isEmpty ? "/export-html" : "/export-html \(outputPath)"))
            lock.unlock()
            notifyChange()

            var payload: [String: Any] = [
                "id": requestID,
                "type": "export_html",
            ]
            if outputPath.isEmpty == false {
                payload["outputPath"] = outputPath
            }
            try transport.sendLine(Self.jsonLine(payload))
        }

        private func submitGetMessagesCommand(commandText: String) throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-messages-\(UUID().uuidString)",
                    "type": "get_messages",
                ]))
        }

        private func submitGetSessionStatsCommand(commandText: String) throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-session-stats-\(UUID().uuidString)",
                    "type": "get_session_stats",
                ]))
        }

        private func requestSessionStats() {
            lock.lock()
            let shouldReconcile = promptTurnCommitted
            lock.unlock()
            if shouldReconcile {
                requestGetStateReconciliation()
            }
            do {
                try transport.sendLine(
                    Self.jsonLine([
                        "id": "nexus-pi-session-stats-auto-\(UUID().uuidString)",
                        "type": "get_session_stats",
                    ]))
            } catch {
                return
            }
        }

        /// Reconcile stuck Thinking… when Pi finished but lifecycle events were dropped (`get_state.isStreaming`).
        private func requestGetStateReconciliation() {
            do {
                try transport.sendLine(
                    Self.jsonLine([
                        "id": "nexus-pi-reconcile-state-\(UUID().uuidString)",
                        "type": "get_state",
                    ]))
            } catch {
                return
            }
        }

        /// Caller must hold `lock`. Only clears an open prompt when Pi reports it is not streaming.
        private func reconcilePromptTurnFromPiGetStateLocked(_ data: [String: Any]) {
            guard promptTurnCommitted,
                bool(for: "isStreaming", in: data) == false
            else {
                return
            }
            finishPiAgentTurnLocked(stopReason: "stop")
            resetTurnWatchdogLocked()
        }

        private func noteStdoutActivityForTurnWatchdogIfCommitted(type: String, object: [String: Any]) {
            guard PiRPCTurnWatchdog.countsAsMeaningfulStdoutProgress(type: type, object: object) else {
                return
            }
            lock.lock()
            guard promptTurnCommitted else {
                lock.unlock()
                return
            }
            lastStdoutActivityUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            watchdogPollsSinceIdleThreshold = 0
            lock.unlock()
        }

        private func resetTurnWatchdogLocked() {
            providerStallDeclared = false
            watchdogPollsSinceIdleThreshold = 0
            lastProviderPollUptimeNanoseconds = nil
            lastStdoutActivityUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        }

        private func startTurnWatchdogIfNeeded() {
            turnWatchdogTask?.cancel()
            turnWatchdogTask = Task { [weak self] in
                let tick = PiRPCTurnWatchdog.configuredWatchdogTickNanoseconds()
                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: tick)
                    self?.runTurnWatchdogTick()
                }
            }
        }

        private func runTurnWatchdogTick() {
            let snapshot:
                (
                    committed: Bool,
                    declared: Bool,
                    lastActivity: UInt64?,
                    lastPoll: UInt64?,
                    polls: Int,
                    sessionID: UUID?,
                    sessionFile: String?
                )
            lock.lock()
            snapshot = (
                promptTurnCommitted,
                providerStallDeclared,
                lastStdoutActivityUptimeNanoseconds,
                lastProviderPollUptimeNanoseconds,
                watchdogPollsSinceIdleThreshold,
                nexusSessionID,
                sessionLinkage?.sessionFile
            )
            lock.unlock()

            let now = DispatchTime.now().uptimeNanoseconds
            let action = PiRPCTurnWatchdog.evaluate(
                promptTurnCommitted: snapshot.committed,
                providerStallDeclared: snapshot.declared,
                lastStdoutActivityUptimeNanoseconds: snapshot.lastActivity,
                lastProviderPollUptimeNanoseconds: snapshot.lastPoll,
                watchdogPollsSinceIdleThreshold: snapshot.polls,
                nowUptimeNanoseconds: now,
                pollIntervalNanoseconds: PiRPCTurnWatchdog.configuredPollIntervalNanoseconds(),
                stallThresholdNanoseconds: PiRPCTurnWatchdog.configuredStallThresholdNanoseconds()
            )

            switch action {
            case .none:
                return
            case .pollProviderState:
                lock.lock()
                lastProviderPollUptimeNanoseconds = now
                watchdogPollsSinceIdleThreshold += 1
                lock.unlock()
                requestGetStateReconciliation()
                requestSessionStatsForWatchdog()
                if let sessionID = snapshot.sessionID {
                    NexusSessionRuntimeDiagnostics.logPiTurnWatchdogPoll(
                        sessionID: sessionID,
                        idleThresholdSeconds: Int(
                            PiRPCTurnWatchdog.configuredStallThresholdNanoseconds() / 1_000_000_000),
                        piSessionFile: snapshot.sessionFile
                    )
                }
            case .declareProviderStall(let idleSeconds):
                declareProviderStall(idleSeconds: idleSeconds, piSessionFile: snapshot.sessionFile)
            }
        }

        private func requestSessionStatsForWatchdog() {
            do {
                try transport.sendLine(
                    Self.jsonLine([
                        "id": "nexus-pi-watchdog-stats-\(UUID().uuidString)",
                        "type": "get_session_stats",
                    ]))
            } catch {
                return
            }
        }

        private func declareProviderStall(idleSeconds: Int, piSessionFile: String?) {
            lock.lock()
            guard promptTurnCommitted, providerStallDeclared == false else {
                lock.unlock()
                return
            }
            providerStallDeclared = true
            let sessionID = nexusSessionID
            let message =
                "Pi stopped responding during this turn (no RPC progress for \(idleSeconds)s). "
                + "Use Stop or relaunch this Session, then try again."
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: message))
            finishPiAgentTurnLocked(stopReason: "provider_stall")
            lock.unlock()

            if let sessionID {
                NexusSessionRuntimeDiagnostics.logPiTurnWatchdogStallDeclared(
                    sessionID: sessionID,
                    idleSeconds: idleSeconds,
                    piSessionFile: piSessionFile
                )
            }
            notifyChange()
        }

        private func isAutomaticSessionStatsRequestID(_ requestID: String?) -> Bool {
            requestID?.hasPrefix("nexus-pi-session-stats-auto-") == true
        }

        private func submitGetLastAssistantTextCommand(commandText: String) throws {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-last-assistant-text-\(UUID().uuidString)",
                    "type": "get_last_assistant_text",
                ]))
        }

        private func submitForkCommand(_ commandText: String) throws {
            let entryID = String(commandText.dropFirst("/fork".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard entryID.isEmpty == false else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /fork <entry-id>"))
                lock.unlock()
                notifyChange()
                return
            }

            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/fork \(entryID)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-fork-\(UUID().uuidString)",
                    "type": "fork",
                    "entryId": entryID,
                ])
            )
        }

        private func submitCloneCommand() throws {
            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/clone"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-clone-\(UUID().uuidString)",
                    "type": "clone",
                ])
            )
        }

        private func submitSetSessionNameCommand(_ commandText: String) throws {
            let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameText: String
            if trimmed.hasPrefix("/session_name") {
                nameText = String(trimmed.dropFirst("/session_name".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            } else {
                nameText = String(trimmed.dropFirst("/session-name".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
            guard nameText.isEmpty == false else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /session-name <name>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            requestID = "nexus-pi-set-session-name-\(UUID().uuidString)"
            pendingSetSessionNamesByRequestID[requestID] = nameText
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/session-name \(nameText)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_session_name",
                    "name": nameText,
                ])
            )
        }

        private func submitSteeringModeCommand(_ commandText: String) throws {
            let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            let modeText: String
            if trimmed.hasPrefix("/steering_mode") {
                modeText = String(trimmed.dropFirst("/steering_mode".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            } else {
                modeText = String(trimmed.dropFirst("/steering-mode".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
            guard let mode = parseQueueModeSelection(modeText) else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(
                    SessionActivityItem(kind: .error, text: "Usage: /steering-mode <all|one-at-a-time>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            draft = ""
            requestID = "nexus-pi-set-steering-mode-\(nextSetSteeringModeRequestSequence)"
            nextSetSteeringModeRequestSequence += 1
            pendingSetSteeringModesByRequestID[requestID] = mode
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/steering-mode \(mode)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_steering_mode",
                    "mode": mode,
                ])
            )
        }

        private func submitFollowUpModeCommand(_ commandText: String) throws {
            let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            let modeText: String
            if trimmed.hasPrefix("/follow_up_mode") {
                modeText = String(trimmed.dropFirst("/follow_up_mode".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            } else {
                modeText = String(trimmed.dropFirst("/follow-up-mode".count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
            guard let mode = parseQueueModeSelection(modeText) else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(
                    SessionActivityItem(kind: .error, text: "Usage: /follow-up-mode <all|one-at-a-time>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            draft = ""
            requestID = "nexus-pi-set-follow-up-mode-\(nextSetFollowUpModeRequestSequence)"
            nextSetFollowUpModeRequestSequence += 1
            pendingSetFollowUpModesByRequestID[requestID] = mode
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/follow-up-mode \(mode)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_follow_up_mode",
                    "mode": mode,
                ])
            )
        }

        private func submitQueuedCommand(
            prompt: SessionPrompt,
            usageText: String,
            activityPrefix: String,
            payload: [String: Any]
        ) throws {
            guard prompt.text.isEmpty == false || prompt.images.isEmpty == false else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: usageText))
                lock.unlock()
                notifyChange()
                return
            }

            let summary = promptSummaryText(for: prompt)
            lock.lock()
            draft = ""
            appendTranscriptEntryLocked("> \(summary)")
            appendActivityItemLocked(
                SessionActivityItem(kind: .message, text: "\(activityPrefix): \(summary)", prompt: prompt))
            lock.unlock()
            notifyChange()

            try transport.sendLine(Self.jsonLine(payload))
        }

        private func promptPayload(type: String, prompt: SessionPrompt) -> [String: Any] {
            var payload: [String: Any] = [
                "type": type,
                "message": prompt.text,
            ]
            if prompt.images.isEmpty == false {
                payload["images"] = prompt.images.map {
                    [
                        "type": "image",
                        "data": $0.data.base64EncodedString(),
                        "mimeType": $0.mimeType,
                    ]
                }
            }
            return payload
        }

        private func promptSummaryText(for prompt: SessionPrompt) -> String {
            guard prompt.images.isEmpty == false else {
                return prompt.text
            }

            let imageSummary = "[\(prompt.images.count) image\(prompt.images.count == 1 ? "" : "s")]"
            if prompt.text.isEmpty {
                return imageSummary
            }
            return "\(prompt.text) \(imageSummary)"
        }

        private func submitModelCommand(_ commandText: String) throws {
            let target = String(commandText.dropFirst("/model".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let selection = parseModelSelection(target) else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /model <provider>/<model>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            requestID = "nexus-pi-set-model-\(nextAvailableModelsRequestSequence)"
            nextAvailableModelsRequestSequence += 1
            pendingSetModelTargetsByRequestID[requestID] = selection.target
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/model \(selection.target)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_model",
                    "provider": selection.provider,
                    "modelId": selection.modelID,
                ])
            )
        }

        private func submitThinkingCommand(_ commandText: String) throws {
            let target = String(commandText.dropFirst("/thinking".count)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard let level = parseThinkingLevelSelection(target) else {
                lock.lock()
                draft = ""
                appendActivityItemLocked(
                    SessionActivityItem(kind: .error, text: "Usage: /thinking <off|minimal|low|medium|high|xhigh>"))
                lock.unlock()
                notifyChange()
                return
            }

            let requestID: String
            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            requestID = "nexus-pi-set-thinking-\(nextSetThinkingRequestSequence)"
            nextSetThinkingRequestSequence += 1
            pendingSetThinkingLevelsByRequestID[requestID] = level
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: "/thinking \(level)"))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": requestID,
                    "type": "set_thinking_level",
                    "level": level,
                ])
            )
        }

        private func submitCycleModelCommand(_ commandText: String) throws {
            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-cycle-model-\(UUID().uuidString)",
                    "type": "cycle_model",
                ])
            )
        }

        private func submitCycleThinkingLevelCommand(_ commandText: String) throws {
            lock.lock()
            guard isStreaming == false else {
                lock.unlock()
                throw PiRPCSessionRuntimeError.busy
            }
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .command, text: commandText))
            lock.unlock()
            notifyChange()

            try transport.sendLine(
                Self.jsonLine([
                    "id": "nexus-pi-cycle-thinking-\(UUID().uuidString)",
                    "type": "cycle_thinking_level",
                ])
            )
        }

        private func handleResponse(
            _ response: [String: Any],
            startupState: StartupState,
            startupWaiter: AsyncResultWaiter<Void>
        ) {
            let id = string(for: "id", in: response)
            let command = string(for: "command", in: response)

            if id == startupStateResponseID {
                if bool(for: "success", in: response) == true {
                    lock.lock()
                    updateSessionLinkageLocked(from: response)
                    updateCurrentStateLocked(from: response)
                    activityItems.removeAll {
                        $0.kind == .error
                            && $0.text.contains("Session stream disconnected")
                    }
                    let connectedStatus = "Pi shared Session stream connected"
                    if activityItems.contains(where: { $0.kind == .status && $0.text == connectedStatus })
                        == false
                    {
                        appendActivityItemLocked(SessionActivityItem(kind: .status, text: connectedStatus))
                    }
                    if let currentModelStatus = currentModelStatusTextLocked(),
                        activityItems.contains(where: { $0.kind == .status && $0.text == currentModelStatus }) == false
                    {
                        appendActivityItemLocked(SessionActivityItem(kind: .status, text: currentModelStatus))
                    }
                    lock.unlock()
                    requestSlashCommands(preferredID: startupCommandsResponseID)
                    requestAvailableModels(preferredID: startupAvailableModelsResponseID)
                    startupWaiter.succeed()
                } else {
                    let errorMessage = string(for: "error", in: response) ?? "Pi RPC startup failed."
                    let startupError = PiRPCSessionRuntimeError.startupFailed(errorMessage)
                    startupState.record(error: startupError)
                    startupWaiter.fail(startupError)
                }
                return
            }

            switch command {
            case "get_state":
                handleGetStateResponse(response, requestID: id)
            case "get_commands":
                handleGetCommandsResponse(response, requestID: id)
            case "get_available_models":
                handleAvailableModelsResponse(response, requestID: id)
            case "set_model":
                handleSetModelResponse(response, requestID: id)
            case "cycle_model":
                handleCycleModelResponse(response)
            case "cycle_thinking_level":
                handleCycleThinkingLevelResponse(response)
            case "set_thinking_level":
                handleSetThinkingLevelResponse(response, requestID: id)
            case "set_steering_mode":
                handleSetSteeringModeResponse(response, requestID: id)
            case "set_follow_up_mode":
                handleSetFollowUpModeResponse(response, requestID: id)
            case "compact":
                handleCompactResponse(response)
            case "set_auto_compaction":
                handleSetAutoCompactionResponse(response, requestID: id)
            case "set_auto_retry":
                handleSetAutoRetryResponse(response, requestID: id)
            case "abort_retry":
                handleAbortRetryResponse(response)
            case "get_fork_messages":
                handleGetForkMessagesResponse(response)
            case "bash":
                handleBashResponse(response, requestID: id)
            case "abort_bash":
                handleAbortBashResponse(response)
            case "export_html":
                handleExportHTMLResponse(response, requestID: id)
            case "get_messages":
                handleGetMessagesResponse(response)
            case "get_session_stats":
                handleGetSessionStatsResponse(response, requestID: id)
            case "get_last_assistant_text":
                handleGetLastAssistantTextResponse(response)
            case "fork":
                handleForkResponse(response)
            case "clone":
                handleCloneResponse(response)
            case "set_session_name":
                handleSetSessionNameResponse(response, requestID: id)
            case "new_session":
                handleSessionTransitionResponse(
                    response, successText: "Started a new session", cancelledText: "New session cancelled")
            case "switch_session":
                handleSessionTransitionResponse(
                    response, successText: "Switched session", cancelledText: "Session switch cancelled")
            case "prompt":
                if bool(for: "success", in: response) == true {
                    lock.lock()
                    awaitingPromptAcceptance = false
                    let sessionID = nexusSessionID
                    lock.unlock()
                    if let sessionID {
                        NexusSessionRuntimeDiagnostics.logPiPromptAccepted(sessionID: sessionID)
                    }
                    requestSlashCommands()
                } else {
                    handlePromptSubmissionRejected(response)
                }
            default:
                handleUnhandledResponse(response)
            }
        }

        private func handleOutputEvent(_ object: [String: Any], type: String) {
            noteStdoutActivityForTurnWatchdogIfCommitted(type: type, object: object)
            switch type {
            case "agent_start":
                notifyChange()
            case "thinking_level_changed":
                handleThinkingLevelChanged(object)
            case "extension_error":
                handleExtensionError(object)
            case "agent_end":
                handleAgentEnd(object)
            case "message_update":
                handleMessageUpdate(object)
            case "message_end":
                handleMessageEnd(object)
            case "extension_ui_request":
                handleExtensionUIRequest(object)
            case "queue_update":
                handleQueueUpdate(object)
            case "compaction_start":
                handleCompactionStart(object)
            case "compaction_end":
                handleCompactionEnd(object)
            case "auto_retry_start":
                handleAutoRetryStart(object)
            case "auto_retry_end":
                handleAutoRetryEnd(object)
            case "new_session", "switch_session":
                handleSessionTransitionEvent(object)
            case "tool_execution_start":
                handleToolExecutionStart(object)
            case "tool_execution_update":
                handleToolExecutionUpdate(object)
            case "tool_execution_end":
                handleToolExecutionEnd(object)
            case "turn_end":
                handleTurnEnd(object)
            default:
                notifyChange()
            }
        }

        private func recordProviderEvent(rawPayload: String, object: [String: Any], type: String) {
            lock.lock()
            let command = type == "response" ? string(for: "command", in: object) : nil
            let event = SessionProviderEvent(
                sequence: nextProviderEventSequence,
                providerID: .pi,
                type: type,
                family: providerEventFamily(for: type),
                command: command,
                rawPayload: rawPayload
            )
            let retainedEvent = PiStructuredSessionProviderEventCompaction.compacted(
                sequence: nextProviderEventSequence,
                type: type,
                family: event.family,
                command: command,
                rawPayload: rawPayload,
                object: object
            )
            nextProviderEventSequence += 1
            providerEvents.append(retainedEvent)
            if providerEvents.count > StructuredSessionLiveHistoryRetention.maxRetainedProviderEvents {
                let removedCount =
                    providerEvents.count - StructuredSessionLiveHistoryRetention.maxRetainedProviderEvents
                persistedProviderEventOverflow.append(contentsOf: providerEvents.prefix(removedCount))
                providerEvents.removeFirst(removedCount)
            }
            providerFacts = providerFacts.appending(event, retainedProviderEventCount: providerEvents.count)
            lock.unlock()
        }

        private func providerEventFamily(for type: String) -> SessionProviderEvent.Family {
            let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedType == "response" {
                return .response
            }
            if normalizedType == "agent" || normalizedType.hasPrefix("agent_") {
                return .agent
            }
            if normalizedType == "turn" || normalizedType.hasPrefix("turn_") {
                return .turn
            }
            if normalizedType == "message" || normalizedType.hasPrefix("message_") {
                return .message
            }
            if normalizedType == "tool_execution" || normalizedType.hasPrefix("tool_execution_") {
                return .toolExecution
            }
            if normalizedType.contains("queue") {
                return .queue
            }
            if normalizedType.contains("compaction") {
                return .compaction
            }
            if normalizedType.contains("retry") {
                return .retry
            }
            if normalizedType == "extension_error"
                || (normalizedType.contains("extension") && normalizedType.contains("error"))
            {
                return .extensionError
            }
            return .unknown
        }

        private func handleQueueUpdate(_ object: [String: Any]) {
            let steering = object["steering"] as? [String] ?? []
            let followUp = object["followUp"] as? [String] ?? []

            let shouldNotify: Bool
            lock.lock()
            shouldNotify = queuedSteeringMessages != steering || queuedFollowUpMessages != followUp
            queuedSteeringMessages = steering
            queuedFollowUpMessages = followUp
            if shouldNotify {
                appendActivityItemLocked(
                    SessionActivityItem(
                        kind: .status,
                        text: queueUpdateStatusText(steering: steering, followUp: followUp)
                    )
                )
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleCompactionStart(_ object: [String: Any]) {
            let reason = trimmedString(for: "reason", in: object) ?? "manual"

            lock.lock()
            switch reason {
            case "threshold", "overflow":
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "Auto-compacting the session context"))
            default:
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Compacting the session context"))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleCompactionEnd(_ object: [String: Any]) {
            lock.lock()

            let reason = trimmedString(for: "reason", in: object) ?? "manual"
            let isAutomatic = reason == "threshold" || reason == "overflow"

            if bool(for: "aborted", in: object) == true {
                appendActivityItemLocked(
                    SessionActivityItem(
                        kind: .error,
                        text: isAutomatic ? "Auto-compaction was cancelled" : "Compaction was cancelled"
                    )
                )
            } else if let result = object["result"] as? [String: Any] {
                appendActivityItemLocked(
                    SessionActivityItem(
                        kind: .status,
                        text: isAutomatic ? "Auto-compacted the session context" : "Compacted the session context"
                    )
                )
                if let summary = trimmedString(for: "summary", in: result) {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Compaction summary: \(summary)"))
                }
            } else if let errorMessage = trimmedString(for: "errorMessage", in: object) {
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: errorMessage))
            }

            lock.unlock()
            notifyChange()
        }

        private func handleAutoRetryStart(_ object: [String: Any]) {
            let attempt = intValue(object["attempt"]) ?? 1
            let maxAttempts = intValue(object["maxAttempts"]) ?? attempt
            let delayMs = intValue(object["delayMs"]) ?? 0
            let delaySeconds = max(1, Int(ceil(Double(delayMs) / 1000)))

            lock.lock()
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: .status,
                    text: "Retrying automatically (attempt \(attempt) of \(maxAttempts)) in \(delaySeconds)s"
                )
            )
            lock.unlock()
            notifyChange()
        }

        private func handleAutoRetryEnd(_ object: [String: Any]) {
            let success = bool(for: "success", in: object) == true
            let attempt = intValue(object["attempt"]) ?? 1
            let finalError = trimmedString(for: "finalError", in: object)

            lock.lock()
            if success {
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "Retry succeeded on attempt \(attempt)"))
            } else {
                let detail = finalError ?? "Unknown error"
                appendActivityItemLocked(
                    SessionActivityItem(kind: .error, text: "Retry failed after \(attempt) attempts: \(detail)"))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleExtensionUIRequest(_ object: [String: Any]) {
            guard let dialogID = string(for: "id", in: object),
                let method = string(for: "method", in: object)
            else {
                return
            }

            let shouldNotify: Bool
            lock.lock()
            switch method {
            case "select":
                let title = string(for: "title", in: object) ?? "Select"
                let options = object["options"] as? [String] ?? []
                upsertExtensionDialogLocked(
                    SessionExtensionUIDialog(
                        id: dialogID,
                        kind: .select,
                        title: title,
                        options: options,
                        timeoutMilliseconds: int(for: "timeout", in: object)
                    )
                )
                shouldNotify = true
            case "confirm":
                let title = string(for: "title", in: object) ?? "Confirm"
                upsertExtensionDialogLocked(
                    SessionExtensionUIDialog(
                        id: dialogID,
                        kind: .confirm,
                        title: title,
                        message: string(for: "message", in: object),
                        timeoutMilliseconds: int(for: "timeout", in: object)
                    )
                )
                shouldNotify = true
            case "input":
                let title = string(for: "title", in: object) ?? "Input"
                upsertExtensionDialogLocked(
                    SessionExtensionUIDialog(
                        id: dialogID,
                        kind: .input,
                        title: title,
                        placeholder: string(for: "placeholder", in: object),
                        timeoutMilliseconds: int(for: "timeout", in: object)
                    )
                )
                shouldNotify = true
            case "editor":
                let title = string(for: "title", in: object) ?? "Editor"
                upsertExtensionDialogLocked(
                    SessionExtensionUIDialog(
                        id: dialogID,
                        kind: .editor,
                        title: title,
                        prefill: string(for: "prefill", in: object)
                    )
                )
                shouldNotify = true
            case "notify":
                if let message = string(for: "message", in: object) {
                    extensionNotifications.append(
                        SessionExtensionUINotification(
                            kind: SessionExtensionUINotificationKind(
                                rawValue: string(for: "notifyType", in: object) ?? "info") ?? .info,
                            message: message
                        )
                    )
                    if extensionNotifications.count > 20 {
                        extensionNotifications.removeFirst(extensionNotifications.count - 20)
                    }
                    shouldNotify = true
                } else {
                    shouldNotify = false
                }
            case "setStatus":
                if let key = string(for: "statusKey", in: object) {
                    if let text = object["statusText"] as? String {
                        upsertExtensionStatusLocked(SessionExtensionUIStatus(key: key, text: text))
                    } else {
                        extensionStatuses.removeAll { $0.key == key }
                    }
                    shouldNotify = true
                } else {
                    shouldNotify = false
                }
            case "setWidget":
                if let key = string(for: "widgetKey", in: object) {
                    if let lines = object["widgetLines"] as? [String] {
                        upsertExtensionWidgetLocked(
                            SessionExtensionUIWidget(
                                key: key,
                                lines: lines,
                                placement: SessionExtensionUIWidgetPlacement(
                                    rawValue: string(for: "widgetPlacement", in: object) ?? "aboveEditor"
                                ) ?? .aboveEditor
                            )
                        )
                    } else {
                        extensionWidgets.removeAll { $0.key == key }
                    }
                    shouldNotify = true
                } else {
                    shouldNotify = false
                }
            case "setTitle":
                extensionTitle = string(for: "title", in: object)
                shouldNotify = true
            case "set_editor_text":
                extensionEditorText = string(for: "text", in: object) ?? ""
                shouldNotify = true
            default:
                shouldNotify = false
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleMessageUpdate(_ object: [String: Any]) {
            noteStdoutActivityForTurnWatchdogIfCommitted(type: "message_update", object: object)
            guard let assistantMessageEvent = object["assistantMessageEvent"] as? [String: Any],
                let eventType = string(for: "type", in: assistantMessageEvent)
            else {
                return
            }

            switch eventType {
            case "text_delta":
                let delta = string(for: "delta", in: assistantMessageEvent) ?? ""
                guard delta.isEmpty == false else {
                    return
                }

                lock.lock()
                currentAssistantText += delta
                liveStreamedAssistantText += delta
                ensureAssistantTranscriptEntryLocked()
                if let assistantTranscriptIndex {
                    transcriptEntries[assistantTranscriptIndex] = currentAssistantText
                    trimTranscriptEntriesLocked()
                }
                lock.unlock()
                notifyChangeThrottledForAssistantTextDelta()
            case "thinking_start":
                return
            case "thinking_end":
                let thinkingText = assistantThinkingText(from: assistantMessageEvent)
                guard thinkingText.isEmpty == false else {
                    return
                }

                lock.lock()
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "thoughts:", detailText: thinkingText))
                lock.unlock()
                notifyChange()
            case "toolcall_end":
                handleToolCallEnd(assistantMessageEvent)
            case "done":
                applyAssistantMessageStopReason(
                    fromAssistantMessageEvent: assistantMessageEvent,
                    object: object,
                    defaultStopReason: "stop"
                )
            case "error":
                applyAssistantMessageStopReason(
                    fromAssistantMessageEvent: assistantMessageEvent,
                    object: object,
                    defaultStopReason: "error"
                )
            default:
                return
            }
        }

        private func handleToolCallEnd(_ assistantMessageEvent: [String: Any]) {
            guard let toolCall = assistantMessageEvent["toolCall"] as? [String: Any],
                let toolCallID = string(for: "id", in: toolCall),
                let toolName = string(for: "name", in: toolCall)
            else {
                return
            }

            let rawArguments = toolCall["arguments"]
            let args: [String: Any]?
            if let dictionary = rawArguments as? [String: Any] {
                args = dictionary
            } else if let jsonString = rawArguments as? String,
                let data = jsonString.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                args = parsed
            } else {
                args = nil
            }

            let callText = toolExecutionCallText(toolName: toolName, args: args)
            guard callText.isEmpty == false else {
                return
            }

            lock.lock()
            if toolActivityItemIDByCallID[toolCallID] != nil {
                lock.unlock()
                return
            }

            let activityItemID = UUID()
            toolNamesByCallID[toolCallID] = toolName
            toolOutputByCallID[toolCallID] = ""
            toolActivityItemIDByCallID[toolCallID] = activityItemID
            if toolName.caseInsensitiveCompare("subagent") == .orderedSame,
                let agent = args.flatMap({ string(for: "agent", in: $0) })?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                agent.isEmpty == false
            {
                toolAgentsByCallID[toolCallID] = agent
            }
            appendActivityItemLocked(SessionActivityItem(id: activityItemID, kind: .command, text: callText))
            lock.unlock()
            notifyChange()
        }

        private func handleMessageEnd(_ object: [String: Any]) {
            guard let message = object["message"] as? [String: Any],
                string(for: "role", in: message) == "assistant"
            else {
                return
            }

            let stopReason = string(for: "stopReason", in: message) ?? "stop"
            applyAssistantMessageStopReason(
                message: message,
                stopReason: stopReason,
                errorMessage: trimmedString(for: "errorMessage", in: message)
            )
        }

        /// Pi RPC: `message_end` and `message_update` (`done` / `error`) share the same stop-reason handling.
        private func applyAssistantMessageStopReason(
            fromAssistantMessageEvent assistantMessageEvent: [String: Any],
            object: [String: Any],
            defaultStopReason: String
        ) {
            let message =
                (assistantMessageEvent["message"] as? [String: Any])
                ?? (object["message"] as? [String: Any])
            guard let message,
                string(for: "role", in: message) == "assistant"
            else {
                return
            }

            let stopReason =
                string(for: "reason", in: assistantMessageEvent)
                ?? string(for: "stopReason", in: message)
                ?? defaultStopReason
            let errorMessage =
                trimmedString(for: "error", in: assistantMessageEvent)
                ?? trimmedString(for: "errorMessage", in: message)
            applyAssistantMessageStopReason(
                message: message,
                stopReason: stopReason,
                errorMessage: errorMessage
            )
        }

        private func applyAssistantMessageStopReason(
            message: [String: Any],
            stopReason: String,
            errorMessage: String?
        ) {
            let resolvedText = resolvedPiAssistantFinalText(from: message)
            let shouldRequestSlashCommands: Bool

            lock.lock()
            switch stopReason {
            case "aborted", "error":
                let errorText =
                    errorMessage
                    ?? (stopReason == "aborted" ? "Operation aborted" : "Error")
                if resolvedText.isEmpty == false {
                    ensureAssistantTranscriptEntryLocked()
                    if let assistantTranscriptIndex {
                        transcriptEntries[assistantTranscriptIndex] = resolvedText
                        trimTranscriptEntriesLocked()
                    }
                    appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(resolvedText)"))
                }
                finishPiAgentTurnLocked(stopReason: stopReason)
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: errorText))
                shouldRequestSlashCommands = true
            case "stop", "length", "toolUse":
                // Provisional assistant text; user prompt stays open until `agent_end`.
                if resolvedText.isEmpty == false {
                    appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(resolvedText)"))
                }
                clearAssistantStreamingDraftBuffersLocked()
                shouldRequestSlashCommands = false
            default:
                if resolvedText.isEmpty == false {
                    appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(resolvedText)"))
                }
                clearAssistantStreamingDraftBuffersLocked()
                shouldRequestSlashCommands = false
            }
            lock.unlock()

            if shouldRequestSlashCommands {
                requestSlashCommands()
            }
            notifyChange()
        }

        private func handlePromptSubmissionRejected(_ response: [String: Any]) {
            let detail = string(for: "error", in: response) ?? "Pi rejected the prompt."
            lock.lock()
            if awaitingPromptAcceptance {
                awaitingPromptAcceptance = false
                finishPiAgentTurnLocked(stopReason: "error")
            }
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            lock.unlock()
            notifyChange()
        }

        private func handleExtensionError(_ object: [String: Any]) {
            let path = trimmedString(for: "extensionPath", in: object) ?? "extension"
            let eventName = trimmedString(for: "event", in: object) ?? "event"
            let error = trimmedString(for: "error", in: object) ?? "Unknown extension error"
            lock.lock()
            appendActivityItemLocked(
                SessionActivityItem(kind: .error, text: "Extension error (\(path), \(eventName)): \(error)"))
            lock.unlock()
            notifyChange()
        }

        /// Undocumented but emitted by Pi after model changes; keep current status in sync.
        private func handleThinkingLevelChanged(_ object: [String: Any]) {
            guard let level = trimmedString(for: "level", in: object) else {
                return
            }

            lock.lock()
            let clampedLevel = clampThinkingLevel(level, for: currentModel)
            guard currentThinkingLevel != clampedLevel else {
                lock.unlock()
                return
            }

            currentThinkingLevel = clampedLevel
            if let currentModelStatus = currentModelStatusTextLocked() {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: currentModelStatus))
            }
            lock.unlock()
            notifyChange()
        }

        /// Pi RPC `prompt.streamingBehavior` when the agent is already running (`docs/rpc.md`).
        private func piStreamingBehavior(for prompt: SessionPrompt) -> String {
            let trimmed = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("/follow-up ") || trimmed.hasPrefix("/follow_up ") {
                return "followUp"
            }
            return "steer"
        }

        private func handleToolExecutionStart(_ object: [String: Any]) {
            guard let toolCallID = string(for: "toolCallId", in: object),
                let toolName = string(for: "toolName", in: object)
            else {
                return
            }

            let args = object["args"] as? [String: Any]
            let callText = toolExecutionCallText(toolName: toolName, args: args)

            lock.lock()
            let activityItemID: UUID
            if let existing = toolActivityItemIDByCallID[toolCallID] {
                // Planning phase (toolcall_end) already created the .command row for this call.
                // Reuse its ID so execution updates/end populate detailText on the
                // originally-recorded tool row (the one the feed segments render).
                activityItemID = existing
            } else if let planned = mostRecentUnfilledCommandItemIDLocked(matchingToolName: toolName) {
                // IDs from toolcall_end (planning) and tool_execution_start may differ.
                // Link the execution stream to the planned row so output lands in the
                // accordion the user sees and opens.
                toolActivityItemIDByCallID[toolCallID] = planned
                activityItemID = planned
            } else {
                activityItemID = UUID()
                toolActivityItemIDByCallID[toolCallID] = activityItemID
                appendActivityItemLocked(SessionActivityItem(id: activityItemID, kind: .command, text: callText))
            }

            toolNamesByCallID[toolCallID] = toolName
            toolOutputByCallID[toolCallID] = ""
            if toolName.caseInsensitiveCompare("subagent") == .orderedSame,
                let agent = args.flatMap({ string(for: "agent", in: $0) })?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                agent.isEmpty == false
            {
                toolAgentsByCallID[toolCallID] = agent
            }
            lock.unlock()
            notifyChange()
        }

        private func handleToolExecutionUpdate(_ object: [String: Any]) {
            guard let toolCallID = string(for: "toolCallId", in: object) else {
                return
            }

            let partialResult = object["partialResult"] as? [String: Any]
            let outputText = toolExecutionResultText(partialResult)
            guard outputText.isEmpty == false else {
                return
            }

            let shouldNotify: Bool
            lock.lock()
            if toolActivityItemIDByCallID[toolCallID] == nil,
                let planned = mostRecentUnfilledCommandItemIDLocked()
            {
                // Bridge execution update to the planned tool row (from toolcall_end) even
                // if tool_execution_start was not seen or used a different toolCallId.
                // This ensures partial results land in the accordion the user opens.
                toolActivityItemIDByCallID[toolCallID] = planned
            }
            let previousText = toolOutputByCallID[toolCallID] ?? ""
            if previousText != outputText,
                let activityItemID = toolActivityItemIDByCallID[toolCallID]
            {
                toolOutputByCallID[toolCallID] = outputText
                setActivityItemDetailTextLocked(id: activityItemID, detailText: outputText)
                shouldNotify = true
            } else {
                shouldNotify = false
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleToolExecutionEnd(_ object: [String: Any]) {
            guard let toolCallID = string(for: "toolCallId", in: object) else {
                return
            }

            let result = object["result"] as? [String: Any]
            let outputText = toolExecutionResultText(result)
            let isError = bool(for: "isError", in: object) == true

            let shouldNotify: Bool
            lock.lock()
            if toolActivityItemIDByCallID[toolCallID] == nil,
                let planned = mostRecentUnfilledCommandItemIDLocked()
            {
                // Bridge final execution result back to the planning tool row created by toolcall_end
                // (or the most recent unfilled .command). This is the row rendered as the accordion
                // in the structured feed; without the link, output never appears inside the open tool bubble.
                toolActivityItemIDByCallID[toolCallID] = planned
            }
            if let activityItemID = toolActivityItemIDByCallID[toolCallID],
                outputText.isEmpty == false
            {
                setActivityItemDetailTextLocked(id: activityItemID, detailText: outputText)
            }

            let toolName = toolNamesByCallID.removeValue(forKey: toolCallID)
            let toolAgent = toolAgentsByCallID.removeValue(forKey: toolCallID)
            toolOutputByCallID.removeValue(forKey: toolCallID)
            toolActivityItemIDByCallID.removeValue(forKey: toolCallID)

            if let toolName,
                toolName.caseInsensitiveCompare("subagent") == .orderedSame,
                outputText.isEmpty == false,
                isError == false
            {
                appendActivityItemLocked(
                    SessionActivityItem(kind: .message, text: "\(toolAgent ?? "subagent"): \(outputText)"))
                shouldNotify = true
            } else if isError, outputText.isEmpty == false {
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: outputText))
                shouldNotify = true
            } else {
                shouldNotify = outputText.isEmpty == false
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleTurnEnd(_ object: [String: Any]) {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let message = object["message"] as? [String: Any]

            lock.lock()
            let finalText = resolvedPiAssistantFinalText(from: message)
            if finalText.isEmpty == false {
                ensureAssistantTranscriptEntryLocked()
                if let assistantTranscriptIndex {
                    transcriptEntries[assistantTranscriptIndex] = finalText
                    trimTranscriptEntriesLocked()
                }
                let finalActivityItem = SessionActivityItem(kind: .message, text: "Pi: \(finalText)")
                appendActivityItemLocked(finalActivityItem)
                recordFinalOutputDiagnosticLocked(
                    trigger: .turnEnd,
                    activityItem: finalActivityItem,
                    providerRuntimeLatencyMilliseconds: elapsedMilliseconds(since: startedAt),
                    expectedThinkingIndicatorVisible: promptTurnCommitted && isStreaming
                )
            }
            // Pi agent loop emits `turn_end` after every tool cycle; only `agent_end` ends the user prompt.
            clearAssistantStreamingBuffersLocked()
            streamingObservationThrottle.reset()
            lastAssistantStopReason = "stop"
            lock.unlock()
            requestSlashCommands()
            requestSessionStats()
            notifyChange()
        }

        /// Clears in-flight assistant text for the current assistant sub-message (between `message_end` and the next `text_delta`).
        private func clearAssistantStreamingDraftBuffersLocked() {
            currentAssistantText = ""
            liveStreamedAssistantText = ""
            assistantTranscriptIndex = nil
        }

        private func clearAssistantStreamingBuffersLocked() {
            clearAssistantStreamingDraftBuffersLocked()
            toolOutputByCallID.removeAll()
            toolNamesByCallID.removeAll()
            toolActivityItemIDByCallID.removeAll()
            toolAgentsByCallID.removeAll()
        }

        /// Ends the user-visible agent turn (Thinking… + scroll policy) at `agent_end` or terminal failure.
        private func finishPiAgentTurnLocked(stopReason: String) {
            awaitingPromptAcceptance = false
            clearAssistantStreamingBuffersLocked()
            streamingObservationThrottle.reset()
            isStreaming = false
            promptTurnCommitted = false
            lastAssistantStopReason = stopReason
            if stopReason != "provider_stall" {
                providerStallDeclared = false
            }
            watchdogPollsSinceIdleThreshold = 0
            lastProviderPollUptimeNanoseconds = nil
        }

        private func handleAgentEnd(_ object: [String: Any]) {
            let willRetry = bool(for: "willRetry", in: object) == true
            if let nexusSessionID {
                NexusSessionRuntimeDiagnostics.logPiAgentEnd(sessionID: nexusSessionID, willRetry: willRetry)
            }
            guard willRetry == false else {
                notifyChange()
                return
            }

            lock.lock()
            let shouldFinalizeTurn = promptTurnCommitted
            let finalText = shouldFinalizeTurn ? resolvedPiAssistantFinalTextFromAgentEndMessages(object) : ""
            if shouldFinalizeTurn {
                if finalText.isEmpty == false {
                    let alreadyHasMatchingPiRow = activityItems.contains {
                        $0.kind == .message && $0.text == "Pi: \(finalText)"
                    }
                    if alreadyHasMatchingPiRow == false {
                        ensureAssistantTranscriptEntryLocked()
                        if let assistantTranscriptIndex {
                            transcriptEntries[assistantTranscriptIndex] = finalText
                            trimTranscriptEntriesLocked()
                        }
                        appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(finalText)"))
                    }
                }
                finishPiAgentTurnLocked(stopReason: "stop")
            }
            lock.unlock()

            if shouldFinalizeTurn {
                requestSlashCommands()
                requestSessionStats()
            }
            notifyChange()
        }

        /// Pi RPC clients often treat `agent_end` as run completion; `turn_end` may be absent or carry no assistant body.
        private func resolvedPiAssistantFinalTextFromAgentEndMessages(_ object: [String: Any]) -> String {
            guard let messages = object["messages"] as? [[String: Any]] else {
                return resolvedPiAssistantFinalText(from: nil)
            }
            var lastAssistant = ""
            for message in messages {
                guard string(for: "role", in: message) == "assistant" else {
                    continue
                }
                let text = assistantText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty == false {
                    lastAssistant = text
                }
            }
            if lastAssistant.isEmpty == false {
                return resolvedPiAssistantFinalText(
                    from: [
                        "role": "assistant",
                        "content": [["type": "text", "text": lastAssistant]],
                    ])
            }
            return resolvedPiAssistantFinalText(from: nil)
        }

        private func handleTermination(status: Int32) {
            let shouldNotify: Bool
            let statusMessage: String
            let resolvedState: Session.State

            lock.lock()
            resolvedState = didRequestStop ? .exited : unexpectedTerminationState
            shouldNotify = runtimeState != resolvedState || didRequestStop == false
            runtimeState = resolvedState
            statusMessage = didRequestStop ? "" : unexpectedTerminationMessageBuilder(status)
            let trimmedStatusMessage = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStatusMessage.isEmpty == false {
                if resolvedState == .interrupted {
                    interruptedFailureMessage = trimmedStatusMessage
                    appendActivityItemLocked(SessionActivityItem(kind: .error, text: trimmedStatusMessage))
                } else {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: trimmedStatusMessage))
                }
            }
            let shouldFinalizeTurn = promptTurnCommitted
            if shouldFinalizeTurn {
                finishPiAgentTurnLocked(stopReason: "aborted")
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func ensureAssistantTranscriptEntryLocked() {
            guard assistantTranscriptIndex == nil else {
                return
            }

            transcriptEntries.append("")
            assistantTranscriptIndex = transcriptEntries.count - 1
            trimTranscriptEntriesLocked()
        }

        private func appendTranscriptEntryLocked(_ entry: String) {
            transcriptEntries.append(entry)
            trimTranscriptEntriesLocked()
        }

        private func trimTranscriptEntriesLocked() {
            let originalCount = transcriptEntries.count
            transcriptEntries = StructuredSessionLiveHistoryRetention.retainedTranscriptEntries(transcriptEntries)

            guard let assistantTranscriptIndex else {
                return
            }

            let removedCount = originalCount - transcriptEntries.count
            let shiftedIndex = assistantTranscriptIndex - removedCount
            guard transcriptEntries.indices.contains(shiftedIndex) else {
                self.assistantTranscriptIndex = nil
                currentAssistantText = ""
                return
            }

            self.assistantTranscriptIndex = shiftedIndex
            currentAssistantText = transcriptEntries[shiftedIndex]
        }

        private func renderedTranscriptLocked() -> String {
            var lines = transcriptEntries
            if draft.isEmpty == false {
                lines.append("> \(draft)")
            }
            return StructuredSessionLiveHistoryRetention.retainedTranscriptEntries(lines).joined(separator: "\n")
        }

        private static func transcriptEntries(from activityItems: [SessionActivityItem]) -> [String] {
            activityItems.compactMap { item in
                guard item.kind == .message else {
                    return nil
                }
                if item.text.hasPrefix("You: ") {
                    return "> \(item.text.dropFirst(5))"
                }
                return item.text.hasPrefix("Pi: ") ? String(item.text.dropFirst(4)) : item.text
            }
        }

        private func handleGetStateResponse(_ response: [String: Any], requestID: String?) {
            let shouldQueueTransition: Bool
            if bool(for: "success", in: response) == true {
                lock.lock()
                updateSessionLinkageLocked(from: response)
                updateCurrentStateLocked(from: response)
                if let data = response["data"] as? [String: Any] {
                    reconcilePromptTurnFromPiGetStateLocked(data)
                }
                shouldQueueTransition =
                    requestID.map { pendingSessionTransitionStateRequestIDs.remove($0) != nil } ?? false
                if shouldQueueTransition,
                    let metadata = sessionLinkage?.sessionRecordAdapterMetadata
                {
                    appendPendingSessionTransitionIfNeededLocked(metadata)
                }
                lock.unlock()
            } else {
                lock.lock()
                if let requestID {
                    pendingSessionTransitionStateRequestIDs.remove(requestID)
                }
                let detail = string(for: "error", in: response) ?? "Pi failed to refresh Session state."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
                lock.unlock()
            }

            notifyChange()
        }

        private func handleGetCommandsResponse(_ response: [String: Any], requestID: String?) {
            let nextSlashCommands: [SessionSlashCommand]?
            if bool(for: "success", in: response) == true {
                nextSlashCommands = parseSlashCommands(from: response) ?? []
            } else {
                nextSlashCommands = nil
            }

            let shouldNotify: Bool
            lock.lock()
            if requestID == pendingSlashCommandsRequestID {
                pendingSlashCommandsRequestID = nil
            }
            if let nextSlashCommands {
                shouldNotify = providerSlashCommands != nextSlashCommands
                providerSlashCommands = nextSlashCommands
            } else {
                shouldNotify = false
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleAvailableModelsResponse(_ response: [String: Any], requestID: String?) {
            let nextModelCommands: [SessionSlashCommand]?
            if bool(for: "success", in: response) == true {
                nextModelCommands = parseAvailableModelCommands(from: response) ?? []
            } else {
                nextModelCommands = nil
            }

            let shouldNotify: Bool
            lock.lock()
            if requestID == pendingAvailableModelsRequestID {
                pendingAvailableModelsRequestID = nil
            }
            if let nextModelCommands {
                shouldNotify = availableModelCommands != nextModelCommands
                availableModelCommands = nextModelCommands
            } else {
                shouldNotify = false
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleSetModelResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let fallbackTarget = requestID.flatMap { pendingSetModelTargetsByRequestID.removeValue(forKey: $0) }

            if bool(for: "success", in: response) == true {
                if let data = response["data"] as? [String: Any],
                    let model = parseModelDescriptor(from: data)
                {
                    currentModel = model
                    if let currentThinkingLevel {
                        self.currentThinkingLevel = clampThinkingLevel(currentThinkingLevel, for: model)
                    }
                }

                let resolvedTarget = formattedModelTarget(fromResponse: response) ?? fallbackTarget ?? "selected model"
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "Model switched to \(resolvedTarget)"))
                if let currentModelStatus = currentModelStatusTextLocked() {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: currentModelStatus))
                }
                lock.unlock()
                requestAvailableModels()
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to switch models."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
                lock.unlock()
            }

            notifyChange()
        }

        private func handleSetThinkingLevelResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let requestedLevel = requestID.flatMap { pendingSetThinkingLevelsByRequestID.removeValue(forKey: $0) }

            if bool(for: "success", in: response) == true {
                let effectiveLevel =
                    requestedLevel.map { clampThinkingLevel($0, for: currentModel) } ?? currentThinkingLevel
                currentThinkingLevel = effectiveLevel
                let message = effectiveLevel.map { "Thinking level set to \($0)" } ?? "Thinking level updated"
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: message))
                if let currentModelStatus = currentModelStatusTextLocked() {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: currentModelStatus))
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to set thinking level."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }

            lock.unlock()
            notifyChange()
        }

        private func handleCycleThinkingLevelResponse(_ response: [String: Any]) {
            lock.lock()

            if bool(for: "success", in: response) == true,
                let data = response["data"] as? [String: Any],
                let level = trimmedString(for: "level", in: data)
            {
                currentThinkingLevel = clampThinkingLevel(level, for: currentModel)
                appendActivityItemLocked(
                    SessionActivityItem(
                        kind: .status, text: "Thinking level cycled to \(currentThinkingLevel ?? level)"))
                if let currentModelStatus = currentModelStatusTextLocked() {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: currentModelStatus))
                }
            } else if bool(for: "success", in: response) == true {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Thinking level stayed the same"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to cycle thinking levels."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }

            lock.unlock()
            notifyChange()
        }

        private func handleCycleModelResponse(_ response: [String: Any]) {
            lock.lock()

            if bool(for: "success", in: response) == true {
                if let data = response["data"] as? [String: Any],
                    let model = data["model"] as? [String: Any],
                    let descriptor = parseModelDescriptor(from: model)
                {
                    currentModel = descriptor
                    if let thinkingLevel = trimmedString(for: "thinkingLevel", in: data) {
                        currentThinkingLevel = clampThinkingLevel(thinkingLevel, for: descriptor)
                    }
                    appendActivityItemLocked(
                        SessionActivityItem(
                            kind: .status, text: "Model cycled to \(formattedModelTarget(for: descriptor))"))
                    if let currentModelStatus = currentModelStatusTextLocked() {
                        appendActivityItemLocked(SessionActivityItem(kind: .status, text: currentModelStatus))
                    }
                    lock.unlock()
                    requestAvailableModels()
                } else {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Model stayed the same"))
                    lock.unlock()
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to cycle models."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
                lock.unlock()
            }

            notifyChange()
        }

        private func handleSetSteeringModeResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let requestedMode = requestID.flatMap { pendingSetSteeringModesByRequestID.removeValue(forKey: $0) }

            if bool(for: "success", in: response) == true {
                if let requestedMode {
                    steeringMode = requestedMode
                }
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "Steering mode set to \(steeringMode)"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to update steering mode."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }

            lock.unlock()
            requestSlashCommands()
            notifyChange()
        }

        private func handleSetFollowUpModeResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let requestedMode = requestID.flatMap { pendingSetFollowUpModesByRequestID.removeValue(forKey: $0) }

            if bool(for: "success", in: response) == true {
                if let requestedMode {
                    followUpMode = requestedMode
                }
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "Follow-up mode set to \(followUpMode)"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to update follow-up mode."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }

            lock.unlock()
            requestSlashCommands()
            notifyChange()
        }

        private func handleCompactResponse(_ response: [String: Any]) {
            lock.lock()
            if bool(for: "success", in: response) == true {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Compacted the session context"))
                if let data = response["data"] as? [String: Any],
                    let summary = trimmedString(for: "summary", in: data)
                {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Compaction summary: \(summary)"))
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to compact the Session context."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleSetAutoCompactionResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let enabled = requestID.flatMap { pendingAutoCompactionSettingsByRequestID.removeValue(forKey: $0) }
            if bool(for: "success", in: response) == true {
                let stateText = enabled == false ? "disabled" : "enabled"
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Auto-compaction \(stateText)"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to update auto-compaction."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleSetAutoRetryResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let enabled = requestID.flatMap { pendingAutoRetrySettingsByRequestID.removeValue(forKey: $0) }
            if bool(for: "success", in: response) == true {
                let stateText = enabled == false ? "disabled" : "enabled"
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Auto-retry \(stateText)"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to update auto-retry."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleAbortRetryResponse(_ response: [String: Any]) {
            lock.lock()
            if bool(for: "success", in: response) == true {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Requested retry cancellation"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to cancel retry."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleGetForkMessagesResponse(_ response: [String: Any]) {
            lock.lock()
            if bool(for: "success", in: response) == true,
                let data = response["data"] as? [String: Any],
                let messages = data["messages"] as? [[String: Any]]
            {
                if messages.isEmpty {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "No fork messages available"))
                } else {
                    for message in messages {
                        guard let entryID = trimmedString(for: "entryId", in: message),
                            let text = trimmedString(for: "text", in: message)
                        else {
                            continue
                        }
                        appendActivityItemLocked(
                            SessionActivityItem(
                                kind: .status,
                                text: "Fork message \(entryID): \(previewText(text, limit: 120))"
                            )
                        )
                    }
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to load fork messages."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleSetSessionNameResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let requestedName = requestID.flatMap { pendingSetSessionNamesByRequestID.removeValue(forKey: $0) }
            if bool(for: "success", in: response) == true {
                if let requestedName {
                    currentSessionName = requestedName
                    appendActivityItemLocked(
                        SessionActivityItem(kind: .status, text: "Session name set to \(requestedName)"))
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to set the Session name."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleSessionTransitionResponse(
            _ response: [String: Any],
            successText: String,
            cancelledText: String
        ) {
            guard bool(for: "success", in: response) == true else {
                handleUnhandledResponse(response)
                return
            }

            let data = response["data"] as? [String: Any]
            if bool(for: "cancelled", in: data ?? [:]) == true {
                lock.lock()
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: cancelledText))
                lock.unlock()
                notifyChange()
                return
            }

            lock.lock()
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: successText))
            lock.unlock()
            notifyChange()
            requestState(forSessionTransition: true)
        }

        private func appendPendingSessionTransitionIfNeeded(_ metadata: SessionRecordAdapterMetadata) {
            lock.lock()
            defer { lock.unlock() }
            appendPendingSessionTransitionIfNeededLocked(metadata)
        }

        private func appendPendingSessionTransitionIfNeededLocked(_ metadata: SessionRecordAdapterMetadata) {
            if let last = pendingSessionTransitions.last?.sessionRecordAdapterMetadata.piSessionLinkage,
                let next = metadata.piSessionLinkage,
                piSessionLinkageMatches(last, next)
            {
                return
            }
            pendingSessionTransitions.append(SessionRuntimeSessionTransition(sessionRecordAdapterMetadata: metadata))
        }

        private func piSessionLinkageMatches(_ lhs: PiSessionLinkage, _ rhs: PiSessionLinkage) -> Bool {
            let lhsFile = lhs.sessionFile?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsFile = rhs.sessionFile?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lhsFile, let rhsFile, lhsFile.isEmpty == false, lhsFile == rhsFile {
                return true
            }
            let lhsID = lhs.piSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsID = rhs.piSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return lhsID != nil && lhsID == rhsID && lhsID?.isEmpty == false
        }

        private func handleUnhandledResponse(_ response: [String: Any]) {
            guard bool(for: "success", in: response) != true else {
                return
            }

            let command = string(for: "command", in: response) ?? "rpc"
            let detail = string(for: "error", in: response) ?? "Pi command failed: \(command)"
            lock.lock()
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            lock.unlock()
            notifyChange()
        }

        private func handleBashResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let requestedCommand = requestID.flatMap { pendingBashCommandsByRequestID.removeValue(forKey: $0) }

            if bool(for: "success", in: response) == true {
                let data = response["data"] as? [String: Any]
                let output = trimmedString(for: "output", in: data ?? [:]) ?? ""
                let exitCode = data?["exitCode"] as? Int ?? 0
                let cancelled = bool(for: "cancelled", in: data ?? [:]) == true
                let truncated = bool(for: "truncated", in: data ?? [:]) == true
                let fullOutputPath = trimmedString(for: "fullOutputPath", in: data ?? [:])

                if output.isEmpty == false {
                    appendActivityItemLocked(SessionActivityItem(kind: .message, text: "bash: \(output)"))
                }

                if cancelled {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Bash cancelled"))
                } else {
                    var detail = "Bash completed with exit code \(exitCode) and will be included on the next prompt"
                    if truncated, let fullOutputPath {
                        detail += " (full output: \(fullOutputPath))"
                    }
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: detail))
                }
            } else {
                let detail =
                    string(for: "error", in: response) ?? requestedCommand.map { "Pi failed to run bash: \($0)" }
                    ?? "Pi failed to run bash."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleAbortBashResponse(_ response: [String: Any]) {
            lock.lock()
            if bool(for: "success", in: response) == true {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Requested bash cancellation"))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to cancel bash."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleExportHTMLResponse(_ response: [String: Any], requestID: String?) {
            lock.lock()
            let requestedPath = requestID.flatMap { pendingExportHTMLPathsByRequestID.removeValue(forKey: $0) }
            if bool(for: "success", in: response) == true {
                let responsePath = (response["data"] as? [String: Any]).flatMap { trimmedString(for: "path", in: $0) }
                let resolvedPath = responsePath ?? requestedPath
                let detail = resolvedPath.map { "Exported session HTML to \($0)" } ?? "Exported session HTML"
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: detail))
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to export Session HTML."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleGetMessagesResponse(_ response: [String: Any]) {
            lock.lock()
            if bool(for: "success", in: response) == true,
                let data = response["data"] as? [String: Any],
                let messages = data["messages"] as? [[String: Any]]
            {
                appendActivityItemLocked(
                    SessionActivityItem(
                        kind: .status, text: "Returned \(messages.count) message\(messages.count == 1 ? "" : "s")"))
                for (index, message) in messages.enumerated() {
                    let summary = sessionMessageSummary(message, index: index + 1)
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: summary))
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to load Session messages."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleGetSessionStatsResponse(_ response: [String: Any], requestID: String?) {
            guard isAutomaticSessionStatsRequestID(requestID) == false else {
                return
            }

            lock.lock()
            if bool(for: "success", in: response) == true,
                let data = response["data"] as? [String: Any]
            {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: sessionStatsSummaryText(data)))
                if let contextUsageText = sessionContextUsageText(data) {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: contextUsageText))
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to load Session stats."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleGetLastAssistantTextResponse(_ response: [String: Any]) {
            lock.lock()
            if bool(for: "success", in: response) == true,
                let data = response["data"] as? [String: Any]
            {
                let trimmedText = (data["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmedText, trimmedText.isEmpty == false {
                    appendActivityItemLocked(
                        SessionActivityItem(kind: .message, text: "Last assistant message: \(trimmedText)"))
                } else {
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "No assistant message yet"))
                }
            } else {
                let detail = string(for: "error", in: response) ?? "Pi failed to load the last assistant message."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
            }
            lock.unlock()
            notifyChange()
        }

        private func handleForkResponse(_ response: [String: Any]) {
            if bool(for: "success", in: response) == true {
                let data = response["data"] as? [String: Any]
                let cancelled = bool(for: "cancelled", in: data ?? [:]) == true
                if cancelled {
                    lock.lock()
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Fork cancelled"))
                    lock.unlock()
                    notifyChange()
                    return
                }

                if let selectedText = trimmedString(for: "text", in: data ?? [:]) {
                    lock.lock()
                    appendActivityItemLocked(
                        SessionActivityItem(
                            kind: .status, text: "Forked from: \(previewText(selectedText, limit: 120))"))
                    lock.unlock()
                }
                requestState(forSessionTransition: true)
            } else {
                lock.lock()
                let detail = string(for: "error", in: response) ?? "Pi failed to fork the Session."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
                lock.unlock()
                notifyChange()
            }
        }

        private func handleCloneResponse(_ response: [String: Any]) {
            if bool(for: "success", in: response) == true {
                let data = response["data"] as? [String: Any]
                if bool(for: "cancelled", in: data ?? [:]) == true {
                    lock.lock()
                    appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Clone cancelled"))
                    lock.unlock()
                    notifyChange()
                    return
                }

                lock.lock()
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Cloned the current session"))
                lock.unlock()
                requestState(forSessionTransition: true)
            } else {
                lock.lock()
                let detail = string(for: "error", in: response) ?? "Pi failed to clone the Session."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
                lock.unlock()
                notifyChange()
            }
        }

        private func requestSlashCommands(preferredID: String? = nil) {
            let requestID: String
            lock.lock()
            if pendingSlashCommandsRequestID != nil {
                lock.unlock()
                return
            }
            if let preferredID {
                requestID = preferredID
            } else {
                requestID = "nexus-pi-commands-\(nextSlashCommandsRequestSequence)"
                nextSlashCommandsRequestSequence += 1
            }
            pendingSlashCommandsRequestID = requestID
            lock.unlock()

            do {
                try transport.sendLine(Self.jsonLine(["id": requestID, "type": "get_commands"]))
            } catch {
                lock.lock()
                if pendingSlashCommandsRequestID == requestID {
                    pendingSlashCommandsRequestID = nil
                }
                lock.unlock()
            }
        }

        private func requestState(forSessionTransition: Bool = false) {
            let requestID = "nexus-pi-state-refresh-\(UUID().uuidString)"
            lock.lock()
            if forSessionTransition {
                pendingSessionTransitionStateRequestIDs.insert(requestID)
            }
            lock.unlock()

            do {
                try transport.sendLine(Self.jsonLine(["id": requestID, "type": "get_state"]))
            } catch {
                lock.lock()
                pendingSessionTransitionStateRequestIDs.remove(requestID)
                lock.unlock()
            }
        }

        private func requestAvailableModels(preferredID: String? = nil) {
            let requestID: String
            lock.lock()
            if pendingAvailableModelsRequestID != nil {
                lock.unlock()
                return
            }
            if let preferredID {
                requestID = preferredID
            } else {
                requestID = "nexus-pi-available-models-\(nextAvailableModelsRequestSequence)"
                nextAvailableModelsRequestSequence += 1
            }
            pendingAvailableModelsRequestID = requestID
            lock.unlock()

            do {
                try transport.sendLine(Self.jsonLine(["id": requestID, "type": "get_available_models"]))
            } catch {
                lock.lock()
                if pendingAvailableModelsRequestID == requestID {
                    pendingAvailableModelsRequestID = nil
                }
                lock.unlock()
            }
        }

        private func parseSlashCommands(from response: [String: Any]) -> [SessionSlashCommand]? {
            guard let data = response["data"] as? [String: Any],
                let rawCommands = data["commands"] as? [[String: Any]]
            else {
                return nil
            }

            return rawCommands.compactMap { command in
                guard let name = string(for: "name", in: command),
                    let sourceValue = string(for: "source", in: command),
                    let source = SessionSlashCommandSource(rawValue: sourceValue)
                else {
                    return nil
                }

                let sourceInfo = command["sourceInfo"] as? [String: Any]
                let path =
                    string(for: "path", in: command)
                    ?? sourceInfo.flatMap { string(for: "path", in: $0) }
                let location =
                    string(for: "location", in: command).flatMap(SessionSlashCommandLocation.init(rawValue:))
                    ?? slashCommandLocation(fromSourceInfo: sourceInfo, fallbackPath: path)

                return SessionSlashCommand(
                    name: name,
                    description: string(for: "description", in: command),
                    source: source,
                    location: location,
                    path: path
                )
            }
        }

        private func slashCommandLocation(fromSourceInfo sourceInfo: [String: Any]?, fallbackPath: String?)
            -> SessionSlashCommandLocation?
        {
            guard let sourceInfo else {
                return fallbackPath == nil ? nil : .path
            }

            switch trimmedString(for: "scope", in: sourceInfo) {
            case "user":
                return .user
            case "project":
                return .project
            case "temporary":
                return .path
            default:
                return fallbackPath == nil ? nil : .path
            }
        }

        private func parseAvailableModelCommands(from response: [String: Any]) -> [SessionSlashCommand]? {
            guard let data = response["data"] as? [String: Any],
                let rawModels = data["models"] as? [[String: Any]]
            else {
                return nil
            }

            return rawModels.compactMap { model in
                guard let provider = trimmedString(for: "provider", in: model),
                    let modelID = trimmedString(for: "id", in: model)
                else {
                    return nil
                }

                let target = "\(provider)/\(modelID)"
                let modelName = trimmedString(for: "name", in: model)
                let displayName = modelName.map { "model \(target) — \($0)" } ?? "model \(target)"
                let description = modelName.map { "Switch to \(target) — \($0)." } ?? "Switch to \(target)."
                return SessionSlashCommand(
                    name: "model \(target)",
                    displayName: displayName,
                    insertionText: "model \(target)",
                    suggestionQueryPrefix: "model ",
                    description: description,
                    source: .builtIn
                )
            }
        }

        private func parseModelSelection(_ target: String) -> (provider: String, modelID: String, target: String)? {
            guard let separator = target.firstIndex(of: "/") else {
                return nil
            }

            let provider = String(target[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = String(target[target.index(after: separator)...]).trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard provider.isEmpty == false, modelID.isEmpty == false else {
                return nil
            }

            return (provider: provider, modelID: modelID, target: "\(provider)/\(modelID)")
        }

        private func parseThinkingLevelSelection(_ target: String) -> String? {
            let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard piExtendedThinkingLevels.contains(normalized) else {
                return nil
            }
            return normalized
        }

        private func parseQueueModeSelection(_ target: String) -> String? {
            let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "all", "one-at-a-time":
                return normalized
            default:
                return nil
            }
        }

        private func parseEnabledSelection(from commandText: String, preferredPrefixes: [String]) -> Bool? {
            let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = preferredPrefixes.first(where: { trimmed.hasPrefix($0) })
            let suffix = prefix.map { String(trimmed.dropFirst($0.count)) } ?? trimmed
            let normalized = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "on", "true", "enabled":
                return true
            case "off", "false", "disabled":
                return false
            default:
                return nil
            }
        }

        private func formattedModelTarget(fromResponse response: [String: Any]) -> String? {
            guard let data = response["data"] as? [String: Any] else {
                return nil
            }
            return formattedModelTarget(fromModel: data)
        }

        private func formattedModelTarget(fromModel model: [String: Any]) -> String? {
            guard let provider = trimmedString(for: "provider", in: model),
                let modelID = trimmedString(for: "id", in: model)
            else {
                return nil
            }

            let target = "\(provider)/\(modelID)"
            if let name = trimmedString(for: "name", in: model) {
                return "\(target) — \(name)"
            }
            return target
        }

        private func parseModelDescriptor(from model: [String: Any]) -> PiRPCModelDescriptor? {
            guard let provider = trimmedString(for: "provider", in: model),
                let modelID = trimmedString(for: "id", in: model)
            else {
                return nil
            }

            return PiRPCModelDescriptor(
                provider: provider,
                id: modelID,
                name: trimmedString(for: "name", in: model),
                availableThinkingLevels: availableThinkingLevels(from: model, provider: provider, modelID: modelID)
            )
        }

        private func availableThinkingLevels(from model: [String: Any], provider: String, modelID: String) -> [String] {
            let reasoning = model["reasoning"] as? Bool ?? true
            guard reasoning else {
                return ["off"]
            }

            if let thinkingLevelMap = model["thinkingLevelMap"] as? [String: Any] {
                return piExtendedThinkingLevels.filter { level in
                    if let mappedValue = thinkingLevelMap[level] {
                        return (mappedValue is NSNull) == false
                    }
                    return level == "xhigh" ? supportsXHighThinkingLevel(provider: provider, modelID: modelID) : true
                }
            }

            return piBasicThinkingLevels
                + (supportsXHighThinkingLevel(provider: provider, modelID: modelID) ? ["xhigh"] : [])
        }

        private func supportsXHighThinkingLevel(provider: String, modelID: String) -> Bool {
            provider.caseInsensitiveCompare("openai") == .orderedSame
                && modelID.localizedCaseInsensitiveContains("codex-max")
        }

        private func clampThinkingLevel(_ level: String, for model: PiRPCModelDescriptor?) -> String {
            let availableLevels = availableThinkingLevels(for: model)
            if availableLevels.contains(level) {
                return level
            }

            guard let requestedIndex = piExtendedThinkingLevels.firstIndex(of: level) else {
                return availableLevels.first ?? "off"
            }

            for candidate in piExtendedThinkingLevels[requestedIndex...] where availableLevels.contains(candidate) {
                return candidate
            }

            for candidate in piExtendedThinkingLevels[..<requestedIndex].reversed()
            where availableLevels.contains(candidate) {
                return candidate
            }

            return availableLevels.first ?? "off"
        }

        private func availableThinkingLevels(for model: PiRPCModelDescriptor?) -> [String] {
            model?.availableThinkingLevels ?? piBasicThinkingLevels
        }

        private func thinkingSlashCommandsLocked() -> [SessionSlashCommand]? {
            guard currentModel != nil || currentThinkingLevel != nil else {
                return nil
            }

            var levels = availableThinkingLevels(for: currentModel)
            if let currentThinkingLevel, levels.contains(currentThinkingLevel) == false {
                levels.append(currentThinkingLevel)
                levels.sort {
                    (piExtendedThinkingLevels.firstIndex(of: $0) ?? piExtendedThinkingLevels.count)
                        < (piExtendedThinkingLevels.firstIndex(of: $1) ?? piExtendedThinkingLevels.count)
                }
            }

            return levels.map { level in
                let isCurrent = level == currentThinkingLevel
                return SessionSlashCommand(
                    name: "thinking \(level)",
                    displayName: "thinking \(level)",
                    insertionText: "thinking \(level)",
                    suggestionQueryPrefix: "thinking ",
                    description: isCurrent ? "Current thinking level." : "Set the thinking level to \(level).",
                    source: .builtIn
                )
            }
        }

        private func queueUpdateStatusText(steering: [String], followUp: [String]) -> String {
            var segments: [String] = []
            if steering.isEmpty == false {
                segments.append("steering: \(steering.map { previewText($0, limit: 80) }.joined(separator: " · "))")
            }
            if followUp.isEmpty == false {
                segments.append("follow-up: \(followUp.map { previewText($0, limit: 80) }.joined(separator: " · "))")
            }
            if segments.isEmpty {
                return "Queue cleared"
            }
            return "Queue updated — \(segments.joined(separator: "; "))"
        }

        private func compactionAndRetrySlashCommandsLocked() -> [SessionSlashCommand] {
            [
                SessionSlashCommand(
                    name: "cycle-model",
                    displayName: "cycle-model",
                    insertionText: "cycle-model",
                    description: "Cycle to the next available model.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "cycle-thinking-level",
                    displayName: "cycle-thinking-level",
                    insertionText: "cycle-thinking-level",
                    description: "Cycle to the next available thinking level.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "compact",
                    displayName: "compact [instructions]",
                    insertionText: "compact ",
                    suggestionQueryPrefix: "compact ",
                    description: "Compact the current session context, optionally with custom instructions.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "auto-compaction on",
                    displayName: "auto-compaction on",
                    insertionText: "auto-compaction on",
                    suggestionQueryPrefix: "auto-compaction ",
                    description: "Enable auto-compaction.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "auto-compaction off",
                    displayName: "auto-compaction off",
                    insertionText: "auto-compaction off",
                    suggestionQueryPrefix: "auto-compaction ",
                    description: "Disable auto-compaction.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "auto-retry on",
                    displayName: "auto-retry on",
                    insertionText: "auto-retry on",
                    suggestionQueryPrefix: "auto-retry ",
                    description: "Enable auto-retry for transient failures.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "auto-retry off",
                    displayName: "auto-retry off",
                    insertionText: "auto-retry off",
                    suggestionQueryPrefix: "auto-retry ",
                    description: "Disable auto-retry for transient failures.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "abort-retry",
                    displayName: "abort-retry",
                    insertionText: "abort-retry",
                    description: "Abort the current retry delay.",
                    source: .builtIn
                ),
            ]
        }

        private func queueControlSlashCommandsLocked() -> [SessionSlashCommand] {
            let steeringModes = ["all", "one-at-a-time"].map { mode in
                SessionSlashCommand(
                    name: "steering-mode \(mode)",
                    displayName: "steering-mode \(mode)",
                    insertionText: "steering-mode \(mode)",
                    suggestionQueryPrefix: "steering-mode ",
                    description: mode == steeringMode ? "Current steering mode." : "Set the steering mode to \(mode).",
                    source: .builtIn
                )
            }
            let followUpModes = ["all", "one-at-a-time"].map { mode in
                SessionSlashCommand(
                    name: "follow-up-mode \(mode)",
                    displayName: "follow-up-mode \(mode)",
                    insertionText: "follow-up-mode \(mode)",
                    suggestionQueryPrefix: "follow-up-mode ",
                    description: mode == followUpMode
                        ? "Current follow-up mode." : "Set the follow-up mode to \(mode).",
                    source: .builtIn
                )
            }
            return [
                SessionSlashCommand(
                    name: "steer",
                    displayName: "steer <message>",
                    insertionText: "steer ",
                    suggestionQueryPrefix: "steer ",
                    description: "Queue a steering message while the agent is running.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "follow-up",
                    displayName: "follow-up <message>",
                    insertionText: "follow-up ",
                    suggestionQueryPrefix: "follow-up ",
                    description: "Queue a follow-up message for after the agent finishes.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "abort",
                    displayName: "abort",
                    insertionText: "abort",
                    description: "Abort the current run.",
                    source: .builtIn
                ),
            ] + steeringModes + followUpModes
        }

        private func sessionGraphSlashCommandsLocked() -> [SessionSlashCommand] {
            [
                SessionSlashCommand(
                    name: "fork",
                    displayName: "fork <entry-id>",
                    insertionText: "fork ",
                    suggestionQueryPrefix: "fork ",
                    description: "Fork from a previous message into a new Named Session.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "clone",
                    displayName: "clone",
                    insertionText: "clone",
                    description: "Clone the current session into a new Named Session.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "fork-messages",
                    displayName: "fork-messages",
                    insertionText: "fork-messages",
                    description: "List messages available for forking.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "session-name",
                    displayName: "session-name <name>",
                    insertionText: "session-name ",
                    suggestionQueryPrefix: "session-name ",
                    description: "Set the current session name and sync it into Nexus.",
                    source: .builtIn
                ),
            ]
        }

        private func rpcUtilitySlashCommandsLocked() -> [SessionSlashCommand] {
            [
                SessionSlashCommand(
                    name: "bash",
                    displayName: "bash <command>",
                    insertionText: "bash ",
                    suggestionQueryPrefix: "bash ",
                    description: "Run host-side bash and include the result on the next prompt.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "abort-bash",
                    displayName: "abort-bash",
                    insertionText: "abort-bash",
                    description: "Cancel the currently running bash command.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "export-html",
                    displayName: "export-html [path]",
                    insertionText: "export-html ",
                    suggestionQueryPrefix: "export-html ",
                    description: "Export the current session to an HTML file.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "messages",
                    displayName: "messages",
                    insertionText: "messages",
                    description: "List messages in the current session.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "session-stats",
                    displayName: "session-stats",
                    insertionText: "session-stats",
                    description: "Show token, tool, and context usage stats.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "last-assistant-text",
                    displayName: "last-assistant-text",
                    insertionText: "last-assistant-text",
                    description: "Show the last assistant text from the current session.",
                    source: .builtIn
                ),
            ]
        }

        private func handleSessionTransitionEvent(_ object: [String: Any]) {
            guard let linkage = sessionTransitionLinkage(from: object),
                let metadata = linkage.sessionRecordAdapterMetadata
            else {
                notifyChange()
                return
            }

            lock.lock()
            sessionLinkage = linkage
            lock.unlock()
            appendPendingSessionTransitionIfNeeded(metadata)
            notifyChange()
        }

        private func sessionTransitionLinkage(from object: [String: Any]) -> PiSessionLinkage? {
            let candidates: [[String: Any]] = [
                object,
                object["data"] as? [String: Any],
                object["session"] as? [String: Any],
            ].compactMap { $0 }

            for candidate in candidates {
                let linkage = PiSessionLinkage(
                    piSessionID: string(for: "sessionId", in: candidate) ?? string(for: "session_id", in: candidate),
                    sessionFile: string(for: "sessionFile", in: candidate) ?? string(for: "session_file", in: candidate)
                )
                if linkage.isEmpty == false {
                    return linkage
                }
            }

            return nil
        }

        private func mergedSlashCommandsLocked() -> [SessionSlashCommand]? {
            let merged = mergeSlashCommands(groups: [
                providerSlashCommands,
                availableModelCommands,
                thinkingSlashCommandsLocked(),
                compactionAndRetrySlashCommandsLocked(),
                queueControlSlashCommandsLocked(),
                sessionGraphSlashCommandsLocked(),
                rpcUtilitySlashCommandsLocked(),
            ])
            return merged.isEmpty ? nil : merged
        }

        private func mergeSlashCommands(groups: [[SessionSlashCommand]?]) -> [SessionSlashCommand] {
            var merged: [SessionSlashCommand] = []
            var seenNames: Set<String> = []

            for group in groups {
                for command in group ?? [] where seenNames.insert(command.name).inserted {
                    merged.append(command)
                }
            }

            return merged
        }

        private func updateSessionLinkageLocked(from response: [String: Any]) {
            guard let data = response["data"] as? [String: Any] else {
                return
            }

            let linkage = PiSessionLinkage(
                piSessionID: string(for: "sessionId", in: data),
                sessionFile: string(for: "sessionFile", in: data)
            )
            guard linkage.isEmpty == false else {
                return
            }

            sessionLinkage = linkage
        }

        private func updateCurrentStateLocked(from response: [String: Any]) {
            guard let data = response["data"] as? [String: Any] else {
                return
            }

            if let model = data["model"] as? [String: Any] {
                currentModel = parseModelDescriptor(from: model)
            } else {
                currentModel = nil
            }
            currentThinkingLevel = trimmedString(for: "thinkingLevel", in: data)
            currentSessionName = trimmedString(for: "sessionName", in: data)
            steeringMode = trimmedString(for: "steeringMode", in: data) ?? steeringMode
            followUpMode = trimmedString(for: "followUpMode", in: data) ?? followUpMode
        }

        private func currentModelStatusTextLocked() -> String? {
            guard let currentModel else {
                return nil
            }

            let target = formattedModelTarget(for: currentModel)
            if let currentThinkingLevel {
                return "\(currentModelStatusPrefix) \(target) (thinking: \(currentThinkingLevel))"
            }
            return "\(currentModelStatusPrefix) \(target)"
        }

        private func formattedModelTarget(for model: PiRPCModelDescriptor) -> String {
            let target = "\(model.provider)/\(model.id)"
            if let name = model.name {
                return "\(target) — \(name)"
            }
            return target
        }

        private func assistantThinkingText(from event: [String: Any]) -> String {
            if let content = trimmedString(for: "content", in: event) {
                return content
            }

            guard let partial = event["partial"] as? [String: Any],
                let content = partial["content"] as? [[String: Any]]
            else {
                return ""
            }

            return
                content
                .compactMap { block -> String? in
                    guard string(for: "type", in: block) == "thinking" else {
                        return nil
                    }
                    return trimmedString(for: "thinking", in: block)
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func toolExecutionCallText(toolName: String, args: [String: Any]?) -> String {
            let normalizedToolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedToolName.caseInsensitiveCompare("subagent") == .orderedSame {
                let agent = args.flatMap { string(for: "agent", in: $0) }?.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let task = args.flatMap { string(for: "task", in: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
                let taskPreview = task.map { previewText($0, limit: 80) }
                if let agent, agent.isEmpty == false, let taskPreview, taskPreview.isEmpty == false {
                    return "subagent \(agent): \(taskPreview)"
                }
                if let agent, agent.isEmpty == false {
                    return "subagent \(agent)"
                }
            }

            if normalizedToolName.caseInsensitiveCompare("read") == .orderedSame,
                let path = args.flatMap({ string(for: "path", in: $0) })?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                path.isEmpty == false
            {
                let offset = args.flatMap { intValue($0["offset"]) }
                let limit = args.flatMap { intValue($0["limit"]) }
                switch (offset, limit) {
                case (let offset?, let limit?) where limit > 0:
                    return "read \(path):\(offset)-\(offset + limit - 1)"
                case (let offset?, _):
                    return "read \(path) from line \(offset)"
                default:
                    return "read \(path)"
                }
            }

            if normalizedToolName.caseInsensitiveCompare("edit") == .orderedSame,
                let path = args.flatMap({ string(for: "path", in: $0) })?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                path.isEmpty == false
            {
                let editCount = (args?["edits"] as? [Any])?.count ?? 0
                return editCount > 0 ? "edit \(path) (\(editCount) change\(editCount == 1 ? "" : "s"))" : "edit \(path)"
            }

            if normalizedToolName.caseInsensitiveCompare("write") == .orderedSame,
                let path = args.flatMap({ string(for: "path", in: $0) })?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                path.isEmpty == false
            {
                return "write \(path)"
            }

            if normalizedToolName.caseInsensitiveCompare("bash") == .orderedSame,
                let command = args.flatMap({ string(for: "command", in: $0) })?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                command.isEmpty == false
            {
                return "bash \(previewText(command, limit: 100))"
            }

            if let command = args.flatMap({ string(for: "command", in: $0) })?.trimmingCharacters(
                in: .whitespacesAndNewlines),
                command.isEmpty == false
            {
                return command
            }

            if let task = args.flatMap({ string(for: "task", in: $0) })?.trimmingCharacters(
                in: .whitespacesAndNewlines),
                task.isEmpty == false
            {
                return "\(normalizedToolName): \(previewText(task, limit: 80))"
            }

            return normalizedToolName.isEmpty ? "Tool" : normalizedToolName
        }

        private func toolExecutionResultText(_ object: [String: Any]?) -> String {
            PiToolExecutionResultText.extract(from: object)
        }

        private func toolExecutionResultText(from value: Any?) -> String {
            PiToolExecutionResultText.extract(from: value)
        }

        private func incrementalToolOutput(from previousText: String, to nextText: String) -> String {
            let trimmedNextText = nextText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedNextText.isEmpty == false else {
                return ""
            }

            let trimmedPreviousText = previousText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPreviousText.isEmpty {
                return trimmedNextText
            }

            if trimmedNextText.hasPrefix(trimmedPreviousText) {
                return String(trimmedNextText.dropFirst(trimmedPreviousText.count)).trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }

            return trimmedNextText == trimmedPreviousText ? "" : trimmedNextText
        }

        private func sessionStatsSummaryText(_ data: [String: Any]) -> String {
            let userMessages = intValue(data["userMessages"]) ?? 0
            let assistantMessages = intValue(data["assistantMessages"]) ?? 0
            let toolCalls = intValue(data["toolCalls"]) ?? 0
            let toolResults = intValue(data["toolResults"]) ?? 0
            let totalMessages = intValue(data["totalMessages"]) ?? 0
            let cost = doubleValue(data["cost"]) ?? 0
            return String(
                format:
                    "Session stats — user: %d · assistant: %d · tool calls: %d · tool results: %d · total: %d · cost: $%.2f",
                userMessages,
                assistantMessages,
                toolCalls,
                toolResults,
                totalMessages,
                cost
            )
        }

        private func sessionContextUsageText(_ data: [String: Any]) -> String? {
            guard let contextUsage = data["contextUsage"] as? [String: Any],
                let contextWindow = intValue(contextUsage["contextWindow"])
            else {
                return nil
            }
            let tokens = intValue(contextUsage["tokens"])
            let percent = intValue(contextUsage["percent"])
            return
                "Context usage — \(tokens.map(String.init) ?? "unknown") / \(contextWindow) tokens (\(percent.map { "\($0)%" } ?? "unknown"))"
        }

        private func previewText(_ text: String, limit: Int) -> String {
            guard text.count > limit else {
                return text
            }
            return String(text.prefix(limit)) + "…"
        }

        private func extensionUIStateLocked() -> SessionExtensionUIState? {
            let state = SessionExtensionUIState(
                title: extensionTitle,
                pendingDialogs: pendingExtensionDialogs,
                notifications: extensionNotifications,
                statuses: extensionStatuses,
                widgets: extensionWidgets,
                editorText: extensionEditorText
            )
            let hasContent =
                state.title != nil
                || state.pendingDialogs.isEmpty == false
                || state.notifications.isEmpty == false
                || state.statuses.isEmpty == false
                || state.widgets.isEmpty == false
                || state.editorText != nil
            return hasContent ? state : nil
        }

        private func upsertExtensionDialogLocked(_ dialog: SessionExtensionUIDialog) {
            pendingExtensionDialogs.removeAll { $0.id == dialog.id }
            pendingExtensionDialogs.append(dialog)
        }

        private func upsertExtensionStatusLocked(_ status: SessionExtensionUIStatus) {
            extensionStatuses.removeAll { $0.key == status.key }
            let plainText = TerminalEscapeSequences.stripForPlainDisplay(status.text)
            extensionStatuses.append(SessionExtensionUIStatus(key: status.key, text: plainText))
        }

        private func upsertExtensionWidgetLocked(_ widget: SessionExtensionUIWidget) {
            extensionWidgets.removeAll { $0.key == widget.key }
            extensionWidgets.append(widget)
        }

        private func recordFinalOutputDiagnosticLocked(
            trigger: StructuredSessionFinalOutputTrigger,
            activityItem: SessionActivityItem,
            providerRuntimeLatencyMilliseconds: Int,
            expectedThinkingIndicatorVisible: Bool
        ) {
            guard let providerEventSequence = providerEvents.last?.sequence else {
                return
            }

            finalOutputDiagnostic = StructuredSessionFinalOutputDiagnostic(
                trigger: trigger,
                providerEventSequence: providerEventSequence,
                providerRuntimeLatencyMilliseconds: providerRuntimeLatencyMilliseconds,
                expectedActivityItemID: activityItem.id,
                expectedActivityItemText: activityItem.text,
                expectedThinkingIndicatorVisible: expectedThinkingIndicatorVisible,
                serviceObservationAnchorUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        }

        private func appendActivityItemLocked(_ item: SessionActivityItem) {
            let trimmedText = TerminalEscapeSequences.stripForPlainDisplay(
                item.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard trimmedText.isEmpty == false else {
                return
            }

            let trimmedDetailText = item.detailText.map {
                TerminalEscapeSequences.stripForPlainDisplay($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            activityItems.append(
                SessionActivityItem(
                    id: item.id,
                    kind: item.kind,
                    text: trimmedText,
                    detailText: trimmedDetailText?.isEmpty == false ? trimmedDetailText : nil,
                    prompt: item.prompt
                )
            )
            if activityItems.count > StructuredSessionLiveHistoryRetention.maxRetainedActivityItems {
                let removedCount = activityItems.count - StructuredSessionLiveHistoryRetention.maxRetainedActivityItems
                persistedActivityItemOverflow.append(contentsOf: activityItems.prefix(removedCount))
                activityItems.removeFirst(removedCount)
            }
        }

        private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
            let now = DispatchTime.now().uptimeNanoseconds
            return Int((now >= startedAt ? now - startedAt : 0) / 1_000_000)
        }

        private func setActivityItemDetailTextLocked(id: UUID, detailText: String) {
            guard let index = activityItems.firstIndex(where: { $0.id == id }) else {
                return
            }

            let trimmedDetailText = TerminalEscapeSequences.stripForPlainDisplay(
                detailText.trimmingCharacters(in: .whitespacesAndNewlines))
            let updatedItem = SessionActivityItem(
                id: activityItems[index].id,
                kind: activityItems[index].kind,
                text: activityItems[index].text,
                detailText: trimmedDetailText.isEmpty ? nil : trimmedDetailText,
                prompt: activityItems[index].prompt
            )
            activityItems[index] = updatedItem
            if let overflowIndex = persistedActivityItemOverflow.firstIndex(where: { $0.id == id }) {
                persistedActivityItemOverflow[overflowIndex] = updatedItem
            }
        }

        /// Returns the ID of the most recent .command activity item that has no (or empty) detailText yet.
        /// Used to bridge `toolcall_end` (planning phase, which creates the visible tool row in the feed)
        /// to later `tool_execution_*` events (which may use a different toolCallId or arrive after
        /// the planning map was not consulted). This ensures tool output appears inside the accordion
        /// the user actually sees and expands.
        private func mostRecentUnfilledCommandItemIDLocked(matchingToolName toolName: String? = nil) -> UUID? {
            for item in activityItems.reversed() {
                guard item.kind == .command else { continue }
                let hasDetail = item.detailText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                if hasDetail { continue }
                return item.id
            }
            return nil
        }

        private func assistantText(from message: [String: Any]?) -> String {
            guard let message,
                let content = message["content"] as? [[String: Any]]
            else {
                return ""
            }

            return
                content
                .compactMap { block -> String? in
                    guard string(for: "type", in: block) == "text" else {
                        return nil
                    }
                    return string(for: "text", in: block)
                }
                .joined()
        }

        /// Pi `turn_end` / `message_end` payloads are sometimes shorter than streamed `text_delta` text.
        /// Prefer the longest non-empty body so the structured feed activity row matches what the user saw stream.
        private func resolvedPiAssistantFinalText(from message: [String: Any]?) -> String {
            let fromMessage = assistantText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
            var candidates = [
                fromMessage,
                liveStreamedAssistantText.trimmingCharacters(in: .whitespacesAndNewlines),
                currentAssistantText.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            if let assistantTranscriptIndex,
                transcriptEntries.indices.contains(assistantTranscriptIndex)
            {
                candidates.append(
                    transcriptEntries[assistantTranscriptIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return candidates.max(by: { $0.count < $1.count }) ?? ""
        }

        private func sessionMessageSummary(_ message: [String: Any], index: Int) -> String {
            let role = trimmedString(for: "role", in: message) ?? "message"
            let preview: String

            switch role {
            case "user":
                preview = sessionMessageContentText(message["content"])
            case "assistant", "toolResult":
                preview = assistantText(from: message)
            case "bashExecution":
                preview = trimmedString(for: "command", in: message) ?? sessionMessageContentText(message["output"])
            default:
                preview = sessionMessageContentText(message["content"])
            }

            let resolvedPreview = preview.isEmpty ? "(no text)" : previewText(preview, limit: 120)
            return "Message \(index) — \(role): \(resolvedPreview)"
        }

        private func sessionMessageContentText(_ value: Any?) -> String {
            switch value {
            case let string as String:
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            case let blocks as [[String: Any]]:
                return
                    blocks
                    .compactMap { block -> String? in
                        guard string(for: "type", in: block) == "text" else {
                            return nil
                        }
                        return string(for: "text", in: block)
                    }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                return ""
            }
        }

        private func responseObject(from line: String) -> [String: Any]? {
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }
            return object
        }

        private func string(for key: String, in object: [String: Any]) -> String? {
            object[key] as? String
        }

        private func trimmedString(for key: String, in object: [String: Any]) -> String? {
            guard let value = string(for: key, in: object)?.trimmingCharacters(in: .whitespacesAndNewlines),
                value.isEmpty == false
            else {
                return nil
            }
            return value
        }

        private func bool(for key: String, in object: [String: Any]) -> Bool? {
            object[key] as? Bool
        }

        private func int(for key: String, in object: [String: Any]) -> Int? {
            object[key] as? Int
        }

        private func intValue(_ value: Any?) -> Int? {
            switch value {
            case let int as Int:
                return int
            case let number as NSNumber:
                return number.intValue
            default:
                return nil
            }
        }

        private func doubleValue(_ value: Any?) -> Double? {
            switch value {
            case let double as Double:
                return double
            case let int as Int:
                return Double(int)
            case let number as NSNumber:
                return number.doubleValue
            default:
                return nil
            }
        }

        private func notifyChange() {
            let handler: (@Sendable () -> Void)?
            lock.lock()
            handler = changeHandler
            lock.unlock()
            handler?()
        }

        private func notifyChangeThrottledForAssistantTextDelta() {
            let shouldNotifyImmediately: Bool
            let flushGeneration: UInt64?
            lock.lock()
            shouldNotifyImmediately = streamingObservationThrottle.shouldNotifyImmediatelyForStreamingDelta()
            flushGeneration =
                shouldNotifyImmediately
                ? nil
                : streamingObservationThrottle.beginScheduledFlushIfNeeded()
            lock.unlock()

            if shouldNotifyImmediately {
                notifyChange()
                return
            }

            guard let flushGeneration else {
                return
            }

            let interval = 0.4
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self else {
                    return
                }
                let shouldFlush = self.streamingObservationThrottle.consumePendingNotify(
                    forScheduledFlushGeneration: flushGeneration
                )
                if shouldFlush {
                    self.notifyChange()
                }
            }
        }

        static func transportArguments(sessionLinkage: PiSessionLinkage?) -> [String] {
            var arguments = ["--mode", "rpc"]

            if let sessionFile = sessionLinkage?.sessionFile?.trimmingCharacters(in: .whitespacesAndNewlines),
                sessionFile.isEmpty == false
            {
                arguments += ["--session", sessionFile]
            } else if let piSessionID = sessionLinkage?.piSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                piSessionID.isEmpty == false
            {
                arguments += ["--session", piSessionID]
            }

            return arguments
        }

        private static func jsonLine(_ object: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let line = String(data: data, encoding: .utf8) else {
                throw PiRPCSessionRuntimeError.startupFailed("Failed to encode Pi RPC command.")
            }
            return line
        }
    }

    private final class StartupState: @unchecked Sendable {
        private let lock = NSLock()
        private var resolvedError: Error?

        var error: Error? {
            lock.lock()
            defer { lock.unlock() }
            return resolvedError
        }

        func record(error: Error) {
            lock.lock()
            if resolvedError == nil {
                resolvedError = error
            }
            lock.unlock()
        }
    }

    final class ProcessPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private struct ProcessInvocation {
            let executable: String
            let arguments: [String]
        }

        private let executable: String
        private let arguments: [String]
        private let workingDirectory: String?
        private let environment: [String: String]?
        private let nexusSessionID: UUID?
        private let lock = NSLock()
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private var process: Process?
        private var stdinHandle: FileHandle?
        private var stdoutHandle: FileHandle?
        private var stderrHandle: FileHandle?
        private var stdoutBuffer = Data()

        init(
            executable: String,
            arguments: [String],
            workingDirectory: String?,
            environment: [String: String]? = nil,
            nexusSessionID: UUID? = nil
        ) throws {
            self.executable = executable
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.environment = environment
            self.nexusSessionID = nexusSessionID
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            lock.lock()
            stdoutLineHandler = handler
            lock.unlock()
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            lock.lock()
            terminationHandler = handler
            lock.unlock()
        }

        func start() throws {
            let invocation = resolvedInvocation()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: invocation.executable)
            process.arguments = invocation.arguments
            if let environment {
                process.environment = environment
            }
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            }

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { [weak self] process in
                self?.handleTermination(process.terminationStatus)
            }

            try process.run()

            if let nexusSessionID {
                NexusSessionRuntimeDiagnostics.logPiProcessStarted(
                    sessionID: nexusSessionID,
                    childPID: process.processIdentifier,
                    executable: invocation.executable,
                    arguments: invocation.arguments
                )
            }

            let stdoutHandle = stdoutPipe.fileHandleForReading
            stdoutHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard data.isEmpty == false else {
                    handle.readabilityHandler = nil
                    return
                }
                self?.consumeStdout(data)
            }

            let stderrHandle = stderrPipe.fileHandleForReading
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                }
            }

            lock.lock()
            self.process = process
            self.stdinHandle = stdinPipe.fileHandleForWriting
            self.stdoutHandle = stdoutHandle
            self.stderrHandle = stderrHandle
            lock.unlock()
        }

        func sendLine(_ line: String) throws {
            Self.appendWireRecord(stream: "stdin", line: line, nexusSessionID: nexusSessionID)
            guard let data = (line + "\n").data(using: .utf8) else {
                throw PiRPCSessionRuntimeError.startupFailed("Failed to encode Pi RPC input.")
            }

            let handle: FileHandle?
            lock.lock()
            handle = stdinHandle
            lock.unlock()
            handle?.write(data)
        }

        func terminate() throws {
            let process: Process?
            let stdoutHandle: FileHandle?
            let stderrHandle: FileHandle?
            lock.lock()
            process = self.process
            stdoutHandle = self.stdoutHandle
            stderrHandle = self.stderrHandle
            lock.unlock()

            stdoutHandle?.readabilityHandler = nil
            stderrHandle?.readabilityHandler = nil
            if process?.isRunning == true {
                process?.terminate()
            }
        }

        private func resolvedInvocation() -> ProcessInvocation {
            guard let shebang = scriptShebang(),
                let envInvocation = envInterpreterInvocation(for: shebang)
            else {
                return ProcessInvocation(executable: executable, arguments: arguments)
            }

            return envInvocation
        }

        private func scriptShebang() -> String? {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: executable), options: .mappedIfSafe),
                let newlineIndex = data.firstIndex(of: 0x0A)
            else {
                return nil
            }

            let lineData = data.prefix(upTo: newlineIndex)
            return String(data: lineData, encoding: .utf8)?.replacingOccurrences(of: "\r", with: "")
        }

        private func envInterpreterInvocation(for shebang: String) -> ProcessInvocation? {
            guard shebang.hasPrefix("#!/usr/bin/env ") else {
                return nil
            }

            var shebangArguments =
                shebang
                .dropFirst("#!/usr/bin/env ".count)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            guard shebangArguments.isEmpty == false else {
                return nil
            }

            if shebangArguments.first == "-S" {
                shebangArguments.removeFirst()
            }

            guard let interpreterName = shebangArguments.first,
                let interpreterExecutable = resolvedInterpreter(named: interpreterName)
            else {
                return nil
            }

            let interpreterArguments = Array(shebangArguments.dropFirst())
            return ProcessInvocation(
                executable: interpreterExecutable,
                arguments: interpreterArguments + [executable] + arguments
            )
        }

        private func resolvedInterpreter(named interpreterName: String) -> String? {
            let siblingExecutable = URL(fileURLWithPath: executable)
                .deletingLastPathComponent()
                .appendingPathComponent(interpreterName, isDirectory: false)
                .path
            if FileManager.default.isExecutableFile(atPath: siblingExecutable) {
                return siblingExecutable
            }

            return SystemProviderExecutableResolver(environment: environment ?? ProcessInfo.processInfo.environment)
                .resolveExecutable(named: interpreterName)
                .resolvedExecutable
        }

        private func consumeStdout(_ data: Data) {
            var lines: [String] = []
            let handler: (@Sendable (String) -> Void)?

            lock.lock()
            stdoutBuffer.append(data)
            while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let lineData = stdoutBuffer.prefix(upTo: newlineIndex)
                stdoutBuffer.removeSubrange(...newlineIndex)
                if let line = String(data: lineData, encoding: .utf8)?.replacingOccurrences(of: "\r", with: "") {
                    lines.append(line)
                }
            }
            handler = stdoutLineHandler
            lock.unlock()

            for line in lines where line.isEmpty == false {
                Self.appendWireRecord(stream: "stdout", line: line, nexusSessionID: nexusSessionID)
                handler?(line)
            }
        }

        private static func appendWireRecord(stream: String, line: String, nexusSessionID: UUID?) {
            guard
                let base = ProcessInfo.processInfo.environment["NEXUS_PI_RPC_RECORD_DIR"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                base.isEmpty == false
            else {
                return
            }
            let sessionToken = nexusSessionID?.uuidString ?? "unknown"
            let directory = URL(fileURLWithPath: base, isDirectory: true)
                .appendingPathComponent(sessionToken, isDirectory: true)
            let fileURL = directory.appendingPathComponent("\(stream).jsonl")
            let payload: [String: Any] = [
                "t": ProcessInfo.processInfo.systemUptime,
                "line": line,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                let record = String(data: data, encoding: .utf8)
            else {
                return
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                if FileManager.default.createFile(atPath: fileURL.path, contents: nil) == false {
                    return
                }
                guard let newHandle = try? FileHandle(forWritingTo: fileURL) else {
                    return
                }
                defer { try? newHandle.close() }
                newHandle.seekToEndOfFile()
                newHandle.write(Data((record + "\n").utf8))
                return
            }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data((record + "\n").utf8))
        }

        private func handleTermination(_ status: Int32) {
            let handler: (@Sendable (Int32) -> Void)?
            let childPID: Int32?
            let sessionID: UUID?
            lock.lock()
            stdoutHandle?.readabilityHandler = nil
            stderrHandle?.readabilityHandler = nil
            handler = terminationHandler
            childPID = process?.processIdentifier
            sessionID = nexusSessionID
            lock.unlock()
            NexusSessionRuntimeDiagnostics.logPiProcessTerminated(
                sessionID: sessionID,
                childPID: childPID,
                exitStatus: status
            )
            handler?(status)
        }
    }
#endif
