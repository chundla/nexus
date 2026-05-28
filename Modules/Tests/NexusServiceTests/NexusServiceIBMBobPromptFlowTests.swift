#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceIBMBobPromptFlowTests {
    @Test func localIBMBobPromptRunsThroughSharedStructuredSessionSurface() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let transportHarness = IBMBobServiceTransportHarness(turns: [
            .init(stdoutLines: [
                #"{"type":"status","text":"Bob turn started"}"#,
                #"{"type":"message","text":"Hello from Bob"}"#,
                #"{"type":"completion","text":"Bob turn complete"}"#
            ])
        ])
        let launcher = ProcessSessionRuntimeLauncher(ibmBobTransportFactory: { executable, arguments, workingDirectory in
            try transportHarness.makeTransport(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        })
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: IBMBobPromptStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: IBMBobPromptStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(stdout: "[]\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let responseScreen = try service.sendSessionInput(sessionID: session.id, text: "ship it")
        let persistedScreen = try service.getSessionScreen(sessionID: session.id)
        let persistedSession = try service.getSessionRecord(sessionID: session.id)

        #expect(responseScreen.session.id == session.id)
        #expect(responseScreen.session.state == .ready)
        #expect(responseScreen.primarySurface == .structuredActivityFeed)
        #expect(responseScreen.activityItems.map(\.kind) == [.status, .message, .status, .message, .completion])
        #expect(responseScreen.activityItems.map(\.text) == [
            "IBM Bob Session ready. Send a prompt to start IBM Bob.",
            "You: ship it",
            "Bob turn started",
            "Hello from Bob",
            "Bob turn complete"
        ])
        #expect(persistedScreen.activityItems == responseScreen.activityItems)
        #expect(persistedSession.state == .ready)
        #expect(transportHarness.launches.count == 1)
        #expect(transportHarness.launches.first?.executable == "/tmp/fake-bob")
        #expect(transportHarness.launches.first?.workingDirectory == workspaceFolder.path(percentEncoded: false))
    }
}

private final class IBMBobServiceTransportHarness: @unchecked Sendable {
    struct Turn {
        let stdoutLines: [String]
        let stderrLines: [String]
        let terminationStatus: Int32

        init(stdoutLines: [String], stderrLines: [String] = [], terminationStatus: Int32 = 0) {
            self.stdoutLines = stdoutLines
            self.stderrLines = stderrLines
            self.terminationStatus = terminationStatus
        }
    }

    struct Launch {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    private let lock = NSLock()
    private let turns: [Turn]
    private(set) var launches: [Launch] = []

    init(turns: [Turn]) {
        self.turns = turns
    }

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any IBMBobTransporting {
        let turn: Turn
        lock.lock()
        launches.append(Launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        turn = turns[min(launches.count - 1, turns.count - 1)]
        lock.unlock()
        return IBMBobServiceSynchronousTransport(turn: turn)
    }
}

private final class IBMBobServiceSynchronousTransport: IBMBobTransporting, @unchecked Sendable {
    private let turn: IBMBobServiceTransportHarness.Turn
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var stderrLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(turn: IBMBobServiceTransportHarness.Turn) {
        self.turn = turn
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stderrLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {
        for line in turn.stdoutLines {
            stdoutLineHandler?(line)
        }
        for line in turn.stderrLines {
            stderrLineHandler?(line)
        }
        terminationHandler?(turn.terminationStatus)
    }

    func terminate() throws {}
}

private struct IBMBobPromptStubExecutableResolver: ProviderExecutableResolving {
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

private struct IBMBobPromptStubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "IBMBobPromptStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}
#endif
