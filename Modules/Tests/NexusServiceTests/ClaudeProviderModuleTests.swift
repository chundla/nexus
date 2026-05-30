#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ClaudeProviderModuleTests {
    @Test func serviceProviderRegistryRoutesClaudeThroughClaudeProviderModule() {
        let registry = ServiceSessionProviderRegistry.providerModules(
            providerAdapters: [
                .claude: ServiceProviderAdapter(
                    providerID: .claude,
                    supportsDefaultSessionLaunch: false,
                    supportsNamedSessions: false,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(state: .misconfigured, summary: "Adapter health should stay behind the seam")
                    },
                    primarySurfaceEvaluator: { _ in .structuredActivityFeed },
                    shouldReuseRemoteHealthSnapshot: { _, _ in false }
                )
            ]
        )
        let workspaceID = UUID()
        let hostID = UUID()
        let workspace = Workspace(
            id: workspaceID,
            name: "Remote Claude",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: hostID
        )
        let remoteContext = RemoteWorkspaceHealthContext(
            host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
            hostValidation: HostValidationSnapshot(
                hostID: hostID,
                state: .available,
                summary: "Host is available",
                checkedAt: Date()
            ),
            workspaceAvailability: WorkspaceAvailabilitySnapshot(
                workspaceID: workspaceID,
                state: .available,
                summary: "Workspace is available",
                checkedAt: Date()
            )
        )

        let module = registry.module(for: .claude)

        #expect(module.supportsDefaultSessionLaunch(in: workspace))
        #expect(module.supportsNamedSessions(in: workspace))
        #expect(module.prelaunchPrimarySurface(in: workspace) == .terminal)
        #expect(module.reusesRemoteHealthSnapshot(
            ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
            remoteContext: remoteContext
        ))
    }

    @Test func claudeProviderModuleHealthUsesProviderHealthEvaluatorInsteadOfAdapter() async {
        let module = ClaudeProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Local Claude",
            kind: .local,
            folderPath: "/tmp/local-claude",
            primaryGroupID: UUID()
        )
        let providerHealthEvaluator = RecordingClaudeProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "Claude health from evaluator",
                resolvedExecutable: "/tmp/fake-claude",
                launchability: .launchable
            )
        )

        let health = await module.providerHealthSummary(
            for: workspace,
            remoteContext: nil,
            providerHealthEvaluator: providerHealthEvaluator
        )

        #expect(health.summary == "Claude health from evaluator")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .claude, workspaceID: workspace.id)
        ])
    }

    @Test func claudeProviderModuleOwnsFreshOpenPlanningForLocalAndRemoteClaudeSessions() async throws {
        let module = ClaudeProviderModule()
        let localWorkspace = Workspace(
            id: UUID(),
            name: "Local Claude",
            kind: .local,
            folderPath: "/tmp/local-claude",
            primaryGroupID: UUID()
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Claude",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let tracker = FreshOpenActionTracker()
        let actions = makeFreshOpenSessionActions(
            tracker: tracker,
            providerID: .claude,
            healthSummary: { workspace in
                ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: workspace.kind == .remote ? "/tmp/remote-claude" : "/tmp/local-claude",
                    launchability: .launchable
                )
            }
        )

        let localDefaultOpen = try await module.openFreshSession(
            .launchDefaultSession(workspace: localWorkspace),
            actions: actions
        )
        let localNamedOpen = try await module.openFreshSession(
            .createNamedSession(workspace: localWorkspace),
            actions: actions
        )
        let remoteDefaultOpen = try await module.openFreshSession(
            .launchDefaultSession(workspace: remoteWorkspace),
            actions: actions
        )

        #expect(localDefaultOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .terminal,
                executable: "/tmp/local-claude"
            )
        ))
        #expect(localNamedOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .terminal,
                executable: "/tmp/local-claude"
            )
        ))
        #expect(remoteDefaultOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .terminal,
                executable: "/tmp/remote-claude"
            )
        ))
        #expect(tracker.healthRequests == [
            .init(workspaceID: localWorkspace.id, providerID: .claude),
            .init(workspaceID: localWorkspace.id, providerID: .claude),
            .init(workspaceID: remoteWorkspace.id, providerID: .claude)
        ])
    }

    @Test func claudeProviderModulePreservesClaudeCatalogReadBehavior() async throws {
        let module = ClaudeProviderModule()
        let workspaceID = UUID()
        let hostID = UUID()
        let workspace = Workspace(
            id: workspaceID,
            name: "Remote Claude",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: hostID
        )
        let providerHealthEvaluator = RecordingClaudeProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "Claude module health",
                resolvedExecutable: "/tmp/fake-claude",
                launchability: .launchable
            )
        )
        let remoteContext = RemoteWorkspaceHealthContext(
            host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
            hostValidation: HostValidationSnapshot(
                hostID: hostID,
                state: .available,
                summary: "Host is available",
                checkedAt: Date()
            ),
            workspaceAvailability: WorkspaceAvailabilitySnapshot(
                workspaceID: workspaceID,
                state: .available,
                summary: "Workspace is available",
                checkedAt: Date()
            )
        )

        let catalogRead = try await module.readCatalog(
            ProviderModuleCatalogReadRequest(
                workspace: workspace,
                remoteContext: remoteContext,
                defaultSession: nil
            ),
            actions: ProviderModuleCatalogReadActions(
                providerHealthSummary: {
                    await module.providerHealthSummary(
                        for: workspace,
                        remoteContext: remoteContext,
                        providerHealthEvaluator: providerHealthEvaluator
                    )
                }
            )
        )

        #expect(catalogRead.health.summary == "Claude module health")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .claude, workspaceID: workspace.id)
        ])
        #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
        #expect(catalogRead.capabilities.createNamedSession.isEnabled)
        #expect(catalogRead.prelaunchPrimarySurface == .terminal)
        #expect(module.reusesRemoteHealthSnapshot(
            ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
            remoteContext: remoteContext
        ))
    }

    @Test func claudeProviderModuleKeepsSharedPersistedRelaunchPlan() {
        let module = ClaudeProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Remote Claude",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let execution = PersistedSessionLaunchExecution(
            session: session,
            workspace: workspace,
            launchSnapshot: LaunchSnapshot(
                sessionID: session.id,
                workspaceID: workspace.id,
                providerID: .claude,
                primarySurface: .terminal,
                resolvedExecutable: "/tmp/claude",
                resolvedWorkingDirectory: workspace.folderPath
            ),
            mode: .recoverRemoteRuntime,
            sessionRecordAdapterMetadataSource: .stored
        )

        #expect(module.planPersistedSessionRelaunch(.init(execution: execution)) == .sharedLaunch)
    }

    @Test func persistedClaudeRelaunchUsesProviderModuleSessionTransitionPlan() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeProviderModuleTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let initialService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ReadyClaudeProviderHealthEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingStaticClaudeRuntimeLauncher())
        )
        let group = try initialService.createWorkspaceGroup(name: "Solo Group")
        let workspace = try initialService.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try initialService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: ProviderID.claude)

        let tracker = ProviderModuleSessionTransitionTracker()
        let relaunchedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ReadyClaudeProviderHealthEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingStaticClaudeRuntimeLauncher()),
            providerModuleRegistry: ProviderModuleRegistry(
                modules: [
                    .claude: TrackingClaudeSessionTransitionProviderModule(tracker: tracker)
                ]
            )
        )

        _ = try relaunchedService.launchOrResumeSession(sessionID: session.id)

        #expect(tracker.requests == [
            .relaunchPersisted(sessionID: session.id)
        ])
    }

    @Test func bootstrappedClaudeServiceUsesProviderModuleRuntimeConstructionByDefault() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeProviderModuleTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let tracker = ClaudeRuntimeConstructionTracker()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ReadyClaudeProviderHealthEvaluator(),
            providerModuleRegistry: ProviderModuleRegistry(
                modules: [
                    .claude: RuntimeTrackingClaudeProviderModule(tracker: tracker)
                ]
            )
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        _ = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        #expect(tracker.requests == [.localTerminal])
    }
}

