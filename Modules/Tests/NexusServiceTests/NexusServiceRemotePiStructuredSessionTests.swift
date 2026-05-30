#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceRemotePiStructuredSessionTests {
    @Test func remotePiDefaultSessionLaunchesStructuredSurfaceThroughSSHBridge() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let screen = try service.getSessionScreen(sessionID: session.id)
        let launch = try #require(transportHarness.launches().first)

        #expect(session.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(launch.executable == "/usr/bin/ssh")
        #expect(launch.arguments.prefix(5) == ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
        #expect(launch.arguments.contains("-tt") == false)
        #expect(launch.arguments.contains("2222"))
        #expect(launch.arguments.last?.contains("tmux new-session") == true)
        #expect(launch.arguments.last?.contains("/home/tester/.local/bin/pi") == true)
        #expect(launch.arguments.last?.contains("--mode") == true)
        #expect(launch.arguments.last?.contains("rpc") == true)
    }

    @Test func remotePiStructuredPromptFlowsThroughSharedSessionSurface() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let screen = try service.sendSessionInput(sessionID: session.id, text: "hello")

        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: Remote hello"
        ])
        #expect(screen.transcript == "> hello\nRemote hello")
    }

    @Test func remotePiApprovalRequestsAndDecisionsFlowThroughSharedServiceContract() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let pendingScreen = try service.sendSessionInput(sessionID: session.id, text: "deploy")
        let approvalRequest = try #require(pendingScreen.approvalRequests.first)
        let approvedScreen = try service.respondToApprovalRequest(
            sessionID: session.id,
            approvalRequestID: approvalRequest.id,
            decision: .approve
        )

        #expect(pendingScreen.activityItems.suffix(2).map(\.text) == [
            "You: deploy",
            "Approval Request: Deploy to production?"
        ])
        #expect(pendingScreen.approvalRequests == [
            SessionApprovalRequest(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "Deploy to production?",
                text: "Pi wants to run deploy --prod.",
                state: .pending
            )
        ])
        #expect(approvedScreen.activityItems.suffix(3).map(\.text) == [
            "Approval Request: Deploy to production?",
            "Approved: Deploy to production?",
            "Pi: Deployment approved"
        ])
        #expect(approvedScreen.approvalRequests == [
            SessionApprovalRequest(
                id: approvalRequest.id,
                title: approvalRequest.title,
                text: approvalRequest.text,
                state: .approved
            )
        ])
        #expect(approvedScreen.transcript == "> deploy\nDeployment approved")
    }

    @Test func remoteControllerCanSendStructuredPromptToRemotePiThroughGenericRemoteSessionInputAPI() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let pairedDeviceID = UUID()
        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let controlledScreen = try service.takeRemoteSessionControl(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            columns: 44,
            rows: 12
        )
        let promptedScreen = try service.sendRemoteSessionInput(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            text: "hello"
        )

        #expect(controlledScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(promptedScreen.primarySurface == .structuredActivityFeed)
        #expect(promptedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(promptedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: Remote hello"
        ])
        #expect(promptedScreen.transcript == "> hello\nRemote hello")
    }

    @Test func remoteControllerCanRespondToRemotePiApprovalRequestThroughGenericDecisionAPI() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let pairedDeviceID = UUID()
        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        _ = try service.takeRemoteSessionControl(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            columns: 44,
            rows: 12
        )
        let pendingScreen = try service.sendRemoteSessionInput(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            text: "deploy"
        )
        let approvalRequest = try #require(pendingScreen.approvalRequests.first)
        let approvedScreen = try service.respondToRemoteApprovalRequest(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            approvalRequestID: approvalRequest.id,
            decision: .approve
        )

        #expect(approvedScreen.primarySurface == .structuredActivityFeed)
        #expect(approvedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(approvedScreen.activityItems.suffix(3).map(\.text) == [
            "Approval Request: Deploy to production?",
            "Approved: Deploy to production?",
            "Pi: Deployment approved"
        ])
        #expect(approvedScreen.approvalRequests.first?.state == .approved)
        #expect(approvedScreen.transcript == "> deploy\nDeployment approved")
    }

    @Test func restartedRemotePiDefaultSessionStaysInterruptedUntilExplicitResumeRecoversExistingRuntime() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let restartedService = try makeService()
        let interruptedScreen = try restartedService.getSessionScreen(sessionID: firstSession.id)
        let launchesAfterInspection = transportHarness.launches()
        let resumedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
        let launches = transportHarness.launches()
        let resumedLaunch = try #require(launches.last)

        #expect(interruptedScreen.session.id == firstSession.id)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(launchesAfterInspection.count == 1)
        #expect(launches.count == 2)
        #expect(firstSession.id == resumedSession.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
        #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
    }

    @Test func remotePiFreshRelaunchFallsBackToNewSessionWhenPersistedLinkageIsRejected() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let firstLaunch = try #require(transportHarness.launches().last)

        transportHarness.failNextAttachStartup(message: "NEXUS_REMOTE_RUNTIME_NOT_FOUND")
        transportHarness.rejectNextFreshLaunchLinkedSession(message: "Invalid Pi session linkage")

        let restartedService = try makeService()
        let resumedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
        let launches = transportHarness.launches()
        let recoveryAttempt = try #require(launches.dropFirst().first)
        let failedFreshLaunch = try #require(launches.dropFirst(2).first)
        let fallbackLaunch = try #require(launches.last)
        let metadataStore = try NexusMetadataStore(storeURL: restartedService.storeURL)
        let metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: resumedSession.id)

        #expect(firstSession.id == resumedSession.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(launches.count == 4)
        #expect(recoveryAttempt.arguments.last?.contains("tmux has-session") == true)
        #expect(failedFreshLaunch.arguments.last?.contains("tmux new-session") == true)
        #expect(failedFreshLaunch.sessionFile == firstLaunch.sessionFile)
        #expect(fallbackLaunch.arguments.last?.contains("tmux new-session") == true)
        #expect(fallbackLaunch.sessionFile != firstLaunch.sessionFile)
        #expect(metadata?.piSessionLinkage?.sessionFile == fallbackLaunch.sessionFile)
    }

    @Test func remotePiNamedSessionUsesStructuredSurfaceAndOwnSessionLinkageAlongsideDefaultSession() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let defaultSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
        let namedScreen = try service.getSessionScreen(sessionID: namedSession.id)

        let restartedService = try makeService()
        let resumedNamedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
        let resumedNamedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)
        let launches = transportHarness.launches()
        let defaultLaunch = try #require(launches.first)
        let namedLaunch = try #require(launches.dropFirst().first)
        let resumedNamedLaunch = try #require(launches.last)
        let metadataStore = try NexusMetadataStore(storeURL: restartedService.storeURL)
        let metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: resumedNamedSession.id)

        #expect(detail.defaultSession?.id == defaultSession.id)
        #expect(detail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(detail.failedSessions.isEmpty)
        #expect(namedScreen.primarySurface == .structuredActivityFeed)
        #expect(namedScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(resumedNamedSession.id == namedSession.id)
        #expect(resumedNamedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedNamedScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(launches.count == 3)
        #expect(defaultLaunch.sessionFile != namedLaunch.sessionFile)
        #expect(namedLaunch.sessionFile == resumedNamedLaunch.sessionFile)
        #expect(metadata?.piSessionLinkage?.sessionFile == namedLaunch.sessionFile)
    }

    @Test func remotePiNamedSessionCanBeStoppedRelaunchedAndDeleted() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")
        let firstLaunch = try #require(transportHarness.launches().last)
        let stoppedSession = try service.stopSession(sessionID: namedSession.id)
        let stoppedRecord = try service.getSessionRecord(sessionID: namedSession.id)

        let restartedService = try makeService()
        let relaunchedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
        let metadataStore = try NexusMetadataStore(storeURL: restartedService.storeURL)
        let metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: relaunchedSession.id)
        _ = try restartedService.stopSession(sessionID: namedSession.id)
        let deleted = try restartedService.deleteSessionRecord(sessionID: namedSession.id)
        let detail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
        let launches = transportHarness.launches()
        let resumedLaunch = try #require(launches.last)

        #expect(namedSession.name == "Review")
        #expect(namedSession.isDefault == false)
        #expect(stoppedSession.id == namedSession.id)
        #expect(stoppedSession.state == .exited)
        #expect(stoppedRecord.state == .exited)
        #expect(relaunchedSession.id == namedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(firstLaunch.sessionFile == resumedLaunch.sessionFile)
        #expect(metadata?.piSessionLinkage?.sessionFile == firstLaunch.sessionFile)
        #expect(deleted)
        #expect(detail.alternateSessions.isEmpty)

        do {
            _ = try restartedService.getSessionScreen(sessionID: namedSession.id)
            Issue.record("Expected deleted remote Pi Session Record to be unavailable")
        } catch {
        }
    }

    @Test func remotePiFailedNamedSessionAppearsInProviderDetailFailedSessionRecords() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        transportHarness.failNextFreshLaunch(message: "Pi RPC startup failed")
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let failedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

        #expect(failedSession.state == .failed)
        #expect(detail.defaultSession == nil)
        #expect(detail.alternateSessions.isEmpty)
        #expect(detail.failedSessions.map(\.id) == [failedSession.id])
    }

    @Test func resumedRemotePiSessionAcceptsStructuredPromptAfterExplicitRecovery() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        transportHarness.disconnectLatestTransport(status: 255)

        let resumedSession = try service.launchOrResumeSession(sessionID: session.id)
        let resumedScreen = try service.sendSessionInput(sessionID: resumedSession.id, text: "again")

        #expect(resumedSession.id == session.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: again",
            "Pi: Remote again"
        ])
        #expect(resumedScreen.transcript == "> again\nRemote again")
    }

    @Test func remotePiBridgeLossLeavesInterruptedInspectableSessionUntilExplicitResume() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        transportHarness.disconnectLatestTransport(status: 255)

        let interruptedScreen = try service.getSessionScreen(sessionID: session.id)
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
        let launchesAfterDisconnect = transportHarness.launches()
        let resumedSession = try service.launchOrResumeSession(sessionID: session.id)
        let resumedScreen = try service.getSessionScreen(sessionID: resumedSession.id)
        let resumedLaunch = try #require(transportHarness.launches().last)

        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.primarySurface == .structuredActivityFeed)
        #expect(detail.defaultSession?.state == .interrupted)
        #expect(launchesAfterDisconnect.count == 1)
        #expect(resumedSession.id == session.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
        #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
    }
}

