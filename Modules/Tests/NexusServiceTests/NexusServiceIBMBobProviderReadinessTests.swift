#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct ProviderHealthFactsIBMBobPassiveProbeTests {
        @Test func localIBMBobPassiveProbeReturnsReadyFactsAndUsesWorkspaceDirectory() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let commandRunner = RecordingBobCommandRunner(results: [
                .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(
                    stdout: "3.4.5\n"),
                .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                    stdout: "[]\n"),
            ])
            let evaluator = ProviderHealthFacts(
                executableResolver: BobStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Local Bob",
                kind: .local,
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: UUID()
            )

            let result = await evaluator.localIBMBobPassiveProbe(workspace: workspace)
            let probeInvocation = try #require(
                commandRunner.invocations.first(where: {
                    $0.arguments == ["-lic", "'/tmp/fake-bob' '--list-sessions'"]
                }))

            #expect(
                result
                    == .passiveProbeCompleted(
                        executable: "/tmp/fake-bob",
                        version: "3.4.5",
                        diagnostics: [],
                        detail: nil
                    ))
            #expect(
                probeInvocation.currentDirectoryURL?.path(percentEncoded: false)
                    == workspaceFolder.path(percentEncoded: false))
        }

        @Test func localIBMBobPassiveProbeReturnsRawFailureDetail() async {
            let evaluator = ProviderHealthFacts(
                executableResolver: BobStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: RecordingBobCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(
                        stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                        stdout: "",
                        stderr: "You must accept the IBM Bob license before continuing.\n",
                        exitStatus: 1
                    ),
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Local Bob",
                kind: .local,
                folderPath: "/tmp/local-bob",
                primaryGroupID: UUID()
            )

            let result = await evaluator.localIBMBobPassiveProbe(workspace: workspace)

            #expect(
                result
                    == .passiveProbeCompleted(
                        executable: "/tmp/fake-bob",
                        version: "3.4.5",
                        diagnostics: [],
                        detail: "You must accept the IBM Bob license before continuing."
                    ))
        }

        @Test func remoteIBMBobPassiveProbeUsesResolutionAndListSessionsWithoutTmux() async throws {
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let commandRunner = SequentialBobCommandRunner(results: [
                .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                .success(stdout: "[]\n"),
            ])
            let evaluator = ProviderHealthFacts(
                executableResolver: BobStubExecutableResolver(executables: [:]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Remote Bob",
                kind: .remote,
                folderPath: "/srv/bob",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )

            let result = await evaluator.remoteIBMBobPassiveProbe(workspace: workspace, host: host)
            let resolutionProbe = try #require(commandRunner.invocations.first)
            let readinessProbe = try #require(commandRunner.invocations.last)

            #expect(
                result
                    == .passiveProbeCompleted(
                        executable: "/tmp/fake-bob",
                        version: "3.4.5",
                        detail: nil
                    ))
            #expect(resolutionProbe.executable == "/usr/bin/ssh")
            #expect(resolutionProbe.arguments.last?.contains("command -v bob") == true)
            #expect(resolutionProbe.arguments.last?.contains("$HOME/.local/bin/bob") == true)
            #expect(resolutionProbe.arguments.last?.contains("tmux") == false)
            #expect(readinessProbe.executable == "/usr/bin/ssh")
            #expect(readinessProbe.arguments.last?.contains("--list-sessions") == true)
            #expect(readinessProbe.arguments.last?.contains("tmux") == false)
        }

        @Test func remoteIBMBobPassiveProbeReturnsRawFailureDetail() async {
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")
            let evaluator = ProviderHealthFacts(
                executableResolver: BobStubExecutableResolver(executables: [:]),
                commandRunner: SequentialBobCommandRunner(results: [
                    .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                    .success(
                        stdout: "",
                        stderr: "bob login required before listing sessions.\n",
                        exitStatus: 1
                    ),
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Remote Bob",
                kind: .remote,
                folderPath: "/srv/bob",
                primaryGroupID: UUID(),
                remoteHostID: host.id
            )

            let result = await evaluator.remoteIBMBobPassiveProbe(workspace: workspace, host: host)

            #expect(
                result
                    == .passiveProbeCompleted(
                        executable: "/tmp/fake-bob",
                        version: "3.4.5",
                        detail: "bob login required before listing sessions."
                    ))
        }
    }

    private struct BobStubExecutableResolver: ProviderExecutableResolving {
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

    private final class RecordingBobCommandRunner: ProviderCommandRunning, @unchecked Sendable {
        struct Invocation: Hashable {
            let executable: String
            let arguments: [String]
        }

        struct RecordedInvocation: Equatable {
            let executable: String
            let arguments: [String]
            let currentDirectoryURL: URL?
        }

        enum StubbedResult {
            case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
        }

        let results: [Invocation: StubbedResult]
        private(set) var invocations: [RecordedInvocation] = []

        init(results: [Invocation: StubbedResult]) {
            self.results = results
        }

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            invocations.append(
                RecordedInvocation(
                    executable: executable, arguments: arguments, currentDirectoryURL: currentDirectoryURL))

            guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
                throw NSError(
                    domain: "RecordingBobCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class SequentialBobCommandRunner: ProviderCommandRunning, @unchecked Sendable {
        struct Invocation: Equatable {
            let executable: String
            let arguments: [String]
            let currentDirectoryURL: URL?
        }

        typealias StubbedResult = RecordingBobCommandRunner.StubbedResult

        private let results: [StubbedResult]
        private(set) var invocations: [Invocation] = []

        init(results: [StubbedResult]) {
            self.results = results
        }

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            invocations.append(
                Invocation(executable: executable, arguments: arguments, currentDirectoryURL: currentDirectoryURL))
            let index = invocations.count - 1
            guard results.indices.contains(index) else {
                throw NSError(
                    domain: "SequentialBobCommandRunner", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Missing sequential stub #\(index) for \(executable) \(arguments)"
                    ])
            }

            switch results[index] {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

#endif
