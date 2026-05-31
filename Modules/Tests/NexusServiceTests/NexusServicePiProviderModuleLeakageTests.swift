#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServicePiProviderModuleLeakageTests {
    @Test func launchingPiSessionUsesProviderModuleRuntimePresentation() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = RecordingPiSessionRuntimeLauncher()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: AlwaysReadyProviderHealthFacts(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        _ = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let launch = try #require(launcher.launches.first)

        #expect(launch.launchConfiguration.initialTranscript == "Launching Local Pi with Pi…\n")
        #expect(launch.launchConfiguration.terminationStatusMessageBuilder(9) == "\n[Pi exited with status 9]\n")
    }

    @Test func relaunchingRemotePiSessionUsesProviderModuleRecoveryFailure() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let initialService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: AlwaysReadyProviderHealthFacts(),
            hostValidationEvaluator: AlwaysAvailableHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: AlwaysAvailableWorkspaceAvailabilityEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingPiSessionRuntimeLauncher())
        )

        let group = try initialService.createWorkspaceGroup(name: "Remote")
        let host = try initialService.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try initialService.validateHost(hostID: host.id)
        let workspace = try initialService.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let session = try initialService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let relaunchedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: AlwaysReadyProviderHealthFacts(),
            hostValidationEvaluator: AlwaysAvailableHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: AlwaysAvailableWorkspaceAvailabilityEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(
                launcher: FailingPiAttachSessionRuntimeLauncher(
                    error: NSError(
                        domain: "NexusServicePiProviderModuleLeakageTests",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "permission denied"]
                    )
                )
            )
        )

        let recoveredSession = try relaunchedService.launchOrResumeSession(sessionID: session.id)
        let runtimeIdentifier = "nexus-\(session.id.uuidString.lowercased())-runtime-1"

        #expect(recoveredSession.state == .interrupted)
        #expect(
            recoveredSession.failureMessage
                == "Could not reach Build Server to recover remote runtime '\(runtimeIdentifier)'. permission denied"
        )
    }
}

private struct AlwaysReadyProviderHealthFacts: ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        ProviderID.allCases.map { providerID in
            WorkspaceProviderCard(
                provider: Provider(id: providerID),
                health: readyHealthSummary(for: providerID),
                defaultSession: ProviderDefaultSessionSummary(
                    state: .notCreated,
                    summary: "No default session yet",
                    actionTitle: "Launch"
                )
            )
        }
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        readyHealthSummary(for: providerID)
    }

    private func readyHealthSummary(for providerID: ProviderID) -> ProviderHealthSummary {
        ProviderHealthSummary(
            state: .available,
            summary: "Ready",
            resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
            launchability: .launchable
        )
    }
}

private struct AlwaysAvailableHostValidationEvaluator: HostValidationEvaluating {
    func validate(host: NexusDomain.Host) -> HostValidationResult {
        HostValidationResult(state: .available, summary: "Host is available", diagnostics: [])
    }
}

private struct AlwaysAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult {
        WorkspaceAvailabilityResult(state: .available, summary: "Workspace is available", diagnostics: [])
    }
}

private final class RecordingPiSessionRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    struct Launch {
        let session: Session
        let workspace: Workspace
        let launchConfiguration: SessionRuntimeLaunchConfiguration
    }

    private(set) var launches: [Launch] = []

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        launches.append(
            Launch(
                session: session,
                workspace: workspace,
                launchConfiguration: launchConfiguration
            )
        )
        return StaticStructuredPiSessionRuntime()
    }
}

private final class FailingPiAttachSessionRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        if launchConfiguration.remoteRuntimeLaunchMode == .attachExisting {
            throw error
        }

        return StaticStructuredPiSessionRuntime()
    }
}

private final class StaticStructuredPiSessionRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Session stream connected")]
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