private func makeRemotePiService(rootURL: URL, transportHarness: RemotePiTransportHarness) throws -> NexusService {
    let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: transportHarness.makeTransport)

    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: RemotePiStructuredStubExecutableResolver(),
            commandRunner: RemotePiStructuredStubCommandRunner(),
            remotePiReadinessProbe: RemotePiStructuredReadyReadinessProbe()
        ),
        hostValidationEvaluator: RemotePiStructuredAvailableHostValidationEvaluator(),
        workspaceAvailabilityEvaluator: RemotePiStructuredAvailableWorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
    )
}

private struct RemotePiStructuredStubExecutableResolver: ProviderExecutableResolving {
    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: nil,
            searchedDirectories: [],
            homeDirectories: [],
            pathEnvironment: nil
        )
    }
}

private struct RemotePiStructuredStubCommandRunner: ProviderCommandRunning {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        ProviderCommandResult(
            exitStatus: 0,
            stdout: "/home/tester/.local/bin/pi\n0.9.0\n",
            stderr: ""
        )
    }
}

private struct RemotePiStructuredReadyReadinessProbe: RemotePiReadinessProbing {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws -> RemotePiReadinessOutcome {
        .ready
    }
}

private struct RemotePiStructuredAvailableHostValidationEvaluator: HostValidationEvaluating {
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

private struct RemotePiStructuredAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult {
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

private final class RemotePiTransportHarness: @unchecked Sendable {
    struct Launch: Sendable {
        let executable: String
        let arguments: [String]
        let sessionID: String
        let sessionFile: String
    }

