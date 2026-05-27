#if os(macOS)
import Darwin
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ProviderHealthEvaluatorLocalShellResolutionTests {
    @Test func localCodexHealthResolvesExecutableFromLoginShellWhenServicePathsMissIt() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProviderHealthEvaluatorLocalShellResolutionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let workspaceFolder = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let executablePath = tempRoot
            .appendingPathComponent("nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("v24.14.1", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)
        try FileManager.default.createDirectory(at: executablePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: executablePath, atomically: true, encoding: .utf8)
        #expect(chmod(executablePath.path(percentEncoded: false), 0o755) == 0)

        let shellBuilder = LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
        let evaluator = ProviderHealthEvaluator(
            executableResolver: TestExecutableResolver(executables: [:]),
            commandRunner: TestCommandRunner(results: [
                .init(executable: "/bin/zsh", arguments: ["-lic", "command -v codex"]): .success(stdout: "\(executablePath.path(percentEncoded: false))\n"),
                .init(executable: "/bin/zsh", arguments: ["-lic", "'\(executablePath.path(percentEncoded: false))' '--version'"]): .success(stdout: "1.2.3\n"),
                .init(executable: "/bin/zsh", arguments: ["-lic", "'\(executablePath.path(percentEncoded: false))' '--help'"]): .success(stdout: "Usage: codex\n")
            ]),
            localShellCommandBuilder: shellBuilder
        )

        let health = evaluator.healthSummary(
            for: .codex,
            workspace: Workspace(
                id: UUID(),
                name: "Local",
                kind: .local,
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: UUID()
            ),
            remoteContext: nil
        )

        #expect(health.state == .available)
        #expect(health.summary == "Codex 1.2.3 is available")
        #expect(health.resolvedExecutable == executablePath.path(percentEncoded: false))
        #expect(health.version == "1.2.3")
        #expect(health.launchability == .launchable)
    }

    @Test func localShellCommandBuilderWrapsLaunchesInLoginShell() {
        let command = LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            .launchCommand(for: "/tmp/fake-codex")

        #expect(command.executable == "/bin/zsh")
        #expect(command.arguments == ["-lic", "exec '/tmp/fake-codex'"])
    }

    @Test func remoteCodexHealthUsesShellAwareDiscoveryForHomeInstalledExecutable() {
        let workspaceID = UUID()
        let hostID = UUID()
        let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
        let runner = RecordingRemoteCommandRunner(
            stdout: "/home/tester/.local/bin/codex\n1.2.3\n"
        )
        let evaluator = ProviderHealthEvaluator(
            executableResolver: TestExecutableResolver(executables: [:]),
            commandRunner: runner
        )

        let health = evaluator.healthSummary(
            for: .codex,
            workspace: Workspace(
                id: workspaceID,
                name: "Remote",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            ),
            remoteContext: RemoteWorkspaceHealthContext(
                host: host,
                hostValidation: HostValidationSnapshot(
                    hostID: hostID,
                    state: .available,
                    summary: "Host is available",
                    checkedAt: Date()
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspaceID,
                    state: .available,
                    summary: "Workspace is available",
                    checkedAt: Date()
                )
            )
        )

        #expect(health.state == .available)
        #expect(health.summary == "Codex 1.2.3 is available")
        #expect(health.resolvedExecutable == "/home/tester/.local/bin/codex")
        #expect(health.version == "1.2.3")
        #expect(health.launchability == .launchable)
        #expect(runner.lastInvocation?.executable == "/usr/bin/ssh")
        #expect(runner.lastInvocation?.arguments.last?.contains("command -v codex") == true)
        #expect(runner.lastInvocation?.arguments.last?.contains("$HOME/.local/bin/codex") == true)
        #expect(runner.lastInvocation?.arguments.last?.contains("for SHELL_ARGS in -lic -lc") == true)
    }
}

private struct TestExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: ["/usr/local/bin", "/opt/homebrew/bin"],
            homeDirectories: ["/Users/tester"],
            pathEnvironment: "/usr/local/bin:/opt/homebrew/bin"
        )
    }
}

private final class RecordingRemoteCommandRunner: ProviderCommandRunning {
    private(set) var lastInvocation: (executable: String, arguments: [String])?
    let stdout: String

    init(stdout: String) {
        self.stdout = stdout
    }

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        lastInvocation = (executable, arguments)
        return ProviderCommandResult(exitStatus: 0, stdout: stdout, stderr: "")
    }
}

private struct TestCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "TestCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}
#endif
