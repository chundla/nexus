#if os(macOS)
import Foundation
import NexusDomain

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

    private let lock = NSLock()
    private let transport: any PiRPCTransporting
    private let stopHandler: (() throws -> Void)?
    private let terminationStatusMessageBuilder: (Int32) -> String
    private let unexpectedTerminationState: Session.State
    private let unexpectedTerminationMessageBuilder: (Int32) -> String
    private let startupResponseID = "nexus-pi-startup"
    private var runtimeState: Session.State = .ready
    private var transcriptEntries: [String] = []
    private var interruptedFailureMessage: String?
    private var draft = ""
    private var activityItems: [SessionActivityItem] = []
    private var approvalRequests: [SessionApprovalRequest] = []
    private var terminalColumns = 80
    private var terminalRows = 24
    private var sessionLinkage: PiSessionLinkage?
    private var changeHandler: (@Sendable () -> Void)?
    private var isStreaming = false
    private var assistantTranscriptIndex: Int?
    private var currentAssistantText = ""
    private var didRequestStop = false

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
            guard let self else { return }

            if let response = self.responseObject(from: line),
               self.string(for: "type", in: response) == "response",
               self.string(for: "id", in: response) == self.startupResponseID {
                if self.bool(for: "success", in: response) == true {
                    self.lock.lock()
                    self.updateSessionLinkageLocked(from: response)
                    self.appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"))
                    self.lock.unlock()
                    startupWaiter.succeed()
                } else {
                    let errorMessage = self.string(for: "error", in: response) ?? "Pi RPC startup failed."
                    let startupError = PiRPCSessionRuntimeError.startupFailed(errorMessage)
                    startupState.record(error: startupError)
                    startupWaiter.fail(startupError)
                }
                return
            }

            self.handleOutputLine(line)
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
        try transport.sendLine(Self.jsonLine(["id": startupResponseID, "type": "get_state"]))

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
        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: runtimeState == .interrupted ? (interruptedFailureMessage ?? renderedTranscriptLocked()) : renderedTranscriptLocked(),
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests
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

        lock.lock()
        guard isStreaming == false else {
            lock.unlock()
            throw PiRPCSessionRuntimeError.busy
        }
        isStreaming = true
        draft = ""
        assistantTranscriptIndex = nil
        currentAssistantText = ""
        transcriptEntries.append("> \(trimmed)")
        appendActivityItemLocked(SessionActivityItem(kind: .message, text: "You: \(trimmed)"))
        lock.unlock()
        notifyChange()

        try transport.sendLine(
            Self.jsonLine([
                "type": "prompt",
                "message": trimmed
            ])
        )
    }

    private func handleOutputLine(_ line: String) {
        guard let object = responseObject(from: line),
              let type = string(for: "type", in: object) else {
            return
        }

        switch type {
        case "agent_start":
            return
        case "message_update":
            handleMessageUpdate(object)
        case "approval_request":
            handleApprovalRequest(object)
        case "turn_end":
            handleTurnEnd(object)
        default:
            return
        }
    }

    private func handleApprovalRequest(_ object: [String: Any]) {
        guard let rawID = string(for: "id", in: object),
              let id = UUID(uuidString: rawID) else {
            return
        }

        let title = string(for: "title", in: object) ?? "Approval Request"
        let text = string(for: "text", in: object) ?? title

        lock.lock()
        approvalRequests.removeAll { $0.id == id }
        approvalRequests.append(SessionApprovalRequest(id: id, title: title, text: text, state: .pending))
        appendActivityItemLocked(SessionActivityItem(kind: .approvalRequest, text: "Approval Request: \(title)"))
        lock.unlock()
        notifyChange()
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
        isStreaming = false
        lock.unlock()
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

    private func bool(for key: String, in object: [String: Any]) -> Bool? {
        object[key] as? Bool
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
