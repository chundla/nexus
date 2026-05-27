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

    var errorDescription: String? {
        switch self {
        case .startupTimedOut:
            return "Pi RPC mode did not finish startup in time."
        case let .startupFailed(message):
            return message
        case .busy:
            return "Pi is already handling a prompt. Wait for the current turn to finish before sending another one."
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

    private let lock = NSLock()
    private let transport: any PiRPCTransporting
    private let terminationStatusMessageBuilder: (Int32) -> String
    private let startupResponseID = "nexus-pi-startup"
    private var runtimeState: Session.State = .ready
    private var transcriptEntries: [String] = []
    private var draft = ""
    private var activityItems: [SessionActivityItem] = []
    private var terminalColumns = 80
    private var terminalRows = 24
    private var changeHandler: (@Sendable () -> Void)?
    private var isStreaming = false
    private var assistantTranscriptIndex: Int?
    private var currentAssistantText = ""
    private var didRequestStop = false

    init(
        executable: String,
        workingDirectory: String,
        terminationStatusMessageBuilder: @escaping (Int32) -> String,
        transportFactory: TransportFactory = { executable, arguments, workingDirectory in
            try ProcessPiRPCTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }
    ) throws {
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
        self.transport = try transportFactory(executable, ["--mode", "rpc", "--no-session"], workingDirectory)

        let startupSemaphore = DispatchSemaphore(value: 0)
        let startupState = StartupState()

        transport.setStdoutLineHandler { [weak self] line in
            guard let self else { return }

            if let response = self.responseObject(from: line),
               self.string(for: "type", in: response) == "response",
               self.string(for: "id", in: response) == self.startupResponseID {
                if self.bool(for: "success", in: response) == true {
                    self.appendActivityItemLocked(SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"))
                } else {
                    let errorMessage = self.string(for: "error", in: response) ?? "Pi RPC startup failed."
                    startupState.error = PiRPCSessionRuntimeError.startupFailed(errorMessage)
                }
                startupSemaphore.signal()
                return
            }

            self.handleOutputLine(line)
        }
        transport.setTerminationHandler { [weak self] status in
            self?.handleTermination(status: status)
        }

        try transport.start()
        try transport.sendLine(Self.jsonLine(["id": startupResponseID, "type": "get_state"]))

        guard startupSemaphore.wait(timeout: .now() + 5) == .success else {
            try? transport.terminate()
            throw PiRPCSessionRuntimeError.startupTimedOut
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
            transcript: renderedTranscriptLocked(),
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems
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
        case "turn_end":
            handleTurnEnd(object)
        default:
            return
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

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let line = String(data: data, encoding: .utf8) else {
            throw PiRPCSessionRuntimeError.startupFailed("Failed to encode Pi RPC command.")
        }
        return line
    }
}

private final class StartupState: @unchecked Sendable {
    var error: Error?
}

final class ProcessPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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
