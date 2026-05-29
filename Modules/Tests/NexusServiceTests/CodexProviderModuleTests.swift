#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct CodexProviderModuleTests {
    @Test func serviceProviderRegistryRoutesCodexThroughCodexProviderModule() {
        let registry = ServiceSessionProviderRegistry.providerModules(
            providerAdapters: [
                .codex: ServiceProviderAdapter(
                    providerID: .codex,
                    supportsDefaultSessionLaunch: false,
                    supportsNamedSessions: false,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(state: .misconfigured, summary: "Adapter health should stay behind the seam")
                    },
                    primarySurfaceEvaluator: { _ in .terminal },
                    shouldReuseRemoteHealthSnapshot: { _, _ in false }
                )
            ]
        )
        let workspaceID = UUID()
        let hostID = UUID()
        let workspace = Workspace(
            id: workspaceID,
            name: "Remote Codex",
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

        let module = registry.module(for: .codex)

        #expect(module.supportsDefaultSessionLaunch(in: workspace))
        #expect(module.supportsNamedSessions(in: workspace))
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(module.reusesRemoteHealthSnapshot(
            ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
            remoteContext: remoteContext
        ))
    }

    @Test func codexProviderModuleHealthUsesProviderHealthEvaluatorInsteadOfAdapter() async {
        let module = CodexProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Local Codex",
            kind: .local,
            folderPath: "/tmp/local-codex",
            primaryGroupID: UUID()
        )
        let providerHealthEvaluator = RecordingCodexProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "Codex health from evaluator",
                resolvedExecutable: "/tmp/fake-codex",
                launchability: .launchable
            )
        )

        let health = await module.providerHealthSummary(
            for: workspace,
            remoteContext: nil,
            providerHealthEvaluator: providerHealthEvaluator
        )

        #expect(health.summary == "Codex health from evaluator")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .codex, workspaceID: workspace.id)
        ])
    }

    @Test func codexProviderModuleOwnsFreshOpenPlanningForLocalAndRemoteCodexSessions() async throws {
        let module = CodexProviderModule()
        let localWorkspace = Workspace(
            id: UUID(),
            name: "Local Codex",
            kind: .local,
            folderPath: "/tmp/local-codex",
            primaryGroupID: UUID()
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Codex",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let tracker = FreshOpenActionTracker()
        let actions = makeFreshOpenSessionActions(
            tracker: tracker,
            providerID: .codex,
            healthSummary: { workspace in
                ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: workspace.kind == .remote ? "/tmp/remote-codex" : "/tmp/local-codex",
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
                primarySurface: .structuredActivityFeed,
                executable: "/tmp/local-codex"
            )
        ))
        #expect(localNamedOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .structuredActivityFeed,
                executable: "/tmp/local-codex"
            )
        ))
        #expect(remoteDefaultOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .structuredActivityFeed,
                executable: "/tmp/remote-codex"
            )
        ))
        #expect(tracker.healthRequests == [
            .init(workspaceID: localWorkspace.id, providerID: .codex),
            .init(workspaceID: localWorkspace.id, providerID: .codex),
            .init(workspaceID: remoteWorkspace.id, providerID: .codex)
        ])
    }

    @Test func codexProviderModulePreservesCodexCatalogReadBehavior() async {
        let module = CodexProviderModule()
        let workspaceID = UUID()
        let hostID = UUID()
        let workspace = Workspace(
            id: workspaceID,
            name: "Remote Codex",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: hostID
        )
        let providerHealthEvaluator = RecordingCodexProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "Codex module health",
                resolvedExecutable: "/tmp/fake-codex",
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

        #expect(health.summary == "Codex module health")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .codex, workspaceID: workspace.id)
        ])
        #expect(capabilities.launchDefaultSession.isEnabled)
        #expect(capabilities.createNamedSession.isEnabled)
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(module.reusesRemoteHealthSnapshot(
            ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
            remoteContext: remoteContext
        ))
    }

    @Test func codexProviderModuleKeepsSharedPersistedRelaunchPlan() {
        let module = CodexProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Remote Codex",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let execution = PersistedSessionLaunchExecution(
            session: session,
            workspace: workspace,
            launchSnapshot: LaunchSnapshot(
                sessionID: session.id,
                workspaceID: workspace.id,
                providerID: .codex,
                primarySurface: .structuredActivityFeed,
                resolvedExecutable: "/tmp/codex",
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

private final class RecordingCodexProviderHealthEvaluator: @unchecked Sendable, ProviderHealthEvaluating {
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
