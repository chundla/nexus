#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceTerminalProviderCompatibilityTests {
    @Test func localWorkspaceSupportsTerminalBackedAndProtocolNativeSessionsSideBySide() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: CompatibilityStubExecutableResolver(executables: [
                    "claude": "/tmp/fake-claude",
                    "codex": "/tmp/fake-codex",
                    "pi": "/tmp/fake-pi"
                ]),
                commandRunner: CompatibilityStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-claude' '--version'"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-claude' '--help'"]): .success(stdout: "Usage: claude\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-codex' '--version'"]): .success(stdout: "1.2.3\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                codexReadinessProbe: CompatibilityCodexReadinessProbe()
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: CompatibilitySessionRuntimeLauncher())
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Workspace",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let claudeSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let codexSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let piSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let codexDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
        let piDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
        let claudeScreen = try service.getSessionScreen(sessionID: claudeSession.id)
        let codexScreen = try service.getSessionScreen(sessionID: codexSession.id)
        let piScreen = try service.getSessionScreen(sessionID: piSession.id)

        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))
        let piCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))

        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
        #expect(codexCard.defaultSession.state == .ready)
        #expect(codexCard.defaultSession.actionTitle == "Resume")
        #expect(piCard.defaultSession.state == .ready)
        #expect(piCard.defaultSession.actionTitle == "Resume")

        #expect(claudeDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(claudeDetail.capabilities.createNamedSession.isEnabled)
        #expect(claudeDetail.defaultSession?.id == claudeSession.id)
        #expect(codexDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(codexDetail.capabilities.createNamedSession.isEnabled)
        #expect(codexDetail.defaultSession?.id == codexSession.id)
        #expect(piDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(piDetail.capabilities.createNamedSession.isEnabled)
        #expect(piDetail.defaultSession?.id == piSession.id)

        #expect(claudeScreen.primarySurface == .terminal)
        #expect(claudeScreen.transcript == "Claude ready")
        #expect(claudeScreen.activityItems.isEmpty)
        #expect(codexScreen.primarySurface == .structuredActivityFeed)
        #expect(codexScreen.transcript == "Codex ready")
        #expect(codexScreen.activityItems.isEmpty)
        #expect(piScreen.primarySurface == .structuredActivityFeed)
        #expect(piScreen.transcript.isEmpty)
        #expect(piScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(piScreen.activityItems.map(\.kind) == [.status])
    }
}

private struct CompatibilityStubExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: ["/tmp/search-a", "/tmp/search-b"],
            homeDirectories: ["/tmp/home"],
            pathEnvironment: "/tmp/search-a:/tmp/search-b"
        )
    }
}

private struct CompatibilityStubCommandRunner: ProviderCommandRunning {
    struct Invocation: Hashable {
        let executable: String
        let arguments: [String]
    }

    enum StubbedResult {
        case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
    }

    let results: [Invocation: StubbedResult]

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
            throw NSError(domain: "CompatibilityStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case .success(let stdout, let stderr, let exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private struct CompatibilityCodexReadinessProbe: CodexReadinessProbing {
    func probe(executable: String, workingDirectory: String) async throws {}
}

private struct CompatibilitySessionRuntimeLauncher: SessionRuntimeLaunching {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        switch session.providerID {
        case .claude:
            CompatibilityStaticSessionRuntime(transcript: "Claude ready")
        case .codex:
            CompatibilityStaticSessionRuntime(primarySurface: .structuredActivityFeed, transcript: "Codex ready")
        case .pi:
            CompatibilityStaticSessionRuntime(
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
            )
        case .ibmBob:
            CompatibilityStaticSessionRuntime(transcript: "")
        }
    }
}

private final class CompatibilityStaticSessionRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let primarySurface: SessionSurface
    private let transcript: String
    private let activityItems: [SessionActivityItem]

    init(primarySurface: SessionSurface = .terminal, transcript: String, activityItems: [SessionActivityItem] = []) {
        self.primarySurface = primarySurface
        self.transcript = transcript
        self.activityItems = activityItems
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: sessionWithCurrentState(session),
            primarySurface: primarySurface,
            transcript: transcript,
            activityItems: activityItems
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}

    func stop() throws {
        state = .exited
    }

    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}

    private func sessionWithCurrentState(_ session: Session) -> Session {
        Session(
            id: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            name: session.name,
            isDefault: session.isDefault,
            state: state,
            failureMessage: session.failureMessage
        )
    }
}
#endif
