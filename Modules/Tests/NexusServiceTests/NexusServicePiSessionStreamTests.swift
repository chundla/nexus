#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServicePiSessionStreamTests {
    @Test func localPiDefaultSessionLaunchAndResumePreserveSharedActivity() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = ActivitySessionRuntimeLauncher(
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")
            ]
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: PiStreamStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let firstScreen = try service.getSessionScreen(sessionID: firstSession.id)
        let resumedSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        #expect(firstSession.providerID == .pi)
        #expect(firstSession.isDefault)
        #expect(resumedSession.id == firstSession.id)
        #expect(firstScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(firstScreen.activityItems.map(\.kind) == [.status])
        #expect(firstScreen.transcript.isEmpty)
        #expect(launcher.launchCount == 1)
    }
}

private struct PiStreamStubExecutableResolver: ProviderExecutableResolving {
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

private struct PiStreamStubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "PiStreamStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private final class ActivitySessionRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    private let activityItems: [SessionActivityItem]
    private(set) var launchCount = 0

    init(activityItems: [SessionActivityItem]) {
        self.activityItems = activityItems
    }

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) throws -> any SessionRuntime {
        launchCount += 1
        return ActivitySessionRuntime(activityItems: activityItems)
    }
}

private final class ActivitySessionRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    private let activityItems: [SessionActivityItem]
    private var terminalColumns = 80
    private var terminalRows = 24
    private var changeHandler: (@Sendable () -> Void)?

    init(activityItems: [SessionActivityItem]) {
        self.activityItems = activityItems
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: session,
            transcript: "",
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        changeHandler = handler
    }

    func stop() throws {
        state = .exited
        changeHandler?()
    }

    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}

    func resize(columns: Int, rows: Int) throws {
        terminalColumns = columns
        terminalRows = rows
        changeHandler?()
    }
}
#endif
