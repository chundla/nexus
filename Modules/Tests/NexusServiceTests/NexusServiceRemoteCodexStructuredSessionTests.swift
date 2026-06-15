#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct NexusServiceRemoteCodexStructuredSessionTests {
        @Test func remoteCodexPrelaunchPrimarySurfaceIsStructuredInOverviewAndDetail() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
            let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))
            let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

            #expect(codexCard.prelaunchPrimarySurface == .structuredActivityFeed)
            #expect(detail.prelaunchPrimarySurface == .structuredActivityFeed)
            #expect(detail.defaultSession == nil)
            #expect(detail.health.summary == "Codex 1.2.3 is available")
            #expect(detail.capabilities.launchDefaultSession.isEnabled)
            #expect(detail.capabilities.createNamedSession.isEnabled)
        }

        @Test func remoteCodexDefaultSessionLaunchesStructuredSurfaceThroughSSHBridge() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            let screen = try service.getSessionScreen(sessionID: session.id)
            let launch = try #require(transportHarness.launches().first)

            #expect(session.state == .ready)
            #expect(screen.primarySurface == .structuredActivityFeed)
            #expect(screen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
            #expect(launch.executable == "/usr/bin/ssh")
            #expect(launch.arguments.prefix(5) == ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
            #expect(launch.arguments.contains("-tt") == false)
            #expect(launch.arguments.contains("2222"))
            #expect(launch.arguments.last?.contains("tmux") == true)
            #expect(launch.arguments.last?.contains("app-server") == true)
        }

        @Test func remoteCodexApprovalRequestsAppearOnSharedStructuredSessionSurface() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            transportHarness.emitCommandApprovalRequestOnLatestTransport(
                requestID: "approval-1",
                itemID: "command-1",
                command: "deploy --prod",
                reason: "Codex needs approval to deploy to production."
            )

            let screen = try service.getSessionScreen(sessionID: session.id)

            #expect(screen.primarySurface == .structuredActivityFeed)
            #expect(
                screen.activityItems.suffix(2).map(\.text) == [
                    "Codex shared Session stream connected",
                    "Approval Request: deploy --prod",
                ])
            #expect(screen.approvalRequests.count == 1)
            #expect(screen.approvalRequests.first?.title == "deploy --prod")
            #expect(screen.approvalRequests.first?.text == "Codex needs approval to deploy to production.")
            #expect(screen.approvalRequests.first?.state == .pending)
        }

        @Test func remoteCodexApprovalDecisionsFlowBackThroughSharedServiceContract() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            transportHarness.emitCommandApprovalRequestOnLatestTransport(
                requestID: "approval-1",
                itemID: "command-1",
                command: "deploy --prod",
                reason: "Codex needs approval to deploy to production."
            )

            let pendingScreen = try service.getSessionScreen(sessionID: session.id)
            let approvalRequest = try #require(pendingScreen.approvalRequests.first)
            let approvedScreen = try service.respondToApprovalRequest(
                sessionID: session.id,
                approvalRequestID: approvalRequest.id,
                decision: .approve
            )

            #expect(approvedScreen.primarySurface == .structuredActivityFeed)
            #expect(
                approvedScreen.activityItems.suffix(2).map(\.text) == [
                    "Approval Request: deploy --prod",
                    "Approved: deploy --prod",
                ])
            #expect(approvedScreen.approvalRequests.first?.state == .approved)
            #expect(transportHarness.sentMessagesOnLatestTransport().last?["id"] as? String == "approval-1")
            #expect(
                (transportHarness.sentMessagesOnLatestTransport().last?["result"] as? [String: String])?["decision"]
                    == "accept")
        }

        @Test func restartedRemoteCodexDefaultSessionRecoversThroughAttachExistingBridgeAndThreadResume() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            func makeService() throws -> NexusService {
                try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            let restartedService = try makeService()
            let resumedSession = try restartedService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .codex)
            let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
            let launches = transportHarness.launches()
            let firstLaunch = try #require(launches.first)
            let resumedLaunch = try #require(launches.last)

            #expect(firstSession.id == resumedSession.id)
            #expect(resumedScreen.primarySurface == .structuredActivityFeed)
            #expect(resumedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
            #expect(launches.count == 2)
            #expect(firstLaunch.method == "thread/start")
            #expect(firstLaunch.requestedThreadID == nil)
            #expect(resumedLaunch.method == "thread/resume")
            #expect(resumedLaunch.requestedThreadID == firstLaunch.resolvedThreadID)
            #expect(resumedLaunch.resolvedThreadID == firstLaunch.resolvedThreadID)
            #expect(firstLaunch.arguments.last?.contains("tmux new-session") == true)
            #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
            #expect(resumedLaunch.arguments.last?.contains("attach-session") == false)
        }

        @Test func remoteCodexFreshRelaunchReusesSameSessionRecordWhenKnownTmuxRuntimeIsGone() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            func makeService() throws -> NexusService {
                try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            let firstLaunch = try #require(transportHarness.launches().last)

            transportHarness.failNextAttachStartup(message: "NEXUS_REMOTE_RUNTIME_NOT_FOUND")

            let restartedService = try makeService()
            let resumedSession = try restartedService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .codex)
            let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
            let launches = transportHarness.launches()
            let resumedLaunch = try #require(launches.last)
            let connectionAttempts = transportHarness.connectionAttempts()
            let recoveryAttempt = try #require(connectionAttempts.dropFirst().first)
            let freshLaunchAttempt = try #require(connectionAttempts.dropFirst(2).first)

            #expect(firstSession.id == resumedSession.id)
            #expect(resumedScreen.session.state == .ready)
            #expect(resumedScreen.primarySurface == .structuredActivityFeed)
            #expect(connectionAttempts.count == 3)
            #expect(recoveryAttempt.arguments.last?.contains("tmux has-session") == true)
            #expect(freshLaunchAttempt.arguments.last?.contains("tmux new-session") == true)
            #expect(launches.count == 2)
            #expect(resumedLaunch.method == "thread/resume")
            #expect(resumedLaunch.requestedThreadID == firstLaunch.resolvedThreadID)
            #expect(resumedLaunch.resolvedThreadID == firstLaunch.resolvedThreadID)
        }

        @Test func remoteCodexFreshRelaunchFallsBackToNewThreadWhenPersistedThreadLinkageIsRejected() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            func makeService() throws -> NexusService {
                try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            let firstLaunch = try #require(transportHarness.launches().last)

            transportHarness.failNextAttachStartup(message: "NEXUS_REMOTE_RUNTIME_NOT_FOUND")
            transportHarness.rejectNextFreshLaunchResume(message: "invalid thread id")

            let restartedService = try makeService()
            let resumedSession = try restartedService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .codex)
            let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
            let launches = transportHarness.launches()
            let failedResumeLaunch = try #require(launches.dropFirst().first)
            let fallbackLaunch = try #require(launches.last)
            let metadataStore = try NexusMetadataStore(storeURL: restartedService.storeURL)
            let metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: resumedSession.id)

            #expect(firstSession.id == resumedSession.id)
            #expect(resumedScreen.session.state == .ready)
            #expect(resumedScreen.primarySurface == .structuredActivityFeed)
            #expect(launches.count == 3)
            #expect(failedResumeLaunch.method == "thread/resume")
            #expect(failedResumeLaunch.requestedThreadID == firstLaunch.resolvedThreadID)
            #expect(fallbackLaunch.method == "thread/start")
            #expect(fallbackLaunch.resolvedThreadID != firstLaunch.resolvedThreadID)
            #expect(metadata?.codexSessionLinkage?.threadID == fallbackLaunch.resolvedThreadID)
        }

        @Test func migratedRemoteTerminalCodexSessionRecordRelaunchesThroughStructuredRuntimeWithoutRecreation() throws
        {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let legacyService = try makeLegacyRemoteTerminalCodexService(rootURL: rootURL)
            let group = try legacyService.createWorkspaceGroup(name: "Remote")
            let host = try legacyService.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try legacyService.validateHost(hostID: host.id)
            let workspace = try legacyService.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let migratedSession = try legacyService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .codex)
            let metadataStore = try NexusMetadataStore(storeURL: legacyService.storeURL)
            try metadataStore.updateLaunchSnapshotPrimarySurface(
                sessionID: migratedSession.id, primarySurface: .terminal)

            let transportHarness = RemoteCodexTransportHarness()
            let migratedService = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
            let relaunchedSession = try migratedService.launchOrResumeSession(sessionID: migratedSession.id)
            let relaunchedScreen = try migratedService.getSessionScreen(sessionID: migratedSession.id)
            let launchSnapshot = try metadataStore.launchSnapshot(sessionID: migratedSession.id)

            #expect(relaunchedSession.id == migratedSession.id)
            #expect(relaunchedScreen.primarySurface == .structuredActivityFeed)
            #expect(relaunchedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
            #expect(try #require(launchSnapshot).primarySurface == .structuredActivityFeed)
            #expect(transportHarness.launches().count == 1)
        }

        @Test func remoteCodexBridgeLossLeavesInterruptedInspectableSessionUntilExplicitResume() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            transportHarness.disconnectLatestTransport(status: 255)

            let screen = try service.getSessionScreen(sessionID: session.id)
            let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

            #expect(screen.session.state == .interrupted)
            #expect(screen.primarySurface == .structuredActivityFeed)
            #expect(detail.defaultSession?.state == .interrupted)
            #expect(transportHarness.launches().count == 1)
        }

        @Test func remoteCodexBridgeLossRecoversThroughExplicitResumeToExistingRemoteRuntime() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            let firstLaunch = try #require(transportHarness.launches().last)
            transportHarness.disconnectLatestTransport(status: 255)

            let resumedSession = try service.launchOrResumeSession(sessionID: session.id)
            let resumedScreen = try service.getSessionScreen(sessionID: resumedSession.id)
            let launches = transportHarness.launches()
            let resumedLaunch = try #require(launches.last)

            #expect(resumedSession.id == session.id)
            #expect(resumedScreen.session.state == .ready)
            #expect(resumedScreen.primarySurface == .structuredActivityFeed)
            #expect(launches.count == 2)
            #expect(resumedLaunch.method == "thread/resume")
            #expect(resumedLaunch.requestedThreadID == firstLaunch.resolvedThreadID)
            #expect(resumedLaunch.resolvedThreadID == firstLaunch.resolvedThreadID)
            #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
            #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
        }

        @Test func remoteCodexNamedSessionUsesStructuredSurfaceAndOwnThreadLinkageAlongsideDefaultSession() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteCodexTransportHarness()
            func makeService() throws -> NexusService {
                try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Codex",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let defaultSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            let namedSession = try service.createNamedSession(
                workspaceID: workspace.id, providerID: .codex, name: "Review")
            let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
            let namedScreen = try service.getSessionScreen(sessionID: namedSession.id)

            let restartedService = try makeService()
            let resumedNamedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
            let resumedNamedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)
            let launches = transportHarness.launches()
            let defaultLaunch = try #require(launches.first)
            let namedLaunch = try #require(launches.dropFirst().first)
            let resumedNamedLaunch = try #require(launches.last)

            #expect(detail.defaultSession?.id == defaultSession.id)
            #expect(detail.alternateSessions.map(\.id) == [namedSession.id])
            #expect(detail.failedSessions.isEmpty)
            #expect(namedScreen.primarySurface == .structuredActivityFeed)
            #expect(namedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
            #expect(resumedNamedSession.id == namedSession.id)
            #expect(resumedNamedScreen.primarySurface == .structuredActivityFeed)
            #expect(resumedNamedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
            #expect(launches.count == 3)
            #expect(defaultLaunch.method == "thread/start")
            #expect(namedLaunch.method == "thread/start")
            #expect(namedLaunch.resolvedThreadID != defaultLaunch.resolvedThreadID)
            #expect(resumedNamedLaunch.method == "thread/resume")
            #expect(resumedNamedLaunch.requestedThreadID == namedLaunch.resolvedThreadID)
            #expect(resumedNamedLaunch.resolvedThreadID == namedLaunch.resolvedThreadID)
            #expect(resumedNamedLaunch.resolvedThreadID != defaultLaunch.resolvedThreadID)
        }
    }

    private func makeRemoteCodexService(rootURL: URL, transportHarness: RemoteCodexTransportHarness) throws
        -> NexusService
    {
        let launcher = ProcessSessionRuntimeLauncher(codexTransportFactory: transportHarness.makeTransport)

        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemoteCodexStubExecutableResolver(),
                commandRunner: RemoteCodexStubCommandRunner(),
                remoteCodexReadinessProbe: RemoteCodexReadyReadinessProbe()
            ),
            hostValidationEvaluator: RemoteCodexAvailableHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: RemoteCodexAvailableWorkspaceAvailabilityEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
    }

    private func makeLegacyRemoteTerminalCodexService(rootURL: URL) throws -> NexusService {
        try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemoteCodexStubExecutableResolver(),
                commandRunner: RemoteCodexStubCommandRunner(),
                remoteCodexReadinessProbe: RemoteCodexReadyReadinessProbe()
            ),
            hostValidationEvaluator: RemoteCodexAvailableHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: RemoteCodexAvailableWorkspaceAvailabilityEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: LegacyRemoteTerminalCodexRuntimeLauncher())
        )
    }

    private struct RemoteCodexStubExecutableResolver: ProviderExecutableResolving {
        func resolveExecutable(named command: String) -> ProviderExecutableResolution {
            ProviderExecutableResolution(
                resolvedExecutable: nil,
                searchedDirectories: [],
                homeDirectories: [],
                pathEnvironment: nil
            )
        }
    }

    private struct RemoteCodexStubCommandRunner: ProviderCommandRunning {
        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            ProviderCommandResult(
                exitStatus: 0,
                stdout: "/home/tester/.local/bin/codex\n1.2.3\n",
                stderr: ""
            )
        }
    }

    private struct RemoteCodexReadyReadinessProbe: RemoteCodexReadinessProbing {
        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemoteCodexReadinessOutcome
        {
            .ready
        }
    }

    private struct RemoteCodexAvailableHostValidationEvaluator: HostValidationEvaluating {
        func validate(host: NexusDomain.Host) -> HostValidationResult {
            HostValidationResult(
                state: .available,
                summary: "Host is available",
                diagnostics: [
                    HostValidationDiagnostic(severity: .info, code: "sshTarget", message: "Validated \(host.sshTarget)")
                ]
            )
        }
    }

    private struct LegacyRemoteTerminalCodexRuntimeLauncher: SessionRuntimeLaunching {
        func makeRuntime(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration)
            async throws -> any SessionRuntime
        {
            LegacyRemoteTerminalCodexRuntime()
        }
    }

    private final class LegacyRemoteTerminalCodexRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .ready
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            SessionScreen(session: session, transcript: "Codex ready")
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
        func stop() throws { state = .exited }
        func sendInput(_ text: String) throws {}
        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
        func resize(columns: Int, rows: Int) throws {}
    }

    private struct RemoteCodexAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
            WorkspaceAvailabilityResult(
                state: .available,
                summary: "Workspace is available",
                diagnostics: [
                    WorkspaceAvailabilityDiagnostic(
                        severity: .info,
                        code: "remotePath",
                        message: "Validated remote path \(workspace.folderPath) on \(host.name)."
                    )
                ]
            )
        }
    }

    private final class RemoteCodexTransportHarness: @unchecked Sendable {
        struct ConnectionAttempt: Sendable {
            let executable: String
            let arguments: [String]
        }

        struct Launch: Sendable {
            let executable: String
            let arguments: [String]
            let method: String
            let requestedThreadID: String?
            let resolvedThreadID: String
        }

        private let lock = NSLock()
        private var recordedConnectionAttempts: [ConnectionAttempt] = []
        private var recordedLaunches: [Launch] = []
        private var activeTransports: [RemoteCodexTransport] = []
        private var nextThreadNumber = 0
        private var nextAttachStartupFailures: [String] = []
        private var nextFreshLaunchResumeFailures: [String] = []

        func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws
            -> any CodexAppServerTransporting
        {
            lock.lock()
            let startupFailureMessage: String?
            if arguments.last?.contains("tmux has-session") == true, nextAttachStartupFailures.isEmpty == false {
                startupFailureMessage = nextAttachStartupFailures.removeFirst()
            } else {
                startupFailureMessage = nil
            }
            let resumeFailureMessage: String?
            if arguments.last?.contains("tmux new-session") == true, nextFreshLaunchResumeFailures.isEmpty == false {
                resumeFailureMessage = nextFreshLaunchResumeFailures.removeFirst()
            } else {
                resumeFailureMessage = nil
            }
            let connectionAttempt = ConnectionAttempt(executable: executable, arguments: arguments)
            recordedConnectionAttempts.append(connectionAttempt)
            lock.unlock()

            let transport = RemoteCodexTransport(
                executable: executable,
                arguments: arguments,
                startupFailureMessage: startupFailureMessage,
                resumeFailureMessage: resumeFailureMessage,
                harness: self
            )
            register(transport)
            return transport
        }

        func failNextAttachStartup(message: String) {
            lock.lock()
            nextAttachStartupFailures.append(message)
            lock.unlock()
        }

        func rejectNextFreshLaunchResume(message: String) {
            lock.lock()
            nextFreshLaunchResumeFailures.append(message)
            lock.unlock()
        }

        func recordLaunch(executable: String, arguments: [String], method: String, requestedThreadID: String?) -> Launch
        {
            lock.lock()
            defer { lock.unlock() }

            let resolvedThreadID: String
            if method == "thread/resume", let requestedThreadID, requestedThreadID.isEmpty == false {
                resolvedThreadID = requestedThreadID
            } else {
                nextThreadNumber += 1
                resolvedThreadID = "codex-thread-\(nextThreadNumber)"
            }

            let launch = Launch(
                executable: executable,
                arguments: arguments,
                method: method,
                requestedThreadID: requestedThreadID,
                resolvedThreadID: resolvedThreadID
            )
            recordedLaunches.append(launch)
            return launch
        }

        func connectionAttempts() -> [ConnectionAttempt] {
            lock.lock()
            defer { lock.unlock() }
            return recordedConnectionAttempts
        }

        func launches() -> [Launch] {
            lock.lock()
            defer { lock.unlock() }
            return recordedLaunches
        }

        func disconnectLatestTransport(status: Int32) {
            lock.lock()
            let transport = activeTransports.last
            lock.unlock()
            transport?.disconnect(status: status)
        }

        func emitCommandApprovalRequestOnLatestTransport(
            requestID: String, itemID: String, command: String, reason: String
        ) {
            lock.lock()
            let transport = activeTransports.last
            lock.unlock()
            transport?.emitCommandApprovalRequest(
                requestID: requestID, itemID: itemID, command: command, reason: reason)
        }

        func sentMessagesOnLatestTransport() -> [[String: Any]] {
            lock.lock()
            let transport = activeTransports.last
            lock.unlock()
            return transport?.sentMessages ?? []
        }

        func register(_ transport: RemoteCodexTransport) {
            lock.lock()
            activeTransports.append(transport)
            lock.unlock()
        }
    }

    private final class RemoteCodexTransport: CodexAppServerTransporting, @unchecked Sendable {
        private let executable: String
        private let arguments: [String]
        private let startupFailureMessage: String?
        private let resumeFailureMessage: String?
        private let harness: RemoteCodexTransportHarness
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (CodexAppServerTermination) -> Void)?
        private(set) var sentMessages: [[String: Any]] = []

        init(
            executable: String, arguments: [String], startupFailureMessage: String?, resumeFailureMessage: String?,
            harness: RemoteCodexTransportHarness
        ) {
            self.executable = executable
            self.arguments = arguments
            self.startupFailureMessage = startupFailureMessage
            self.resumeFailureMessage = resumeFailureMessage
            self.harness = harness
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (CodexAppServerTermination) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return
            }

            sentMessages.append(object)

            switch object["method"] as? String {
            case "initialize":
                emit([
                    "id": object["id"] ?? 0,
                    "result": ["userAgent": "nexus-test"],
                ])
            case "thread/start", "thread/resume":
                if let startupFailureMessage {
                    emit([
                        "id": object["id"] ?? 0,
                        "error": ["message": startupFailureMessage],
                    ])
                    return
                }

                let params = object["params"] as? [String: Any]
                let method = object["method"] as? String ?? "thread/start"
                let launch = harness.recordLaunch(
                    executable: executable,
                    arguments: arguments,
                    method: method,
                    requestedThreadID: params?["threadId"] as? String
                )
                if method == "thread/resume", let resumeFailureMessage {
                    emit([
                        "id": object["id"] ?? 0,
                        "error": ["message": resumeFailureMessage],
                    ])
                    return
                }
                emit([
                    "id": object["id"] ?? 0,
                    "result": [
                        "thread": ["id": launch.resolvedThreadID]
                    ],
                ])
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(CodexAppServerTermination(status: 0, stderr: nil))
        }

        func disconnect(status: Int32) {
            terminationHandler?(CodexAppServerTermination(status: status, stderr: nil))
        }

        func emitCommandApprovalRequest(requestID: String, itemID: String, command: String, reason: String) {
            emit([
                "jsonrpc": "2.0",
                "id": requestID,
                "method": "item/commandExecution/requestApproval",
                "params": [
                    "threadId": harness.launches().last?.resolvedThreadID ?? "codex-thread-1",
                    "turnId": "turn-1",
                    "itemId": itemID,
                    "startedAtMs": 1,
                    "reason": reason,
                    "command": command,
                    "cwd": "/srv/api",
                ],
            ])
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }
#endif
