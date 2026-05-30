#if os(macOS)
import Foundation
import NexusDomain

protocol IBMBobTransporting: AnyObject {
    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?)
    func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?)
    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?)
    func start() throws
    func terminate() throws
}

enum IBMBobSessionRuntimeError: LocalizedError, Equatable {
    case busy
    case noActiveTurnToStop

    var errorDescription: String? {
        switch self {
        case .busy:
            return "IBM Bob is already handling a prompt. Wait for the current turn to finish before sending another one."
        case .noActiveTurnToStop:
            return "IBM Bob has no active turn to stop."
        }
    }
}

final class IBMBobSessionRuntime: SessionRuntime, @unchecked Sendable {
    typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any IBMBobTransporting

    private let executable: String
    private let workingDirectory: String
    private let terminationStatusMessageBuilder: (Int32) -> String
    private let unexpectedTerminationStateEvaluator: (Int32, String) -> Session.State
    private let transportFactory: TransportFactory
    private let lock = NSLock()
    private var sessionLinkage: IBMBobSessionLinkage?
    private var runtimeState: Session.State = .ready
    private var terminalColumns = 80
    private var terminalRows = 24
    private var draft = ""
    private var transcriptEntries: [String] = []
    private var activityItems: [SessionActivityItem]
    private let slashCommands: [SessionSlashCommand]?
    private var changeHandler: (@Sendable () -> Void)?
    private var activeTransport: (any IBMBobTransporting)?
    private var activeTurn: ActiveTurn?
    private var isStreaming = false
    private var stderrLines: [String] = []
    private var didRequestStop = false

    init(
        executable: String,
        workingDirectory: String,
        sessionLinkage: IBMBobSessionLinkage? = nil,
        terminationStatusMessageBuilder: @escaping (Int32) -> String,
        unexpectedTerminationState: Session.State = .failed,
        unexpectedTerminationStateEvaluator: ((Int32, String) -> Session.State)? = nil,
        transportFactory: @escaping TransportFactory = { executable, arguments, workingDirectory in
            try ProcessIBMBobTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }
    ) throws {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.sessionLinkage = sessionLinkage.map { IBMBobSessionLinkage(sessionID: $0.sessionID) }
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
        self.unexpectedTerminationStateEvaluator = unexpectedTerminationStateEvaluator ?? { _, _ in unexpectedTerminationState }
        self.transportFactory = transportFactory
        self.slashCommands = Self.discoverSlashCommands(executable: executable, workingDirectory: workingDirectory)
        let restoredActivityItems = sessionLinkage?.persistedActivityItems ?? []
        self.activityItems = restoredActivityItems.isEmpty ? Self.defaultActivityItems : restoredActivityItems
        self.transcriptEntries = Self.transcriptEntries(from: self.activityItems)
    }

