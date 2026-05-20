import Darwin
import Foundation
import NexusDomain
import NexusIPC

public protocol NexusEmbeddedServiceSession: AnyObject {
    var listenerEndpoint: NSXPCListenerEndpoint { get }
    var storeURL: URL { get }
}

public enum NexusEmbeddedServiceBootstrap {
    public static func bootstrap() throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrap()
    }

    public static func bootstrapForTests() throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrapForTests()
    }

    public static func bootstrapForTests(rootURL: URL) throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrapForTests(rootURL: rootURL)
    }
}

protocol SessionRuntimeManaging: AnyObject {
    func launchOrResume(session: Session, workspace: Workspace, executable: String) throws
    func hasRuntime(for session: Session) -> Bool
    func runtimeState(for session: Session) -> Session.State?
    func sessionScreen(for session: Session) throws -> SessionScreen
    func sendInput(_ text: String, to session: Session) throws -> SessionScreen
    func sendText(_ text: String, to session: Session) throws -> SessionScreen
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen
    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen
}

protocol SessionRuntimeLaunching {
    func makeRuntime(session: Session, workspace: Workspace, executable: String) throws -> any SessionRuntime
}

protocol SessionRuntime: AnyObject {
    var state: Session.State { get }
    var transcript: String { get }
    var terminalColumns: Int { get }
    var terminalRows: Int { get }
    func sendInput(_ text: String) throws
    func sendText(_ text: String) throws
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws
    func resize(columns: Int, rows: Int) throws
}

final class InMemorySessionRuntimeManager: SessionRuntimeManaging {
    private let launcher: any SessionRuntimeLaunching
    private let lock = NSLock()
    private var runtimes: [UUID: any SessionRuntime] = [:]

    init(launcher: any SessionRuntimeLaunching = ProcessSessionRuntimeLauncher()) {
        self.launcher = launcher
    }

    func launchOrResume(session: Session, workspace: Workspace, executable: String) throws {
        try withLock {
            if let runtime = runtimes[session.id], runtime.state == .ready {
                return
            }

            runtimes[session.id] = try launcher.makeRuntime(session: session, workspace: workspace, executable: executable)
        }
    }

    func hasRuntime(for session: Session) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id]?.state
    }

    func sessionScreen(for session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.terminalColumns,
            terminalRows: runtime.terminalRows
        )
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.sendInput(text)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.terminalColumns,
            terminalRows: runtime.terminalRows
        )
    }

    func sendText(_ text: String, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.sendText(text)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.terminalColumns,
            terminalRows: runtime.terminalRows
        )
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.sendInputKey(key, applicationCursorMode: applicationCursorMode)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.terminalColumns,
            terminalRows: runtime.terminalRows
        )
    }

    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.resize(columns: columns, rows: rows)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.terminalColumns,
            terminalRows: runtime.terminalRows
        )
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

final class ProcessSessionRuntimeLauncher: SessionRuntimeLaunching {
    func makeRuntime(session: Session, workspace: Workspace, executable: String) throws -> any SessionRuntime {
        try ProcessSessionRuntime(executable: executable, workspace: workspace)
    }
}

final class ProcessSessionRuntime: SessionRuntime, @unchecked Sendable {
    private let pid: pid_t
    private let terminalHandle: FileHandle
    private let masterFileDescriptor: Int32
    private let readSource: DispatchSourceRead
    private let terminationSource: DispatchSourceProcess
    private let lock = NSLock()
    private var runtimeState: Session.State
    private var storage: String
    private var columns: Int
    private var rows: Int

