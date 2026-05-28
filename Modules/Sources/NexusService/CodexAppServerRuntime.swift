#if os(macOS)
import Foundation
import NexusDomain

protocol CodexAppServerTransporting: AnyObject {
    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?)
    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?)
    func start() throws
    func sendLine(_ line: String) throws
    func terminate() throws
}

enum CodexAppServerRuntimeError: LocalizedError {
    case startupTimedOut
    case startupFailed(String)
    case approvalRequestNotFound

    var errorDescription: String? {
        switch self {
        case .startupTimedOut:
            return "Codex app-server did not finish startup in time."
        case let .startupFailed(message):
            return message
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
        case let .string(string):
            string
        case let .number(number):
            number
        }
    }
}

private struct PendingCodexApprovalRequest: Sendable {
    let requestID: CodexJSONRPCRequestID
}

final class CodexAppServerRuntime: SessionRuntime, @unchecked Sendable {
    typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any CodexAppServerTransporting

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
    private let terminationStatusMessageBuilder: (Int32) -> String
    private let initializeRequestID = "nexus-codex-initialize"
    private let startupThreadRequestID = "nexus-codex-thread-start"
    private var runtimeState: Session.State = .ready
    private var terminalColumns = 80
    private var terminalRows = 24
    private var transcript = ""
    private var activityItems: [SessionActivityItem] = []
    private var approvalRequests: [SessionApprovalRequest] = []
    private var pendingApprovalRequests: [UUID: PendingCodexApprovalRequest] = [:]
    private var pendingTurnRequestIDs: Set<String> = []
    private var nextTurnRequestSequence = 0
    private var completedAgentMessageItemIDs: Set<String> = []
    private var didAnnounceConnectedStatus = false
    private var sessionLinkage: CodexSessionLinkage?
    private var changeHandler: (@Sendable () -> Void)?
    private var didRequestStop = false

