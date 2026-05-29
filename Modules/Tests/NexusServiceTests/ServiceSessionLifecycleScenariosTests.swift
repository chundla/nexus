#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ServiceSessionLifecycleScenariosTests {
    @Test func launchOrResumeDefaultSessionReusesExistingDefaultSessionLane() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let existingSession = try fixture.store.createDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            state: .ready,
            failureMessage: nil
        )
        let lifecycle = fixture.makeLifecycle()

        let resumedSession = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude
        )

        #expect(resumedSession.id == existingSession.id)
        #expect(fixture.tracker.resumedSessions.map { $0.0.id } == [existingSession.id])
        #expect(fixture.tracker.freshLaunches.isEmpty)
    }

    @Test func createNamedSessionCreatesReadyNamedSessionAndLaunchSnapshot() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let lifecycle = fixture.makeLifecycle()

        let namedSession = try await lifecycle.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            name: "Review"
        )
        let persistedSession = try #require(try fixture.store.session(id: namedSession.id))
        let launch = try #require(fixture.tracker.freshLaunches.first)
        let launchSnapshot = try #require(try fixture.store.launchSnapshot(sessionID: namedSession.id))

        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Review")
        #expect(namedSession.state == .ready)
        #expect(persistedSession == namedSession)
        #expect(fixture.tracker.resumedSessions.isEmpty)
        #expect(launch.session.id == namedSession.id)
        #expect(launch.workspace.id == fixture.workspace.id)
        #expect(launch.launchSnapshot.resolvedExecutable == "/tmp/claude")
        #expect(launchSnapshot.sessionID == namedSession.id)
        #expect(launchSnapshot.primarySurface == .terminal)
        #expect(launchSnapshot.resolvedWorkingDirectory == fixture.workspace.folderPath)
    }

    @Test func failedDefaultLaunchCreatesInspectableFailedSessionRecord() async throws {
        let fixture = try ServiceSessionLifecycleFixture(
            health: ProviderHealthSummary(
                state: .misconfigured,
                summary: "Claude needs login",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "auth-required",
                        message: "Claude needs login"
                    )
                ]
            )
        )
        let lifecycle = fixture.makeLifecycle()

        let failedSession = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude
        )
        let persistedSession = try #require(try fixture.store.session(id: failedSession.id))

        #expect(failedSession.isDefault)
        #expect(failedSession.state == .failed)
        #expect(failedSession.failureMessage == "Claude needs login")
        #expect(persistedSession == failedSession)
        #expect(fixture.tracker.resumedSessions.isEmpty)
        #expect(fixture.tracker.freshLaunches.isEmpty)
        #expect(try fixture.store.launchSnapshot(sessionID: failedSession.id) == nil)
    }

    @Test func createNamedSessionPersistsThroughSessionRecordStoreAdapter() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let sessionRecordStore = TrackingSessionRecordStore(metadataStore: fixture.store)
        let lifecycle = ServiceSessionLifecycle(
            dependencies: ServiceSessionLifecycleDependencies(
                workspace: { try fixture.store.workspace(id: $0) },
                sessionRecordStore: sessionRecordStore,
                providerAdapter: { providerID in
                    ServiceProviderAdapter(
                        providerID: providerID,
                        supportsDefaultSessionLaunch: true,
                        supportsNamedSessions: true,
                        healthSummaryEvaluator: { _, _, _ in fixture.health }
                    )
                },
                remoteWorkspaceHealthContext: { _ in Optional<RemoteWorkspaceHealthContext>.none },
                providerHealthSummary: { _, _, _ in fixture.health },
                resolveNamedSessionName: { requestedName, _ in requestedName ?? "Session 1" },
                launchOrResumePersistedSession: { session, workspace in
                    fixture.tracker.resumedSessions.append((session, workspace))
                    return session
                },
                launchFreshSession: { session, workspace, launchSnapshot in
                    fixture.tracker.freshLaunches.append((session, workspace, launchSnapshot))
                    return session
                }
            )
        )

        let namedSession = try await lifecycle.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            name: "Review"
        )

        #expect(namedSession.name == "Review")
        #expect(sessionRecordStore.calls == [
            .listSessions(workspaceID: fixture.workspace.id, providerID: .claude),
            .createNamedSession(workspaceID: fixture.workspace.id, providerID: .claude, name: "Review", state: .ready),
            .ensureLaunchSnapshot(sessionID: namedSession.id)
        ])
    }
}

private final class TrackingSessionRecordStore: SessionRecordStore {
    enum Call: Equatable {
        case listSessions(workspaceID: UUID, providerID: ProviderID)
        case createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String, state: Session.State)
        case ensureLaunchSnapshot(sessionID: UUID)
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
        calls.append(.listSessions(workspaceID: workspaceID, providerID: providerID))
        return try metadataStore.listSessions(workspaceID: workspaceID, providerID: providerID)
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
        calls.append(.createNamedSession(workspaceID: workspaceID, providerID: providerID, name: name, state: state))
        return try metadataStore.createNamedSession(
            workspaceID: workspaceID,
            providerID: providerID,
            name: name,
            state: state,
            failureMessage: failureMessage
        )
    }

    func updateSession(id: UUID, state: Session.State, failureMessage: String?) throws -> Session {
        try metadataStore.updateSession(id: id, state: state, failureMessage: failureMessage)
    }

    func deleteSessionRecord(id: UUID) throws -> Bool {
        try metadataStore.deleteSession(id: id)
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
        calls.append(.ensureLaunchSnapshot(sessionID: sessionID))
        return try metadataStore.ensureLaunchSnapshot(
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

private struct ServiceSessionLifecycleFixture {
    let rootURL: URL
    let workspace: Workspace
    let store: NexusMetadataStore
    let tracker = SessionLifecycleTracker()
    let health: ProviderHealthSummary

    init(
        health: ProviderHealthSummary = ProviderHealthSummary(
            state: .available,
            summary: "Ready",
            resolvedExecutable: "/tmp/claude",
            launchability: .launchable
        )
    ) throws {
        self.health = health
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        store = try NexusMetadataStore(storeURL: rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false))
        let group = try store.createWorkspaceGroup(name: "Solo Group")
        workspace = try store.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
    }

    func makeLifecycle() -> ServiceSessionLifecycle {
        ServiceSessionLifecycle(
            dependencies: ServiceSessionLifecycleDependencies(
                workspace: { try store.workspace(id: $0) },
                sessionRecordStore: TrackingSessionRecordStore(metadataStore: store),
                providerAdapter: { providerID in
                    ServiceProviderAdapter(
                        providerID: providerID,
                        supportsDefaultSessionLaunch: true,
                        supportsNamedSessions: true,
                        healthSummaryEvaluator: { _, _, _ in health }
                    )
                },
                remoteWorkspaceHealthContext: { _ in Optional<RemoteWorkspaceHealthContext>.none },
                providerHealthSummary: { _, _, _ in health },
                resolveNamedSessionName: { requestedName, _ in requestedName ?? "Session 1" },
                launchOrResumePersistedSession: { session, workspace in
                    tracker.resumedSessions.append((session, workspace))
                    return session
                },
                launchFreshSession: { session, workspace, launchSnapshot in
                    tracker.freshLaunches.append((session, workspace, launchSnapshot))
                    return session
                }
            )
        )
    }
}

private final class SessionLifecycleTracker: @unchecked Sendable {
    var resumedSessions: [(Session, Workspace)] = []
    var freshLaunches: [(session: Session, workspace: Workspace, launchSnapshot: LaunchSnapshot)] = []
}
#endif