private func makeFreshOpenSessionActions(
    tracker: FreshOpenActionTracker,
    providerID: ProviderID,
    healthSummary: @escaping (Workspace) -> ProviderHealthSummary
) -> ProviderModuleFreshSessionOpenActions {
    ProviderModuleFreshSessionOpenActions(
        providerHealthSummary: { workspace in
            tracker.healthRequests.append(.init(workspaceID: workspace.id, providerID: providerID))
            return healthSummary(workspace)
        }
    )
}

private final class FreshOpenActionTracker: @unchecked Sendable {
    struct SessionRequest: Equatable {
        let workspaceID: UUID
        let providerID: ProviderID
    }

    var healthRequests: [SessionRequest] = []
}

private enum ProviderModuleSessionTransitionRequestExpectation: Equatable {
    case openFresh
    case relaunchPersisted(sessionID: UUID)

    init(request: ProviderModuleSessionTransitionRequest) {
        switch request {
        case .openFresh:
            self = .openFresh
        case let .relaunchPersisted(relaunchRequest):
            self = .relaunchPersisted(sessionID: relaunchRequest.execution.session.id)
        }
    }
}

private final class ProviderModuleSessionTransitionTracker: @unchecked Sendable {
    var requests: [ProviderModuleSessionTransitionRequestExpectation] = []
}

