#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ServiceSessionLifecycleScenariosTests {
    @Test func localClaudeDefaultSessionFreshOpenUsesProviderModuleSessionTransitionPlan() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let tracker = ProviderModuleSessionTransitionTracker()
        let lifecycle = fixture.makeLifecycle(
            providerModule: RecordingSessionTransitionProviderModule(
                providerID: .claude,
                tracker: tracker
            )
        )

        _ = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude
        )

        #expect(tracker.requests == [
            .openFresh(.launchDefaultSession(workspaceID: fixture.workspace.id))
        ])
    }

    @Test func localPiDefaultSessionFreshOpenRoutesThroughProviderModuleSeam() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let tracker = ProviderModuleFreshOpenTracker()
        let lifecycle = fixture.makeLifecycle(
            providerModule: RecordingFreshOpenProviderModule(
                providerID: .pi,
                tracker: tracker
            )
        )

        _ = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )

        #expect(tracker.requests == [
            .launchDefaultSession(workspaceID: fixture.workspace.id)
        ])
    }

    @Test func localPiNamedSessionFreshOpenRoutesThroughProviderModuleSeam() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let tracker = ProviderModuleFreshOpenTracker()
        let lifecycle = fixture.makeLifecycle(
            providerModule: RecordingFreshOpenProviderModule(
                providerID: .pi,
                tracker: tracker
            )
        )

        _ = try await lifecycle.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi,
            name: "Review"
        )

        #expect(tracker.requests == [
            .createNamedSession(workspaceID: fixture.workspace.id)
        ])
    }

    @Test func localPiDefaultSessionLaunchUsesProviderModuleSupportAndStructuredPrelaunchSurface() async throws {
        let fixture = try ServiceSessionLifecycleFixture(
            health: ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/pi",
                launchability: .launchable
            )
        )
        let lifecycle = fixture.makeLifecycle(
            providerModule: PiProviderModule()
        )

        let session = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let launch = try #require(fixture.tracker.freshLaunches.first)
        let launchSnapshot = try #require(try fixture.store.launchSnapshot(sessionID: session.id))

        #expect(session.providerID == .pi)
        #expect(session.isDefault)
        #expect(session.state == .ready)
        #expect(launch.launchSnapshot.primarySurface == .structuredActivityFeed)
        #expect(launchSnapshot.primarySurface == .structuredActivityFeed)
    }

    @Test func localPiNamedSessionLaunchUsesProviderModuleSupportAndStructuredPrelaunchSurface() async throws {
        let fixture = try ServiceSessionLifecycleFixture(
            health: ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/pi",
                launchability: .launchable
            )
        )
        let lifecycle = fixture.makeLifecycle(
            providerModule: PiProviderModule()
        )

        let session = try await lifecycle.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi,
            name: "Review"
        )
        let launch = try #require(fixture.tracker.freshLaunches.first)
        let launchSnapshot = try #require(try fixture.store.launchSnapshot(sessionID: session.id))

        #expect(session.providerID == .pi)
        #expect(session.isDefault == false)
        #expect(session.name == "Review")
        #expect(session.state == .ready)
        #expect(launch.launchSnapshot.primarySurface == .structuredActivityFeed)
        #expect(launchSnapshot.primarySurface == .structuredActivityFeed)
    }

    @Test func launchOrResumeSessionPlansPersistedLaunchThroughSessionModule() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let existingSession = try fixture.store.createDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            state: .ready,
            failureMessage: nil
        )
        let lifecycle = fixture.makeLifecycle()

        let resumedSession = try await lifecycle.launchOrResumeSession(sessionID: existingSession.id)
        let launchSnapshot = try #require(try fixture.store.launchSnapshot(sessionID: existingSession.id))

        #expect(resumedSession.id == existingSession.id)
        #expect(fixture.tracker.resumedSessions.isEmpty)
        #expect(fixture.tracker.persistedLaunchExecutions == [
            PersistedLaunchExecutionExpectation(
                sessionID: existingSession.id,
                mode: .launchFresh(forceFreshRemoteRuntime: false),
                launchSnapshot: launchSnapshot
            )
        ])
        #expect(fixture.tracker.freshLaunches.isEmpty)
    }

    @Test func launchOrResumeDefaultSessionPlansExistingDefaultSessionThroughSessionModule() async throws {
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
        let launchSnapshot = try #require(try fixture.store.launchSnapshot(sessionID: existingSession.id))

        #expect(resumedSession.id == existingSession.id)
        #expect(fixture.tracker.resumedSessions.isEmpty)
        #expect(fixture.tracker.persistedLaunchExecutions == [
            PersistedLaunchExecutionExpectation(
                sessionID: existingSession.id,
                mode: .launchFresh(forceFreshRemoteRuntime: false),
                launchSnapshot: launchSnapshot
            )
        ])
        #expect(fixture.tracker.freshLaunches.isEmpty)
    }

    @Test func explicitResumePlansRemoteRecoveryThroughSessionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let store = try NexusMetadataStore(storeURL: rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false))
        let group = try store.createWorkspaceGroup(name: "Remote")
        let host = try store.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        let workspace = try store.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let existingSession = try store.createDefaultSession(
            workspaceID: workspace.id,
            providerID: .pi,
            state: .interrupted,
            failureMessage: "Session interrupted"
        )
        let launchSnapshot = try store.ensureLaunchSnapshot(
            sessionID: existingSession.id,
            workspaceID: workspace.id,
            providerID: .pi,
            primarySurface: .structuredActivityFeed,
            resolvedExecutable: "/tmp/pi",
            resolvedWorkingDirectory: workspace.folderPath
        )
        let tracker = SessionLifecycleTracker()
        let lifecycle = ServiceSessionLifecycle(
            dependencies: ServiceSessionLifecycleDependencies(
                workspace: { try store.workspace(id: $0) },
                sessionRecordStore: TrackingSessionRecordStore(metadataStore: store),
                providerModule: { providerID in
                    GenericProviderModule(
                        adapter: ServiceProviderAdapter(
                            providerID: providerID,
                            supportsDefaultSessionLaunch: true,
                            supportsNamedSessions: true,
                            healthSummaryEvaluator: { _, _, _ in
                                ProviderHealthSummary(
                                    state: .available,
                                    summary: "Ready",
                                    resolvedExecutable: "/tmp/pi",
                                    launchability: .launchable
                                )
                            }
                        )
                    )
                },
                remoteWorkspaceHealthContext: { _ in Optional<RemoteWorkspaceHealthContext>.none },
                providerHealthSummary: { _, _, _ in
                    ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: "/tmp/pi",
                        launchability: .launchable
                    )
                },
                resolveNamedSessionName: { requestedName, _ in requestedName ?? "Session 1" },
                reconcileSessionRuntimeState: { $0 },
                sessionMayRemainReadyWithoutRuntime: { _, _ in false },
                hasRuntime: { _ in false },
                runtimeState: { _ in .interrupted },
                executePersistedSessionLaunch: { execution in
                    tracker.persistedLaunchExecutions.append(
                        PersistedLaunchExecutionExpectation(
                            sessionID: execution.session.id,
                            mode: expectedMode(for: execution.mode),
                            launchSnapshot: execution.launchSnapshot
                        )
                    )
                    return execution.session
                },
                launchFreshSession: { session, workspace, launchSnapshot in
                    tracker.freshLaunches.append((session, workspace, launchSnapshot))
                    return session
                }
            )
        )

        let resumedSession = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: workspace.id,
            providerID: .pi
        )

        #expect(resumedSession.id == existingSession.id)
        #expect(resumedSession.state == .ready)
        #expect(tracker.resumedSessions.isEmpty)
        #expect(tracker.persistedLaunchExecutions == [
            PersistedLaunchExecutionExpectation(
                sessionID: existingSession.id,
                mode: .recoverRemoteRuntime,
                launchSnapshot: launchSnapshot
            )
        ])
        #expect(tracker.freshLaunches.isEmpty)
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
                providerModule: { providerID in
                    GenericProviderModule(
                        adapter: ServiceProviderAdapter(
                            providerID: providerID,
                            supportsDefaultSessionLaunch: true,
                            supportsNamedSessions: true,
                            healthSummaryEvaluator: { _, _, _ in fixture.health }
                        )
                    )
                },
                remoteWorkspaceHealthContext: { _ in Optional<RemoteWorkspaceHealthContext>.none },
                providerHealthSummary: { _, _, _ in fixture.health },
                resolveNamedSessionName: { requestedName, _ in requestedName ?? "Session 1" },
                reconcileSessionRuntimeState: { $0 },
                sessionMayRemainReadyWithoutRuntime: { _, _ in false },
                hasRuntime: { _ in false },
                runtimeState: { _ in nil },
                executePersistedSessionLaunch: { execution in
                    fixture.tracker.persistedLaunchExecutions.append(
                        PersistedLaunchExecutionExpectation(
                            sessionID: execution.session.id,
                            mode: expectedMode(for: execution.mode),
                            launchSnapshot: execution.launchSnapshot
                        )
                    )
                    return execution.session
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

    private func adapter(for providerID: ProviderID) -> GenericProviderModule {
        GenericProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: providerID,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in health }
            )
        )
    }

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

    func makeLifecycle(
        providerModule: (any ProviderModule)? = nil
    ) -> ServiceSessionLifecycle {
        ServiceSessionLifecycle(
            dependencies: ServiceSessionLifecycleDependencies(
                workspace: { try store.workspace(id: $0) },
                sessionRecordStore: TrackingSessionRecordStore(metadataStore: store),
                providerModule: { providerID in
                    providerModule ?? adapter(for: providerID)
                },
                remoteWorkspaceHealthContext: { _ in Optional<RemoteWorkspaceHealthContext>.none },
                providerHealthSummary: { _, _, _ in health },
                resolveNamedSessionName: { requestedName, _ in requestedName ?? "Session 1" },
                reconcileSessionRuntimeState: { $0 },
                sessionMayRemainReadyWithoutRuntime: { _, _ in false },
                hasRuntime: { _ in false },
                runtimeState: { _ in nil },
                executePersistedSessionLaunch: { execution in
                    tracker.persistedLaunchExecutions.append(
                        PersistedLaunchExecutionExpectation(
                            sessionID: execution.session.id,
                            mode: expectedMode(for: execution.mode),
                            launchSnapshot: execution.launchSnapshot
                        )
                    )
                    return execution.session
                },
                launchFreshSession: { session, workspace, launchSnapshot in
                    tracker.freshLaunches.append((session, workspace, launchSnapshot))
                    return session
                }
            )
        )
    }
}

