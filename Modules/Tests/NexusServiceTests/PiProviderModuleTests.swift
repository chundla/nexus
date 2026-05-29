#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct PiProviderModuleTests {
    @Test func genericProviderModuleUsesSharedOpenAndPersistedLaunchActions() async throws {
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
        let openedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let launchedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Review",
            isDefault: false,
            state: .ready
        )
        let openTracker = OpenActionTracker()
        let launchTracker = PersistedLaunchTracker()

        let openResult = try await module.openSession(
            .launchOrResumeDefaultSession(workspace: workspace, providerID: .claude),
            actions: makeOpenSessionActions(
                tracker: openTracker,
                defaultSessions: [workspace.id: openedSession],
                namedSessions: [:],
                healthSummary: { _, _ in
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

        #expect(openResult == openedSession)
        #expect(launchResult == launchedSession)
        #expect(openTracker.defaultSessionLookups == [
            .init(workspaceID: workspace.id, providerID: .claude)
        ])
        #expect(openTracker.healthRequests == [
            .init(workspaceID: workspace.id, providerID: .claude)
        ])
        #expect(openTracker.createdDefaultSessions == [
            .init(workspaceID: workspace.id, providerID: .claude, state: .ready, failureMessage: nil)
        ])
        #expect(openTracker.freshLaunches == [
            .init(sessionID: openedSession.id, workspaceID: workspace.id, primarySurface: .terminal, executable: "/tmp/fake-claude")
        ])
        #expect(openTracker.persistedLaunches.isEmpty)
        #expect(launchTracker.didUseSharedLaunch)
    }

    @Test func piProviderModuleOwnsOpenSessionSeamForLocalAndRemotePiSessions() async throws {
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
        let tracker = OpenActionTracker()
        let localDefaultSession = Session(
            id: UUID(),
            workspaceID: localWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let localNamedSession = Session(
            id: UUID(),
            workspaceID: localWorkspace.id,
            providerID: .pi,
            name: "Review",
            isDefault: false,
            state: .ready
        )
        let localPersistedSession = Session(
            id: UUID(),
            workspaceID: localWorkspace.id,
            providerID: .pi,
            name: "Persisted Local",
            isDefault: false,
            state: .ready
        )
        let remoteDefaultSession = Session(
            id: UUID(),
            workspaceID: remoteWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let remotePersistedSession = Session(
            id: UUID(),
            workspaceID: remoteWorkspace.id,
            providerID: .pi,
            name: "Persisted Remote",
            isDefault: false,
            state: .ready
        )
        let actions = makeOpenSessionActions(
            tracker: tracker,
            defaultSessions: [
                localWorkspace.id: localDefaultSession,
                remoteWorkspace.id: remoteDefaultSession
            ],
            namedSessions: [
                localWorkspace.id: localNamedSession
            ],
            healthSummary: { _, workspace in
                ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: workspace.kind == .remote ? "/tmp/remote-pi" : "/tmp/local-pi",
                    launchability: .launchable
                )
            }
        )

        let localDefaultOpen = try await module.openSession(
            .launchOrResumeDefaultSession(workspace: localWorkspace, providerID: .pi),
            actions: actions
        )
        let localNamedOpen = try await module.openSession(
            .createNamedSession(workspace: localWorkspace, providerID: .pi, name: localNamedSession.name),
            actions: actions
        )
        let localPersistedOpen = try await module.openSession(
            .launchOrResumePersistedSession(localPersistedSession, workspace: localWorkspace),
            actions: actions
        )
        let remoteDefaultOpen = try await module.openSession(
            .launchOrResumeDefaultSession(workspace: remoteWorkspace, providerID: .pi),
            actions: actions
        )
        let remotePersistedOpen = try await module.openSession(
            .launchOrResumePersistedSession(remotePersistedSession, workspace: remoteWorkspace),
            actions: actions
        )

        #expect(localDefaultOpen == localDefaultSession)
        #expect(localNamedOpen == localNamedSession)
        #expect(localPersistedOpen == localPersistedSession)
        #expect(remoteDefaultOpen == remoteDefaultSession)
        #expect(remotePersistedOpen == remotePersistedSession)
        #expect(tracker.defaultSessionLookups == [
            .init(workspaceID: localWorkspace.id, providerID: .pi),
            .init(workspaceID: remoteWorkspace.id, providerID: .pi)
        ])
        #expect(tracker.listSessionRequests == [
            .init(workspaceID: localWorkspace.id, providerID: .pi)
        ])
        #expect(tracker.healthRequests == [
            .init(workspaceID: localWorkspace.id, providerID: .pi),
            .init(workspaceID: localWorkspace.id, providerID: .pi),
            .init(workspaceID: remoteWorkspace.id, providerID: .pi)
        ])
        #expect(tracker.createdDefaultSessions == [
            .init(workspaceID: localWorkspace.id, providerID: .pi, state: .ready, failureMessage: nil),
            .init(workspaceID: remoteWorkspace.id, providerID: .pi, state: .ready, failureMessage: nil)
        ])
        #expect(tracker.createdNamedSessions == [
            .init(workspaceID: localWorkspace.id, providerID: .pi, name: "Review", state: .ready, failureMessage: nil)
        ])
        #expect(tracker.freshLaunches == [
            .init(sessionID: localDefaultSession.id, workspaceID: localWorkspace.id, primarySurface: .structuredActivityFeed, executable: "/tmp/local-pi"),
            .init(sessionID: localNamedSession.id, workspaceID: localWorkspace.id, primarySurface: .structuredActivityFeed, executable: "/tmp/local-pi"),
            .init(sessionID: remoteDefaultSession.id, workspaceID: remoteWorkspace.id, primarySurface: .structuredActivityFeed, executable: "/tmp/remote-pi")
        ])
        #expect(tracker.persistedLaunches == [
            .init(sessionID: localPersistedSession.id, workspaceID: localWorkspace.id),
            .init(sessionID: remotePersistedSession.id, workspaceID: remoteWorkspace.id)
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