    init(executable: String, workspace: Workspace) throws {
        self.runtimeState = .ready
        self.storage = "Launching \(workspace.name) with Claude…\n"
        self.columns = 80
        self.rows = 24

        var masterFileDescriptor: Int32 = -1
        var initialWindowSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&masterFileDescriptor, nil, nil, &initialWindowSize)
        guard pid >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }

        if pid == 0 {
            chdir(workspace.folderPath)
            setenv("TERM", "xterm-256color", 1)
            executable.withCString { executablePath in
                var arguments: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: executablePath), nil]
                execv(executablePath, &arguments)
            }
            _exit(127)
        }

        self.pid = pid
        self.masterFileDescriptor = masterFileDescriptor
        self.terminalHandle = FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true)
        self.readSource = DispatchSource.makeReadSource(fileDescriptor: masterFileDescriptor, queue: .global())
        self.terminationSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())

        readSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            let estimatedBytes = max(Int(self.readSource.data), 1)
            var buffer = [UInt8](repeating: 0, count: estimatedBytes)
            let bytesRead = Darwin.read(self.masterFileDescriptor, &buffer, buffer.count)
            guard bytesRead > 0 else {
                return
            }

            let data = Data(buffer.prefix(bytesRead))
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            self.append(text)
        }
        readSource.activate()

        terminationSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            var status: Int32 = 0
            _ = waitpid(self.pid, &status, 0)
            self.lock.lock()
            self.runtimeState = .exited
            self.lock.unlock()
            self.append("\n[Claude exited with status \(status)]\n")
            self.readSource.cancel()
            self.terminationSource.cancel()
        }
        terminationSource.activate()
    }

    deinit {
        readSource.cancel()
        terminationSource.cancel()
    }

    var state: Session.State {
        lock.lock()
        defer { lock.unlock() }
        return runtimeState
    }

    var transcript: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var terminalColumns: Int {
        lock.lock()
        defer { lock.unlock() }
        return columns
    }

    var terminalRows: Int {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    func sendInput(_ text: String) throws {
        if text.isEmpty {
            try sendInputKey(.enter, applicationCursorMode: false)
            return
        }

        let trimmed = text.trimmingCharacters(in: .newlines)
        guard trimmed.isEmpty == false else {
            return
        }

        append("\n> \(trimmed)\n")
        guard let data = "\(trimmed)\n".data(using: .utf8) else {
            return
        }
        terminalHandle.write(data)
    }

    func sendText(_ text: String) throws {
        guard text.isEmpty == false, let data = text.data(using: .utf8) else {
            return
        }
        terminalHandle.write(data)
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {
        let escapeSequence: String
        switch key {
        case .enter:
            escapeSequence = "\r"
        case .tab:
            escapeSequence = "\t"
        case .escape:
            escapeSequence = "\u{001B}"
        case .backspace:
            escapeSequence = "\u{007F}"
        case .deleteForward:
            escapeSequence = "\u{001B}[3~"
        case .endOfTransmission:
            escapeSequence = "\u{0004}"
        case .interrupt:
            escapeSequence = "\u{0003}"
        case .home:
            escapeSequence = applicationCursorMode ? "\u{001B}OH" : "\u{001B}[H"
        case .end:
            escapeSequence = applicationCursorMode ? "\u{001B}OF" : "\u{001B}[F"
        case .upArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OA" : "\u{001B}[A"
        case .downArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OB" : "\u{001B}[B"
        case .leftArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OD" : "\u{001B}[D"
        case .rightArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OC" : "\u{001B}[C"
        }

        guard let data = escapeSequence.data(using: .utf8) else {
            return
        }
        terminalHandle.write(data)
    }

    func resize(columns: Int, rows: Int) throws {
        let clampedColumns = max(1, columns)
        let clampedRows = max(1, rows)

        var windowSize = winsize(ws_row: UInt16(clampedRows), ws_col: UInt16(clampedColumns), ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(masterFileDescriptor, TIOCSWINSZ, &windowSize) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }

        lock.lock()
        self.columns = clampedColumns
        self.rows = clampedRows
        lock.unlock()
    }

    private func append(_ text: String) {
        lock.lock()
        storage.append(text)
        lock.unlock()
    }
}

public final class NexusService: NSObject, NexusEmbeddedServiceSession {
    nonisolated public let listener: NSXPCListener
    nonisolated public let storeURL: URL

    nonisolated public var listenerEndpoint: NSXPCListenerEndpoint {
        listener.endpoint
    }

    private let metadataStore: NexusMetadataStore
    private let providerHealthEvaluator: any ProviderHealthEvaluating
    private let sessionRuntimeManager: any SessionRuntimeManaging

    private init(
        listener: NSXPCListener,
        storeURL: URL,
        metadataStore: NexusMetadataStore,
        providerHealthEvaluator: any ProviderHealthEvaluating,
        sessionRuntimeManager: any SessionRuntimeManaging
    ) {
        self.listener = listener
        self.storeURL = storeURL
        self.metadataStore = metadataStore
        self.providerHealthEvaluator = providerHealthEvaluator
        self.sessionRuntimeManager = sessionRuntimeManager
        super.init()
        self.listener.delegate = self
        self.listener.resume()
    }

    nonisolated public static func bootstrap() throws -> NexusService {
        let rootURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Nexus", isDirectory: true)

        return try bootstrap(rootURL: rootURL)
    }

    nonisolated public static func bootstrapForTests() throws -> NexusService {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return try bootstrap(rootURL: rootURL)
    }

    nonisolated public static func bootstrapForTests(rootURL: URL) throws -> NexusService {
        try bootstrap(rootURL: rootURL)
    }

    static func bootstrapForTests(
        rootURL: URL,
        providerHealthEvaluator: any ProviderHealthEvaluating,
        sessionRuntimeManager: any SessionRuntimeManaging = InMemorySessionRuntimeManager()
    ) throws -> NexusService {
        try bootstrap(
            rootURL: rootURL,
            providerHealthEvaluator: providerHealthEvaluator,
            sessionRuntimeManager: sessionRuntimeManager
        )
    }

    private nonisolated static func bootstrap(
        rootURL: URL,
        providerHealthEvaluator: any ProviderHealthEvaluating = ProviderHealthEvaluator(),
        sessionRuntimeManager: any SessionRuntimeManaging = InMemorySessionRuntimeManager()
    ) throws -> NexusService {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        if FileManager.default.fileExists(atPath: storeURL.path) == false {
            FileManager.default.createFile(atPath: storeURL.path, contents: Data())
        }

        let metadataStore = try NexusMetadataStore(storeURL: storeURL)
        return NexusService(
            listener: NSXPCListener.anonymous(),
            storeURL: storeURL,
            metadataStore: metadataStore,
            providerHealthEvaluator: providerHealthEvaluator,
            sessionRuntimeManager: sessionRuntimeManager
        )
    }

    nonisolated public func serviceStatus() -> NexusServiceStatus {
        NexusServiceStatus(
            state: .running,
            store: .init(
                kind: .sqlite,
                owner: .backgroundService,
                location: storeURL
            )
        )
    }

    func listWorkspaceGroups() throws -> [WorkspaceGroup] {
        try metadataStore.listWorkspaceGroups()
    }

    func createWorkspaceGroup(name: String) throws -> WorkspaceGroup {
        try metadataStore.createWorkspaceGroup(name: name)
    }

    func listWorkspaces() throws -> [Workspace] {
        try metadataStore.listWorkspaces()
    }

    func getWorkspaceOverview(workspaceID: UUID) throws -> WorkspaceOverview {
        guard let workspace = try metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        let providerCards = try ProviderID.allCases.map { providerID in
            WorkspaceProviderCard(
                provider: Provider(id: providerID),
                health: providerHealthEvaluator.healthSummary(for: providerID, workspace: workspace),
                defaultSession: try defaultSessionSummary(for: workspace, providerID: providerID)
            )
        }

        return WorkspaceOverview(workspace: workspace, providerCards: providerCards)
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) throws -> Workspace {
        try metadataStore.createLocalWorkspace(name: name, folderPath: folderPath, primaryGroupID: primaryGroupID)
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session {
        guard let workspace = try metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        guard providerID == .claude else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let health = providerHealthEvaluator.healthSummary(for: providerID, workspace: workspace)
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            let failureMessage = health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
            if let session = try metadataStore.defaultSession(workspaceID: workspaceID, providerID: providerID) {
                return try metadataStore.updateSession(
                    id: session.id,
                    state: .failed,
                    failureMessage: failureMessage
                )
            }

            return try metadataStore.createDefaultSession(
                workspaceID: workspaceID,
                providerID: providerID,
                state: .failed,
                failureMessage: failureMessage
            )
        }

        let session: Session
        if let existingSession = try metadataStore.defaultSession(workspaceID: workspaceID, providerID: providerID) {
            session = existingSession.state == .ready && existingSession.failureMessage == nil
                ? existingSession
                : try metadataStore.updateSession(id: existingSession.id, state: .ready, failureMessage: nil)
        } else {
            session = try metadataStore.createDefaultSession(
                workspaceID: workspaceID,
                providerID: providerID,
                state: .ready,
                failureMessage: nil
            )
        }

        do {
            try sessionRuntimeManager.launchOrResume(session: session, workspace: workspace, executable: executable)
            let terminalSize = try metadataStore.sessionTerminalSize(id: session.id)
            _ = try sessionRuntimeManager.resize(
                session: session,
                columns: terminalSize.columns,
                rows: terminalSize.rows
            )
            return session
        } catch {
            let failedSession = try metadataStore.updateSession(
                id: session.id,
                state: .failed,
                failureMessage: error.localizedDescription
            )
            return failedSession
        }
    }

    func getSessionScreen(sessionID: UUID) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)

        switch resolvedSession.state {
        case .failed:
            return try staticSessionScreen(
                for: resolvedSession,
                transcript: resolvedSession.failureMessage ?? "Session launch failed"
            )
        case .interrupted:
            return try staticSessionScreen(
                for: resolvedSession,
                transcript: resolvedSession.failureMessage ?? "Session interrupted"
            )
        case .exited:
            if sessionRuntimeManager.hasRuntime(for: resolvedSession) {
                return normalizedSessionScreen(try sessionRuntimeManager.sessionScreen(for: resolvedSession))
            }
            return try staticSessionScreen(
                for: resolvedSession,
                transcript: resolvedSession.failureMessage ?? "Session exited"
            )
        case .ready:
            return normalizedSessionScreen(try sessionRuntimeManager.sessionScreen(for: resolvedSession))
        }
    }

    func sendSessionInput(sessionID: UUID, text: String) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        return normalizedSessionScreen(try sessionRuntimeManager.sendInput(text, to: resolvedSession))
    }

    func sendSessionText(sessionID: UUID, text: String) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        return normalizedSessionScreen(try sessionRuntimeManager.sendText(text, to: resolvedSession))
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        let currentScreen = try sessionRuntimeManager.sessionScreen(for: resolvedSession)
        let renderState = renderTerminalState(
            from: currentScreen.transcript,
            terminalColumns: currentScreen.terminalColumns,
            terminalRows: currentScreen.terminalRows
        )

        return normalizedSessionScreen(
            try sessionRuntimeManager.sendInputKey(
                key,
                applicationCursorMode: renderState.applicationCursorMode,
                to: resolvedSession
            )
        )
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        let screen = try sessionRuntimeManager.resize(session: resolvedSession, columns: columns, rows: rows)
        try metadataStore.updateSessionTerminalSize(
            id: resolvedSession.id,
            columns: screen.terminalColumns,
            rows: screen.terminalRows
        )
        return normalizedSessionScreen(screen)
    }

    private func staticSessionScreen(for session: Session, transcript: String) throws -> SessionScreen {
        let terminalSize = try metadataStore.sessionTerminalSize(id: session.id)
        return normalizedSessionScreen(
            SessionScreen(
                session: session,
                transcript: transcript,
                terminalColumns: terminalSize.columns,
                terminalRows: terminalSize.rows
            )
        )
    }

    private func normalizedSessionScreen(_ screen: SessionScreen) -> SessionScreen {
        let renderState = renderTerminalState(
            from: screen.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows
        )

        return SessionScreen(
            session: screen.session,
            transcript: renderState.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows,
            visibleLines: renderState.visibleLines,
            cursorRow: renderState.cursorRow,
            cursorColumn: renderState.cursorColumn,
            cursorVisible: renderState.cursorVisible
        )
    }

    private func renderTerminalState(
        from transcript: String,
        terminalColumns: Int,
        terminalRows: Int
    ) -> (transcript: String, visibleLines: [String], cursorRow: Int, cursorColumn: Int, cursorVisible: Bool, applicationCursorMode: Bool) {
        var lines: [[Character]] = [[]]
        var cursorLine = 0
        var cursorColumn = 0
        var cursorVisible = true
        var applicationCursorMode = false
        var savedCursorLine = 0
        var savedCursorColumn = 0
        var primaryBufferLines = lines
        var primaryBufferCursorLine = cursorLine
        var primaryBufferCursorColumn = cursorColumn
        var usingAlternateBuffer = false
        var scrollRegionTop = 0
        var scrollRegionBottom = max(0, terminalRows - 1)
        var hasExplicitScrollRegion = false
        var iterator = transcript.unicodeScalars.makeIterator()

        func ensureLine(_ lineIndex: Int) {
            while lines.count <= lineIndex {
                lines.append([])
            }
        }

        func ensureCurrentLine() {
            ensureLine(cursorLine)
        }

        func activeScrollRegion() -> ClosedRange<Int>? {
            guard hasExplicitScrollRegion else {
                return nil
            }

            let top = max(0, scrollRegionTop)
            let bottom = max(top, scrollRegionBottom)
            ensureLine(bottom)
            return top...bottom
        }

        func explicitScrollRegion() -> ClosedRange<Int> {
            let top = max(0, scrollRegionTop)
            let bottom = max(top, scrollRegionBottom)
            ensureLine(bottom)
            return top...bottom
        }

        func scrollUpWithinRegion(_ count: Int) {
            let region = explicitScrollRegion()
            let scrollCount = max(0, count)
            guard scrollCount > 0 else {
                return
            }

            let regionHeight = region.count
            if scrollCount >= regionHeight {
                for lineIndex in region {
                    lines[lineIndex] = []
                }
                return
            }

            lines.removeSubrange(region.lowerBound..<(region.lowerBound + scrollCount))
            lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: region.upperBound - scrollCount + 1)
        }

        func scrollDownWithinRegion(_ count: Int) {
            let region = explicitScrollRegion()
            let scrollCount = max(0, count)
            guard scrollCount > 0 else {
                return
            }

            let regionHeight = region.count
            if scrollCount >= regionHeight {
                for lineIndex in region {
                    lines[lineIndex] = []
                }
                return
            }

            lines.removeSubrange((region.upperBound - scrollCount + 1)...region.upperBound)
            lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: region.lowerBound)
        }

        func insertBlankLinesWithinRegion(_ count: Int, at lineIndex: Int) {
            let region = explicitScrollRegion()
            guard region.contains(lineIndex) else {
                return
            }

            let insertCount = min(max(0, count), region.upperBound - lineIndex + 1)
            guard insertCount > 0 else {
                return
            }

            let regionSlice = Array(lines[lineIndex...region.upperBound])
            let replacement = Array(repeating: [Character](), count: insertCount) + Array(regionSlice.dropLast(insertCount))
            lines.replaceSubrange(lineIndex...region.upperBound, with: replacement)
        }

        func deleteLinesWithinRegion(_ count: Int, at lineIndex: Int) {
            let region = explicitScrollRegion()
            guard region.contains(lineIndex) else {
                return
            }

            let deleteCount = min(max(0, count), region.upperBound - lineIndex + 1)
            guard deleteCount > 0 else {
                return
            }

            let regionSlice = Array(lines[lineIndex...region.upperBound])
            let replacement = Array(regionSlice.dropFirst(deleteCount)) + Array(repeating: [Character](), count: deleteCount)
            lines.replaceSubrange(lineIndex...region.upperBound, with: replacement)
        }

        func csiParameters(_ parameters: String) -> [Int?] {
            guard parameters.isEmpty == false else {
                return []
            }

            return parameters
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { segment in
                    guard segment.isEmpty == false else {
                        return nil
                    }
                    return Int(segment)
                }
        }

        func skipOperatingSystemCommand() {
            while let scalar = iterator.next() {
                if scalar == "\u{0007}" {
                    return
                }

                if scalar == "\u{001B}", let terminator = iterator.next(), terminator == "\\" {
                    return
                }
            }
        }

        func parseCSI(finalCharacter: UnicodeScalar, parameters: String) {
            let finalCharacter = Character(finalCharacter)
            let isPrivateMode = parameters.first == "?"
            let normalizedParameters = isPrivateMode ? String(parameters.dropFirst()) : parameters
            let values = csiParameters(normalizedParameters)
            let value = values.first.flatMap { $0 }
            let defaultValue = value ?? 1
            let eraseMode = value ?? 0

            if isPrivateMode {
                switch finalCharacter {
                case "h":
                    switch value {
                    case 1:
                        applicationCursorMode = true
                    case 47, 1047, 1049:
                        guard usingAlternateBuffer == false else {
                            break
                        }
                        primaryBufferLines = lines
                        primaryBufferCursorLine = cursorLine
                        primaryBufferCursorColumn = cursorColumn
                        lines = [[]]
                        cursorLine = 0
                        cursorColumn = 0
                        usingAlternateBuffer = true
                    case 25:
                        cursorVisible = true
                    case 1048:
                        savedCursorLine = cursorLine
                        savedCursorColumn = cursorColumn
                    default:
                        break
                    }
                case "l":
                    switch value {
                    case 1:
                        applicationCursorMode = false
                    case 25:
                        cursorVisible = false
                    case 47, 1047, 1049:
                        guard usingAlternateBuffer else {
                            break
                        }
                        lines = primaryBufferLines
                        cursorLine = primaryBufferCursorLine
                        cursorColumn = primaryBufferCursorColumn
                        usingAlternateBuffer = false
                    case 1048:
                        cursorLine = savedCursorLine
                        cursorColumn = savedCursorColumn
                        ensureCurrentLine()
                    default:
                        break
                    }
                default:
                    break
                }
                return
            }

            switch finalCharacter {
            case "A":
                cursorLine = max(0, cursorLine - defaultValue)
                ensureCurrentLine()
            case "B":
                cursorLine += defaultValue
                ensureCurrentLine()
            case "C":
                cursorColumn += defaultValue
            case "D":
                cursorColumn = max(0, cursorColumn - defaultValue)
            case "E":
                if let region = activeScrollRegion() {
                    for _ in 0..<defaultValue {
                        if cursorLine == region.upperBound {
                            scrollUpWithinRegion(1)
                        } else {
                            cursorLine += 1
                        }
                    }
                } else {
                    cursorLine += defaultValue
                }
                cursorColumn = 0
                ensureCurrentLine()
            case "F":
                cursorLine = max(0, cursorLine - defaultValue)
                cursorColumn = 0
                ensureCurrentLine()
            case "G":
                cursorColumn = max(0, defaultValue - 1)
            case "H", "f":
                let row = values.first.flatMap { $0 } ?? 1
                let column = values.dropFirst().first.flatMap { $0 } ?? 1
                cursorLine = max(0, row - 1)
                cursorColumn = max(0, column - 1)
                ensureCurrentLine()
            case "J":
                ensureCurrentLine()
                switch eraseMode {
                case 1:
                    if cursorLine > 0 {
                        for lineIndex in 0..<cursorLine {
                            lines[lineIndex].removeAll()
                        }
                    }
                    while lines[cursorLine].count <= cursorColumn {
                        lines[cursorLine].append(" ")
                    }
                    for index in 0...cursorColumn {
                        lines[cursorLine][index] = " "
                    }
                case 2:
                    lines = [[]]
                    cursorLine = 0
                    cursorColumn = 0
                default:
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine].removeSubrange(cursorColumn...)
                    }
                    if cursorLine + 1 < lines.count {
                        lines.removeSubrange((cursorLine + 1)..<lines.count)
                    }
                }
            case "K":
                ensureCurrentLine()
                switch eraseMode {
                case 1:
                    while lines[cursorLine].count <= cursorColumn {
                        lines[cursorLine].append(" ")
                    }
                    for index in 0...cursorColumn {
                        lines[cursorLine][index] = " "
                    }
                case 2:
                    lines[cursorLine].removeAll()
                default:
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine].removeSubrange(cursorColumn...)
                    }
                }
            case "@":
                ensureCurrentLine()
                let insertCount = max(0, defaultValue)
                guard insertCount > 0 else {
                    break
                }
                while lines[cursorLine].count < cursorColumn {
                    lines[cursorLine].append(" ")
                }
                let blanks = Array(repeating: Character(" "), count: insertCount)
                lines[cursorLine].insert(contentsOf: blanks, at: cursorColumn)
            case "L":
                ensureCurrentLine()
                let insertCount = max(0, defaultValue)
                guard insertCount > 0 else {
                    break
                }
                if activeScrollRegion()?.contains(cursorLine) == true {
                    insertBlankLinesWithinRegion(insertCount, at: cursorLine)
                } else {
                    let blanks = Array(repeating: [Character](), count: insertCount)
                    lines.insert(contentsOf: blanks, at: cursorLine)
                }
            case "M":
                ensureCurrentLine()
                let deleteCount = max(0, defaultValue)
                guard deleteCount > 0 else {
                    break
                }
                if activeScrollRegion()?.contains(cursorLine) == true {
                    deleteLinesWithinRegion(deleteCount, at: cursorLine)
                } else {
                    let endLine = min(lines.count, cursorLine + deleteCount)
                    if cursorLine < endLine {
                        lines.removeSubrange(cursorLine..<endLine)
                    }
                    ensureCurrentLine()
                }
            case "P":
                ensureCurrentLine()
                guard cursorColumn < lines[cursorLine].count else {
                    break
                }
                let endIndex = min(lines[cursorLine].count, cursorColumn + defaultValue)
                lines[cursorLine].removeSubrange(cursorColumn..<endIndex)
            case "S":
                ensureCurrentLine()
                let scrollCount = max(0, defaultValue)
                guard scrollCount > 0 else {
                    break
                }
                if activeScrollRegion() != nil {
                    scrollUpWithinRegion(scrollCount)
                } else {
                    let visibleLineCount = max(lines.count, cursorLine + 1)
                    if scrollCount >= visibleLineCount {
                        lines = Array(repeating: [], count: visibleLineCount)
                    } else {
                        lines.removeFirst(scrollCount)
                        lines.append(contentsOf: Array(repeating: [], count: scrollCount))
                    }
                }
                ensureCurrentLine()
            case "T":
                ensureCurrentLine()
                let scrollCount = max(0, defaultValue)
                guard scrollCount > 0 else {
                    break
                }
                if activeScrollRegion() != nil {
                    scrollDownWithinRegion(scrollCount)
                } else {
                    let visibleLineCount = max(lines.count, cursorLine + 1)
                    if scrollCount >= visibleLineCount {
                        lines = Array(repeating: [], count: visibleLineCount)
                    } else {
                        lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: 0)
                        lines.removeLast(min(scrollCount, lines.count))
                    }
                }
                ensureCurrentLine()
            case "r":
                let requestedTop = max(1, values.first.flatMap { $0 } ?? 1)
                let requestedBottom = max(requestedTop, values.dropFirst().first.flatMap { $0 } ?? terminalRows)
                scrollRegionTop = min(max(0, requestedTop - 1), max(0, terminalRows - 1))
                scrollRegionBottom = min(max(scrollRegionTop, requestedBottom - 1), max(0, terminalRows - 1))
                hasExplicitScrollRegion = true
                cursorLine = 0
                cursorColumn = 0
                ensureCurrentLine()
            case "X":
                ensureCurrentLine()
                let eraseCount = max(0, defaultValue)
                guard eraseCount > 0 else {
                    break
                }
                while lines[cursorLine].count < cursorColumn {
                    lines[cursorLine].append(" ")
                }
                let endIndex = min(lines[cursorLine].count, cursorColumn + eraseCount)
                if cursorColumn < endIndex {
                    for index in cursorColumn..<endIndex {
                        lines[cursorLine][index] = " "
                    }
                }
            case "s":
                guard parameters.isEmpty else {
                    break
                }
                savedCursorLine = cursorLine
                savedCursorColumn = cursorColumn
            case "u":
                guard parameters.isEmpty else {
                    break
                }
                cursorLine = savedCursorLine
                cursorColumn = savedCursorColumn
                ensureCurrentLine()
            default:
                break
            }
        }

        while let scalar = iterator.next() {
            switch scalar {
            case "\u{001B}":
                guard let next = iterator.next() else {
                    continue
                }

                if next == "[" {
                    var parameters = ""
                    while let scalar = iterator.next() {
                        if (0x40...0x7E).contains(scalar.value) {
                            parseCSI(finalCharacter: scalar, parameters: parameters)
                            break
                        }
                        parameters.unicodeScalars.append(scalar)
                    }
                } else if next == "]" {
                    skipOperatingSystemCommand()
                } else if next == "7" {
                    savedCursorLine = cursorLine
                    savedCursorColumn = cursorColumn
                } else if next == "8" {
                    cursorLine = savedCursorLine
                    cursorColumn = savedCursorColumn
                    ensureCurrentLine()
                } else if next == "D" {
                    if let region = activeScrollRegion() {
                        if cursorLine == region.upperBound {
                            scrollUpWithinRegion(1)
                        } else {
                            cursorLine += 1
                        }
                    } else {
                        let visibleLineCount = max(lines.count, cursorLine + 1)
                        if cursorLine + 1 < visibleLineCount {
                            cursorLine += 1
                        } else {
                            lines.removeFirst()
                            lines.append([])
                            cursorLine = max(0, visibleLineCount - 1)
                        }
                    }
                    ensureCurrentLine()
                } else if next == "E" {
                    if let region = activeScrollRegion() {
                        if cursorLine == region.upperBound {
                            scrollUpWithinRegion(1)
                        } else {
                            cursorLine += 1
                        }
                    } else {
                        let visibleLineCount = max(lines.count, cursorLine + 1)
                        if cursorLine + 1 < visibleLineCount {
                            cursorLine += 1
                        } else {
                            lines.removeFirst()
                            lines.append([])
                            cursorLine = max(0, visibleLineCount - 1)
                        }
                    }
                    cursorColumn = 0
                    ensureCurrentLine()
                } else if next == "M" {
                    if let region = activeScrollRegion() {
                        if cursorLine == region.lowerBound {
                            scrollDownWithinRegion(1)
                        } else {
                            cursorLine -= 1
                        }
                    } else if cursorLine > 0 {
                        cursorLine -= 1
                    } else {
                        let visibleLineCount = max(lines.count, 1)
                        lines.insert([], at: 0)
                        if lines.count > visibleLineCount {
                            lines.removeLast(lines.count - visibleLineCount)
                        }
                    }
                    ensureCurrentLine()
                } else if next == "c" {
                    lines = [[]]
                    cursorLine = 0
                    cursorColumn = 0
                    cursorVisible = true
                    applicationCursorMode = false
                    savedCursorLine = 0
                    savedCursorColumn = 0
                    primaryBufferLines = lines
                    primaryBufferCursorLine = cursorLine
                    primaryBufferCursorColumn = cursorColumn
                    usingAlternateBuffer = false
                    scrollRegionTop = 0
                    scrollRegionBottom = max(0, terminalRows - 1)
                    hasExplicitScrollRegion = false
                }
            case "\r":
                cursorColumn = 0
            case "\u{8}":
                guard cursorColumn > 0 else {
                    continue
                }
                cursorColumn -= 1
            case "\u{7F}":
                guard cursorColumn > 0 else {
                    continue
                }
                ensureCurrentLine()
                cursorColumn -= 1
                if cursorColumn < lines[cursorLine].count {
                    lines[cursorLine].remove(at: cursorColumn)
                }
            case "\n":
                if let region = activeScrollRegion() {
                    if cursorLine == region.upperBound {
                        scrollUpWithinRegion(1)
                    } else {
                        cursorLine += 1
                    }
                } else {
                    cursorLine += 1
                }
                cursorColumn = 0
                ensureCurrentLine()
            case "\t":
                ensureCurrentLine()
                let tabWidth = 8
                let nextTabStop = ((cursorColumn / tabWidth) + 1) * tabWidth
                while lines[cursorLine].count < nextTabStop {
                    lines[cursorLine].append(" ")
                }
                cursorColumn = nextTabStop
            default:
                let character = Character(scalar)
                ensureCurrentLine()
                if cursorColumn < lines[cursorLine].count {
                    lines[cursorLine][cursorColumn] = character
                } else {
                    while lines[cursorLine].count < cursorColumn {
                        lines[cursorLine].append(" ")
                    }
                    lines[cursorLine].append(character)
                }
                cursorColumn += 1
            }
        }

        let renderedLines = lines.map { String($0) }
        let normalizedTranscript = renderedLines.joined(separator: "\n")
        let viewport = makeViewport(
            lines: renderedLines,
            cursorLine: cursorLine,
            cursorColumn: cursorColumn,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            transcript: normalizedTranscript
        )

        return (
            transcript: viewport.transcript,
            visibleLines: viewport.visibleLines,
            cursorRow: viewport.cursorRow,
            cursorColumn: viewport.cursorColumn,
            cursorVisible: cursorVisible,
            applicationCursorMode: applicationCursorMode
        )
    }

    private func makeViewport(
        lines: [String],
        cursorLine: Int,
        cursorColumn: Int,
        terminalColumns: Int,
        terminalRows: Int,
        transcript: String
    ) -> (transcript: String, visibleLines: [String], cursorRow: Int, cursorColumn: Int) {
        let columns = max(1, terminalColumns)
        let rows = max(1, terminalRows)
        let sourceLines = lines.isEmpty ? [""] : lines
        var wrappedLines: [String] = []
        var cursorWrappedRow = 0
        var cursorWrappedColumn = 0

        for (lineIndex, line) in sourceLines.enumerated() {
            let segments: [String]
            if line.isEmpty {
                segments = [""]
            } else {
                var builtSegments: [String] = []
                var startIndex = line.startIndex
                while startIndex < line.endIndex {
                    let endIndex = line.index(startIndex, offsetBy: columns, limitedBy: line.endIndex) ?? line.endIndex
                    builtSegments.append(String(line[startIndex..<endIndex]))
                    startIndex = endIndex
                }
                segments = builtSegments
            }

            let baseWrappedRow = wrappedLines.count
            wrappedLines.append(contentsOf: segments)

            if lineIndex == cursorLine {
                let segmentIndex = min(max(cursorColumn / columns, 0), max(segments.count - 1, 0))
                cursorWrappedRow = baseWrappedRow + segmentIndex
                cursorWrappedColumn = min(cursorColumn - (segmentIndex * columns), columns)
            }
        }

        let visibleStartIndex = max(0, wrappedLines.count - rows)
        let visibleLines = Array(wrappedLines.suffix(rows))
        let cursorRow = max(0, cursorWrappedRow - visibleStartIndex)

        return (
            transcript: transcript,
            visibleLines: visibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorWrappedColumn
        )
    }

    private func defaultSessionSummary(for workspace: Workspace, providerID: ProviderID) throws -> ProviderDefaultSessionSummary {
        guard let session = try metadataStore.defaultSession(workspaceID: workspace.id, providerID: providerID) else {
            return ProviderDefaultSessionSummary(
                state: .notCreated,
                summary: "No default session yet",
                actionTitle: "Launch"
            )
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)

        switch resolvedSession.state {
        case .ready:
            return ProviderDefaultSessionSummary(
                state: .ready,
                summary: "Default session ready",
                actionTitle: "Resume",
                sessionID: resolvedSession.id
            )
        case .interrupted:
            return ProviderDefaultSessionSummary(
                state: .interrupted,
                summary: resolvedSession.failureMessage ?? "Session interrupted after the service restarted",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        case .exited:
            return ProviderDefaultSessionSummary(
                state: .exited,
                summary: resolvedSession.failureMessage ?? "Session exited",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        case .failed:
            return ProviderDefaultSessionSummary(
                state: .failed,
                summary: resolvedSession.failureMessage ?? "Last launch failed",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        }
    }

    private func reconcileSessionRuntimeState(_ session: Session) throws -> Session {
        guard session.state == .ready else {
            return session
        }

        if let runtimeState = sessionRuntimeManager.runtimeState(for: session) {
            guard runtimeState != .ready else {
                return session
            }

            return try metadataStore.updateSession(
                id: session.id,
                state: .exited,
                failureMessage: "Session exited. Relaunch to start a new live runtime."
            )
        }

        guard sessionRuntimeManager.hasRuntime(for: session) == false else {
            return session
        }

        return try metadataStore.updateSession(
            id: session.id,
            state: .interrupted,
            failureMessage: "Session interrupted because the background service restarted. Relaunch to create a new live runtime."
        )
    }
}

extension NexusService: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: NexusXPCProtocol.self)
        newConnection.exportedObject = NexusXPCBridge(service: self)
        newConnection.resume()
        return true
    }
}