private enum ProviderModuleFreshOpenRequestExpectation: Equatable {
    case launchDefaultSession(workspaceID: UUID)
    case createNamedSession(workspaceID: UUID)

    init(request: ProviderModuleFreshSessionOpenRequest) {
        switch request {
        case let .launchDefaultSession(workspace):
            self = .launchDefaultSession(workspaceID: workspace.id)
        case let .createNamedSession(workspace):
            self = .createNamedSession(workspaceID: workspace.id)
        }
    }
}

private final class ProviderModuleFreshOpenTracker: @unchecked Sendable {
    var requests: [ProviderModuleFreshOpenRequestExpectation] = []
}

private enum ProviderModuleSessionTransitionRequestExpectation: Equatable {
    case openFresh(ProviderModuleFreshOpenRequestExpectation)
    case relaunchPersisted(sessionID: UUID)

    init(request: ProviderModuleSessionTransitionRequest) {
        switch request {
        case let .openFresh(freshRequest, _):
            self = .openFresh(.init(request: freshRequest))
        case let .relaunchPersisted(relaunchRequest):
            self = .relaunchPersisted(sessionID: relaunchRequest.execution.session.id)
        }
    }
}

private final class ProviderModuleSessionTransitionTracker: @unchecked Sendable {
    var requests: [ProviderModuleSessionTransitionRequestExpectation] = []
}

