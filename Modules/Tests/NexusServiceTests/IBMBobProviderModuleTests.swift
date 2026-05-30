#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct IBMBobProviderModuleTests {
    @Test func serviceProviderRegistryRoutesIBMBobThroughIBMBobProviderModule() {
        let registry = ServiceSessionProviderRegistry.providerModules(
            providerAdapters: [
                .ibmBob: ServiceProviderAdapter(
                    providerID: .ibmBob,
                    supportsDefaultSessionLaunch: false,
                    supportsNamedSessions: false,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(state: .misconfigured, summary: "Adapter health should stay behind the seam")
                    },
                    primarySurfaceEvaluator: { _ in .terminal }
                )
            ]
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Remote IBM Bob",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )

        let module = registry.module(for: .ibmBob)

        #expect(module.supportsDefaultSessionLaunch(in: workspace))
        #expect(module.supportsNamedSessions(in: workspace))
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
    }

    @Test func ibmBobProviderModuleRelaunchesInterruptedSessionsWithExplicitIdleContinuity() {
        let module = IBMBobProviderModule()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .interrupted
        )
        let storedActivityItems = [
            SessionActivityItem(kind: .message, text: "You: ship it"),
            SessionActivityItem(kind: .message, text: "Done")
        ]

        let storedMetadata = SessionRecordAdapterMetadata.ibmBob(
            sessionID: "bob-session-123",
            activityItems: storedActivityItems,
            turnInProgress: true
        )

        let source = module.persistedSessionRelaunchMetadataSource(
            for: session,
            storedMetadata: storedMetadata
        )

        guard case let .explicit(metadata) = source else {
            Issue.record("Expected explicit IBM Bob continuity for interrupted relaunch")
            return
        }

        #expect(metadata?.ibmBobSessionLinkage?.sessionID == "bob-session-123")
        #expect(metadata?.ibmBobSessionLinkage?.persistedActivityItems == storedActivityItems)
        #expect(metadata?.ibmBobSessionLinkage?.turnInProgress == false)
    }

    @Test func ibmBobProviderModuleKeepsIdleStructuredSessionsReadyWithoutRuntime() {
        let module = IBMBobProviderModule()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )

        let mayRemainReady = module.sessionMayRemainReadyWithoutRuntime(
            session,
            workspace: nil,
            persistedPrimarySurface: .structuredActivityFeed,
            storedMetadata: SessionRecordAdapterMetadata.ibmBob(
                sessionID: "bob-session-123",
                activityItems: [SessionActivityItem(kind: .message, text: "Done")],
                turnInProgress: false
            )
        )

        #expect(mayRemainReady)
    }

    @Test func ibmBobProviderModuleChoosesLocalProtocolNativeRuntimeConstructionThroughProviderModuleSeam() async throws {
        let module = IBMBobProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Local IBM Bob",
            kind: .local,
            folderPath: "/tmp/local-ibm-bob",
            primaryGroupID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )
        let tracker = IBMBobRuntimeConstructionTracker()

        let runtime = try await module.constructRuntime(
            for: session,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/tmp/fake-bob",
                workingDirectory: workspace.folderPath,
                remoteHost: nil
            ),
            actions: ProviderModuleRuntimeConstructionActions(
                makeLocalTerminalRuntime: {
                    Issue.record("IBM Bob should not choose a terminal runtime for local structured Sessions")
                    return StaticIBMBobRuntime()
                },
                makeRemoteTerminalRuntime: {
                    Issue.record("IBM Bob should not choose a terminal runtime for local structured Sessions")
                    return StaticIBMBobRuntime()
                },
                makeLocalProtocolNativeRuntime: {
                    tracker.requests.append(.localProtocolNative)
                    return StaticIBMBobRuntime()
                },
                makeRemoteProtocolNativeRuntime: {
                    Issue.record("IBM Bob should not choose a remote runtime for local structured Sessions")
                    return StaticIBMBobRuntime()
                }
            )
        )

        #expect(tracker.requests == [.localProtocolNative])
        #expect(runtime?.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
    }

    @Test func ibmBobProviderModuleChoosesRemoteProtocolNativeRuntimeConstructionThroughProviderModuleSeam() async throws {
        let module = IBMBobProviderModule()
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")
        let workspace = Workspace(
            id: UUID(),
            name: "Remote IBM Bob",
            kind: .remote,
            folderPath: "/srv/bob",
            primaryGroupID: UUID(),
            remoteHostID: host.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )
        let tracker = IBMBobRuntimeConstructionTracker()

        let runtime = try await module.constructRuntime(
            for: session,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/home/tester/.local/bin/bob",
                workingDirectory: workspace.folderPath,
                remoteHost: host,
                remoteRuntimeIdentifier: "nexus-runtime-1"
            ),
            actions: ProviderModuleRuntimeConstructionActions(
                makeLocalTerminalRuntime: {
                    Issue.record("IBM Bob should not choose a terminal runtime for remote structured Sessions")
                    return StaticIBMBobRuntime()
                },
                makeRemoteTerminalRuntime: {
                    Issue.record("IBM Bob should not choose a terminal runtime for remote structured Sessions")
                    return StaticIBMBobRuntime()
                },
                makeLocalProtocolNativeRuntime: {
                    Issue.record("IBM Bob should not choose a local runtime for remote structured Sessions")
                    return StaticIBMBobRuntime()
                },
                makeRemoteProtocolNativeRuntime: {
                    tracker.requests.append(.remoteProtocolNative)
                    return StaticIBMBobRuntime()
                }
            )
        )

        #expect(tracker.requests == [.remoteProtocolNative])
        #expect(runtime?.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
    }

    @Test func ibmBobProviderModulePreservesIBMBobCatalogReadBehavior() async throws {
        let module = IBMBobProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Local IBM Bob",
            kind: .local,
            folderPath: "/tmp/local-ibm-bob",
            primaryGroupID: UUID()
        )
        let providerHealthEvaluator = RecordingIBMBobProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "IBM Bob module health",
                resolvedExecutable: "/tmp/fake-bob",
                launchability: .launchable
            )
        )

        let catalogRead = try await module.readCatalog(
            ProviderModuleCatalogReadRequest(
                workspace: workspace,
                remoteContext: nil,
                defaultSession: nil
            ),
            actions: ProviderModuleCatalogReadActions(
                providerHealthSummary: {
                    await module.providerHealthSummary(
                        for: workspace,
                        remoteContext: nil,
                        providerHealthEvaluator: providerHealthEvaluator
                    )
                }
            )
        )

        #expect(catalogRead.health.summary == "IBM Bob module health")
        #expect(providerHealthEvaluator.requests == [.init(providerID: .ibmBob, workspaceID: workspace.id)])
        #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
        #expect(catalogRead.capabilities.createNamedSession.isEnabled)
        #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(module.reusesRemoteHealthSnapshot(ProviderHealthSummary(state: .available, summary: "snapshot", checkedAt: Date()), remoteContext: nil) == false)
    }

    @Test func persistedIBMBobRelaunchUsesProviderModuleSessionTransitionPlan() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IBMBobProviderModuleTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let initialService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ReadyIBMBobProviderHealthEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingStaticIBMBobRuntimeLauncher())
        )
        let group = try initialService.createWorkspaceGroup(name: "Solo Group")
        let workspace = try initialService.createLocalWorkspace(
            name: "Local IBM Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try initialService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)

        let tracker = IBMBobProviderModuleSessionTransitionTracker()
        let relaunchedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ReadyIBMBobProviderHealthEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingStaticIBMBobRuntimeLauncher()),
            providerModuleRegistry: ProviderModuleRegistry(
                modules: [
                    .ibmBob: TrackingIBMBobSessionTransitionProviderModule(tracker: tracker)
                ]
            )
        )

        _ = try relaunchedService.launchOrResumeSession(sessionID: session.id)

        #expect(tracker.requests == [.relaunchPersisted(sessionID: session.id)])
    }

    @Test func bootstrappedIBMBobServiceUsesProviderModuleRuntimeConstructionByDefault() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IBMBobProviderModuleTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let tracker = IBMBobRuntimeConstructionTracker()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ReadyIBMBobProviderHealthEvaluator(),
            providerModuleRegistry: ProviderModuleRegistry(
                modules: [
                    .ibmBob: RuntimeTrackingIBMBobProviderModule(tracker: tracker)
                ]
            )
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local IBM Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        _ = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)

        #expect(tracker.requests == [.localProtocolNative])
    }
}

