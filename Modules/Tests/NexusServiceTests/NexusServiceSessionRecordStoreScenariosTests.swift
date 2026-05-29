#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceSessionRecordStoreScenariosTests {
    @Test func runtimeLinkageAndExitStatePersistThroughSessionRecordStoreAdapter() throws {
        let fixture = try NexusServiceSessionRecordStoreFixture(
            providerID: .pi,
            runtimeMetadata: PiSessionLinkage(piSessionID: "pi-session-1", sessionFile: "/tmp/pi-session.json").sessionRecordAdapterMetadata
        )

        let session = try fixture.service.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi,
            name: "Review"
        )

        #expect(
            fixture.sessionRecordStore.calls.contains(
                .saveMetadata(sessionID: session.id, providerID: .pi)
            )
        )

        let stoppedSession = try fixture.service.stopSession(sessionID: session.id)

        #expect(stoppedSession.state == .exited)
        #expect(
            fixture.sessionRecordStore.calls.contains(
                .updateState(
                    sessionID: session.id,
                    state: .exited,
                    failureMessage: "Session exited. Relaunch to start a new live runtime."
                )
            )
        )
    }

    @Test func readySessionRecordDeletionStaysBlockedBeforeSessionRecordStoreDelete() throws {
        let fixture = try NexusServiceSessionRecordStoreFixture(providerID: .claude)
        let session = try fixture.service.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            name: "Review"
        )

        #expect {
            try fixture.service.deleteSessionRecord(sessionID: session.id)
        } throws: { error in
            guard case NexusMetadataStoreError.sessionRecordDeletionRequiresStoppedSession = error else {
                return false
            }
            return true
        }
        #expect(fixture.sessionRecordStore.calls.contains { call in
            if case .deleteSessionRecord(session.id) = call {
                return true
            }
            return false
        } == false)
    }
}

private struct NexusServiceSessionRecordStoreFixture {
    let rootURL: URL
    let workspace: Workspace
    let service: NexusService
    let sessionRecordStore: TrackingServiceSessionRecordStore

    init(providerID: ProviderID, runtimeMetadata: SessionRecordAdapterMetadata? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let runtimeManager = InMemorySessionRuntimeManager(
            launcher: TrackingSessionRuntimeLauncher(runtimeMetadata: runtimeMetadata)
        )
        let health = ProviderHealthSummary(
            state: .available,
            summary: "Ready",
            resolvedExecutable: "/tmp/provider",
            launchability: .launchable
        )

        var trackingStore: TrackingServiceSessionRecordStore?
        service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(),
            sessionRuntimeManager: runtimeManager,
            sessionRecordStoreFactory: { metadataStore in
                let store = TrackingServiceSessionRecordStore(metadataStore: metadataStore)
                trackingStore = store
                return store
            },
            providerAdapters: [
                providerID: ServiceProviderAdapter(
                    providerID: providerID,
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { _, _, _ in health }
                )
            ]
        )
        sessionRecordStore = try #require(trackingStore)

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        workspace = try service.createLocalWorkspace(
            name: "Local Workspace",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
    }
}

private final class TrackingServiceSessionRecordStore: SessionRecordStore {
    enum Call: Equatable {
        case saveMetadata(sessionID: UUID, providerID: ProviderID)
        case updateState(sessionID: UUID, state: Session.State, failureMessage: String?)
        case deleteSessionRecord(UUID)
    }

    private let metadataStore: NexusMetadataStore
    private(set) var calls: [Call] = []

    init(metadataStore: NexusMetadataStore) {
        self.metadataStore = metadataStore
    }

    func defaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session? {
        try metadataStore.defaultSession(workspaceID: workspaceID, providerID: providerID)
    }

    func listSessions(workspaceID: UUID, providerID: ProviderID) throws -> [Session] {
        try metadataStore.listSessions(workspaceID: workspaceID, providerID: providerID)
    }

    func listAllSessions() throws -> [Session] {
        try metadataStore.listAllSessions()
    }

    func session(id: UUID) throws -> Session? {
        try metadataStore.session(id: id)
    }

