#if os(macOS)
    import Foundation
    import NexusDomain

    struct CodexAppServerTermination: Sendable {
        let status: Int32
        let stderr: String?
    }

    protocol CodexAppServerTransporting: AnyObject {
        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?)
        func setTerminationHandler(_ handler: (@Sendable (CodexAppServerTermination) -> Void)?)
        func start() throws
        func sendLine(_ line: String) throws
        func terminate() throws
    }

    private func normalizedCodexRemoteStartupFailureMessage(_ raw: String) -> String {
        let lines =
            raw
            .replacingOccurrences(of: "\r", with: "")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let meaningful =
            lines.filter { line in
                line.hasPrefix("bash: no job control") == false
                    && line.hasPrefix("sh: no job control") == false
            }
        let candidate = meaningful.last ?? lines.last ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : candidate
    }

    enum CodexAppServerRuntimeError: LocalizedError {
        case startupTimedOut
        case startupFailed(String)
        case approvalRequestNotFound

        var errorDescription: String? {
            switch self {
            case .startupTimedOut:
                return "Codex app-server did not finish startup in time."
            case .startupFailed(let message):
                return normalizedCodexRemoteStartupFailureMessage(message)
            case .approvalRequestNotFound:
                return "Approval Request was not found for this Session."
            }
        }
    }

    private enum CodexJSONRPCRequestID: Sendable {
        case string(String)
        case number(Double)

        init?(_ value: Any?) {
            if let string = value as? String {
                self = .string(string)
            } else if let number = value as? NSNumber {
                self = .number(number.doubleValue)
            } else {
                return nil
            }
        }

        var jsonValue: Any {
            switch self {
            case .string(let string):
                string
            case .number(let number):
                number
            }
        }
    }

    private struct PendingCodexApprovalRequest: Sendable {
        let requestID: CodexJSONRPCRequestID
    }

    final class CodexAppServerRuntime: SessionRuntime, @unchecked Sendable {
        typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws
            -> any CodexAppServerTransporting

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

        private let lock = NSLock()
        private let transport: any CodexAppServerTransporting
        private let stopHandler: (() throws -> Void)?
        private let terminationStatusMessageBuilder: (Int32) -> String
        private let unexpectedTerminationState: Session.State
        private let unexpectedTerminationMessageBuilder: (Int32) -> String
        private let initializeRequestID = "nexus-codex-initialize"
        private let startupThreadRequestID = "nexus-codex-thread-start"
        private var runtimeState: Session.State = .ready
        private var terminalColumns = 80
        private var terminalRows = 24
        private var transcript = ""
        private var activityItems: [SessionActivityItem] = []
        private var approvalRequests: [SessionApprovalRequest] = []
        private var slashCommands: [SessionSlashCommand]?
        private var providerEvents: [SessionProviderEvent] = []
        private var providerFacts: StructuredSessionProviderFacts = .empty
        private var finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic?
        private var nextProviderEventSequence = 0
        private var pendingApprovalRequests: [UUID: PendingCodexApprovalRequest] = [:]
        private var pendingTurnRequestIDs: Set<String> = []
        private var pendingSlashCommandRequestIDs: Set<String> = []
        private var nextTurnRequestSequence = 0
        private var nextSlashCommandRequestSequence = 0
        private var completedAgentMessageItemIDs: Set<String> = []
        private var startedItemIDs: Set<String> = []
        private var streamedToolOutputByItemID: [String: String] = [:]
        private var toolLabelsByItemID: [String: String] = [:]
        private var isTurnInProgress = false
        private var didAnnounceConnectedStatus = false
        private var sessionLinkage: CodexSessionLinkage?
        private var changeHandler: (@Sendable () -> Void)?
        private var didRequestStop = false

        convenience init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: CodexSessionLinkage? = nil,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State = .exited,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
            stopHandler: (() throws -> Void)? = nil,
            processEnvironment: [String: String]? = nil,
            transportFactory: TransportFactory? = nil
        ) throws {
            let resolvedTransportFactory =
                transportFactory ?? { executable, arguments, workingDirectory in
                    try ProcessCodexAppServerTransport(
                        executable: executable,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: processEnvironment
                    )
                }

            try self.init(
                executable: executable,
                workingDirectory: workingDirectory,
                sessionLinkage: sessionLinkage,
                terminationStatusMessageBuilder: terminationStatusMessageBuilder,
                unexpectedTerminationState: unexpectedTerminationState,
                unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder,
                stopHandler: stopHandler,
                transportFactory: resolvedTransportFactory,
                performStartup: false
            )
            try AsyncOperationSupport.blocking { try await self.completeStartup(workingDirectory: workingDirectory) }
        }

        convenience init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: CodexSessionLinkage? = nil,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State = .exited,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
            stopHandler: (() throws -> Void)? = nil,
            processEnvironment: [String: String]? = nil,
            transportFactory: TransportFactory? = nil
        ) async throws {
            let resolvedTransportFactory =
                transportFactory ?? { executable, arguments, workingDirectory in
                    try ProcessCodexAppServerTransport(
                        executable: executable,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: processEnvironment
                    )
                }

            try self.init(
                executable: executable,
                workingDirectory: workingDirectory,
                sessionLinkage: sessionLinkage,
                terminationStatusMessageBuilder: terminationStatusMessageBuilder,
                unexpectedTerminationState: unexpectedTerminationState,
                unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder,
                stopHandler: stopHandler,
                transportFactory: resolvedTransportFactory,
                performStartup: false
            )
            try await self.completeStartup(workingDirectory: workingDirectory)
        }

        private init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: CodexSessionLinkage?,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)?,
            stopHandler: (() throws -> Void)?,
            transportFactory: TransportFactory,
            performStartup: Bool
        ) throws {
            self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
            self.unexpectedTerminationState = unexpectedTerminationState
            self.unexpectedTerminationMessageBuilder =
                unexpectedTerminationMessageBuilder ?? terminationStatusMessageBuilder
            self.sessionLinkage = sessionLinkage
            self.stopHandler = stopHandler
            self.transport = try transportFactory(executable, ["app-server"], workingDirectory)
        }

        private func completeStartup(workingDirectory: String) async throws {
            let startupState = CodexStartupState()
            let initializeWaiter = AsyncResultWaiter<Void>()
            let resolveThreadWaiter = AsyncResultWaiter<Void>()
            let shouldAttemptStartupResume = sessionLinkage?.isEmpty == false
            let startupFreshThreadFallbackRequestID = "nexus-codex-thread-start-fallback"

            transport.setStdoutLineHandler { [weak self] line in
                guard let self, let object = self.responseObject(from: line) else {
                    return
                }

                self.recordProviderEvent(rawPayload: line, object: object)

                let id = self.string(for: "id", in: object)
                if id == self.initializeRequestID {
                    startupState.markInitialized()
                    initializeWaiter.succeed()
                    return
                }

                if id == self.startupThreadRequestID || id == startupFreshThreadFallbackRequestID {
                    if self.captureThreadLinkage(from: object, appendConnectedStatus: true) {
                        startupState.markResolvedThread()
                        resolveThreadWaiter.succeed()
                        return
                    }

                    if let error = self.rpcErrorMessage(from: object) {
                        if id == self.startupThreadRequestID,
                            shouldAttemptStartupResume,
                            self.shouldRetryStartupWithFreshThread(after: error)
                        {
                            do {
                                try self.transport.sendLine(
                                    Self.jsonLine([
                                        "jsonrpc": "2.0",
                                        "id": startupFreshThreadFallbackRequestID,
                                        "method": "thread/start",
                                        "params": self.startupThreadParameters(
                                            workingDirectory: workingDirectory, sessionLinkage: nil),
                                    ]))
                            } catch {
                                startupState.record(error: error)
                                resolveThreadWaiter.fail(error)
                            }
                            return
                        }

                        let startupError = CodexAppServerRuntimeError.startupFailed(error)
                        startupState.record(error: startupError)
                        (startupState.didInitialize ? resolveThreadWaiter : initializeWaiter).fail(startupError)
                    }
                    return
                }

                if let error = self.rpcErrorMessage(from: object), startupState.didResolveThread == false {
                    let startupError = CodexAppServerRuntimeError.startupFailed(error)
                    startupState.record(error: startupError)
                    (startupState.didInitialize ? resolveThreadWaiter : initializeWaiter).fail(startupError)
                    return
                }

                if self.handleStartupThreadNotification(
                    object, startupState: startupState, resolveThreadWaiter: resolveThreadWaiter)
                {
                    return
                }

                if startupState.didResolveThread {
                    if self.handleRequestResponse(object) {
                        return
                    }
                    self.handleNotification(object)
                }
            }
            transport.setTerminationHandler { [weak self] termination in
                if startupState.recordUnexpectedTerminationIfNeeded(termination: termination) {
                    let startupError = startupState.error ?? CodexAppServerRuntimeError.startupTimedOut
                    (startupState.didInitialize ? resolveThreadWaiter : initializeWaiter).fail(startupError)
                }
                self?.handleTermination(status: termination.status)
            }

            try transport.start()
            try transport.sendLine(
                Self.jsonLine([
                    "jsonrpc": "2.0",
                    "id": initializeRequestID,
                    "method": "initialize",
                    "params": [
                        "clientInfo": [
                            "name": "nexus",
                            "version": "1",
                        ]
                    ],
                ]))

            do {
                try await initializeWaiter.wait(
                    timeoutNanoseconds: 5_000_000_000,
                    timeoutError: { startupState.error ?? CodexAppServerRuntimeError.startupTimedOut }
                )
            } catch {
                try? transport.terminate()
                throw startupState.error ?? error
            }

            try transport.sendLine(
                Self.jsonLine([
                    "jsonrpc": "2.0",
                    "method": "initialized",
                    "params": [:],
                ]))
            try transport.sendLine(
                Self.jsonLine([
                    "jsonrpc": "2.0",
                    "id": startupThreadRequestID,
                    "method": shouldAttemptStartupResume ? "thread/resume" : "thread/start",
                    "params": startupThreadParameters(
                        workingDirectory: workingDirectory, sessionLinkage: sessionLinkage),
                ]))

            do {
                try await resolveThreadWaiter.wait(
                    timeoutNanoseconds: 5_000_000_000,
                    timeoutError: { startupState.error ?? CodexAppServerRuntimeError.startupTimedOut }
                )
            } catch {
                try? transport.terminate()
                throw startupState.error ?? error
            }

            if let startupError = startupState.error {
                try? transport.terminate()
                throw startupError
            }

            requestSlashCommands(forceRefresh: true)
        }

        func sessionScreen(for session: Session) -> SessionScreen {
            lock.lock()
            defer { lock.unlock() }
            return SessionScreen(
                session: sessionWithCurrentState(session),
                primarySurface: .structuredActivityFeed,
                transcript: transcript,
                terminalColumns: terminalColumns,
                terminalRows: terminalRows,
                activityItems: activityItems,
                approvalRequests: approvalRequests,
                slashCommands: slashCommands,
                providerEvents: providerEvents,
                providerFacts: providerFacts,
                finalOutputDiagnostic: finalOutputDiagnostic,
                isAgentTurnInProgress: isTurnInProgress
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
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return
            }

            let requestID: String
            let threadID: String
            lock.lock()
            guard let resolvedThreadID = sessionLinkage?.threadID?.trimmingCharacters(in: .whitespacesAndNewlines),
                resolvedThreadID.isEmpty == false
            else {
                lock.unlock()
                throw CodexAppServerRuntimeError.startupFailed("Codex Session thread ID is unavailable.")
            }
            threadID = resolvedThreadID
            nextTurnRequestSequence += 1
            requestID = "nexus-codex-turn-\(nextTurnRequestSequence)"
            pendingTurnRequestIDs.insert(requestID)
            isTurnInProgress = true
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "You: \(trimmed)"))
            lock.unlock()
            notifyChange()

            do {
                try transport.sendLine(
                    Self.jsonLine([
                        "jsonrpc": "2.0",
                        "id": requestID,
                        "method": "turn/start",
                        "params": [
                            "threadId": threadID,
                            "input": [
                                [
                                    "type": "text",
                                    "text": trimmed,
                                ]
                            ],
                        ],
                    ])
                )
            } catch {
                lock.lock()
                pendingTurnRequestIDs.remove(requestID)
                lock.unlock()
                throw error
            }
        }

        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {
            let pendingApprovalRequest: PendingCodexApprovalRequest
            let request: SessionApprovalRequest

            lock.lock()
            guard let resolvedPendingApprovalRequest = pendingApprovalRequests[approvalRequestID],
                let index = approvalRequests.firstIndex(where: { $0.id == approvalRequestID && $0.state == .pending })
            else {
                lock.unlock()
                throw CodexAppServerRuntimeError.approvalRequestNotFound
            }
            pendingApprovalRequest = resolvedPendingApprovalRequest
            request = approvalRequests[index]
            lock.unlock()

            try transport.sendLine(
                Self.jsonLine([
                    "jsonrpc": "2.0",
                    "id": pendingApprovalRequest.requestID.jsonValue,
                    "result": [
                        "decision": decision == .approve ? "accept" : "decline"
                    ],
                ])
            )

            lock.lock()
            pendingApprovalRequests.removeValue(forKey: approvalRequestID)
            if let index = approvalRequests.firstIndex(where: { $0.id == approvalRequestID }) {
                approvalRequests[index] = SessionApprovalRequest(
                    id: request.id,
                    title: request.title,
                    text: request.text,
                    state: decision == .approve ? .approved : .denied
                )
            }
            appendActivityItemLocked(
                SessionActivityItem(
                    kind: .approvalDecision,
                    text: "\(decision == .approve ? "Approved" : "Denied"): \(request.title)"
                )
            )
            lock.unlock()
            notifyChange()
        }

        func resize(columns: Int, rows: Int) throws {
            lock.lock()
            terminalColumns = max(1, columns)
            terminalRows = max(1, rows)
            lock.unlock()
            notifyChange()
        }

        private func handleRequestResponse(_ object: [String: Any]) -> Bool {
            guard let id = string(for: "id", in: object) else {
                return false
            }

            lock.lock()
            let isPendingTurnRequest = pendingTurnRequestIDs.contains(id)
            if isPendingTurnRequest {
                pendingTurnRequestIDs.remove(id)
                lock.unlock()

                if let error = rpcErrorMessage(from: object) {
                    lock.lock()
                    isTurnInProgress = false
                    appendActivityItemLocked(SessionActivityItem(kind: .error, text: error))
                    lock.unlock()
                    notifyChange()
                }

                return true
            }

            let isPendingSlashCommandRequest = pendingSlashCommandRequestIDs.contains(id)
            if isPendingSlashCommandRequest {
                pendingSlashCommandRequestIDs.remove(id)
            }
            lock.unlock()

            guard isPendingSlashCommandRequest else {
                return false
            }

            if let nextSlashCommands = parseSlashCommands(from: object) {
                let shouldNotify: Bool
                lock.lock()
                shouldNotify = slashCommands != nextSlashCommands
                slashCommands = nextSlashCommands
                lock.unlock()

                if shouldNotify {
                    notifyChange()
                }
            }

            return true
        }

        private func handleNotification(_ object: [String: Any]) {
            guard let method = string(for: "method", in: object) else {
                return
            }

            switch method {
            case "error":
                if let params = object["params"] as? [String: Any],
                    let message = string(for: "message", in: params)
                {
                    lock.lock()
                    appendActivityItemLocked(SessionActivityItem(kind: .error, text: message))
                    lock.unlock()
                    notifyChange()
                }
            case "thread/started", "thread/resumed":
                if captureThreadLinkage(from: object, appendConnectedStatus: true) {
                    notifyChange()
                    requestSlashCommands(forceRefresh: true)
                }
            case "model/rerouted", "account/updated", "config/warning", "warning":
                requestSlashCommands(forceRefresh: true)
            case "item/started":
                handleStartedItem(object["params"] as? [String: Any])
            case "item/updated":
                handleUpdatedItem(object["params"] as? [String: Any])
            case "item/completed":
                handleCompletedItem(object["params"] as? [String: Any])
            case "item/commandExecution/requestApproval":
                handleCommandExecutionApprovalRequest(
                    object["params"] as? [String: Any],
                    requestID: CodexJSONRPCRequestID(object["id"])
                )
            case "item/fileChange/requestApproval":
                handleFileChangeApprovalRequest(
                    object["params"] as? [String: Any],
                    requestID: CodexJSONRPCRequestID(object["id"])
                )
            default:
                return
            }
        }

        private func handleStartupThreadNotification(
            _ object: [String: Any],
            startupState: CodexStartupState,
            resolveThreadWaiter: AsyncResultWaiter<Void>
        ) -> Bool {
            guard startupState.didResolveThread == false,
                let method = string(for: "method", in: object),
                method == "thread/started" || method == "thread/resumed",
                captureThreadLinkage(from: object, appendConnectedStatus: true)
            else {
                return false
            }

            startupState.markResolvedThread()
            resolveThreadWaiter.succeed()
            return true
        }

        private func captureThreadLinkage(from object: [String: Any], appendConnectedStatus: Bool) -> Bool {
            guard let threadID = resolvedThreadID(from: object) else {
                return false
            }

            let didChange: Bool
            lock.lock()
            let existingThreadID = sessionLinkage?.threadID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldUpdateThreadID = existingThreadID != threadID
            if shouldUpdateThreadID {
                sessionLinkage = CodexSessionLinkage(threadID: threadID)
            }
            let shouldAppendConnectedStatus = appendConnectedStatus && didAnnounceConnectedStatus == false
            if shouldAppendConnectedStatus {
                appendActivityItemLocked(
                    SessionActivityItem(kind: .status, text: "Codex shared Session stream connected"))
                didAnnounceConnectedStatus = true
            }
            didChange = shouldUpdateThreadID || shouldAppendConnectedStatus
            lock.unlock()

            return didChange
        }

        private func requestSlashCommands(forceRefresh _: Bool) {
            let requestID: String
            lock.lock()
            if pendingSlashCommandRequestIDs.isEmpty == false {
                lock.unlock()
                return
            }
            requestID = "nexus-codex-model-list-\(nextSlashCommandRequestSequence)"
            nextSlashCommandRequestSequence += 1
            pendingSlashCommandRequestIDs.insert(requestID)
            lock.unlock()

            do {
                try transport.sendLine(
                    Self.jsonLine([
                        "jsonrpc": "2.0",
                        "id": requestID,
                        "method": "model/list",
                        "params": [
                            "includeHidden": false,
                            "limit": 100,
                        ],
                    ]))
            } catch {
                lock.lock()
                pendingSlashCommandRequestIDs.remove(requestID)
                lock.unlock()
            }
        }

        private func parseSlashCommands(from object: [String: Any]) -> [SessionSlashCommand]? {
            guard let result = object["result"] as? [String: Any],
                let data = result["data"] as? [[String: Any]]
            else {
                return nil
            }

            return data.compactMap { model in
                guard let id = trimmedString(for: "id", in: model) else {
                    return nil
                }

                let displayName = trimmedString(for: "displayName", in: model)
                let description = trimmedString(for: "description", in: model)
                let isDefault = model["isDefault"] as? Bool == true
                let summaryPrefix = isDefault ? "Default model. " : ""
                let summary = [summaryPrefix.isEmpty ? nil : summaryPrefix, description].compactMap { $0 }.joined()

                return SessionSlashCommand(
                    name: "model \(id)",
                    displayName: displayName.map { "model \(id) — \($0)" } ?? "model \(id)",
                    insertionText: "model \(id)",
                    suggestionQueryPrefix: "model ",
                    description: summary.isEmpty ? nil : summary,
                    source: .builtIn
                )
            }
        }

        private func handleStartedItem(_ params: [String: Any]?) {
            guard let item = params?["item"] as? [String: Any],
                let itemID = string(for: "id", in: item)
            else {
                return
            }

            let announcement = codexToolAnnouncement(for: item)
            guard announcement.isEmpty == false else {
                return
            }

            let shouldNotify: Bool
            lock.lock()
            shouldNotify = startedItemIDs.insert(itemID).inserted
            if shouldNotify {
                toolLabelsByItemID[itemID] = codexToolLabel(for: item)
                appendActivityItemLocked(SessionActivityItem(kind: .command, text: announcement))
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleUpdatedItem(_ params: [String: Any]?) {
            guard let item = params?["item"] as? [String: Any],
                let itemID = string(for: "id", in: item)
            else {
                return
            }

            let outputText = codexToolOutputText(from: item)
            guard outputText.isEmpty == false else {
                return
            }

            let shouldNotify: Bool
            lock.lock()
            let previousText = streamedToolOutputByItemID[itemID] ?? ""
            let nextDelta = incrementalToolOutput(from: previousText, to: outputText)
            streamedToolOutputByItemID[itemID] = outputText
            if nextDelta.isEmpty == false {
                let toolLabel = toolLabelsByItemID[itemID] ?? codexToolLabel(for: item)
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

        private func handleCompletedItem(_ params: [String: Any]?) {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            guard let item = params?["item"] as? [String: Any],
                let itemID = string(for: "id", in: item)
            else {
                return
            }

            let itemType = string(for: "type", in: item)?.lowercased() ?? ""
            let shouldNotify: Bool

            lock.lock()
            if itemType == "agentmessage" {
                let text = codexAgentMessageText(from: item)
                guard text.isEmpty == false else {
                    lock.unlock()
                    return
                }

                let inserted = completedAgentMessageItemIDs.insert(itemID).inserted
                if inserted {
                    let finalActivityItem = SessionActivityItem(kind: .message, text: "Codex: \(text)")
                    appendActivityItemLocked(finalActivityItem)
                    recordFinalOutputDiagnosticLocked(
                        trigger: .turnEnd,
                        activityItem: finalActivityItem,
                        providerRuntimeLatencyMilliseconds: elapsedMilliseconds(since: startedAt),
                        expectedThinkingIndicatorVisible: false
                    )
                    isTurnInProgress = false
                }
                shouldNotify = inserted
            } else {
                let announcement = codexToolAnnouncement(for: item)
                let outputText = codexToolOutputText(from: item)
                let previousOutputText = streamedToolOutputByItemID[itemID] ?? ""
                let toolLabel = toolLabelsByItemID[itemID] ?? codexToolLabel(for: item)
                let outputDelta = incrementalToolOutput(from: previousOutputText, to: outputText)
                let isError = codexItemIsError(item)

                var didAppend = false
                if startedItemIDs.contains(itemID) == false, announcement.isEmpty == false {
                    appendActivityItemLocked(SessionActivityItem(kind: .command, text: announcement))
                    didAppend = true
                }

                if outputDelta.isEmpty == false {
                    appendActivityItemLocked(
                        SessionActivityItem(
                            kind: isError ? .error : .message,
                            text: isError ? outputDelta : "\(toolLabel): \(outputDelta)"
                        )
                    )
                    didAppend = true
                }

                startedItemIDs.remove(itemID)
                streamedToolOutputByItemID.removeValue(forKey: itemID)
                toolLabelsByItemID.removeValue(forKey: itemID)
                shouldNotify = didAppend
            }
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func handleCommandExecutionApprovalRequest(_ params: [String: Any]?, requestID: CodexJSONRPCRequestID?)
        {
            guard let requestID else {
                return
            }

            let command = params.flatMap { string(for: "command", in: $0) }?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let reason = params.flatMap { string(for: "reason", in: $0) }?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let title = command?.isEmpty == false ? command! : (reason?.isEmpty == false ? reason! : "Approval Request")
            let text = reason?.isEmpty == false ? reason! : title

            registerApprovalRequest(
                SessionApprovalRequest(title: title, text: text, state: .pending),
                requestID: requestID
            )
        }

        private func handleFileChangeApprovalRequest(_ params: [String: Any]?, requestID: CodexJSONRPCRequestID?) {
            guard let requestID else {
                return
            }

            let reason = params.flatMap { string(for: "reason", in: $0) }?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let title = "File changes need approval"
            let text = reason?.isEmpty == false ? reason! : title

            registerApprovalRequest(
                SessionApprovalRequest(title: title, text: text, state: .pending),
                requestID: requestID
            )
        }

        private func registerApprovalRequest(
            _ approvalRequest: SessionApprovalRequest, requestID: CodexJSONRPCRequestID
        ) {
            lock.lock()
            approvalRequests.append(approvalRequest)
            pendingApprovalRequests[approvalRequest.id] = PendingCodexApprovalRequest(requestID: requestID)
            appendActivityItemLocked(
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: \(approvalRequest.title)"))
            lock.unlock()
            notifyChange()
        }

        private func codexAgentMessageText(from item: [String: Any]) -> String {
            if let text = string(for: "text", in: item)?.trimmingCharacters(in: .whitespacesAndNewlines),
                text.isEmpty == false
            {
                return text
            }

            if let content = item["content"] as? [[String: Any]] {
                let text = content.compactMap { block -> String? in
                    guard string(for: "type", in: block)?.lowercased() == "text" else {
                        return nil
                    }
                    return string(for: "text", in: block)
                }.joined()
                if text.isEmpty == false {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            return ""
        }

        private func codexToolAnnouncement(for item: [String: Any]) -> String {
            let itemType = string(for: "type", in: item)?.lowercased() ?? ""
            guard itemType.contains("agentmessage") == false else {
                return ""
            }

            let label = codexToolLabel(for: item)
            if let command = codexString(in: item, keys: ["command", "cmd", "title", "summary"]) {
                return label == "subagent"
                    ? "subagent: \(previewText(command, limit: 80))" : previewText(command, limit: 120)
            }

            if label == "subagent" {
                if let agent = codexString(in: item, keys: ["agent", "agentName"]) {
                    if let task = codexString(in: item, keys: ["task", "prompt"]) {
                        return "subagent \(agent): \(previewText(task, limit: 80))"
                    }
                    return "subagent \(agent)"
                }
                if let task = codexString(in: item, keys: ["task", "prompt"]) {
                    return "subagent: \(previewText(task, limit: 80))"
                }
                return "subagent"
            }

            return label == "tool" ? "" : label
        }

        private func codexToolLabel(for item: [String: Any]) -> String {
            let itemType = string(for: "type", in: item)?.lowercased() ?? ""
            if itemType.contains("subagent") || itemType.contains("delegate") || itemType.contains("task") {
                return "subagent"
            }
            if itemType.contains("command") {
                return "command"
            }
            if itemType.contains("filechange") || itemType.contains("patch") || itemType.contains("diff") {
                return "diff"
            }
            if itemType.contains("reason") || itemType.contains("thinking") {
                return "thinking"
            }
            return itemType.isEmpty ? "tool" : itemType
        }

        private func codexToolOutputText(from item: [String: Any]) -> String {
            codexToolOutputText(from: item as Any)
        }

        private func codexToolOutputText(from value: Any?) -> String {
            switch value {
            case let string as String:
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            case let object as [String: Any]:
                if let text = codexString(in: object, keys: ["output", "text", "delta", "message", "summary"]) {
                    return text
                }

                for key in ["content", "result"] {
                    let text = codexToolOutputText(from: object[key])
                    if text.isEmpty == false {
                        return text
                    }
                }

                return ""
            case let array as [Any]:
                let text =
                    array
                    .map { codexToolOutputText(from: $0) }
                    .filter { $0.isEmpty == false }
                    .joined()
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                return ""
            }
        }

        private func codexItemIsError(_ item: [String: Any]) -> Bool {
            if item["isError"] as? Bool == true {
                return true
            }
            if let status = string(for: "status", in: item)?.lowercased(),
                status.contains("error") || status.contains("failed")
            {
                return true
            }
            if let result = item["result"] as? [String: Any] {
                return codexItemIsError(result)
            }
            return false
        }

        private func codexString(in object: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let value = string(for: key, in: object)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    value.isEmpty == false
                {
                    return value
                }
            }
            return nil
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

        private func previewText(_ text: String, limit: Int) -> String {
            guard text.count > limit else {
                return text
            }
            return String(text.prefix(limit)) + "…"
        }

        private func handleTermination(status: Int32) {
            let shouldNotify: Bool
            let statusMessage: String
            let resolvedState: Session.State

            lock.lock()
            resolvedState = didRequestStop ? .exited : unexpectedTerminationState
            shouldNotify = runtimeState != resolvedState || didRequestStop == false
            runtimeState = resolvedState
            isTurnInProgress = false
            statusMessage = didRequestStop ? "" : unexpectedTerminationMessageBuilder(status)
            let trimmedStatusMessage = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStatusMessage.isEmpty == false {
                if resolvedState == .interrupted {
                    transcript = trimmedStatusMessage
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

        private func recordProviderEvent(rawPayload: String, object: [String: Any]) {
            let type = providerEventType(for: object)

            lock.lock()
            let event = SessionProviderEvent(
                sequence: nextProviderEventSequence,
                providerID: .codex,
                type: type,
                family: providerEventFamily(for: type),
                rawPayload: rawPayload
            )
            nextProviderEventSequence += 1
            providerEvents.append(event)
            providerEvents = StructuredSessionLiveHistoryRetention.retainedProviderEvents(providerEvents)
            providerFacts = providerFacts.appending(event, retainedProviderEventCount: providerEvents.count)
            lock.unlock()
        }

        private func providerEventType(for object: [String: Any]) -> String {
            if let method = string(for: "method", in: object) {
                return method
            }

            if object["error"] != nil {
                return "error"
            }

            return "response"
        }

        private func providerEventFamily(for type: String) -> SessionProviderEvent.Family {
            let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedType == "response" {
                return .response
            }
            if normalizedType.contains("thread") || normalizedType.contains("turn") {
                return .turn
            }
            if normalizedType.contains("item") || normalizedType.contains("approval") {
                return .toolExecution
            }
            if normalizedType.contains("message") {
                return .message
            }
            return .unknown
        }

        private func startupThreadParameters(workingDirectory: String, sessionLinkage: CodexSessionLinkage?) -> [String:
            Any]
        {
            if let threadID = sessionLinkage?.threadID?.trimmingCharacters(in: .whitespacesAndNewlines),
                threadID.isEmpty == false
            {
                return ["threadId": threadID, "cwd": workingDirectory]
            }

            return ["cwd": workingDirectory, "serviceName": "nexus"]
        }

        private func resolvedThreadID(from object: [String: Any]) -> String? {
            if let result = object["result"] as? [String: Any],
                let thread = result["thread"] as? [String: Any],
                let threadID = trimmedString(for: "id", in: thread)
            {
                return threadID
            }

            if let params = object["params"] as? [String: Any],
                let thread = params["thread"] as? [String: Any],
                let threadID = trimmedString(for: "id", in: thread)
            {
                return threadID
            }

            if let result = object["result"] as? [String: Any],
                let threadID = trimmedString(for: "threadId", in: result)
            {
                return threadID
            }

            if let params = object["params"] as? [String: Any],
                let threadID = trimmedString(for: "threadId", in: params)
            {
                return threadID
            }

            return nil
        }

        private func rpcErrorMessage(from object: [String: Any]) -> String? {
            guard let error = object["error"] as? [String: Any] else {
                return nil
            }
            return string(for: "message", in: error) ?? "Codex app-server startup failed."
        }

        private func shouldRetryStartupWithFreshThread(after error: String) -> Bool {
            let normalizedError = error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalizedError.contains("no rollout found for thread id")
                || normalizedError.contains("invalid thread id")
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

            activityItems.append(SessionActivityItem(id: item.id, kind: item.kind, text: trimmedText))
            activityItems = StructuredSessionLiveHistoryRetention.retainedActivityItems(activityItems)
        }

        private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
            let now = DispatchTime.now().uptimeNanoseconds
            return Int((now >= startedAt ? now - startedAt : 0) / 1_000_000)
        }

        private func sessionWithCurrentState(_ session: Session) -> Session {
            Session(
                id: session.id,
                workspaceID: session.workspaceID,
                providerID: session.providerID,
                name: session.name,
                isDefault: session.isDefault,
                state: runtimeState,
                failureMessage: session.failureMessage
            )
        }

        private func notifyChange() {
            let handler: (@Sendable () -> Void)?
            lock.lock()
            handler = changeHandler
            lock.unlock()
            handler?()
        }

        private static func jsonLine(_ object: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CodexAppServerRuntimeError.startupFailed("Failed to encode Codex app-server command.")
            }
            return line
        }
    }

    private final class CodexStartupState: @unchecked Sendable {
        private let lock = NSLock()
        private var resolvedError: Error?
        private var initialized = false
        private var resolvedThread = false

        var error: Error? {
            lock.lock()
            defer { lock.unlock() }
            return resolvedError
        }

        var didInitialize: Bool {
            lock.lock()
            defer { lock.unlock() }
            return initialized
        }

        var didResolveThread: Bool {
            lock.lock()
            defer { lock.unlock() }
            return resolvedThread
        }

        func markInitialized() {
            lock.lock()
            initialized = true
            lock.unlock()
        }

        func markResolvedThread() {
            lock.lock()
            resolvedThread = true
            lock.unlock()
        }

        func record(error: Error) {
            lock.lock()
            if resolvedError == nil {
                resolvedError = error
            }
            lock.unlock()
        }

        func recordUnexpectedTerminationIfNeeded(termination: CodexAppServerTermination) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard resolvedThread == false else {
                return false
            }
            if resolvedError == nil {
                let stderr = termination.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
                let message =
                    if let stderr, stderr.isEmpty == false {
                        normalizedCodexRemoteStartupFailureMessage(stderr)
                    } else if termination.status == 0 {
                        "Codex app-server exited before startup completed."
                    } else {
                        "Codex app-server exited with status \(termination.status) before startup completed."
                    }
                resolvedError = CodexAppServerRuntimeError.startupFailed(message)
            }
            return true
        }
    }

    final class ProcessCodexAppServerTransport: CodexAppServerTransporting, @unchecked Sendable {
        private struct ProcessInvocation {
            let executable: String
            let arguments: [String]
        }

        private let executable: String
        private let arguments: [String]
        private let workingDirectory: String?
        private let environment: [String: String]?
        private let lock = NSLock()
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (CodexAppServerTermination) -> Void)?
        private var process: Process?
        private var stdinHandle: FileHandle?
        private var stdoutHandle: FileHandle?
        private var stderrHandle: FileHandle?
        private var stdoutBuffer = Data()
        private var stderrBuffer = Data()

        init(executable: String, arguments: [String], workingDirectory: String?, environment: [String: String]? = nil)
            throws
        {
            self.executable = executable
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.environment = environment
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            lock.lock()
            stdoutLineHandler = handler
            lock.unlock()
        }

        func setTerminationHandler(_ handler: (@Sendable (CodexAppServerTermination) -> Void)?) {
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
            stderrHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard data.isEmpty == false else {
                    handle.readabilityHandler = nil
                    return
                }
                self?.consumeStderr(data)
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
                throw CodexAppServerRuntimeError.startupFailed("Failed to encode Codex app-server input.")
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
                handler?(line)
            }
        }

        private func consumeStderr(_ data: Data) {
            lock.lock()
            stderrBuffer.append(data)
            lock.unlock()
        }

        private func handleTermination(_ status: Int32) {
            let handler: (@Sendable (CodexAppServerTermination) -> Void)?
            let stderr: String?
            lock.lock()
            stdoutHandle?.readabilityHandler = nil
            stderrHandle?.readabilityHandler = nil
            if let stderrHandle, status != 0, stderrBuffer.isEmpty {
                let remainingStderr = stderrHandle.readDataToEndOfFile()
                if remainingStderr.isEmpty == false {
                    stderrBuffer.append(remainingStderr)
                }
            }
            handler = terminationHandler
            let stderrText = String(data: stderrBuffer, encoding: .utf8)?
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            stderr = stderrText?.isEmpty == false ? stderrText : nil
            lock.unlock()
            handler?(CodexAppServerTermination(status: status, stderr: stderr))
        }
    }
#endif
