#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct NexusServiceSessionLaunchFactReuseTests {
        @Test func freshLocalLaunchReusesRecentProviderHealthSnapshotAcrossBootstrap() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceSessionLaunchFactReuseTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let firstEvaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    .claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Cached Claude health",
                        resolvedExecutable: "/tmp/cached-claude",
                        launchability: .launchable
                    )
                ]
            )
            let firstService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: firstEvaluator,
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StaticSessionRuntimeLauncher())
            )
            let group = try firstService.createWorkspaceGroup(name: "Solo Group")
            let workspace = try firstService.createLocalWorkspace(
                name: "Local Claude",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            _ = try await firstService.getWorkspaceOverview(workspaceID: workspace.id)
            #expect(await firstEvaluator.callCount(for: .claude) == 1)

            let secondEvaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    .claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Fresh Claude health should stay unused",
                        resolvedExecutable: "/tmp/fresh-claude",
                        launchability: .launchable
                    )
                ]
            )
            let secondService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: secondEvaluator,
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StaticSessionRuntimeLauncher())
            )

            let session = try await secondService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .claude)

            #expect(session.state == .ready)
            #expect(await secondEvaluator.callCount(for: .claude) == 0)
        }

        @Test func remoteRelaunchWithLaunchSnapshotSkipsFreshProviderHealthChecks() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceSessionLaunchFactReuseTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let firstService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: CountingProviderHealthEvaluator(
                    summariesByProvider: [
                        .claude: ProviderHealthSummary(
                            state: .available,
                            summary: "Cached Claude health",
                            resolvedExecutable: "/tmp/cached-remote-claude",
                            launchability: .launchable
                        )
                    ]
                ),
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StaticSessionRuntimeLauncher())
            )
            let group = try firstService.createWorkspaceGroup(name: "Remote")
            let host = try firstService.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            let workspace = try firstService.createRemoteWorkspace(
                name: "Remote Claude",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )
            let session = try await firstService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .claude)

            let secondEvaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    .claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Fresh Claude health should stay unused",
                        resolvedExecutable: "/tmp/fresh-remote-claude",
                        launchability: .launchable
                    )
                ]
            )
            let secondService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: secondEvaluator,
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StaticSessionRuntimeLauncher())
            )

            let relaunchedSession = try await secondService.launchOrResumeSession(sessionID: session.id)

            #expect(relaunchedSession.id == session.id)
            #expect(relaunchedSession.state == .ready)
            #expect(await secondEvaluator.callCount(for: .claude) == 0)
        }

        @Test func remoteRelaunchFallsBackToFreshProviderHealthWhenCachedSnapshotIsStale() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceSessionLaunchFactReuseTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let metadataStore = try NexusMetadataStore(
                storeURL: rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false))
            let group = try metadataStore.createWorkspaceGroup(name: "Remote")
            let host = try metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            let workspace = try metadataStore.createRemoteWorkspace(
                name: "Remote Claude",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )
            _ = try metadataStore.createDefaultSession(
                workspaceID: workspace.id,
                providerID: .claude,
                state: .failed,
                failureMessage: "Stale Claude health"
            )

            _ = try metadataStore.saveProviderHealth(
                workspaceID: workspace.id,
                providerID: .claude,
                summary: ProviderHealthSummary(
                    state: .available,
                    summary: "Stale Claude health",
                    resolvedExecutable: "/tmp/stale-remote-claude",
                    launchability: .launchable
                ),
                checkedAt: Date().addingTimeInterval(-120)
            )

            let secondEvaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    .claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Fresh Claude health",
                        resolvedExecutable: "/tmp/fresh-remote-claude",
                        launchability: .launchable
                    )
                ]
            )
            let secondService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: secondEvaluator,
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StaticSessionRuntimeLauncher())
            )

            let relaunchedSession = try await secondService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .claude)

            #expect(relaunchedSession.state == .ready)
            #expect(await secondEvaluator.callCount(for: .claude) == 1)
        }
    }

    private actor CountingProviderHealthEvaluator: ProviderHealthEvaluating {
        let summariesByProvider: [ProviderID: ProviderHealthSummary]
        private var callsByProvider: [ProviderID: Int] = [:]

        init(summariesByProvider: [ProviderID: ProviderHealthSummary]) {
            self.summariesByProvider = summariesByProvider
        }

        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            ProviderID.allCases.map { providerID in
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: ProviderHealthSummary(state: .notChecked, summary: "Unused"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .notCreated,
                        summary: "No default session yet",
                        actionTitle: "Launch"
                    )
                )
            }
        }

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            callsByProvider[providerID, default: 0] += 1
            return summariesByProvider[providerID] ?? ProviderHealthSummary(state: .notChecked, summary: "Unused")
        }

        func callCount(for providerID: ProviderID) -> Int {
            callsByProvider[providerID, default: 0]
        }
    }

    private struct AvailableHostValidationEvaluator: HostValidationEvaluating {
        func validate(host: NexusDomain.Host) -> HostValidationResult {
            HostValidationResult(state: .available, summary: "Host is available", diagnostics: [])
        }
    }

    private struct AvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
            WorkspaceAvailabilityResult(state: .available, summary: "Workspace is available", diagnostics: [])
        }
    }

    private final class StaticSessionRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            StaticSessionRuntime()
        }
    }

    private final class StaticSessionRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .ready
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            SessionScreen(session: session, primarySurface: .terminal, transcript: "Ready")
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
