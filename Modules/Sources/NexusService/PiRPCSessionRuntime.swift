#if os(macOS)
import Foundation
import NexusDomain

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
        case let .startupFailed(message):
            return message
        case .busy:
            return "Pi is already handling a prompt. Wait for the current turn to finish before sending another one."
        case .approvalRequestNotFound:
            return "Approval Request was not found for this Session."
        case .extensionDialogNotFound:
            return "Extension UI dialog was not found for this Session."
        }
    }
}

final class PiRPCSessionRuntime: SessionRuntime, @unchecked Sendable {
    typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any PiRPCTransporting

    var state: Session.State {
        lock.lock()
        defer { lock.unlock() }
        return runtimeState
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return sessionLinkage?.sessionRecordAdapterMetadata
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
    private let currentModelStatusPrefix = "Current Pi model:"
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
    private var approvalRequests: [SessionApprovalRequest] = []
    private var pendingExtensionDialogs: [SessionExtensionUIDialog] = []
    private var extensionNotifications: [SessionExtensionUINotification] = []
    private var extensionStatuses: [SessionExtensionUIStatus] = []
    private var extensionWidgets: [SessionExtensionUIWidget] = []
    private var extensionTitle: String?
    private var extensionEditorText: String?
    private var providerEvents: [SessionProviderEvent] = []
    private var nextProviderEventSequence = 0
    private var providerSlashCommands: [SessionSlashCommand]?
    private var availableModelCommands: [SessionSlashCommand]?
    private var terminalColumns = 80
    private var terminalRows = 24
    private var sessionLinkage: PiSessionLinkage?
    private var pendingSessionTransitions: [SessionRuntimeSessionTransition] = []
    private var changeHandler: (@Sendable () -> Void)?
    private var isStreaming = false
    private var assistantTranscriptIndex: Int?
    private var currentAssistantText = ""
    private var toolOutputByCallID: [String: String] = [:]
    private var toolNamesByCallID: [String: String] = [:]
    private var didRequestStop = false
    private var pendingSlashCommandsRequestID: String?
    private var pendingAvailableModelsRequestID: String?
    private var pendingSetModelTargetsByRequestID: [String: String] = [:]
    private var pendingSetThinkingLevelsByRequestID: [String: String] = [:]
    private var pendingSetSteeringModesByRequestID: [String: String] = [:]
    private var pendingSetFollowUpModesByRequestID: [String: String] = [:]
    private var pendingSetSessionNamesByRequestID: [String: String] = [:]
    private var pendingSessionTransitionStateRequestIDs: Set<String> = []
    private var nextSlashCommandsRequestSequence = 0
    private var nextAvailableModelsRequestSequence = 0
    private var nextSetThinkingRequestSequence = 0
    private var nextSetSteeringModeRequestSequence = 0
    private var nextSetFollowUpModeRequestSequence = 0

    convenience init(
        executable: String,
        workingDirectory: String,
        sessionLinkage: PiSessionLinkage? = nil,
        terminationStatusMessageBuilder: @escaping (Int32) -> String,
        unexpectedTerminationState: Session.State = .exited,
        unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
        stopHandler: (() throws -> Void)? = nil,
        transportFactory: TransportFactory = { executable, arguments, workingDirectory in
            try ProcessPiRPCTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }
    ) throws {
        try self.init(
            executable: executable,
            workingDirectory: workingDirectory,
            sessionLinkage: sessionLinkage,
            terminationStatusMessageBuilder: terminationStatusMessageBuilder,
            unexpectedTerminationState: unexpectedTerminationState,
            unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder,
            stopHandler: stopHandler,
            transportFactory: transportFactory,
            performStartup: false
        )
        try AsyncOperationSupport.blocking { try await self.completeStartup() }
    }

    convenience init(
        executable: String,
        workingDirectory: String,
        sessionLinkage: PiSessionLinkage? = nil,
        terminationStatusMessageBuilder: @escaping (Int32) -> String,
        unexpectedTerminationState: Session.State = .exited,
        unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
        stopHandler: (() throws -> Void)? = nil,
        transportFactory: TransportFactory = { executable, arguments, workingDirectory in
            try ProcessPiRPCTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }
    ) async throws {
        try self.init(
            executable: executable,
            workingDirectory: workingDirectory,
            sessionLinkage: sessionLinkage,
            terminationStatusMessageBuilder: terminationStatusMessageBuilder,
            unexpectedTerminationState: unexpectedTerminationState,
            unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder,
            stopHandler: stopHandler,
            transportFactory: transportFactory,
            performStartup: false
        )
        try await self.completeStartup()
    }

    private init(
        executable: String,
        workingDirectory: String,
        sessionLinkage: PiSessionLinkage?,
        terminationStatusMessageBuilder: @escaping (Int32) -> String,
        unexpectedTerminationState: Session.State,
        unexpectedTerminationMessageBuilder: ((Int32) -> String)?,
        stopHandler: (() throws -> Void)?,
        transportFactory: TransportFactory,
        performStartup: Bool
    ) throws {
        self.stopHandler = stopHandler
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
        self.unexpectedTerminationState = unexpectedTerminationState
        self.unexpectedTerminationMessageBuilder = unexpectedTerminationMessageBuilder ?? terminationStatusMessageBuilder
        self.sessionLinkage = sessionLinkage
        self.transport = try transportFactory(executable, Self.transportArguments(sessionLinkage: sessionLinkage), workingDirectory)
    }

    private func completeStartup() async throws {
        let startupState = StartupState()
        let startupWaiter = AsyncResultWaiter<Void>()

        transport.setStdoutLineHandler { [weak self] line in
            guard let self,
                  let object = self.responseObject(from: line),
                  let type = self.string(for: "type", in: object) else {
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
                let startupError = PiRPCSessionRuntimeError.startupFailed("Pi RPC mode exited before startup completed.")
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
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        defer { lock.unlock() }
        let currentSession = currentSessionName.map {
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
            transcript: runtimeState == .interrupted ? (interruptedFailureMessage ?? renderedTranscriptLocked()) : renderedTranscriptLocked(),
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: extensionUIStateLocked(),
            slashCommands: mergedSlashCommandsLocked(),
            providerEvents: providerEvents,
            isAgentTurnInProgress: isStreaming
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
        try submitPrompt(text)
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
            try submitPrompt(prompt)
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
        guard let index = approvalRequests.firstIndex(where: { $0.id == approvalRequestID && $0.state == .pending }) else {
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
                "decision": decision.rawValue
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
            "id": dialogID
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

    private func submitPrompt(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
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

        if trimmed == "/thinking" || trimmed.hasPrefix("/thinking ") {
            try submitThinkingCommand(trimmed)
            return
        }

        if trimmed == "/abort" {
            try submitAbortCommand()
            return
        }

        if trimmed == "/steering-mode" || trimmed.hasPrefix("/steering-mode ") || trimmed == "/steering_mode" || trimmed.hasPrefix("/steering_mode ") {
            try submitSteeringModeCommand(trimmed)
            return
        }

        if trimmed == "/follow-up-mode" || trimmed.hasPrefix("/follow-up-mode ") || trimmed == "/follow_up_mode" || trimmed.hasPrefix("/follow_up_mode ") {
            try submitFollowUpModeCommand(trimmed)
            return
        }

        if trimmed == "/steer" || trimmed.hasPrefix("/steer ") {
            try submitSteeringCommand(trimmed)
            return
        }

        if trimmed == "/follow-up" || trimmed.hasPrefix("/follow-up ") || trimmed == "/follow_up" || trimmed.hasPrefix("/follow_up ") {
            try submitFollowUpCommand(trimmed)
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

        if trimmed == "/session-name" || trimmed.hasPrefix("/session-name ") || trimmed == "/session_name" || trimmed.hasPrefix("/session_name ") {
            try submitSetSessionNameCommand(trimmed)
            return
        }

        lock.lock()
        let isCurrentlyStreaming = isStreaming
        if isCurrentlyStreaming == false {
            isStreaming = true
            assistantTranscriptIndex = nil
            currentAssistantText = ""
        }
        draft = ""
        transcriptEntries.append("> \(trimmed)")
        appendActivityItemLocked(
            SessionActivityItem(
                kind: .message,
                text: isCurrentlyStreaming ? "Queued steering: \(trimmed)" : "You: \(trimmed)"
            )
        )
        lock.unlock()
        notifyChange()

        var payload: [String: Any] = [
            "type": "prompt",
            "message": trimmed
        ]
        if isCurrentlyStreaming {
            payload["streamingBehavior"] = "steer"
        }
        try transport.sendLine(Self.jsonLine(payload))
    }

    private func submitSteeringCommand(_ commandText: String) throws {
        let message = String(commandText.dropFirst("/steer".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        try submitQueuedCommand(
            message: message,
            usageText: "Usage: /steer <message>",
            activityText: "Queued steering: \(message)",
            payload: [
                "type": "steer",
                "message": message
            ]
        )
    }

    private func submitFollowUpCommand(_ commandText: String) throws {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if trimmed.hasPrefix("/follow_up") {
            message = String(trimmed.dropFirst("/follow_up".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            message = String(trimmed.dropFirst("/follow-up".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try submitQueuedCommand(
            message: message,
            usageText: "Usage: /follow-up <message>",
            activityText: "Queued follow-up: \(message)",
            payload: [
                "type": "follow_up",
                "message": message
            ]
        )
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

        try transport.sendLine(Self.jsonLine([
            "id": "nexus-pi-fork-messages-\(UUID().uuidString)",
            "type": "get_fork_messages"
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
                "entryId": entryID
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
                "type": "clone"
            ])
        )
    }

    private func submitSetSessionNameCommand(_ commandText: String) throws {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameText: String
        if trimmed.hasPrefix("/session_name") {
            nameText = String(trimmed.dropFirst("/session_name".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            nameText = String(trimmed.dropFirst("/session-name".count)).trimmingCharacters(in: .whitespacesAndNewlines)
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
                "name": nameText
            ])
        )
    }

    private func submitSteeringModeCommand(_ commandText: String) throws {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let modeText: String
        if trimmed.hasPrefix("/steering_mode") {
            modeText = String(trimmed.dropFirst("/steering_mode".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            modeText = String(trimmed.dropFirst("/steering-mode".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let mode = parseQueueModeSelection(modeText) else {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /steering-mode <all|one-at-a-time>"))
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
                "mode": mode
            ])
        )
    }

    private func submitFollowUpModeCommand(_ commandText: String) throws {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let modeText: String
        if trimmed.hasPrefix("/follow_up_mode") {
            modeText = String(trimmed.dropFirst("/follow_up_mode".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            modeText = String(trimmed.dropFirst("/follow-up-mode".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let mode = parseQueueModeSelection(modeText) else {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /follow-up-mode <all|one-at-a-time>"))
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
                "mode": mode
            ])
        )
    }

    private func submitQueuedCommand(
        message: String,
        usageText: String,
        activityText: String,
        payload: [String: Any]
    ) throws {
        guard message.isEmpty == false else {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: usageText))
            lock.unlock()
            notifyChange()
            return
        }

        lock.lock()
        draft = ""
        transcriptEntries.append("> \(message)")
        appendActivityItemLocked(SessionActivityItem(kind: .message, text: activityText))
        lock.unlock()
        notifyChange()

        try transport.sendLine(Self.jsonLine(payload))
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
                "modelId": selection.modelID
            ])
        )
    }

    private func submitThinkingCommand(_ commandText: String) throws {
        let target = String(commandText.dropFirst("/thinking".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let level = parseThinkingLevelSelection(target) else {
            lock.lock()
            draft = ""
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: "Usage: /thinking <off|minimal|low|medium|high|xhigh>"))
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
                "level": level
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
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"))
                if let currentModelStatus = currentModelStatusTextLocked() {
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

        if command == "get_state" {
            handleGetStateResponse(response, requestID: id)
            return
        }

        if command == "get_commands" {
            handleGetCommandsResponse(response, requestID: id)
            return
        }

        if command == "get_available_models" {
            handleAvailableModelsResponse(response, requestID: id)
            return
        }

        if command == "set_model" {
            handleSetModelResponse(response, requestID: id)
            return
        }

        if command == "set_thinking_level" {
            handleSetThinkingLevelResponse(response, requestID: id)
            return
        }

        if command == "set_steering_mode" {
            handleSetSteeringModeResponse(response, requestID: id)
            return
        }

        if command == "set_follow_up_mode" {
            handleSetFollowUpModeResponse(response, requestID: id)
            return
        }

        if command == "get_fork_messages" {
            handleGetForkMessagesResponse(response)
            return
        }

        if command == "fork" {
            handleForkResponse(response)
            return
        }

        if command == "clone" {
            handleCloneResponse(response)
            return
        }

        if command == "set_session_name" {
            handleSetSessionNameResponse(response, requestID: id)
            return
        }

        if command == "prompt", bool(for: "success", in: response) == true {
            requestSlashCommands()
        }
    }

    private func handleOutputEvent(_ object: [String: Any], type: String) {
        switch type {
        case "agent_start":
            notifyChange()
        case "message_update":
            handleMessageUpdate(object)
        case "message_end":
            handleMessageEnd(object)
        case "extension_ui_request":
            handleExtensionUIRequest(object)
        case "queue_update":
            handleQueueUpdate(object)
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
        let event = SessionProviderEvent(
            sequence: nextProviderEventSequence,
            providerID: .pi,
            type: type,
            family: providerEventFamily(for: type),
            command: type == "response" ? string(for: "command", in: object) : nil,
            rawPayload: rawPayload
        )
        nextProviderEventSequence += 1
        providerEvents.append(event)
        if providerEvents.count > 1_000 {
            providerEvents.removeFirst(providerEvents.count - 1_000)
        }
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
        if normalizedType == "extension_error" || (normalizedType.contains("extension") && normalizedType.contains("error")) {
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

    private func handleExtensionUIRequest(_ object: [String: Any]) {
        guard let dialogID = string(for: "id", in: object),
              let method = string(for: "method", in: object) else {
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
                        kind: SessionExtensionUINotificationKind(rawValue: string(for: "notifyType", in: object) ?? "info") ?? .info,
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
        guard let assistantMessageEvent = object["assistantMessageEvent"] as? [String: Any],
              let eventType = string(for: "type", in: assistantMessageEvent) else {
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
            ensureAssistantTranscriptEntryLocked()
            if let assistantTranscriptIndex {
                transcriptEntries[assistantTranscriptIndex] = currentAssistantText
            }
            lock.unlock()
            notifyChange()
        default:
            return
        }
    }

    private func handleMessageEnd(_ object: [String: Any]) {
        guard let message = object["message"] as? [String: Any],
              string(for: "role", in: message) == "assistant",
              let stopReason = string(for: "stopReason", in: message),
              stopReason == "aborted" || stopReason == "error" else {
            return
        }

        let finalText = assistantText(from: message)
        let errorText = trimmedString(for: "errorMessage", in: message)
            ?? (stopReason == "aborted" ? "Operation aborted" : "Error")

        lock.lock()
        if finalText.isEmpty == false {
            ensureAssistantTranscriptEntryLocked()
            if let assistantTranscriptIndex {
                transcriptEntries[assistantTranscriptIndex] = finalText
            }
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(finalText)"))
        }
        currentAssistantText = ""
        assistantTranscriptIndex = nil
        toolOutputByCallID.removeAll()
        toolNamesByCallID.removeAll()
        isStreaming = false
        appendActivityItemLocked(SessionActivityItem(kind: .error, text: errorText))
        lock.unlock()
        requestSlashCommands()
        notifyChange()
    }

    private func handleToolExecutionStart(_ object: [String: Any]) {
        guard let toolCallID = string(for: "toolCallId", in: object),
              let toolName = string(for: "toolName", in: object) else {
            return
        }

        let args = object["args"] as? [String: Any]
        let callText = toolExecutionCallText(toolName: toolName, args: args)

        lock.lock()
        toolNamesByCallID[toolCallID] = toolName
        toolOutputByCallID[toolCallID] = ""
        appendActivityItemLocked(SessionActivityItem(kind: .command, text: callText))
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
        let previousText = toolOutputByCallID[toolCallID] ?? ""
        let nextDelta = incrementalToolOutput(from: previousText, to: outputText)
        toolOutputByCallID[toolCallID] = outputText
        if nextDelta.isEmpty == false {
            let toolLabel = toolExecutionOutputLabel(for: toolNamesByCallID[toolCallID])
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "\(toolLabel): \(nextDelta)"))
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
        let previousText = toolOutputByCallID[toolCallID] ?? ""
        let nextDelta = incrementalToolOutput(from: previousText, to: outputText)
        toolOutputByCallID.removeValue(forKey: toolCallID)
        let toolLabel = toolExecutionOutputLabel(for: toolNamesByCallID.removeValue(forKey: toolCallID))

        if nextDelta.isEmpty == false {
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: isError ? .error : .message,
                    text: isError ? nextDelta : "\(toolLabel): \(nextDelta)"
                )
            )
            shouldNotify = true
        } else {
            shouldNotify = false
        }
        lock.unlock()

        if shouldNotify {
            notifyChange()
        }
    }

    private func handleTurnEnd(_ object: [String: Any]) {
        let resolvedText = assistantText(from: object["message"] as? [String: Any])

        lock.lock()
        let finalText = resolvedText.isEmpty ? currentAssistantText : resolvedText
        if finalText.isEmpty == false {
            ensureAssistantTranscriptEntryLocked()
            if let assistantTranscriptIndex {
                transcriptEntries[assistantTranscriptIndex] = finalText
            }
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(finalText)"))
        }
        currentAssistantText = ""
        assistantTranscriptIndex = nil
        toolOutputByCallID.removeAll()
        toolNamesByCallID.removeAll()
        isStreaming = false
        lock.unlock()
        requestSlashCommands()
        notifyChange()
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
    }

    private func renderedTranscriptLocked() -> String {
        var lines = transcriptEntries
        if draft.isEmpty == false {
            lines.append("> \(draft)")
        }
        return lines.joined(separator: "\n")
    }

    private func handleGetStateResponse(_ response: [String: Any], requestID: String?) {
        let shouldQueueTransition: Bool
        if bool(for: "success", in: response) == true {
            lock.lock()
            updateSessionLinkageLocked(from: response)
            updateCurrentStateLocked(from: response)
            shouldQueueTransition = requestID.map { pendingSessionTransitionStateRequestIDs.remove($0) != nil } ?? false
            if shouldQueueTransition,
               let metadata = sessionLinkage?.sessionRecordAdapterMetadata {
                pendingSessionTransitions.append(
                    SessionRuntimeSessionTransition(sessionRecordAdapterMetadata: metadata)
                )
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
               let model = parseModelDescriptor(from: data) {
                currentModel = model
                if let currentThinkingLevel {
                    self.currentThinkingLevel = clampThinkingLevel(currentThinkingLevel, for: model)
                }
            }

            let resolvedTarget = formattedModelTarget(fromResponse: response) ?? fallbackTarget ?? "selected model"
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi model switched to \(resolvedTarget)"))
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
            let effectiveLevel = requestedLevel.map { clampThinkingLevel($0, for: currentModel) } ?? currentThinkingLevel
            currentThinkingLevel = effectiveLevel
            let message = effectiveLevel.map { "Pi thinking level set to \($0)" } ?? "Pi thinking level updated"
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

    private func handleSetSteeringModeResponse(_ response: [String: Any], requestID: String?) {
        lock.lock()
        let requestedMode = requestID.flatMap { pendingSetSteeringModesByRequestID.removeValue(forKey: $0) }

        if bool(for: "success", in: response) == true {
            if let requestedMode {
                steeringMode = requestedMode
            }
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi steering mode set to \(steeringMode)"))
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
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi follow-up mode set to \(followUpMode)"))
        } else {
            let detail = string(for: "error", in: response) ?? "Pi failed to update follow-up mode."
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
        }

        lock.unlock()
        requestSlashCommands()
        notifyChange()
    }

    private func handleGetForkMessagesResponse(_ response: [String: Any]) {
        lock.lock()
        if bool(for: "success", in: response) == true,
           let data = response["data"] as? [String: Any],
           let messages = data["messages"] as? [[String: Any]] {
            if messages.isEmpty {
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "No fork messages available"))
            } else {
                for message in messages {
                    guard let entryID = trimmedString(for: "entryId", in: message),
                          let text = trimmedString(for: "text", in: message) else {
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
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi session name set to \(requestedName)"))
            }
        } else {
            let detail = string(for: "error", in: response) ?? "Pi failed to set the Session name."
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: detail))
        }
        lock.unlock()
        notifyChange()
    }

    private func handleForkResponse(_ response: [String: Any]) {
        if bool(for: "success", in: response) == true {
            if let data = response["data"] as? [String: Any],
               let selectedText = trimmedString(for: "text", in: data) {
                lock.lock()
                appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Forked from: \(previewText(selectedText, limit: 120))"))
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
            lock.lock()
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Cloned the current Pi Session"))
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
              let rawCommands = data["commands"] as? [[String: Any]] else {
            return nil
        }

        return rawCommands.compactMap { command in
            guard let name = string(for: "name", in: command),
                  let sourceValue = string(for: "source", in: command),
                  let source = SessionSlashCommandSource(rawValue: sourceValue) else {
                return nil
            }

            return SessionSlashCommand(
                name: name,
                description: string(for: "description", in: command),
                source: source,
                location: string(for: "location", in: command).flatMap(SessionSlashCommandLocation.init(rawValue:)),
                path: string(for: "path", in: command)
            )
        }
    }

    private func parseAvailableModelCommands(from response: [String: Any]) -> [SessionSlashCommand]? {
        guard let data = response["data"] as? [String: Any],
              let rawModels = data["models"] as? [[String: Any]] else {
            return nil
        }

        return rawModels.compactMap { model in
            guard let provider = trimmedString(for: "provider", in: model),
                  let modelID = trimmedString(for: "id", in: model) else {
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
        let modelID = String(target[target.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func formattedModelTarget(fromResponse response: [String: Any]) -> String? {
        guard let data = response["data"] as? [String: Any] else {
            return nil
        }
        return formattedModelTarget(fromModel: data)
    }

    private func formattedModelTarget(fromModel model: [String: Any]) -> String? {
        guard let provider = trimmedString(for: "provider", in: model),
              let modelID = trimmedString(for: "id", in: model) else {
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
              let modelID = trimmedString(for: "id", in: model) else {
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

        return piBasicThinkingLevels + (supportsXHighThinkingLevel(provider: provider, modelID: modelID) ? ["xhigh"] : [])
    }

    private func supportsXHighThinkingLevel(provider: String, modelID: String) -> Bool {
        provider.caseInsensitiveCompare("openai") == .orderedSame && modelID.localizedCaseInsensitiveContains("codex-max")
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

        for candidate in piExtendedThinkingLevels[..<requestedIndex].reversed() where availableLevels.contains(candidate) {
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
                (piExtendedThinkingLevels.firstIndex(of: $0) ?? piExtendedThinkingLevels.count) < (piExtendedThinkingLevels.firstIndex(of: $1) ?? piExtendedThinkingLevels.count)
            }
        }

        return levels.map { level in
            let isCurrent = level == currentThinkingLevel
            return SessionSlashCommand(
                name: "thinking \(level)",
                displayName: "thinking \(level)",
                insertionText: "thinking \(level)",
                suggestionQueryPrefix: "thinking ",
                description: isCurrent ? "Current Pi thinking level." : "Set Pi thinking level to \(level).",
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
            return "Pi queue cleared"
        }
        return "Pi queue updated — \(segments.joined(separator: "; "))"
    }

    private func queueControlSlashCommandsLocked() -> [SessionSlashCommand] {
        let steeringModes = ["all", "one-at-a-time"].map { mode in
            SessionSlashCommand(
                name: "steering-mode \(mode)",
                displayName: "steering-mode \(mode)",
                insertionText: "steering-mode \(mode)",
                suggestionQueryPrefix: "steering-mode ",
                description: mode == steeringMode ? "Current Pi steering mode." : "Set Pi steering mode to \(mode).",
                source: .builtIn
            )
        }
        let followUpModes = ["all", "one-at-a-time"].map { mode in
            SessionSlashCommand(
                name: "follow-up-mode \(mode)",
                displayName: "follow-up-mode \(mode)",
                insertionText: "follow-up-mode \(mode)",
                suggestionQueryPrefix: "follow-up-mode ",
                description: mode == followUpMode ? "Current Pi follow-up mode." : "Set Pi follow-up mode to \(mode).",
                source: .builtIn
            )
        }
        return [
            SessionSlashCommand(
                name: "steer",
                displayName: "steer <message>",
                insertionText: "steer ",
                suggestionQueryPrefix: "steer ",
                description: "Queue a steering message while Pi is running.",
                source: .builtIn
            ),
            SessionSlashCommand(
                name: "follow-up",
                displayName: "follow-up <message>",
                insertionText: "follow-up ",
                suggestionQueryPrefix: "follow-up ",
                description: "Queue a follow-up message for after Pi finishes.",
                source: .builtIn
            ),
            SessionSlashCommand(
                name: "abort",
                displayName: "abort",
                insertionText: "abort",
                description: "Abort the current Pi run.",
                source: .builtIn
            )
        ] + steeringModes + followUpModes
    }

    private func sessionGraphSlashCommandsLocked() -> [SessionSlashCommand] {
        [
            SessionSlashCommand(
                name: "fork",
                displayName: "fork <entry-id>",
                insertionText: "fork ",
                suggestionQueryPrefix: "fork ",
                description: "Fork from a previous Pi message into a new Named Session.",
                source: .builtIn
            ),
            SessionSlashCommand(
                name: "clone",
                displayName: "clone",
                insertionText: "clone",
                description: "Clone the current Pi Session into a new Named Session.",
                source: .builtIn
            ),
            SessionSlashCommand(
                name: "fork-messages",
                displayName: "fork-messages",
                insertionText: "fork-messages",
                description: "List Pi messages available for forking.",
                source: .builtIn
            ),
            SessionSlashCommand(
                name: "session-name",
                displayName: "session-name <name>",
                insertionText: "session-name ",
                suggestionQueryPrefix: "session-name ",
                description: "Set the current Pi Session name and sync it into Nexus.",
                source: .builtIn
            )
        ]
    }

    private func handleSessionTransitionEvent(_ object: [String: Any]) {
        guard let linkage = sessionTransitionLinkage(from: object),
              let metadata = linkage.sessionRecordAdapterMetadata else {
            notifyChange()
            return
        }

        lock.lock()
        sessionLinkage = linkage
        pendingSessionTransitions.append(
            SessionRuntimeSessionTransition(sessionRecordAdapterMetadata: metadata)
        )
        lock.unlock()
        notifyChange()
    }

    private func sessionTransitionLinkage(from object: [String: Any]) -> PiSessionLinkage? {
        let candidates: [[String: Any]] = [
            object,
            object["data"] as? [String: Any],
            object["session"] as? [String: Any]
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
            queueControlSlashCommandsLocked(),
            sessionGraphSlashCommandsLocked()
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

    private func toolExecutionCallText(toolName: String, args: [String: Any]?) -> String {
        let normalizedToolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedToolName.caseInsensitiveCompare("subagent") == .orderedSame {
            let agent = args.flatMap { string(for: "agent", in: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let task = args.flatMap { string(for: "task", in: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let taskPreview = task.map { previewText($0, limit: 80) }
            if let agent, agent.isEmpty == false, let taskPreview, taskPreview.isEmpty == false {
                return "subagent \(agent): \(taskPreview)"
            }
            if let agent, agent.isEmpty == false {
                return "subagent \(agent)"
            }
        }

        if let command = args.flatMap({ string(for: "command", in: $0) })?.trimmingCharacters(in: .whitespacesAndNewlines),
           command.isEmpty == false {
            return command
        }

        if let task = args.flatMap({ string(for: "task", in: $0) })?.trimmingCharacters(in: .whitespacesAndNewlines),
           task.isEmpty == false {
            return "\(normalizedToolName): \(previewText(task, limit: 80))"
        }

        return normalizedToolName.isEmpty ? "Tool" : normalizedToolName
    }

    private func toolExecutionOutputLabel(for toolName: String?) -> String {
        let normalizedToolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedToolName, normalizedToolName.isEmpty == false else {
            return "Tool"
        }
        return normalizedToolName.caseInsensitiveCompare("subagent") == .orderedSame ? "subagent" : normalizedToolName
    }

    private func toolExecutionResultText(_ object: [String: Any]?) -> String {
        toolExecutionResultText(from: object)
    }

    private func toolExecutionResultText(from value: Any?) -> String {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let object as [String: Any]:
            if let text = string(for: "text", in: object)
                ?? string(for: "delta", in: object)
                ?? string(for: "message", in: object)
                ?? string(for: "output", in: object)
                ?? string(for: "summary", in: object) {
                return text
            }

            for key in ["content", "result", "partialResult"] {
                let text = toolExecutionResultText(from: object[key])
                if text.isEmpty == false {
                    return text
                }
            }

            return ""
        case let array as [Any]:
            let text = array
                .map { toolExecutionResultText(from: $0) }
                .filter { $0.isEmpty == false }
                .joined()
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return ""
        }
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
            return String(trimmedNextText.dropFirst(trimmedPreviousText.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedNextText == trimmedPreviousText ? "" : trimmedNextText
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
        let hasContent = state.title != nil
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
        extensionStatuses.append(status)
    }

    private func upsertExtensionWidgetLocked(_ widget: SessionExtensionUIWidget) {
        extensionWidgets.removeAll { $0.key == widget.key }
        extensionWidgets.append(widget)
    }

    private func appendActivityItemLocked(_ item: SessionActivityItem) {
        let trimmedText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            return
        }

        activityItems.append(SessionActivityItem(id: item.id, kind: item.kind, text: trimmedText))
        if activityItems.count > 200 {
            activityItems.removeFirst(activityItems.count - 200)
        }
    }

    private func assistantText(from message: [String: Any]?) -> String {
        guard let message,
              let content = message["content"] as? [[String: Any]] else {
            return ""
        }

        return content
            .compactMap { block -> String? in
                guard string(for: "type", in: block) == "text" else {
                    return nil
                }
                return string(for: "text", in: block)
            }
            .joined()
    }

    private func responseObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func string(for key: String, in object: [String: Any]) -> String? {
        object[key] as? String
    }

    private func trimmedString(for key: String, in object: [String: Any]) -> String? {
        guard let value = string(for: key, in: object)?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
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

    private func notifyChange() {
        let handler: (@Sendable () -> Void)?
        lock.lock()
        handler = changeHandler
        lock.unlock()
        handler?()
    }

    static func transportArguments(sessionLinkage: PiSessionLinkage?) -> [String] {
        var arguments = ["--mode", "rpc"]

        if let sessionFile = sessionLinkage?.sessionFile?.trimmingCharacters(in: .whitespacesAndNewlines),
           sessionFile.isEmpty == false {
            arguments += ["--session", sessionFile]
        } else if let piSessionID = sessionLinkage?.piSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  piSessionID.isEmpty == false {
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
    private let lock = NSLock()
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()

    init(executable: String, arguments: [String], workingDirectory: String?) throws {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
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
              let envInvocation = envInterpreterInvocation(for: shebang) else {
            return ProcessInvocation(executable: executable, arguments: arguments)
        }

        return envInvocation
    }

    private func scriptShebang() -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: executable), options: .mappedIfSafe),
              let newlineIndex = data.firstIndex(of: 0x0A) else {
            return nil
        }

        let lineData = data.prefix(upTo: newlineIndex)
        return String(data: lineData, encoding: .utf8)?.replacingOccurrences(of: "\r", with: "")
    }

    private func envInterpreterInvocation(for shebang: String) -> ProcessInvocation? {
        guard shebang.hasPrefix("#!/usr/bin/env ") else {
            return nil
        }

        var shebangArguments = shebang
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
              let interpreterExecutable = resolvedInterpreter(named: interpreterName) else {
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

        return SystemProviderExecutableResolver()
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
            handler?(line)
        }
    }

    private func handleTermination(_ status: Int32) {
        let handler: (@Sendable (Int32) -> Void)?
        lock.lock()
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        handler = terminationHandler
        lock.unlock()
        handler?(status)
    }
}
#endif
