#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct PiProviderModuleTests {
    @Test func genericProviderModuleUsesSharedFreshOpenAndPersistedRelaunchPlan() async throws {
        let module = ServiceProviderAdapter(
            providerID: .claude,
            supportsDefaultSessionLaunch: true,
            supportsNamedSessions: true,
            healthSummaryEvaluator: { _, _, _ in
                ProviderHealthSummary(state: .available, summary: "Ready", resolvedExecutable: "/tmp/fake-claude", launchability: .launchable)
            }
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Local Claude",
            kind: .local,
            folderPath: "/tmp/local-claude",
            primaryGroupID: UUID()
        )
        let launchedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Review",
            isDefault: false,
            state: .ready
        )
        let openTracker = FreshOpenActionTracker()

        let openResult = try await module.openFreshSession(
            .launchDefaultSession(workspace: workspace),
            actions: makeFreshOpenSessionActions(
                tracker: openTracker,
                providerID: .claude,
                healthSummary: { _ in
                    ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: "/tmp/fake-claude",
                        launchability: .launchable
                    )
                }
            )
        )
        let relaunchPlan = module.planPersistedSessionRelaunch(
            ProviderModulePersistedSessionRelaunchRequest(
                execution: PersistedSessionLaunchExecution(
                    session: launchedSession,
                    workspace: workspace,
                    launchSnapshot: LaunchSnapshot(
                        sessionID: launchedSession.id,
                        workspaceID: workspace.id,
                        providerID: .claude,
                        primarySurface: .terminal,
                        resolvedExecutable: "/tmp/claude",
                        resolvedWorkingDirectory: workspace.folderPath
                    ),
                    mode: .launch(forceFreshRemoteRuntime: false),
                    sessionRecordAdapterMetadataSource: .stored
                )
            )
        )

        #expect(openResult == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .terminal,
                executable: "/tmp/fake-claude"
            )
        ))
        #expect(relaunchPlan == .sharedLaunch)
        #expect(openTracker.healthRequests == [
            .init(workspaceID: workspace.id, providerID: .claude)
        ])
        #expect(try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            NSError(domain: "PiProviderModuleTests", code: 1),
            metadata: nil
        ) == false)
    }

    @Test func piProviderModuleOwnsPiLaunchSupportInsteadOfDelegatingToAdapter() {
        let module = PiProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )

        #expect(module.supportsDefaultSessionLaunch(in: workspace))
        #expect(module.supportsNamedSessions(in: workspace))
    }

    @Test func piProviderModuleHealthUsesProviderHealthEvaluatorInsteadOfAdapter() async {
        let module = PiProviderModule()
        let workspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )
        let providerHealthEvaluator = RecordingPiProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "Pi health from evaluator",
                resolvedExecutable: "/tmp/fake-pi",
                launchability: .launchable
            )
        )

        let health = await module.providerHealthSummary(
            for: workspace,
            remoteContext: nil,
            providerHealthEvaluator: providerHealthEvaluator
        )

        #expect(health.summary == "Pi health from evaluator")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .pi, workspaceID: workspace.id)
        ])
    }

    @Test func piProviderModuleOwnsRemoteHealthSnapshotReusePolicyInsteadOfDelegatingToAdapter() {
        let module = PiProviderModule()
        let workspaceID = UUID()
        let hostID = UUID()

        let shouldReuse = module.reusesRemoteHealthSnapshot(
            ProviderHealthSummary(
                state: .available,
                summary: "Pi ready",
                checkedAt: Date()
            ),
            remoteContext: RemoteWorkspaceHealthContext(
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
        )

        #expect(shouldReuse)
    }

    @Test func piProviderModulePlansRemoteRecoveryAndFreshRemoteRelaunchBehindProviderModuleSeam() {
        let module = PiProviderModule()
        let localWorkspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let localSession = Session(
            id: UUID(),
            workspaceID: localWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let remoteSession = Session(
            id: UUID(),
            workspaceID: remoteWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )

        let localPlan = module.planPersistedSessionRelaunch(
            ProviderModulePersistedSessionRelaunchRequest(
                execution: PersistedSessionLaunchExecution(
                    session: localSession,
                    workspace: localWorkspace,
                    launchSnapshot: LaunchSnapshot(
                        sessionID: localSession.id,
                        workspaceID: localWorkspace.id,
                        providerID: .pi,
                        primarySurface: .structuredActivityFeed,
                        resolvedExecutable: "/tmp/pi",
                        resolvedWorkingDirectory: localWorkspace.folderPath
                    ),
                    mode: .launch(forceFreshRemoteRuntime: false),
                    sessionRecordAdapterMetadataSource: .stored
                )
            )
        )
        let remoteRecoveryPlan = module.planPersistedSessionRelaunch(
            ProviderModulePersistedSessionRelaunchRequest(
                execution: PersistedSessionLaunchExecution(
                    session: remoteSession,
                    workspace: remoteWorkspace,
                    launchSnapshot: LaunchSnapshot(
                        sessionID: remoteSession.id,
                        workspaceID: remoteWorkspace.id,
                        providerID: .pi,
                        primarySurface: .structuredActivityFeed,
                        resolvedExecutable: "/tmp/pi",
                        resolvedWorkingDirectory: remoteWorkspace.folderPath
                    ),
                    mode: .recoverRemoteRuntime,
                    sessionRecordAdapterMetadataSource: .stored
                )
            )
        )
        let remoteFreshPlan = module.planPersistedSessionRelaunch(
            ProviderModulePersistedSessionRelaunchRequest(
                execution: PersistedSessionLaunchExecution(
                    session: remoteSession,
                    workspace: remoteWorkspace,
                    launchSnapshot: LaunchSnapshot(
                        sessionID: remoteSession.id,
                        workspaceID: remoteWorkspace.id,
                        providerID: .pi,
                        primarySurface: .structuredActivityFeed,
                        resolvedExecutable: "/tmp/pi",
                        resolvedWorkingDirectory: remoteWorkspace.folderPath
                    ),
                    mode: .launch(forceFreshRemoteRuntime: true),
                    sessionRecordAdapterMetadataSource: .stored
                )
            )
        )

        #expect(localPlan == .sharedLaunch)
        #expect(remoteRecoveryPlan == .recoverRemoteRuntime(
            ProviderModuleFreshRemotePersistedSessionRelaunch(
                sessionRecordAdapterMetadataSource: .stored,
                retriesWithoutContinuity: true
            )
        ))
        #expect(remoteFreshPlan == .launchFreshRemoteRuntime(
            ProviderModuleFreshRemotePersistedSessionRelaunch(
                sessionRecordAdapterMetadataSource: .stored,
                retriesWithoutContinuity: true
            )
        ))
    }

    @Test func serviceProviderRegistryRoutesPiThroughPiProviderModule() {
        let registry = ServiceSessionProviderRegistry.providerModules(
            providerAdapters: [
                .claude: ServiceProviderAdapter(
                    providerID: .claude,
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Claude ready",
                            resolvedExecutable: "/tmp/fake-claude",
                            launchability: .launchable
                        )
                    },
                    primarySurfaceEvaluator: { _ in .terminal }
                ),
                .pi: ServiceProviderAdapter(
                    providerID: .pi,
                    supportsDefaultSessionLaunch: false,
                    supportsNamedSessions: false,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(state: .misconfigured, summary: "Adapter health should be ignored")
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
            name: "Local Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: UUID()
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
        let checkedSnapshot = ProviderHealthSummary(
            state: .available,
            summary: "reuse me",
            checkedAt: Date()
        )

        let piModule = registry.module(for: .pi)
        let claudeModule = registry.module(for: .claude)

        #expect(piModule.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(claudeModule.prelaunchPrimarySurface(in: workspace) == .terminal)
        #expect(piModule.reusesRemoteHealthSnapshot(checkedSnapshot, remoteContext: remoteContext))
        #expect(claudeModule.reusesRemoteHealthSnapshot(checkedSnapshot, remoteContext: remoteContext) == false)
    }

    @Test func piProviderModuleOwnsFreshOpenPlanningForLocalAndRemotePiSessions() async throws {
        let module = PiProviderModule()
        let localWorkspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let tracker = FreshOpenActionTracker()
        let actions = makeFreshOpenSessionActions(
            tracker: tracker,
            providerID: .pi,
            healthSummary: { workspace in
                ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: workspace.kind == .remote ? "/tmp/remote-pi" : "/tmp/local-pi",
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
                executable: "/tmp/local-pi"
            )
        ))
        #expect(localNamedOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .structuredActivityFeed,
                executable: "/tmp/local-pi"
            )
        ))
        #expect(remoteDefaultOpen == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .structuredActivityFeed,
                executable: "/tmp/remote-pi"
            )
        ))
        #expect(tracker.healthRequests == [
            .init(workspaceID: localWorkspace.id, providerID: .pi),
            .init(workspaceID: localWorkspace.id, providerID: .pi),
            .init(workspaceID: remoteWorkspace.id, providerID: .pi)
        ])
    }

    @Test func piProviderModuleRetriesFreshRemotePersistedRelaunchWithoutContinuityOnlyForRejectedPiLinkage() throws {
        let module = PiProviderModule()
        let linkageMetadata = PiSessionLinkage(
            piSessionID: "pi-session-1",
            sessionFile: "/tmp/pi-session-1.jsonl"
        ).sessionRecordAdapterMetadata

        let invalidPiSessionRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            NSError(
                domain: "PiProviderModuleTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Pi session linkage"]
            ),
            metadata: linkageMetadata
        )
        let missingSessionRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            NSError(
                domain: "PiProviderModuleTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "session not found"]
            ),
            metadata: linkageMetadata
        )
        let unrelatedErrorRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            NSError(
                domain: "PiProviderModuleTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "permission denied"]
            ),
            metadata: linkageMetadata
        )
        let missingMetadataRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            NSError(
                domain: "PiProviderModuleTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Pi session linkage"]
            ),
            metadata: nil
        )

        #expect(invalidPiSessionRetry)
        #expect(missingSessionRetry)
        #expect(unrelatedErrorRetry == false)
        #expect(missingMetadataRetry == false)
    }

    @Test func piProviderModulePreservesPiCatalogReadBehavior() async {
        let module = PiProviderModule()
        let workspaceID = UUID()
        let hostID = UUID()
        let workspace = Workspace(
            id: workspaceID,
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )
        let providerHealthEvaluator = RecordingPiProviderHealthEvaluator(
            summary: ProviderHealthSummary(
                state: .available,
                summary: "Pi module health",
                resolvedExecutable: "/tmp/fake-pi",
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
            remoteContext: nil,
            providerHealthEvaluator: providerHealthEvaluator
        )
        let capabilities = module.providerCapabilities(in: workspace, health: health, defaultSession: nil)

        #expect(health.summary == "Pi module health")
        #expect(providerHealthEvaluator.requests == [
            .init(providerID: .pi, workspaceID: workspace.id)
        ])
        #expect(capabilities.launchDefaultSession.isEnabled)
        #expect(capabilities.createNamedSession.isEnabled)
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(module.reusesRemoteHealthSnapshot(
            ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
            remoteContext: remoteContext
        ))
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

private final class RecordingPiProviderHealthEvaluator: @unchecked Sendable, ProviderHealthEvaluating {
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
