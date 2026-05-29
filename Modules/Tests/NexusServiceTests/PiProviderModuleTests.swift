#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct PiProviderModuleTests {
    @Test func genericProviderModuleUsesSharedFreshOpenAndPersistedLaunchActions() async throws {
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
        let launchTracker = PersistedLaunchTracker()

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
        let launchResult = try await module.launchPersistedSession(
            ProviderModulePersistedSessionLaunchRequest(
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
                ),
                actions: ProviderModulePersistedSessionLaunchActions(
                    executeSharedLaunch: {
                        launchTracker.didUseSharedLaunch = true
                        return launchedSession
                    },
                    attemptRemoteRuntimeRecovery: { launchedSession },
                    remoteRuntimeRecoveryFailureContext: { _ in
                        RemoteRuntimeRecoveryFailureContext(
                            detail: "unused",
                            normalizedDetail: "unused",
                            runtimeIdentifier: "runtime-1",
                            hostName: "Build Server"
                        )
                    },
                    persistRemoteRecoveryFailure: { _ in launchedSession },
                    attemptLaunch: { _, _ in launchedSession },
                    persistLaunchFailure: { _ in launchedSession },
                    resolvedSessionRecordAdapterMetadata: { _ in nil }
                )
            )
        )

        #expect(openResult == .launch(
            ProviderModuleFreshSessionLaunch(
                primarySurface: .terminal,
                executable: "/tmp/fake-claude"
            )
        ))
        #expect(launchResult == launchedSession)
        #expect(openTracker.healthRequests == [
            .init(workspaceID: workspace.id, providerID: .claude)
        ])
        #expect(launchTracker.didUseSharedLaunch)
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
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Pi ready",
                            resolvedExecutable: "/tmp/fake-pi",
                            launchability: .launchable
                        )
                    },
                    primarySurfaceEvaluator: { _ in .terminal },
                    shouldReuseRemoteHealthSnapshot: { snapshot, _ in
                        snapshot.summary == "reuse me"
                    }
                )
            ]
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Local Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: UUID()
        )

        let piModule = registry.module(for: .pi)
        let claudeModule = registry.module(for: .claude)

        #expect(piModule.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(claudeModule.prelaunchPrimarySurface(in: workspace) == .terminal)
        #expect(piModule.reusesRemoteHealthSnapshot(ProviderHealthSummary(state: .available, summary: "reuse me"), remoteContext: nil))
        #expect(claudeModule.reusesRemoteHealthSnapshot(ProviderHealthSummary(state: .available, summary: "reuse me"), remoteContext: nil) == false)
    }

    @Test func piProviderModuleOwnsFreshOpenPlanningForLocalAndRemotePiSessions() async throws {
        let module = PiProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(state: .available, summary: "Ready", resolvedExecutable: "/tmp/fake-pi", launchability: .launchable)
                }
            )
        )
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

    @Test func piProviderModuleOwnsRemoteRecoveryAndInvalidContinuityFallback() async throws {
        let module = PiProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(state: .available, summary: "Ready", resolvedExecutable: "/tmp/fake-pi", launchability: .launchable)
                }
            )
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: remoteWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let tracker = PersistedLaunchTracker()
        let recoveredSession = Session(
            id: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            isDefault: session.isDefault,
            state: .ready
        )

        let launchedSession = try await module.launchPersistedSession(
            ProviderModulePersistedSessionLaunchRequest(
                execution: PersistedSessionLaunchExecution(
                    session: session,
                    workspace: remoteWorkspace,
                    launchSnapshot: LaunchSnapshot(
                        sessionID: session.id,
                        workspaceID: remoteWorkspace.id,
                        providerID: .pi,
                        primarySurface: .structuredActivityFeed,
                        resolvedExecutable: "/tmp/pi",
                        resolvedWorkingDirectory: remoteWorkspace.folderPath
                    ),
                    mode: .recoverRemoteRuntime,
                    sessionRecordAdapterMetadataSource: .stored
                ),
                actions: ProviderModulePersistedSessionLaunchActions(
                    executeSharedLaunch: {
                        tracker.didUseSharedLaunch = true
                        return session
                    },
                    attemptRemoteRuntimeRecovery: {
                        throw NSError(
                            domain: "PiProviderModuleTests",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "NEXUS_REMOTE_RUNTIME_NOT_FOUND"]
                        )
                    },
                    remoteRuntimeRecoveryFailureContext: { error in
                        tracker.recoveryFailureErrors.append(error.localizedDescription)
                        return RemoteRuntimeRecoveryFailureContext(
                            detail: error.localizedDescription,
                            normalizedDetail: error.localizedDescription.lowercased(),
                            runtimeIdentifier: "runtime-1",
                            hostName: "Build Server"
                        )
                    },
                    persistRemoteRecoveryFailure: { context in
                        tracker.persistedRecoveryFailures.append(context)
                        return session
                    },
                    attemptLaunch: { _, metadataSource in
                        tracker.launchMetadataSources.append(metadataSource)
                        if tracker.launchMetadataSources.count == 1 {
                            throw NSError(
                                domain: "PiProviderModuleTests",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid Pi session linkage"]
                            )
                        }
                        return recoveredSession
                    },
                    persistLaunchFailure: { error in
                        tracker.persistedLaunchFailureErrors.append(error.localizedDescription)
                        return session
                    },
                    resolvedSessionRecordAdapterMetadata: { source in
                        switch source {
                        case .stored:
                            PiSessionLinkage(
                                piSessionID: "pi-session-1",
                                sessionFile: "/tmp/pi-session-1.jsonl"
                            ).sessionRecordAdapterMetadata
                        case let .explicit(metadata):
                            metadata
                        }
                    }
                )
            )
        )

        #expect(launchedSession == recoveredSession)
        #expect(tracker.didUseSharedLaunch == false)
        #expect(tracker.recoveryFailureErrors == ["NEXUS_REMOTE_RUNTIME_NOT_FOUND"])
        #expect(tracker.persistedRecoveryFailures.isEmpty)
        #expect(tracker.launchMetadataSources.count == 2)
        switch tracker.launchMetadataSources[0] {
        case .stored:
            break
        case .explicit:
            Issue.record("Expected first recovery fallback launch to keep stored Pi continuity")
        }
        switch tracker.launchMetadataSources[1] {
        case .stored:
            Issue.record("Expected second recovery fallback launch to clear stored Pi continuity")
        case let .explicit(metadata):
            #expect(metadata == nil)
        }
        #expect(tracker.persistedLaunchFailureErrors.isEmpty)
    }

    @Test func piProviderModulePreservesRemoteRecoveryFailureMapping() async throws {
        let module = PiProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(state: .available, summary: "Ready", resolvedExecutable: "/tmp/fake-pi", launchability: .launchable)
                }
            )
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: remoteWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let tracker = PersistedLaunchTracker()
        let failedSession = Session(
            id: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            isDefault: session.isDefault,
            state: .interrupted,
            failureMessage: "Could not reach Build Server"
        )

        let launchedSession = try await module.launchPersistedSession(
            ProviderModulePersistedSessionLaunchRequest(
                execution: PersistedSessionLaunchExecution(
                    session: session,
                    workspace: remoteWorkspace,
                    launchSnapshot: LaunchSnapshot(
                        sessionID: session.id,
                        workspaceID: remoteWorkspace.id,
                        providerID: .pi,
                        primarySurface: .structuredActivityFeed,
                        resolvedExecutable: "/tmp/pi",
                        resolvedWorkingDirectory: remoteWorkspace.folderPath
                    ),
                    mode: .recoverRemoteRuntime,
                    sessionRecordAdapterMetadataSource: .stored
                ),
                actions: ProviderModulePersistedSessionLaunchActions(
                    executeSharedLaunch: {
                        tracker.didUseSharedLaunch = true
                        return session
                    },
                    attemptRemoteRuntimeRecovery: {
                        throw NSError(
                            domain: "PiProviderModuleTests",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Connection refused"]
                        )
                    },
                    remoteRuntimeRecoveryFailureContext: { error in
                        let context = RemoteRuntimeRecoveryFailureContext(
                            detail: error.localizedDescription,
                            normalizedDetail: error.localizedDescription.lowercased(),
                            runtimeIdentifier: "runtime-1",
                            hostName: "Build Server"
                        )
                        tracker.persistedRecoveryFailures.append(context)
                        return context
                    },
                    persistRemoteRecoveryFailure: { _ in
                        tracker.recoveryFailureErrors.append("persisted")
                        return failedSession
                    },
                    attemptLaunch: { _, _ in
                        tracker.launchMetadataSources.append(.stored)
                        return session
                    },
                    persistLaunchFailure: { error in
                        tracker.persistedLaunchFailureErrors.append(error.localizedDescription)
                        return session
                    },
                    resolvedSessionRecordAdapterMetadata: { _ in nil }
                )
            )
        )

        #expect(launchedSession == failedSession)
        #expect(tracker.didUseSharedLaunch == false)
        #expect(tracker.persistedRecoveryFailures.count == 1)
        #expect(tracker.launchMetadataSources.isEmpty)
        #expect(tracker.recoveryFailureErrors == ["persisted"])
        #expect(tracker.persistedLaunchFailureErrors.isEmpty)
    }

    @Test func piProviderModulePreservesPiCatalogReadBehavior() async {
        let module = PiProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(
                        state: .available,
                        summary: "Pi module health",
                        resolvedExecutable: "/tmp/fake-pi",
                        launchability: .launchable
                    )
                },
                primarySurfaceEvaluator: { _ in .terminal },
                shouldReuseRemoteHealthSnapshot: { snapshot, _ in
                    snapshot.summary == "reuse me"
                }
            )
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )

        let health = await module.providerHealthSummary(
            for: workspace,
            remoteContext: nil,
            providerHealthEvaluator: UnusedPiProviderHealthEvaluator()
        )
        let capabilities = module.providerCapabilities(in: workspace, health: health, defaultSession: nil)

        #expect(health.summary == "Pi module health")
        #expect(capabilities.launchDefaultSession.isEnabled)
        #expect(capabilities.createNamedSession.isEnabled)
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(module.reusesRemoteHealthSnapshot(ProviderHealthSummary(state: .available, summary: "reuse me"), remoteContext: nil))
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

private final class PersistedLaunchTracker: @unchecked Sendable {
    var didUseSharedLaunch = false
    var recoveryFailureErrors: [String] = []
    var persistedRecoveryFailures: [RemoteRuntimeRecoveryFailureContext] = []
    var launchMetadataSources: [SessionRecordAdapterMetadataLaunchSource] = []
    var persistedLaunchFailureErrors: [String] = []
}

private struct UnusedPiProviderHealthEvaluator: ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        Issue.record("PiProviderModule should use its adapter-owned health summary evaluator in direct module tests")
        return []
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        Issue.record("PiProviderModule should use its adapter-owned health summary evaluator in direct module tests")
        return ProviderHealthSummary(state: .notChecked, summary: "unused")
    }
}
#endif