private struct TrackingClaudeSessionTransitionProviderModule: ProviderModule {
    let provider = Provider(id: .claude)
    let tracker: ProviderModuleSessionTransitionTracker

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
    func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: .claude, workspace: workspace, remoteContext: remoteContext)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        makeProviderCapabilities(
            provider: provider,
            supportsDefaultSessionLaunch: true,
            supportsNamedSessions: true,
            health: health,
            defaultSession: defaultSession
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
        case .openFresh:
            Issue.record("Persisted relaunch test should not open a fresh Session")
            return .openFresh(.failed("unexpected"))
        case .relaunchPersisted:
            return .relaunchPersisted(.sharedLaunch)
        }
    }

    func planPersistedSessionRelaunch(
        _ request: ProviderModulePersistedSessionRelaunchRequest
    ) -> ProviderModulePersistedSessionRelaunchPlan {
        Issue.record("Persisted relaunch should route through planSessionTransition")
        return .sharedLaunch
    }
}

private final class RecordingStaticClaudeRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        StaticClaudeSessionRuntime()
    }
}

private final class StaticClaudeSessionRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(session: session, primarySurface: .terminal, transcript: "Claude ready")
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
    func stop() throws { state = .exited }
    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}
}

private enum ClaudeRuntimeConstructionRequest: Equatable {
    case localTerminal
}

private final class ClaudeRuntimeConstructionTracker: @unchecked Sendable {
    var requests: [ClaudeRuntimeConstructionRequest] = []
}

private struct RuntimeTrackingClaudeProviderModule: ProviderModule {
    let provider = Provider(id: .claude)
    let tracker: ClaudeRuntimeConstructionTracker

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
    func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: .claude, workspace: workspace, remoteContext: remoteContext)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        makeProviderCapabilities(
            provider: provider,
            supportsDefaultSessionLaunch: true,
            supportsNamedSessions: true,
            health: health,
            defaultSession: defaultSession
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

    func constructRuntime(
        for session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration,
        actions: ProviderModuleRuntimeConstructionActions
    ) async throws -> (any SessionRuntime)? {
        tracker.requests.append(.localTerminal)
        return try actions.makeLocalTerminalRuntime()
    }
}

private struct ReadyClaudeProviderHealthEvaluator: ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        ProviderID.allCases.map { providerID in
            WorkspaceProviderCard(
                provider: Provider(id: providerID),
                health: ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
                    launchability: .launchable
                ),
                defaultSession: ProviderDefaultSessionSummary(
                    state: .notCreated,
                    summary: "No default session yet",
                    actionTitle: "Launch"
                )
            )
        }
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        ProviderHealthSummary(
            state: .available,
            summary: "Ready",
            resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
            launchability: .launchable
        )
    }
}

private final class RecordingClaudeProviderHealthEvaluator: @unchecked Sendable, ProviderHealthEvaluating {
    struct Request: Equatable {
        let providerID: ProviderID
        let workspaceID: UUID
    }

    let summary: ProviderHealthSummary
    private(set) var requests: [Request] = []

    init(summary: ProviderHealthSummary) {
        self.summary = summary
    }

    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        []
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        requests.append(.init(providerID: providerID, workspaceID: workspace.id))
        return summary
    }
}
#endif
