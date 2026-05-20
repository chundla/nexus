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
            return SessionScreen(session: resolvedSession, transcript: resolvedSession.failureMessage ?? "Session launch failed")
        case .interrupted:
            return SessionScreen(session: resolvedSession, transcript: resolvedSession.failureMessage ?? "Session interrupted")
        case .exited:
            if sessionRuntimeManager.hasRuntime(for: resolvedSession) {
                return try sessionRuntimeManager.sessionScreen(for: resolvedSession)
            }
            return SessionScreen(session: resolvedSession, transcript: resolvedSession.failureMessage ?? "Session exited")
        case .ready:
            return try sessionRuntimeManager.sessionScreen(for: resolvedSession)
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

        return try sessionRuntimeManager.sendInput(text, to: resolvedSession)
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        return try sessionRuntimeManager.resize(session: resolvedSession, columns: columns, rows: rows)
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