    var state: Session.State {
        lock.lock()
        defer { lock.unlock() }
        return runtimeState
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        lock.lock()
        let sessionID = sessionLinkage?.sessionID
        let snapshotActivityItems = activityItems
        let turnInProgress = isStreaming
        lock.unlock()
        return SessionRecordAdapterMetadata.ibmBob(
            sessionID: sessionID,
            activityItems: snapshotActivityItems,
            turnInProgress: turnInProgress
        )
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let state = runtimeState
        let transcript = renderedTranscriptLocked()
        let terminalColumns = terminalColumns
        let terminalRows = terminalRows
        let activityItems = activityItems
        let isTurnInProgress = isStreaming
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
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            slashCommands: slashCommands,
            isAgentTurnInProgress: isTurnInProgress
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func stop() throws {
        let transport: any IBMBobTransporting
        lock.lock()
        guard isStreaming, let activeTransport else {
            lock.unlock()
            throw IBMBobSessionRuntimeError.noActiveTurnToStop
        }
        didRequestStop = true
        transport = activeTransport
        lock.unlock()

        try transport.terminate()
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
        throw NexusSessionApprovalError.approvalRequestsUnavailable
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
        let sessionLinkage = self.sessionLinkage
        lock.unlock()
        try startPrompt(
            trimmed,
            announceUserMessage: true,
            sessionLinkage: sessionLinkage
        )
    }

    private func handleStdoutLine(_ line: String) {
        guard let object = jsonObject(from: line) else {
            return
        }

        lock.lock()
        if let sessionID = resolvedSessionID(from: object) {
            sessionLinkage = IBMBobSessionLinkage(sessionID: sessionID)
        }
        guard let event = bobEvent(from: object) else {
            lock.unlock()
            return
        }
        switch event.kind {
        case .status:
            activityItems.append(SessionActivityItem(kind: .status, text: event.text))
        case .message:
            transcriptEntries.append(event.text)
            activityItems.append(SessionActivityItem(kind: .message, text: event.text))
        case .command:
            activityItems.append(SessionActivityItem(kind: .command, text: event.text))
        case .diff:
            activityItems.append(SessionActivityItem(kind: .diff, text: event.text))
        case .completion:
            activityItems.append(SessionActivityItem(kind: .completion, text: event.text))
        case .error:
            activityItems.append(SessionActivityItem(kind: .error, text: event.text))
        default:
            break
        }
        lock.unlock()
        notifyChange()
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
        let shouldAppendError: Bool
        let errorText: String
        let shouldNotify: Bool
        let retryPrompt: String?

        lock.lock()
        let requestedStop = didRequestStop
        let activeTurn = self.activeTurn
        errorText = resolvedTerminationErrorTextLocked(status: status)
        let shouldRetryFresh = requestedStop == false
            && status != 0
            && activeTurn?.resumedSessionID != nil
            && shouldRetryFreshTurnAfterInvalidContinuity(errorText)
        didRequestStop = false
        isStreaming = false
        activeTransport = nil
        self.activeTurn = nil
        shouldAppendError = requestedStop == false && status != 0 && shouldRetryFresh == false
        shouldNotify = shouldAppendError || requestedStop == false
        retryPrompt = shouldRetryFresh ? activeTurn?.prompt : nil
        if shouldRetryFresh {
            runtimeState = .ready
            sessionLinkage = nil
            activityItems.append(
                SessionActivityItem(
                    kind: .status,
                    text: "Stored IBM Bob continuity was unavailable. Started a fresh Bob conversation on this Session."
                )
            )
        } else if shouldAppendError {
            runtimeState = unexpectedTerminationStateEvaluator(status, errorText)
            activityItems.append(SessionActivityItem(kind: .error, text: errorText))
        } else {
            runtimeState = .ready
            if requestedStop {
                activityItems.append(SessionActivityItem(kind: .status, text: "IBM Bob turn stopped."))
            }
        }
        stderrLines = []
        lock.unlock()

        if let retryPrompt {
            notifyChange()
            retryFreshPrompt(retryPrompt)
            return
        }

        if shouldNotify || requestedStop {
            notifyChange()
        }
    }

    private func startPrompt(
        _ prompt: String,
        announceUserMessage: Bool,
        sessionLinkage: IBMBobSessionLinkage?
    ) throws {
        lock.lock()
        guard isStreaming == false else {
            lock.unlock()
            throw IBMBobSessionRuntimeError.busy
        }
        draft = ""
        didRequestStop = false
        stderrLines = []
        runtimeState = .ready
        if announceUserMessage {
            transcriptEntries.append("> \(prompt)")
            activityItems.append(SessionActivityItem(kind: .message, text: "You: \(prompt)"))
        }
        lock.unlock()
        notifyChange()

        let transport: any IBMBobTransporting
        do {
            transport = try transportFactory(
                executable,
                Self.launchArguments(prompt: prompt, sessionLinkage: sessionLinkage),
                workingDirectory
            )
        } catch {
            failPromptLaunch(error.localizedDescription)
            return
        }

        transport.setStdoutLineHandler { [weak self] line in
            self?.handleStdoutLine(line)
        }
        transport.setStderrLineHandler { [weak self] line in
            self?.handleStderrLine(line)
        }
        transport.setTerminationHandler { [weak self] status in
            self?.handleTermination(status: status)
        }

        lock.lock()
        isStreaming = true
        activeTransport = transport
        activeTurn = ActiveTurn(prompt: prompt, resumedSessionID: sessionLinkage?.sessionID)
        lock.unlock()
        notifyChange()

        do {
            try transport.start()
        } catch {
            failPromptLaunch(error.localizedDescription)
        }
    }

    private func failPromptLaunch(_ message: String) {
        let resolvedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "IBM Bob failed to start."
            : message.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        didRequestStop = false
        isStreaming = false
        activeTransport = nil
        activeTurn = nil
        runtimeState = .failed
        activityItems.append(SessionActivityItem(kind: .error, text: resolvedMessage))
        lock.unlock()
        notifyChange()
    }

    private func retryFreshPrompt(_ prompt: String) {
        do {
            try startPrompt(
                prompt,
                announceUserMessage: false,
                sessionLinkage: nil
            )
        } catch {
            lock.lock()
            activityItems.append(SessionActivityItem(kind: .error, text: error.localizedDescription))
            lock.unlock()
            notifyChange()
        }
    }

    private func shouldRetryFreshTurnAfterInvalidContinuity(_ errorText: String) -> Bool {
        let normalized = errorText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("invalid bob session")
            || normalized.contains("invalid session")
            || normalized.contains("session not found")
            || normalized.contains("resume") && normalized.contains("not found")
    }

    private func resolvedTerminationErrorTextLocked(status: Int32) -> String {
        let stderr = stderrLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if stderr.isEmpty == false {
            return stderr
        }

        let fallback = terminationStatusMessageBuilder(status).trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty == false ? fallback : "IBM Bob exited with status \(status)."
    }

    private func renderedTranscriptLocked() -> String {
        transcriptEntries.joined(separator: "\n")
    }

    private func notifyChange() {
        let handler: (@Sendable () -> Void)?
        lock.lock()
        handler = changeHandler
        lock.unlock()
        handler?()
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func bobEvent(from object: [String: Any]) -> BobEvent? {
        guard let rawType = stringValue(in: object, keys: ["type", "event"])?.lowercased() else {
            return nil
        }

        switch rawType {
        case "status", "agent_start", "turn_start":
            let text = stringValue(in: object, keys: ["text", "status", "message"]) ?? "IBM Bob turn started"
            return BobEvent(kind: .status, text: text)
        case "message", "assistant_message", "message_delta", "text":
            guard shouldProjectMessageEvent(rawType: rawType, object: object),
                  let text = messageText(in: object),
                  text.isEmpty == false else {
                return nil
            }
            return BobEvent(kind: .message, text: text)
        case "command", "tool_use":
            let explicitText = stringValue(in: object, keys: ["command", "text", "message"])
            let toolName = stringValue(in: object, keys: ["tool_name", "toolName", "name"])
            let parameterPreview = toolParameterPreview(in: object)
            let text = explicitText
                ?? {
                    if let toolName, let parameterPreview {
                        return "\(toolName): \(parameterPreview)"
                    }
                    return toolName
                }()
            guard let text, text.isEmpty == false else {
                return nil
            }
            return BobEvent(kind: .command, text: text)
        case "tool_result":
            if stringValue(in: object, keys: ["status"])?.lowercased() == "success" {
                guard let text = stringValue(in: object, keys: ["output", "text", "message", "result"]), text.isEmpty == false else {
                    return nil
                }
                return BobEvent(kind: .message, text: text)
            }
            let text = stringValue(in: object, keys: ["output", "text", "error", "message", "detail"]) ?? "IBM Bob reported an error."
            return BobEvent(kind: .error, text: text)
        case "diff", "patch":
            guard let text = stringValue(in: object, keys: ["text", "diff", "patch", "message"]), text.isEmpty == false else {
                return nil
            }
            return BobEvent(kind: .diff, text: text)
        case "completion", "turn_end", "done":
            let text = stringValue(in: object, keys: ["text", "message", "summary"]) ?? "IBM Bob turn complete"
            return BobEvent(kind: .completion, text: text)
        case "error", "tool_result_error":
            let text = stringValue(in: object, keys: ["text", "error", "message", "detail"]) ?? "IBM Bob reported an error."
            return BobEvent(kind: .error, text: text)
        default:
            return nil
        }
    }

    private func shouldProjectMessageEvent(rawType: String, object: [String: Any]) -> Bool {
        if rawType == "assistant_message" {
            return true
        }

        guard let role = messageRole(in: object) else {
            return true
        }

        switch role {
        case "assistant", "model", "ai", "bot", "tool":
            return true
        case "user", "human", "system":
            return false
        default:
            return true
        }
    }

    private func messageRole(in object: [String: Any]) -> String? {
        if let role = stringValue(in: object, keys: ["role", "author", "sender"])?.lowercased() {
            return role
        }

        if let message = object["message"] as? [String: Any],
           let role = stringValue(in: message, keys: ["role", "author", "sender"])?.lowercased() {
            return role
        }

        return nil
    }

    private func messageText(in object: [String: Any]) -> String? {
        if let text = stringValue(in: object, keys: ["text", "message", "content", "delta"]) {
            return text
        }

        if let message = object["message"] as? [String: Any],
           let text = nestedTextContent(in: message) {
            return text
        }

        return nestedTextContent(in: object)
    }

    private func nestedTextContent(in object: [String: Any]) -> String? {
        guard let content = object["content"] as? [[String: Any]] else {
            return nil
        }

        let text = content.compactMap { block -> String? in
            guard stringValue(in: block, keys: ["type"])?.lowercased() == "text" else {
                return nil
            }
            return stringValue(in: block, keys: ["text", "delta", "content"])
        }.joined()

        return text.isEmpty ? nil : text
    }

    private func toolParameterPreview(in object: [String: Any]) -> String? {
        guard let parameters = object["parameters"] as? [String: Any] else {
            return nil
        }

        if let agent = stringValue(in: parameters, keys: ["agent"]),
           let task = stringValue(in: parameters, keys: ["task", "prompt"]) {
            return "\(agent): \(previewText(task, limit: 80))"
        }

        if let command = stringValue(in: parameters, keys: ["command", "task", "prompt", "result"]) {
            return previewText(command, limit: 80)
        }

        return nil
    }

    private func previewText(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }
        return String(text.prefix(limit)) + "…"
    }

    private func resolvedSessionID(from object: [String: Any]) -> String? {
        if let sessionID = stringValue(in: object, keys: ["session_id", "sessionId", "conversation_id", "conversationId"]) {
            return sessionID
        }

        if let session = object["session"] as? [String: Any],
           let sessionID = stringValue(in: session, keys: ["id", "session_id", "sessionId"]) {
            return sessionID
        }

        return nil
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

    private static func discoverSlashCommands(executable: String, workingDirectory: String) -> [SessionSlashCommand]? {
        guard shouldDiscoverSlashCommandsLocally(executable: executable, workingDirectory: workingDirectory) else {
            return nil
        }

        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let projectRoot = URL(fileURLWithPath: workingDirectory, isDirectory: true)

        var commandsByName: [String: SessionSlashCommand] = [:]
        for command in loadBobCustomCommands(from: homeDirectory.appendingPathComponent(".bob/commands", isDirectory: true), location: .user) {
            commandsByName[command.name] = command
        }
        for command in loadBobCustomModes(from: homeDirectory.appendingPathComponent(".bob/custom_modes.yaml", isDirectory: false), location: .user) {
            commandsByName[command.name] = command
        }
        for command in loadBobCustomCommands(from: projectRoot.appendingPathComponent(".bob/commands", isDirectory: true), location: .project) {
            commandsByName[command.name] = command
        }
        for command in loadBobCustomModes(from: projectRoot.appendingPathComponent(".bob/custom_modes.yaml", isDirectory: false), location: .project) {
            commandsByName[command.name] = command
        }

        let commands = commandsByName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return commands.isEmpty ? nil : commands
    }

    private static func shouldDiscoverSlashCommandsLocally(executable: String, workingDirectory: String) -> Bool {
        let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        guard executableName != "ssh" else {
            return false
        }
        return FileManager.default.fileExists(atPath: workingDirectory)
    }

    private static func loadBobCustomCommands(from directory: URL, location: SessionSlashCommandLocation) -> [SessionSlashCommand] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = (fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects ?? []).compactMap { $0 as? URL }
        let resolvedDirectoryPath = directory.resolvingSymlinksInPath().path
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { fileURL in
                let resolvedFilePath = fileURL.resolvingSymlinksInPath().path
                let relativePath = resolvedFilePath.replacingOccurrences(of: resolvedDirectoryPath + "/", with: "")
                let commandName = (relativePath as NSString).deletingPathExtension.replacingOccurrences(of: "\\", with: "/")
                guard commandName.isEmpty == false else {
                    return nil
                }

                let metadata = readBobMarkdownMetadata(at: fileURL)
                let description = metadata.description ?? "Custom Bob command"
                let displayName = metadata.argumentHint.map { "\(commandName) \($0)" }
                let insertionText = metadata.argumentHint == nil ? nil : "\(commandName) "

                return SessionSlashCommand(
                    name: commandName,
                    displayName: displayName,
                    insertionText: insertionText,
                    description: description,
                    source: .prompt,
                    location: location,
                    path: resolvedFilePath
                )
            }
    }

    private static func loadBobCustomModes(from fileURL: URL, location: SessionSlashCommandLocation) -> [SessionSlashCommand] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        struct PendingMode {
            var slug: String?
            var name: String?
            var whenToUse: String?
        }

        func finalize(_ mode: PendingMode) -> SessionSlashCommand? {
            guard let slug = mode.slug?.trimmingCharacters(in: .whitespacesAndNewlines), slug.isEmpty == false else {
                return nil
            }
            let trimmedWhenToUse = mode.whenToUse?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = mode.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = (trimmedWhenToUse?.isEmpty == false ? trimmedWhenToUse : nil)
                ?? (trimmedName?.isEmpty == false ? trimmedName : nil)
                ?? "Custom Bob mode"
            return SessionSlashCommand(
                name: slug,
                description: summary,
                source: .builtIn,
                location: location,
                path: fileURL.resolvingSymlinksInPath().path
            )
        }

        var commands: [SessionSlashCommand] = []
        var current = PendingMode()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- slug:") {
                if let command = finalize(current) {
                    commands.append(command)
                }
                current = PendingMode(slug: parseBobConfigValue(from: line, key: "- slug:"))
                continue
            }
            if current.slug == nil {
                continue
            }
            if line.hasPrefix("slug:") {
                current.slug = parseBobConfigValue(from: line, key: "slug:")
            } else if line.hasPrefix("name:") {
                current.name = parseBobConfigValue(from: line, key: "name:")
            } else if line.hasPrefix("whenToUse:") {
                current.whenToUse = parseBobConfigValue(from: line, key: "whenToUse:")
            }
        }
        if let command = finalize(current) {
            commands.append(command)
        }
        return commands
    }

    private static func readBobMarkdownMetadata(at fileURL: URL) -> (description: String?, argumentHint: String?) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return (nil, nil)
        }

        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return (nil, nil)
        }

        var description: String?
        var argumentHint: String?
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" {
                break
            }
            if trimmed.hasPrefix("description:") {
                description = parseBobConfigValue(from: trimmed, key: "description:")
            } else if trimmed.hasPrefix("argument-hint:") {
                argumentHint = parseBobConfigValue(from: trimmed, key: "argument-hint:")
            }
        }

        return (description, argumentHint)
    }

    private static func parseBobConfigValue(from line: String, key: String) -> String? {
        let value = line.dropFirst(key.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false,
              value != "|-",
              value != ">-",
              value != "|",
              value != ">" else {
            return nil
        }
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static var defaultActivityItems: [SessionActivityItem] {
        [SessionActivityItem(kind: .status, text: "IBM Bob Session ready. Send a prompt to start IBM Bob.")]
    }

    private static func transcriptEntries(from activityItems: [SessionActivityItem]) -> [String] {
        activityItems.compactMap { item in
            guard item.kind == .message else {
                return nil
            }
            if item.text.hasPrefix("You: ") {
                return "> \(item.text.dropFirst(5))"
            }
            return item.text
        }
    }

    private static func launchArguments(prompt: String, sessionLinkage: IBMBobSessionLinkage?) -> [String] {
        var arguments = [
            "-o", "stream-json",
            "--chat-mode", "advanced",
            "--hide-intermediary-output",
            "--approval-mode", "yolo"
        ]
        if let sessionID = sessionLinkage?.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           sessionID.isEmpty == false {
            arguments += ["--resume", sessionID]
        }
        arguments.append(prompt)
        return arguments
    }

    private struct ActiveTurn {
        let prompt: String
        let resumedSessionID: String?
    }

    private struct BobEvent {
        let kind: SessionActivityItem.Kind
        let text: String
    }
}

final class ProcessIBMBobTransport: IBMBobTransporting, @unchecked Sendable {
    private struct ProcessInvocation {
        let executable: String
        let arguments: [String]
    }

    private let executable: String
    private let arguments: [String]
    private let workingDirectory: String?
    private let lock = NSLock()
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var stderrLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

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
        let invocation = resolvedInvocation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
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
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
        lock.unlock()
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

        return ProcessInvocation(
            executable: interpreterExecutable,
            arguments: Array(shebangArguments.dropFirst()) + [executable] + arguments
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
