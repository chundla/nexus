#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceLocalCodexMigrationTests {
    @Test func migratedLocalCodexSessionRecordPersistsStructuredSurfaceAfterRelaunch() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let healthEvaluator = ProviderHealthEvaluator(
            executableResolver: MigrationStubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
            commandRunner: MigrationStubCommandRunner(results: [
                .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-codex' '--version'"]): .success(stdout: "1.2.3\n")
            ]),
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
            codexReadinessProbe: MigrationCodexReadinessProbe()
        )

        let oldService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: MigrationTerminalCodexRuntimeLauncher())
        )
        let group = try oldService.createWorkspaceGroup(name: "Solo Group")
        let workspace = try oldService.createLocalWorkspace(
            name: "Local Workspace",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let migratedSession = try oldService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)

        func makeStructuredService() throws -> NexusService {
            let providerModuleRegistry = ServiceSessionProviderRegistry.providerModules(
                overrides: [
                    .codex: TestProviderModule(
                        providerID: .codex,
                        healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                            await providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
                        },
                        primarySurfaceEvaluator: { _ in .structuredActivityFeed },
                        runtimeConstructor: { _, _, _, _ in MigrationStructuredCodexRuntime() }
                    )
                ]
            )
            let launcher = ProcessSessionRuntimeLauncher(providerModuleRegistry: providerModuleRegistry)
            return try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: healthEvaluator,
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher),
                providerModuleRegistry: providerModuleRegistry
            )
        }

        let migratedService = try makeStructuredService()
        let relaunchedSession = try migratedService.launchOrResumeSession(sessionID: migratedSession.id)
        let relaunchedScreen = try migratedService.getSessionScreen(sessionID: migratedSession.id)

        let restartedService = try makeStructuredService()
        let interruptedScreen = try restartedService.getSessionScreen(sessionID: migratedSession.id)

        #expect(relaunchedSession.id == migratedSession.id)
        #expect(relaunchedScreen.primarySurface == .structuredActivityFeed)
        #expect(relaunchedScreen.activityItems.map { $0.text } == ["Codex shared Session stream connected"])
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.primarySurface == .structuredActivityFeed)
    }
}

private struct MigrationStubExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: ["/tmp/bin"],
            homeDirectories: ["/tmp/home"],
            pathEnvironment: "/tmp/bin"
        )
    }
}

private struct MigrationStubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "MigrationStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private struct MigrationCodexReadinessProbe: CodexReadinessProbing {
    func probe(executable: String, workingDirectory: String) async throws {}
}

private struct MigrationTerminalCodexRuntimeLauncher: SessionRuntimeLaunching {
    func makeRuntime(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) async throws -> any SessionRuntime {
        MigrationTerminalCodexRuntime()
    }
}

private final class MigrationTerminalCodexRuntime: SessionRuntime, @unchecked Sendable {
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

private final class MigrationStructuredCodexRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        SessionRecordAdapterMetadata(providerID: .codex, values: ["threadID": "codex-thread-1"])
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Codex shared Session stream connected")]
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