    init(
        executable: String,
        workingDirectory: String,
        sessionLinkage: CodexSessionLinkage? = nil,
        terminationStatusMessageBuilder: @escaping (Int32) -> String,
        transportFactory: TransportFactory = { executable, arguments, workingDirectory in
            try ProcessCodexAppServerTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }
    ) throws {
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
        self.sessionLinkage = sessionLinkage
        self.transport = try transportFactory(executable, ["app-server"], workingDirectory)

        let startupSemaphore = DispatchSemaphore(value: 0)
        let startupState = CodexStartupState()
        let shouldAttemptStartupResume = sessionLinkage?.isEmpty == false
        let startupFreshThreadFallbackRequestID = "nexus-codex-thread-start-fallback"

        transport.setStdoutLineHandler { [weak self] line in
            guard let self, let object = self.responseObject(from: line) else {
                return
            }

            let id = self.string(for: "id", in: object)
            if id == self.initializeRequestID {
                startupState.markInitialized()
                startupSemaphore.signal()
                return
            }

            if id == self.startupThreadRequestID || id == startupFreshThreadFallbackRequestID {
                if self.captureThreadLinkage(from: object, appendConnectedStatus: true) {
                    startupState.markResolvedThread()
                    startupSemaphore.signal()
                    return
                }

                if let error = self.rpcErrorMessage(from: object) {
                    if id == self.startupThreadRequestID,
                       shouldAttemptStartupResume,
                       self.shouldRetryStartupWithFreshThread(after: error) {
                        do {
                            try self.transport.sendLine(Self.jsonLine([
                                "jsonrpc": "2.0",
                                "id": startupFreshThreadFallbackRequestID,
                                "method": "thread/start",
                                "params": self.startupThreadParameters(workingDirectory: workingDirectory, sessionLinkage: nil)
                            ]))
                        } catch {
                            startupState.record(error: error)
                            startupSemaphore.signal()
                        }
                        return
                    }

                    startupState.record(error: CodexAppServerRuntimeError.startupFailed(error))
                    startupSemaphore.signal()
                }
                return
            }

            if let error = self.rpcErrorMessage(from: object), startupState.didResolveThread == false {
                startupState.record(error: CodexAppServerRuntimeError.startupFailed(error))
                startupSemaphore.signal()
                return
            }

            if self.handleStartupThreadNotification(object, startupState: startupState, startupSemaphore: startupSemaphore) {
                return
            }

            if startupState.didResolveThread {
                if self.handleRequestResponse(object) {
                    return
                }
                self.handleNotification(object)
            }
        }
        transport.setTerminationHandler { [weak self] status in
            if startupState.recordUnexpectedTerminationIfNeeded(status: status) {
                startupSemaphore.signal()
            }
            self?.handleTermination(status: status)
        }

        try transport.start()
        try transport.sendLine(Self.jsonLine([
            "jsonrpc": "2.0",
            "id": initializeRequestID,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "nexus",
                    "version": "1"
                ]
            ]
        ]))

        guard startupSemaphore.wait(timeout: .now() + 5) == .success, startupState.didInitialize else {
            try? transport.terminate()
            throw startupState.error ?? CodexAppServerRuntimeError.startupTimedOut
        }

        try transport.sendLine(Self.jsonLine([
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ]))
        try transport.sendLine(Self.jsonLine([
            "jsonrpc": "2.0",
            "id": startupThreadRequestID,
            "method": shouldAttemptStartupResume ? "thread/resume" : "thread/start",
            "params": startupThreadParameters(workingDirectory: workingDirectory, sessionLinkage: sessionLinkage)
        ]))

        guard startupSemaphore.wait(timeout: .now() + 5) == .success, startupState.didResolveThread else {
            try? transport.terminate()
            throw startupState.error ?? CodexAppServerRuntimeError.startupTimedOut
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
            session: sessionWithCurrentState(session),
            primarySurface: .structuredActivityFeed,
            transcript: transcript,
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
              resolvedThreadID.isEmpty == false else {
            lock.unlock()
            throw CodexAppServerRuntimeError.startupFailed("Codex Session thread ID is unavailable.")
        }
        threadID = resolvedThreadID
        nextTurnRequestSequence += 1
        requestID = "nexus-codex-turn-\(nextTurnRequestSequence)"
        pendingTurnRequestIDs.insert(requestID)
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
                        "input": [[
                            "type": "text",
                            "text": trimmed
                        ]]
                    ]
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
              let index = approvalRequests.firstIndex(where: { $0.id == approvalRequestID && $0.state == .pending }) else {
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
                ]
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

        let shouldHandle: Bool
        lock.lock()
        shouldHandle = pendingTurnRequestIDs.contains(id)
        if shouldHandle {
            pendingTurnRequestIDs.remove(id)
        }
        lock.unlock()

        guard shouldHandle else {
            return false
        }

        if let error = rpcErrorMessage(from: object) {
            lock.lock()
            appendActivityItemLocked(SessionActivityItem(kind: .error, text: error))
            lock.unlock()
            notifyChange()
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
               let message = string(for: "message", in: params) {
                lock.lock()
                appendActivityItemLocked(SessionActivityItem(kind: .error, text: message))
                lock.unlock()
                notifyChange()
            }
        case "thread/started", "thread/resumed":
            if captureThreadLinkage(from: object, appendConnectedStatus: true) {
                notifyChange()
            }
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
        startupSemaphore: DispatchSemaphore
    ) -> Bool {
        guard startupState.didResolveThread == false,
              let method = string(for: "method", in: object),
              method == "thread/started" || method == "thread/resumed",
              captureThreadLinkage(from: object, appendConnectedStatus: true) else {
            return false
        }

        startupState.markResolvedThread()
        startupSemaphore.signal()
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
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Codex shared Session stream connected"))
            didAnnounceConnectedStatus = true
        }
        didChange = shouldUpdateThreadID || shouldAppendConnectedStatus
        lock.unlock()

        return didChange
    }

    private func handleCompletedItem(_ params: [String: Any]?) {
        guard let item = params?["item"] as? [String: Any],
              string(for: "type", in: item) == "agentMessage",
              let itemID = string(for: "id", in: item) else {
            return
        }

        let text = string(for: "text", in: item)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.isEmpty == false else {
            return
        }

        lock.lock()
        let inserted = completedAgentMessageItemIDs.insert(itemID).inserted
        if inserted {
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Codex: \(text)"))
        }
        lock.unlock()

        if inserted {
            notifyChange()
        }
    }

    private func handleCommandExecutionApprovalRequest(_ params: [String: Any]?, requestID: CodexJSONRPCRequestID?) {
        guard let requestID else {
            return
        }

        let command = params.flatMap { string(for: "command", in: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = params.flatMap { string(for: "reason", in: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let reason = params.flatMap { string(for: "reason", in: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = "File changes need approval"
        let text = reason?.isEmpty == false ? reason! : title

        registerApprovalRequest(
            SessionApprovalRequest(title: title, text: text, state: .pending),
            requestID: requestID
        )
    }

    private func registerApprovalRequest(_ approvalRequest: SessionApprovalRequest, requestID: CodexJSONRPCRequestID) {
        lock.lock()
        approvalRequests.append(approvalRequest)
        pendingApprovalRequests[approvalRequest.id] = PendingCodexApprovalRequest(requestID: requestID)
        appendActivityItemLocked(SessionActivityItem(kind: .approvalRequest, text: "Approval Request: \(approvalRequest.title)"))
        lock.unlock()
        notifyChange()
    }

    private func handleTermination(status: Int32) {
        let shouldNotify: Bool
        let statusMessage: String

        lock.lock()
        shouldNotify = runtimeState != .exited || didRequestStop == false
        runtimeState = .exited
        statusMessage = didRequestStop ? "" : terminationStatusMessageBuilder(status)
        if statusMessage.isEmpty == false {
            appendActivityItemLocked(SessionActivityItem(kind: .status, text: statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        lock.unlock()

        if shouldNotify {
            notifyChange()
        }
    }

    private func startupThreadParameters(workingDirectory: String, sessionLinkage: CodexSessionLinkage?) -> [String: Any] {
        if let threadID = sessionLinkage?.threadID?.trimmingCharacters(in: .whitespacesAndNewlines), threadID.isEmpty == false {
            return ["threadId": threadID, "cwd": workingDirectory]
        }

        return ["cwd": workingDirectory, "serviceName": "nexus"]
    }

    private func resolvedThreadID(from object: [String: Any]) -> String? {
        if let result = object["result"] as? [String: Any],
           let thread = result["thread"] as? [String: Any],
           let threadID = trimmedString(for: "id", in: thread) {
            return threadID
        }

        if let params = object["params"] as? [String: Any],
           let thread = params["thread"] as? [String: Any],
           let threadID = trimmedString(for: "id", in: thread) {
            return threadID
        }

        if let result = object["result"] as? [String: Any],
           let threadID = trimmedString(for: "threadId", in: result) {
            return threadID
        }

        if let params = object["params"] as? [String: Any],
           let threadID = trimmedString(for: "threadId", in: params) {
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

    func recordUnexpectedTerminationIfNeeded(status: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard resolvedThread == false else {
            return false
        }
        if resolvedError == nil {
            let message = status == 0
                ? "Codex app-server exited before startup completed."
                : "Codex app-server exited with status \(status) before startup completed."
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