private final class NexusXPCBridge: NSObject, NexusXPCProtocol {
    let service: NexusService

    init(service: NexusService) {
        self.service = service
    }

    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { service.serviceStatus() }, reply: reply)
    }

    func listWorkspaceGroups(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listWorkspaceGroups, reply: reply)
    }

    func createWorkspaceGroup(name: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.createWorkspaceGroup(name: name) }, reply: reply)
    }

    func listWorkspaces(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listWorkspaces, reply: reply)
    }

    func getWorkspaceOverview(workspaceID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.getWorkspaceOverview(workspaceID: resolveUUID(workspaceID)) }, reply: reply)
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                try service.createLocalWorkspace(
                    name: name,
                    folderPath: folderPath,
                    primaryGroupID: try primaryGroupID.map(resolveUUID)
                )
            },
            reply: reply
        )
    }

    func launchOrResumeDefaultSession(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                guard let resolvedProviderID = ProviderID(rawValue: providerID) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try service.launchOrResumeDefaultSession(
                    workspaceID: resolveUUID(workspaceID),
                    providerID: resolvedProviderID
                )
            },
            reply: reply
        )
    }

    func getSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.getSessionScreen(sessionID: resolveUUID(sessionID)) }, reply: reply)
    }

    func sendSessionInput(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { try service.sendSessionInput(sessionID: resolveUUID(sessionID), text: text) },
            reply: reply
        )
    }

    func sendSessionText(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { try service.sendSessionText(sessionID: resolveUUID(sessionID), text: text) },
            reply: reply
        )
    }

    func sendSessionInputKey(sessionID: String, key: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                guard let resolvedKey = SessionInputKey(rawValue: key) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try service.sendSessionInputKey(sessionID: resolveUUID(sessionID), key: resolvedKey)
            },
            reply: reply
        )
    }

    func resizeSession(sessionID: String, columns: Int, rows: Int, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { try service.resizeSession(sessionID: resolveUUID(sessionID), columns: columns, rows: rows) },
            reply: reply
        )
    }

    private func sendReply<T: Encodable>(with operation: () throws -> T, reply: @escaping (Data?, NSString?) -> Void) {
        do {
            let payload = try JSONEncoder().encode(operation())
            reply(payload, nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    private func resolveUUID(_ rawValue: String) throws -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        return uuid
    }
}