    func createDefaultSession(
        workspaceID: UUID,
        providerID: ProviderID,
        state: Session.State,
        failureMessage: String?
    ) throws -> Session {
        try metadataStore.createDefaultSession(
            workspaceID: workspaceID,
            providerID: providerID,
            state: state,
            failureMessage: failureMessage
        )
    }

    func createNamedSession(
        workspaceID: UUID,
        providerID: ProviderID,
        name: String,
        state: Session.State,
        failureMessage: String?
    ) throws -> Session {
        try metadataStore.createNamedSession(
            workspaceID: workspaceID,
            providerID: providerID,
            name: name,
            state: state,
            failureMessage: failureMessage
        )
    }

    func updateSession(id: UUID, state: Session.State, failureMessage: String?) throws -> Session {
        let updatedSession = try metadataStore.updateSession(id: id, state: state, failureMessage: failureMessage)
        calls.append(.updateState(sessionID: id, state: state, failureMessage: failureMessage))
        return updatedSession
    }

    func deleteSessionRecord(id: UUID) throws -> Bool {
        calls.append(.deleteSessionRecord(id))
        return try metadataStore.deleteSession(id: id)
    }

    func launchSnapshot(sessionID: UUID) throws -> LaunchSnapshot? {
        try metadataStore.launchSnapshot(sessionID: sessionID)
    }

    func ensureLaunchSnapshot(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        primarySurface: SessionSurface,
        resolvedExecutable: String,
        resolvedWorkingDirectory: String
    ) throws -> LaunchSnapshot {
        try metadataStore.ensureLaunchSnapshot(
            sessionID: sessionID,
            workspaceID: workspaceID,
            providerID: providerID,
            primarySurface: primarySurface,
            resolvedExecutable: resolvedExecutable,
            resolvedWorkingDirectory: resolvedWorkingDirectory
        )
    }

    func updateLaunchSnapshotPrimarySurface(sessionID: UUID, primarySurface: SessionSurface) throws {
        try metadataStore.updateLaunchSnapshotPrimarySurface(sessionID: sessionID, primarySurface: primarySurface)
    }

    func sessionRecordAdapterMetadata(sessionID: UUID) throws -> SessionRecordAdapterMetadata? {
        try metadataStore.sessionRecordAdapterMetadata(sessionID: sessionID)
    }

    func saveSessionRecordAdapterMetadata(sessionID: UUID, metadata: SessionRecordAdapterMetadata) throws {
        try metadataStore.saveSessionRecordAdapterMetadata(sessionID: sessionID, metadata: metadata)
        calls.append(.saveMetadata(sessionID: sessionID, providerID: metadata.providerID))
    }

    func updateSessionTerminalSize(id: UUID, columns: Int, rows: Int) throws {
        try metadataStore.updateSessionTerminalSize(id: id, columns: columns, rows: rows)
    }

    func sessionTerminalSize(id: UUID) throws -> (columns: Int, rows: Int) {
        try metadataStore.sessionTerminalSize(id: id)
    }

    func remoteRuntimeGeneration(sessionID: UUID) throws -> Int {
        try metadataStore.remoteRuntimeGeneration(sessionID: sessionID)
    }

    func advanceRemoteRuntimeGeneration(sessionID: UUID) throws -> Int {
        try metadataStore.advanceRemoteRuntimeGeneration(sessionID: sessionID)
    }
}

private struct TrackingSessionRuntimeLauncher: SessionRuntimeLaunching {
    let runtimeMetadata: SessionRecordAdapterMetadata?

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        TrackingSessionRuntime(runtimeMetadata: runtimeMetadata)
    }
}

private final class TrackingSessionRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    let sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
    private var changeHandler: (@Sendable () -> Void)?

    init(runtimeMetadata: SessionRecordAdapterMetadata?) {
        sessionRecordAdapterMetadata = runtimeMetadata
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(session: session, transcript: "Provider ready")
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        changeHandler = handler
    }

    func stop() throws {
        state = .exited
        changeHandler?()
    }

    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}
}
#endif