    private struct SessionState {
        let sessionID: String
        let sessionFile: String
    }

    private let lock = NSLock()
    private var nextSessionNumber = 0
    private var sessionsByID: [String: SessionState] = [:]
    private var sessionsByFile: [String: SessionState] = [:]
    private var sessionsByRuntimeIdentifier: [String: SessionState] = [:]
    private var recordedLaunches: [Launch] = []
    private var activeTransports: [RemotePiTransport] = []
    private var nextAttachStartupFailures: [String] = []
    private var nextFreshLaunchStartupFailures: [String] = []
    private var nextFreshLaunchLinkedSessionFailures: [String] = []

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any PiRPCTransporting {
        lock.lock()
        let sessionArgument = sessionArgument(in: arguments)
        let runtimeIdentifier = runtimeIdentifier(in: arguments)
        let session = currentSession(for: sessionArgument, runtimeIdentifier: runtimeIdentifier)
        let startupFailureMessage: String?
        if arguments.last?.contains("tmux has-session") == true, nextAttachStartupFailures.isEmpty == false {
            startupFailureMessage = nextAttachStartupFailures.removeFirst()
        } else if arguments.last?.contains("tmux new-session") == true,
                  nextFreshLaunchStartupFailures.isEmpty == false {
            startupFailureMessage = nextFreshLaunchStartupFailures.removeFirst()
        } else if arguments.last?.contains("tmux new-session") == true,
                  sessionArgument != nil,
                  nextFreshLaunchLinkedSessionFailures.isEmpty == false {
            startupFailureMessage = nextFreshLaunchLinkedSessionFailures.removeFirst()
        } else {
            startupFailureMessage = nil
        }
        recordedLaunches.append(
            Launch(
                executable: executable,
                arguments: arguments,
                sessionID: session.sessionID,
                sessionFile: session.sessionFile
            )
        )
        lock.unlock()

        let transport = RemotePiTransport(
            sessionID: session.sessionID,
            sessionFile: session.sessionFile,
            startupFailureMessage: startupFailureMessage
        )
        register(transport)
        return transport
    }

