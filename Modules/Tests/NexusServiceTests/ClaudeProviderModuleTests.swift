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

    @Test func claudeProviderModulePreservesClaudeCatalogReadBehavior() async {
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

        let health = await module.providerHealthSummary(
            for: workspace,
            remoteContext: remoteContext,
            providerHealthEvaluator: providerHealthEvaluator
        )
        let capabilities = module.providerCapabilities(in: workspace, health: health, defaultSession: nil)

        #expect(health.summary == "Claude module health")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .claude, workspaceID: workspace.id)
        ])
        #expect(capabilities.launchDefaultSession.isEnabled)
        #expect(capabilities.createNamedSession.isEnabled)
        #expect(module.prelaunchPrimarySurface(in: workspace) == .terminal)
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