private struct RecordingSessionTransitionProviderModule: ProviderModule {
    let provider: Provider
    let tracker: ProviderModuleSessionTransitionTracker

    init(providerID: ProviderID, tracker: ProviderModuleSessionTransitionTracker) {
        self.provider = Provider(id: providerID)
        self.tracker = tracker
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        true
    }

    func supportsNamedSessions(in workspace: Workspace) -> Bool {
        true
    }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: provider.id, workspace: workspace, remoteContext: remoteContext)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        ProviderCapabilities(
            launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
            createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
        )
    }

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
        .terminal
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        false
    }

    func planSessionTransition(
        _ request: ProviderModuleSessionTransitionRequest
    ) async throws -> ProviderModuleSessionTransitionPlan {
        tracker.requests.append(.init(request: request))
        switch request {
        case let .openFresh(freshRequest, actions):
            return .openFresh(try await executeSharedFreshSessionOpen(freshRequest, actions: actions))
        case let .relaunchPersisted(relaunchRequest):
            return .relaunchPersisted(planPersistedSessionRelaunch(relaunchRequest))
        }
    }

    func openFreshSession(
        _ request: ProviderModuleFreshSessionOpenRequest,
        actions: ProviderModuleFreshSessionOpenActions
    ) async throws -> ProviderModuleFreshSessionOpenResult {
        Issue.record("Fresh Session open should route through planSessionTransition")
        return try await executeSharedFreshSessionOpen(request, actions: actions)
    }
}