    func launches() -> [Launch] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunches
    }

    func failNextAttachStartup(message: String) {
        lock.lock()
        nextAttachStartupFailures.append(message)
        lock.unlock()
    }

    func failNextFreshLaunch(message: String) {
        lock.lock()
        nextFreshLaunchStartupFailures.append(message)
        lock.unlock()
    }

    func rejectNextFreshLaunchLinkedSession(message: String) {
        lock.lock()
        nextFreshLaunchLinkedSessionFailures.append(message)
        lock.unlock()
    }

    func disconnectLatestTransport(status: Int32) {
        lock.lock()
        let transport = activeTransports.last
        lock.unlock()
        transport?.disconnect(status: status)
    }

    private func register(_ transport: RemotePiTransport) {
        lock.lock()
        activeTransports.append(transport)
        lock.unlock()
    }

    private func currentSession(for sessionArgument: String?, runtimeIdentifier: String?) -> SessionState {
        if let sessionArgument {
            if let session = sessionsByFile[sessionArgument] ?? sessionsByID[sessionArgument] {
                if let runtimeIdentifier {
                    sessionsByRuntimeIdentifier[runtimeIdentifier] = session
                }
                return session
            }

            let session = SessionState(
                sessionID: sessionArgument.hasSuffix(".jsonl") ? "pi-session-unknown" : sessionArgument,
                sessionFile: sessionArgument.hasSuffix(".jsonl") ? sessionArgument : "/tmp/\(sessionArgument).jsonl"
            )
            sessionsByID[session.sessionID] = session
            sessionsByFile[session.sessionFile] = session
            if let runtimeIdentifier {
                sessionsByRuntimeIdentifier[runtimeIdentifier] = session
            }
            return session
        }

        if let runtimeIdentifier,
           let session = sessionsByRuntimeIdentifier[runtimeIdentifier] {
            return session
        }

        nextSessionNumber += 1
        let sessionID = "pi-session-\(nextSessionNumber)"
        let sessionFile = "/tmp/\(sessionID).jsonl"
        let session = SessionState(sessionID: sessionID, sessionFile: sessionFile)
        sessionsByID[sessionID] = session
        sessionsByFile[sessionFile] = session
        if let runtimeIdentifier {
            sessionsByRuntimeIdentifier[runtimeIdentifier] = session
        }
        return session
    }

    private func sessionArgument(in arguments: [String]) -> String? {
        guard let command = arguments.last,
              let sessionFlagRange = command.range(of: "\"--session\" \"") else {
            return nil
        }

        let remainder = command[sessionFlagRange.upperBound...]
        guard let closingQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }
        return String(remainder[..<closingQuote])
    }

    private func runtimeIdentifier(in arguments: [String]) -> String? {
        guard let command = arguments.last else {
            return nil
        }

        for marker in ["tmux new-session -d -s '", "tmux has-session -t '"] {
            guard let range = command.range(of: marker) else {
                continue
            }

            let remainder = command[range.upperBound...]
            guard let closingQuote = remainder.firstIndex(of: "'") else {
                continue
            }
            return String(remainder[..<closingQuote])
        }

        return nil
    }
}

private final class RemotePiTransport: PiRPCTransporting, @unchecked Sendable {
    private let sessionID: String
    private let sessionFile: String
    private let startupFailureMessage: String?
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(sessionID: String, sessionFile: String, startupFailureMessage: String?) {
        self.sessionID = sessionID
        self.sessionFile = sessionFile
        self.startupFailureMessage = startupFailureMessage
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch object["type"] as? String {
        case "get_state":
            if let startupFailureMessage {
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "success": false,
                    "error": startupFailureMessage
                ])
                return
            }

            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "success": true,
                "data": [
                    "sessionId": sessionID,
                    "sessionFile": sessionFile
                ]
            ])
        case "prompt":
            let prompt = object["message"] as? String ?? ""
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])

            if prompt == "deploy" {
                emit([
                    "type": "approval_request",
                    "id": "11111111-1111-1111-1111-111111111111",
                    "title": "Deploy to production?",
                    "text": "Pi wants to run deploy --prod."
                ])
                return
            }

            let responseText = prompt.isEmpty ? "Remote Pi ready" : "Remote \(prompt)"
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": responseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": responseText
                        ]
                    ]
                ]
            ])
        case "approval_response":
            let decision = object["decision"] as? String ?? "deny"
            let responseText = decision == "approve" ? "Deployment approved" : "Deployment denied"
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": responseText
                        ]
                    ]
                ]
            ])
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    func disconnect(status: Int32) {
        terminationHandler?(status)
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}
#endif
