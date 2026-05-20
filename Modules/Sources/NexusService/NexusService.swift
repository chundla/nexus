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
    func sessionScreen(for session: Session) throws -> SessionScreen
    func sendInput(_ text: String, to session: Session) throws -> SessionScreen
    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen
}

protocol SessionRuntimeLaunching {
    func makeRuntime(session: Session, workspace: Workspace, executable: String) throws -> any SessionRuntime
}

protocol SessionRuntime: AnyObject {
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
            if runtimes[session.id] == nil {
                runtimes[session.id] = try launcher.makeRuntime(session: session, workspace: workspace, executable: executable)
            }
        }
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
    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let lock = NSLock()
    private var storage: String
    private var columns: Int
    private var rows: Int

    init(executable: String, workspace: Workspace) throws {
        self.process = Process()
        self.storage = "Launching \(workspace.name) with Claude…\n"
        self.columns = 80
        self.rows = 24

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable, isDirectory: false)
        process.currentDirectoryURL = URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = ProcessInfo.processInfo.environment.merging(["TERM": "xterm-256color"]) { _, newValue in newValue }

        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false, let self else {
                return
            }

            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            self.append(text)
        }

        process.terminationHandler = { [weak self] process in
            self?.append("\n[Claude exited with status \(process.terminationStatus)]\n")
            self?.outputHandle.readabilityHandler = nil
        }

        try process.run()
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
        inputHandle.write(data)
    }

    func resize(columns: Int, rows: Int) throws {
        lock.lock()
        self.columns = max(1, columns)
        self.rows = max(1, rows)
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

        if session.state == .failed {
            return SessionScreen(session: session, transcript: session.failureMessage ?? "Session launch failed")
        }

        return try sessionRuntimeManager.sessionScreen(for: session)
    }

    func sendSessionInput(sessionID: UUID, text: String) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        guard session.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        return try sessionRuntimeManager.sendInput(text, to: session)
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        guard session.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        return try sessionRuntimeManager.resize(session: session, columns: columns, rows: rows)
    }

    private func defaultSessionSummary(for workspace: Workspace, providerID: ProviderID) throws -> ProviderDefaultSessionSummary {
        guard let session = try metadataStore.defaultSession(workspaceID: workspace.id, providerID: providerID) else {
            return ProviderDefaultSessionSummary(
                state: .notCreated,
                summary: "No default session yet",
                actionTitle: "Launch"
            )
        }

        switch session.state {
        case .ready:
            return ProviderDefaultSessionSummary(
                state: .ready,
                summary: "Default session ready",
                actionTitle: "Resume",
                sessionID: session.id
            )
        case .failed:
            return ProviderDefaultSessionSummary(
                state: .failed,
                summary: session.failureMessage ?? "Last launch failed",
                actionTitle: "Relaunch",
                sessionID: session.id
            )
        }
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