private func makeOpenSessionActions(
    tracker: OpenActionTracker,
    defaultSessions: [UUID: Session],
    namedSessions: [UUID: Session],
    healthSummary: @escaping (ProviderID, Workspace) -> ProviderHealthSummary
) -> ProviderModuleOpenSessionActions {
    ProviderModuleOpenSessionActions(
        defaultSession: { workspaceID, providerID in
            tracker.defaultSessionLookups.append(.init(workspaceID: workspaceID, providerID: providerID))
            return nil
        },
        listSessions: { workspaceID, providerID in
            tracker.listSessionRequests.append(.init(workspaceID: workspaceID, providerID: providerID))
            return []
        },
        resolveNamedSessionName: { requestedName, existingSessions in
            tracker.namedSessionNameRequests.append((requestedName, existingSessions.map { $0.id }))
            return requestedName ?? "Session 1"
        },
        providerHealthSummary: { providerID, workspace in
            tracker.healthRequests.append(.init(workspaceID: workspace.id, providerID: providerID))
            return healthSummary(providerID, workspace)
        },
        createDefaultSession: { workspaceID, providerID, state, failureMessage in
            tracker.createdDefaultSessions.append(
                .init(workspaceID: workspaceID, providerID: providerID, state: state, failureMessage: failureMessage)
            )
            return try #require(defaultSessions[workspaceID])
        },
        createNamedSession: { workspaceID, providerID, name, state, failureMessage in
            tracker.createdNamedSessions.append(
                .init(workspaceID: workspaceID, providerID: providerID, name: name, state: state, failureMessage: failureMessage)
            )
            return try #require(namedSessions[workspaceID])
        },
        launchFreshSession: { session, workspace, primarySurface, executable in
            tracker.freshLaunches.append(
                .init(sessionID: session.id, workspaceID: workspace.id, primarySurface: primarySurface, executable: executable)
            )
            return session
        },
        launchPersistedSession: { session, workspace in
            tracker.persistedLaunches.append(.init(sessionID: session.id, workspaceID: workspace.id))
            return session
        }
    )
}

private final class OpenActionTracker: @unchecked Sendable {
    struct SessionRequest: Equatable {
        let workspaceID: UUID
        let providerID: ProviderID
    }

    struct CreatedDefaultSession: Equatable {
        let workspaceID: UUID
        let providerID: ProviderID
        let state: Session.State
        let failureMessage: String?
    }

    struct CreatedNamedSession: Equatable {
        let workspaceID: UUID
        let providerID: ProviderID
        let name: String
        let state: Session.State
        let failureMessage: String?
    }

    struct FreshLaunch: Equatable {
        let sessionID: UUID
        let workspaceID: UUID
        let primarySurface: SessionSurface
        let executable: String
    }

    struct PersistedLaunch: Equatable {
        let sessionID: UUID
        let workspaceID: UUID
    }

    var defaultSessionLookups: [SessionRequest] = []
    var listSessionRequests: [SessionRequest] = []
    var namedSessionNameRequests: [(requestedName: String?, existingSessionIDs: [UUID])] = []
    var healthRequests: [SessionRequest] = []
    var createdDefaultSessions: [CreatedDefaultSession] = []
    var createdNamedSessions: [CreatedNamedSession] = []
    var freshLaunches: [FreshLaunch] = []
    var persistedLaunches: [PersistedLaunch] = []
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
