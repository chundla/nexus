#if os(macOS)
    import Foundation
    import NexusDomain

    enum ClaudeStreamJSONRuntimeError: LocalizedError {
        case approvalRequestNotFound

        var errorDescription: String? {
            switch self {
            case .approvalRequestNotFound:
                "That Claude Approval Request is no longer pending."
            }
        }
    }

    protocol ClaudeStreamJSONTransporting: AnyObject {
        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?)
        func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?)
        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?)
        func start() throws
        func sendLine(_ line: String) throws
        func terminate() throws
    }

    /// Mirrors the stream-json contract captured in `docs/agents/claude-stream-json-protocol.md` (issue #249):
    /// `-p --input-format stream-json --output-format stream-json` requires `--verbose`, and `--session-id` /
    /// `--resume` are the only supported ways to fix the Claude session id Nexus persists for relaunch.
    final class ClaudeStreamJSONRuntime: SessionRuntime, @unchecked Sendable {
        typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws
            -> any ClaudeStreamJSONTransporting

        private let lock = NSLock()
        private let transport: any ClaudeStreamJSONTransporting
        private let unexpectedTerminationMessageBuilder: (Int32) -> String
        private let unexpectedTerminationState: Session.State
        private let stopHandler: (() throws -> Void)?
        private var runtimeState: Session.State = .ready
        private var terminalColumns = 80
        private var terminalRows = 24
        private var draft = ""
        private var activityItems: [SessionActivityItem]
        private var sessionLinkage: ClaudeSessionLinkage?
        private var toolNamesByUseID: [String: String] = [:]
        private var isTurnInProgress = false
        private var stderrLines: [String] = []
        private var changeHandler: (@Sendable () -> Void)?
        private let approvalHookBridge: any ClaudeApprovalHookBridging
        private var approvalRequests: [SessionApprovalRequest] = []
        private var pendingApprovalHookRequestIDs: [UUID: String] = [:]
        private var didRequestStop = false

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

        convenience init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: ClaudeSessionLinkage? = nil,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State = .exited,
            unexpectedTerminationMessageBuilder: ((Int32) -> String)? = nil,
            processEnvironment: [String: String]? = nil,
            stopHandler: (() throws -> Void)? = nil,
            sessionIDGenerator: @escaping () -> String = { UUID().uuidString },
            approvalHookBridge: (any ClaudeApprovalHookBridging)? = nil,
            transportFactory: TransportFactory? = nil
        ) throws {
            let resolvedTransportFactory =
                transportFactory ?? { executable, arguments, workingDirectory in
                    ProcessClaudeStreamJSONTransport(
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
                unexpectedTerminationMessageBuilder: unexpectedTerminationMessageBuilder
                    ?? terminationStatusMessageBuilder,
                stopHandler: stopHandler,
                sessionIDGenerator: sessionIDGenerator,
                approvalHookBridge: approvalHookBridge ?? ClaudeApprovalHookBridge(),
                transportFactory: resolvedTransportFactory
            )
        }

        init(
            executable: String,
            workingDirectory: String,
            sessionLinkage: ClaudeSessionLinkage?,
            terminationStatusMessageBuilder: @escaping (Int32) -> String,
            unexpectedTerminationState: Session.State,
            unexpectedTerminationMessageBuilder: @escaping (Int32) -> String,
            stopHandler: (() throws -> Void)?,
            sessionIDGenerator: @escaping () -> String,
            approvalHookBridge: any ClaudeApprovalHookBridging,
            transportFactory: TransportFactory
        ) throws {
            self.unexpectedTerminationMessageBuilder = unexpectedTerminationMessageBuilder
            self.unexpectedTerminationState = unexpectedTerminationState
            self.stopHandler = stopHandler
            self.activityItems = Self.defaultActivityItems
            self.approvalHookBridge = approvalHookBridge
            let isResuming = sessionLinkage?.isEmpty == false
            let resolvedLinkage =
                isResuming
                ? sessionLinkage
                : ClaudeSessionLinkage(claudeSessionID: sessionIDGenerator())
            self.sessionLinkage = resolvedLinkage

            try approvalHookBridge.start()
            self.transport = try transportFactory(
                executable,
                Self.launchArguments(
                    workingDirectory: workingDirectory, sessionLinkage: resolvedLinkage, isResuming: isResuming,
                    approvalHookSettingsJSON: approvalHookBridge.settingsJSON),
                workingDirectory
            )

            transport.setStdoutLineHandler { [weak self] line in
                self?.handleStdoutLine(line)
            }
            transport.setStderrLineHandler { [weak self] line in
                self?.handleStderrLine(line)
            }
            transport.setTerminationHandler { [weak self] status in
                self?.handleTermination(status: status)
            }
            try transport.start()

            approvalHookBridge.setRequestHandler { [weak self] request in
                self?.handleApprovalHookRequest(request)
            }
        }

        func sessionScreen(for session: Session) -> SessionScreen {
            lock.lock()
            let state = runtimeState
            let activityItems = activityItems
            let terminalColumns = terminalColumns
            let terminalRows = terminalRows
            let turnInProgress = isTurnInProgress
            let approvalRequests = approvalRequests
            lock.unlock()

            return SessionScreen(
                session: Session(
                    id: session.id,
                    workspaceID: session.workspaceID,
                    providerID: session.providerID,
                    name: session.name,
                    isDefault: session.isDefault,
                    state: state,
                    failureMessage: session.failureMessage
                ),
                primarySurface: .structuredActivityFeed,
                transcript: renderedTranscriptLocked(activityItems: activityItems),
                terminalColumns: terminalColumns,
                terminalRows: terminalRows,
                activityItems: activityItems,
                approvalRequests: approvalRequests,
                isAgentTurnInProgress: turnInProgress
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
            approvalHookBridge.stop()
            try stopHandler?()
            try transport.terminate()
            notifyChange()
        }

        func sendInput(_ text: String) throws {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return
            }

            lock.lock()
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "You: \(trimmed)"))
            isTurnInProgress = true
            lock.unlock()
            notifyChange()

            let payload: [String: Any] = [
                "type": "user",
                "message": [
                    "role": "user",
                    "content": [["type": "text", "text": trimmed]],
                ],
            ]
            try transport.sendLine(Self.jsonLine(payload))
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
                draft = ""
                lock.unlock()
                try sendInput(prompt)
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
            guard let hookRequestID = pendingApprovalHookRequestIDs[approvalRequestID],
                let index = approvalRequests.firstIndex(where: { $0.id == approvalRequestID && $0.state == .pending })
            else {
                lock.unlock()
                throw ClaudeStreamJSONRuntimeError.approvalRequestNotFound
            }
            let request = approvalRequests[index]
            lock.unlock()

            try approvalHookBridge.resolve(
                requestID: hookRequestID,
                decision: decision == .approve ? .allow : .deny,
                reason: decision == .approve
                    ? "Approved by the Nexus Controller." : "Denied by the Nexus Controller."
            )

            lock.lock()
            pendingApprovalHookRequestIDs.removeValue(forKey: approvalRequestID)
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

        private func handleApprovalHookRequest(_ request: ClaudeApprovalHookRequest) {
            let approvalRequest = SessionApprovalRequest(
                title: request.toolName,
                text: request.toolInputPreview.map { "\(request.toolName): \($0)" } ?? request.toolName,
                state: .pending
            )

            lock.lock()
            approvalRequests.append(approvalRequest)
            pendingApprovalHookRequestIDs[approvalRequest.id] = request.id
            appendActivityItemLocked(
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: \(approvalRequest.title)"))
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

        private func handleStdoutLine(_ line: String) {
            guard let object = jsonObject(from: line) else {
                return
            }

            lock.lock()
            if let sessionID = stringValue(in: object, keys: ["session_id"]), sessionID.isEmpty == false {
                sessionLinkage = ClaudeSessionLinkage(claudeSessionID: sessionID)
            }

            switch stringValue(in: object, keys: ["type"]) {
            case "system":
                handleSystemEventLocked(object)
            case "assistant":
                handleAssistantEventLocked(object)
            case "user":
                handleUserToolResultEventLocked(object)
            case "result":
                handleResultEventLocked(object)
            default:
                break
            }
            lock.unlock()
            notifyChange()
        }

        private func handleSystemEventLocked(_ object: [String: Any]) {
            guard stringValue(in: object, keys: ["subtype"]) == "init" else {
                return
            }
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Claude Session started."))
        }

        private func handleAssistantEventLocked(_ object: [String: Any]) {
            guard let message = object["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else {
                return
            }

            for block in content {
                guard let blockType = stringValue(in: block, keys: ["type"]) else {
                    continue
                }
                switch blockType {
                case "text":
                    if let text = stringValue(in: block, keys: ["text"]), text.isEmpty == false {
                        appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Claude: \(text)"))
                    }
                case "thinking":
                    if let text = stringValue(in: block, keys: ["thinking"]), text.isEmpty == false {
                        appendActivityItemLocked(
                            SessionActivityItem(kind: .message, text: "Claude (thinking): \(text)"))
                    }
                case "tool_use":
                    let toolName = stringValue(in: block, keys: ["name"]) ?? "Tool"
                    if let toolUseID = stringValue(in: block, keys: ["id"]) {
                        toolNamesByUseID[toolUseID] = toolName
                    }
                    let preview = toolInputPreview(block["input"])
                    let text = preview.map { "\(toolName): \($0)" } ?? toolName
                    appendActivityItemLocked(SessionActivityItem(kind: .command, text: text))
                default:
                    break
                }
            }
        }

        private func handleUserToolResultEventLocked(_ object: [String: Any]) {
            guard let message = object["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else {
                return
            }

            for block in content {
                guard stringValue(in: block, keys: ["type"]) == "tool_result" else {
                    continue
                }

                let toolUseID = stringValue(in: block, keys: ["tool_use_id"])
                let toolLabel = toolUseID.flatMap { toolNamesByUseID[$0] }
                let text = toolResultText(block["content"]) ?? "Claude tool result"
                let isError = (block["is_error"] as? Bool) ?? false

                if isError {
                    appendActivityItemLocked(SessionActivityItem(kind: .error, text: text))
                } else {
                    let labeled = toolLabel.map { "\($0): \(text)" } ?? text
                    appendActivityItemLocked(SessionActivityItem(kind: .message, text: labeled))
                }
            }
        }

        private func handleResultEventLocked(_ object: [String: Any]) {
            isTurnInProgress = false
            let subtype = stringValue(in: object, keys: ["subtype"]) ?? "unknown"
            if subtype == "success" {
                let text = stringValue(in: object, keys: ["result"]) ?? "Claude turn complete."
                appendActivityItemLocked(SessionActivityItem(kind: .completion, text: text))
            } else {
                let text = stringValue(in: object, keys: ["result", "error"]) ?? "Claude turn ended with an error."
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: text))
            }
        }

        private func handleStderrLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return
            }
            lock.lock()
            stderrLines.append(trimmed)
            lock.unlock()
        }

        private func handleTermination(status: Int32) {
            let shouldNotify: Bool

            lock.lock()
            let wasTurnInProgress = isTurnInProgress
            isTurnInProgress = false
            if didRequestStop {
                shouldNotify = runtimeState != .exited
                runtimeState = .exited
            } else if status != 0 {
                runtimeState = unexpectedTerminationState
                let stderr = stderrLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let message = stderr.isEmpty == false ? stderr : unexpectedTerminationMessageBuilder(status)
                appendActivityItemLocked(
                    SessionActivityItem(
                        kind: .error,
                        text: message
                    ))
                shouldNotify = true
            } else {
                if wasTurnInProgress {
                    runtimeState = .ready
                }
                shouldNotify = wasTurnInProgress
            }
            stderrLines = []
            lock.unlock()

            if shouldNotify {
                notifyChange()
            }
        }

        private func appendActivityItemLocked(_ item: SessionActivityItem) {
            activityItems.append(item)
        }

        private func renderedTranscriptLocked(activityItems: [SessionActivityItem]) -> String {
            activityItems.map(\.text).joined(separator: "\n")
        }

        private func notifyChange() {
            let handler: (@Sendable () -> Void)?
            lock.lock()
            handler = changeHandler
            lock.unlock()
            handler?()
        }

        private func toolInputPreview(_ input: Any?) -> String? {
            guard let input = input as? [String: Any], input.isEmpty == false else {
                return nil
            }
            if let path = stringValue(in: input, keys: ["file_path", "path"]) {
                return path
            }
            if let command = stringValue(in: input, keys: ["command"]) {
                return command
            }
            guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
                let json = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return json.count > 120 ? String(json.prefix(120)) + "…" : json
        }

        private func toolResultText(_ content: Any?) -> String? {
            if let text = content as? String {
                return text
            }
            if let blocks = content as? [[String: Any]] {
                let text = blocks.compactMap { stringValue(in: $0, keys: ["text"]) }.joined(separator: "\n")
                return text.isEmpty ? nil : text
            }
            return nil
        }

        private func jsonObject(from line: String) -> [String: Any]? {
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }
            return object
        }

        private func stringValue(in object: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty == false {
                        return trimmed
                    }
                }
            }
            return nil
        }

        private static var defaultActivityItems: [SessionActivityItem] {
            [SessionActivityItem(kind: .status, text: "Claude Session ready. Send a prompt to start Claude.")]
        }

        static func launchArguments(
            workingDirectory: String, sessionLinkage: ClaudeSessionLinkage?, isResuming: Bool,
            approvalHookSettingsJSON: String
        ) -> [String] {
            var arguments = [
                "-p",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--include-partial-messages",
                "--verbose",
                "--permission-mode", "default",
                "--add-dir", workingDirectory,
            ]
            if let sessionID = sessionLinkage?.claudeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                sessionID.isEmpty == false
            {
                arguments += [isResuming ? "--resume" : "--session-id", sessionID]
            }
            arguments += ["--settings", approvalHookSettingsJSON]
            return arguments
        }

        private static func jsonLine(_ payload: [String: Any]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8)
            else {
                return "{}"
            }
            return json
        }
    }

    final class ProcessClaudeStreamJSONTransport: ClaudeStreamJSONTransporting, @unchecked Sendable {
        private let executable: String
        private let arguments: [String]
        private let workingDirectory: String?
        private let environment: [String: String]?
        private let lock = NSLock()
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private var process: Process?
        private var stdinHandle: FileHandle?
        private var stdoutHandle: FileHandle?
        private var stderrHandle: FileHandle?
        private var stdoutBuffer = Data()
        private var stderrBuffer = Data()

        init(executable: String, arguments: [String], workingDirectory: String?, environment: [String: String]? = nil) {
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

        func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            lock.lock()
            stderrLineHandler = handler
            lock.unlock()
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            lock.lock()
            terminationHandler = handler
            lock.unlock()
        }

        func start() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
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
                return
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
            var lines: [String] = []
            let handler: (@Sendable (String) -> Void)?

            lock.lock()
            stderrBuffer.append(data)
            while let newlineIndex = stderrBuffer.firstIndex(of: 0x0A) {
                let lineData = stderrBuffer.prefix(upTo: newlineIndex)
                stderrBuffer.removeSubrange(...newlineIndex)
                if let line = String(data: lineData, encoding: .utf8)?.replacingOccurrences(of: "\r", with: "") {
                    lines.append(line)
                }
            }
            handler = stderrLineHandler
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