private struct RecordingFreshOpenProviderModule: ProviderModule {
    let provider: Provider
    let tracker: ProviderModuleFreshOpenTracker

    init(providerID: ProviderID, tracker: ProviderModuleFreshOpenTracker) {
        self.provider = Provider(id: providerID)
        self.tracker = tracker
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        true
    }

    func supportsNamedSessions(in workspace: Workspace) -> Bool {
        true
    }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: provider.id, workspace: workspace, remoteContext: remoteContext)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        ProviderCapabilities(
            launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
            createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
        )
    }

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
        .structuredActivityFeed
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        false
    }

    func openFreshSession(
        _ request: ProviderModuleFreshSessionOpenRequest,
        actions: ProviderModuleFreshSessionOpenActions
    ) async throws -> ProviderModuleFreshSessionOpenResult {
        tracker.requests.append(.init(request: request))
        return try await executeSharedFreshSessionOpen(request, actions: actions)
    }
}

private struct PersistedLaunchExecutionExpectation: Equatable {
    enum Mode: Equatable {
        case recoverRemoteRuntime
        case launchFresh(forceFreshRemoteRuntime: Bool)
    }

    let sessionID: UUID
    let mode: Mode
    let launchSnapshot: LaunchSnapshot
}

private func expectedMode(for mode: PersistedSessionLaunchMode) -> PersistedLaunchExecutionExpectation.Mode {
    switch mode {
    case .recoverRemoteRuntime:
        .recoverRemoteRuntime
    case let .launch(forceFreshRemoteRuntime):
        .launchFresh(forceFreshRemoteRuntime: forceFreshRemoteRuntime)
    }
}

private final class SessionLifecycleTracker: @unchecked Sendable {
    var resumedSessions: [(Session, Workspace)] = []
    var persistedLaunchExecutions: [PersistedLaunchExecutionExpectation] = []
    var freshLaunches: [(session: Session, workspace: Workspace, launchSnapshot: LaunchSnapshot)] = []
}
#endif
