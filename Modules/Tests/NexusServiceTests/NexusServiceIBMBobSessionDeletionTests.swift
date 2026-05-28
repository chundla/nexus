#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceIBMBobSessionDeletionTests {
    @Test func localIBMBobDeleteAttemptsBestEffortNativeCleanupWhenStoredContinuityExists() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let commandRunner = RecordingIBMBobDeletionCommandRunner(expectations: [
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]),
                result: .success(stdout: "3.4.5\n")
            ),
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                result: .success(stdout: "[]\n")
            ),
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                result: .success(stdout: #"[{"session_id":"bob-session-1","index":2}]"# + "\n")
            ),
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"]),
                result: .success(stdout: "deleted\n")
            )
        ])
        let service = try makeIBMBobDeletionService(
            rootURL: rootURL,
            commandRunner: commandRunner,
            turns: [
                .init(stdoutLines: [
                    #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                    #"{"type":"message","text":"First reply"}"#,
                    #"{"type":"completion","text":"First turn complete"}"#
                ])
            ]
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        _ = try service.sendSessionInput(sessionID: session.id, text: "ship it")
        let deleted = try service.deleteSessionRecord(sessionID: session.id)
        let cleanupInvocation = try #require(commandRunner.invocations.last)

        #expect(deleted)
        #expect(cleanupInvocation.arguments == ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"])
    }

    @Test func localIBMBobDeleteStillRemovesSessionRecordWhenNativeCleanupFails() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let commandRunner = RecordingIBMBobDeletionCommandRunner(expectations: [
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]),
                result: .success(stdout: "3.4.5\n")
            ),
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                result: .success(stdout: "[]\n")
            ),
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                result: .success(stdout: #"[{"session_id":"bob-session-1","index":2}]"# + "\n")
            ),
            .init(
                invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"]),
                result: .success(stdout: "", stderr: "delete failed\n", exitStatus: 1)
            )
        ])
        let service = try makeIBMBobDeletionService(
            rootURL: rootURL,
            commandRunner: commandRunner,
            turns: [
                .init(stdoutLines: [
                    #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                    #"{"type":"message","text":"First reply"}"#,
                    #"{"type":"completion","text":"First turn complete"}"#
                ])
            ]
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        _ = try service.sendSessionInput(sessionID: session.id, text: "ship it")
        let deleted = try service.deleteSessionRecord(sessionID: session.id)
        let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

        #expect(deleted)
        #expect(providerDetail.defaultSession == nil)
        #expect(commandRunner.invocations.contains(where: { $0.arguments == ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"] }))
    }
}

private func makeIBMBobDeletionService(
    rootURL: URL,
    commandRunner: RecordingIBMBobDeletionCommandRunner,
    turns: [IBMBobDeletionTransportHarness.Turn]
) throws -> NexusService {
    let transportHarness = IBMBobDeletionTransportHarness(turns: turns)
    let launcher = ProcessSessionRuntimeLauncher(ibmBobTransportFactory: { executable, arguments, workingDirectory in
        try transportHarness.makeTransport(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    })
    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: IBMBobDeletionStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
            commandRunner: commandRunner,
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
        ),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher),
        ibmBobNativeSessionCleaner: IBMBobNativeSessionCleaner(
            executableResolver: IBMBobDeletionStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
            commandRunner: commandRunner,
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
        )
    )
}

private struct IBMBobDeletionStubExecutableResolver: ProviderExecutableResolving {
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

private final class RecordingIBMBobDeletionCommandRunner: ProviderCommandRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
    }

    struct Expectation {
        let invocation: Invocation
        let result: StubbedResult
    }

    struct RecordedInvocation: Equatable {
        let executable: String
        let arguments: [String]
        let currentDirectoryURL: URL?
    }

    enum StubbedResult {
        case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
    }

    private let expectations: [Expectation]
    private(set) var invocations: [RecordedInvocation] = []

    init(expectations: [Expectation]) {
        self.expectations = expectations
    }

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        let recordedInvocation = RecordedInvocation(executable: executable, arguments: arguments, currentDirectoryURL: currentDirectoryURL)
        invocations.append(recordedInvocation)

        let invocation = Invocation(executable: executable, arguments: arguments)
        guard expectations.indices.contains(invocations.count - 1),
              expectations[invocations.count - 1].invocation == invocation else {
            throw NSError(domain: "RecordingIBMBobDeletionCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected stub lookup for \(executable) \(arguments)"])
        }

        switch expectations[invocations.count - 1].result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private final class IBMBobDeletionTransportHarness: @unchecked Sendable {
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

    private let turns: [Turn]
    private var launchCount = 0

    init(turns: [Turn]) {
        self.turns = turns
    }

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any IBMBobTransporting {
        defer { launchCount += 1 }
        return IBMBobDeletionSynchronousTransport(turn: turns[min(launchCount, turns.count - 1)])
    }
}

private final class IBMBobDeletionSynchronousTransport: IBMBobTransporting, @unchecked Sendable {
    private let turn: IBMBobDeletionTransportHarness.Turn
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var stderrLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(turn: IBMBobDeletionTransportHarness.Turn) {
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
#endif