private enum IBMBobProviderModuleSessionTransitionRequestExpectation: Equatable {
    case relaunchPersisted(sessionID: UUID)

    init(request: ProviderModuleSessionTransitionRequest) {
        switch request {
        case .openFresh:
            Issue.record("Persisted relaunch test should not open a fresh Session")
            self = .relaunchPersisted(sessionID: UUID())
        case let .relaunchPersisted(relaunchRequest):
            self = .relaunchPersisted(sessionID: relaunchRequest.execution.session.id)
        }
    }
}

private final class IBMBobProviderModuleSessionTransitionTracker: @unchecked Sendable {
    var requests: [IBMBobProviderModuleSessionTransitionRequestExpectation] = []
}

private struct TrackingIBMBobSessionTransitionProviderModule: ProviderModule {
    let provider = Provider(id: .ibmBob)
    let tracker: IBMBobProviderModuleSessionTransitionTracker

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
    func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: .ibmBob, workspace: workspace, remoteContext: remoteContext)
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
        .structuredActivityFeed
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
        return .relaunchPersisted(.sharedLaunch)
    }

    func planPersistedSessionRelaunch(
        _ request: ProviderModulePersistedSessionRelaunchRequest
    ) -> ProviderModulePersistedSessionRelaunchPlan {
        Issue.record("Persisted relaunch should route through planSessionTransition")
        return .sharedLaunch
    }
}

private enum IBMBobRuntimeConstructionRequest: Equatable {
    case localProtocolNative
    case remoteProtocolNative
}

private final class IBMBobRuntimeConstructionTracker: @unchecked Sendable {
    var requests: [IBMBobRuntimeConstructionRequest] = []
}

private struct RuntimeTrackingIBMBobProviderModule: ProviderModule {
    let provider = Provider(id: .ibmBob)
    let tracker: IBMBobRuntimeConstructionTracker

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
    func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: .ibmBob, workspace: workspace, remoteContext: remoteContext)
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
        .structuredActivityFeed
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
        tracker.requests.append(.localProtocolNative)
        return StaticIBMBobRuntime()
    }
}

private final class RecordingStaticIBMBobRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        StaticIBMBobRuntime()
    }
}

private struct ReadyIBMBobProviderHealthEvaluator: ProviderHealthEvaluating {
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

private final class RecordingIBMBobProviderHealthEvaluator: @unchecked Sendable, ProviderHealthEvaluating {
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

private final class StaticIBMBobRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "IBM Bob ready")]
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
    func stop() throws { state = .exited }
    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}
}
#endif
