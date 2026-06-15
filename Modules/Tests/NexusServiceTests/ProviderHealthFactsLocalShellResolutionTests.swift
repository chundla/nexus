#if os(macOS)
    import Darwin
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct ProviderHealthFactsLocalShellResolutionTests {
        @Test func healthSummaryUsesProviderModuleRegistryInsteadOfCentralProviderSwitch() async {
            let expected = ProviderHealthSummary(
                state: .available,
                summary: "Module-owned Claude health",
                launchability: .launchable,
                diagnostics: []
            )
            let evaluator = ProviderHealthFacts(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .claude: TestProviderModule(providerID: .claude) { _, _, _ in expected }
                    ]
                )
            )

            let health = await evaluator.healthSummary(
                for: .claude,
                workspace: Workspace(
                    id: UUID(),
                    name: "Local",
                    kind: .local,
                    folderPath: "/tmp/workspace",
                    primaryGroupID: UUID()
                ),
                remoteContext: nil
            )

            #expect(health == expected)
        }

        @Test func localCodexHealthResolvesExecutableFromLoginShellWhenServicePathsMissIt() throws {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProviderHealthFactsLocalShellResolutionTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            let workspaceFolder = tempRoot.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let executablePath =
                tempRoot
                .appendingPathComponent("nvm", isDirectory: true)
                .appendingPathComponent("versions", isDirectory: true)
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("v24.14.1", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
            try FileManager.default.createDirectory(
                at: executablePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nexit 0\n".write(to: executablePath, atomically: true, encoding: .utf8)
            #expect(chmod(executablePath.path(percentEncoded: false), 0o755) == 0)

            let shellBuilder = LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            let readinessProbe = RecordingCodexReadinessProbe()
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: TestCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "command -v codex"]): .success(
                        stdout: "\(executablePath.path(percentEncoded: false))\n"),
                    .init(
                        executable: "/bin/zsh",
                        arguments: ["-lic", "'\(executablePath.path(percentEncoded: false))' '--version'"]): .success(
                            stdout: "1.2.3\n"),
                ]),
                localShellCommandBuilder: shellBuilder,
                codexReadinessProbe: readinessProbe
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
            #expect(readinessProbe.invocations.count == 1)
            #expect(readinessProbe.invocations.first?.executable == executablePath.path(percentEncoded: false))
            #expect(readinessProbe.invocations.first?.workingDirectory == workspaceFolder.path(percentEncoded: false))
        }

        @Test func localShellCommandBuilderAvoidsInteractivePosixShellForLaunches() {
            let command = LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                .launchCommand(for: "/tmp/fake-codex")

            #expect(command.executable == "/bin/zsh")
            #expect(command.arguments == ["-lc", "exec '/tmp/fake-codex'"])
        }

        @Test func localShellCommandBuilderAvoidsInteractiveCShellForLaunches() {
            let command = LocalShellCommandBuilder(environment: ["SHELL": "/bin/csh"])
                .launchCommand(for: "/tmp/fake-codex")

            #expect(command.executable == "/bin/csh")
            #expect(command.arguments == ["-c", "if ( -f ~/.login ) source ~/.login; exec '/tmp/fake-codex'"])
        }

        @Test func localShellCommandBuilderUsesLoginFishWithoutInteractiveModeForLaunches() throws {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProviderHealthFactsLocalShellResolutionTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            let fishPath = tempRoot.appendingPathComponent("fish", isDirectory: false)
            try "#!/bin/sh\nexit 0\n".write(to: fishPath, atomically: true, encoding: .utf8)
            #expect(chmod(fishPath.path(percentEncoded: false), 0o755) == 0)

            let command = LocalShellCommandBuilder(environment: ["SHELL": fishPath.path(percentEncoded: false)])
                .launchCommand(for: "/tmp/fake-codex")

            #expect(command.executable == fishPath.path(percentEncoded: false))
            #expect(command.arguments == ["-l", "-c", "exec '/tmp/fake-codex'"])
        }

        @Test func localCodexHealthResolvesExecutableFromInteractiveCShellWhenServicePathsMissIt() throws {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProviderHealthFactsLocalShellResolutionTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            let workspaceFolder = tempRoot.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let executablePath =
                tempRoot
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
            try FileManager.default.createDirectory(
                at: executablePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nexit 0\n".write(to: executablePath, atomically: true, encoding: .utf8)
            #expect(chmod(executablePath.path(percentEncoded: false), 0o755) == 0)

            let wrappedCommand = "if ( -f ~/.login ) source ~/.login; command -v codex"
            let wrappedVersionCommand =
                "if ( -f ~/.login ) source ~/.login; '\(executablePath.path(percentEncoded: false))' '--version'"
            let shellBuilder = LocalShellCommandBuilder(environment: ["SHELL": "/bin/csh"])
            let readinessProbe = RecordingCodexReadinessProbe()
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: TestCommandRunner(results: [
                    .init(executable: "/bin/csh", arguments: ["-i", "-c", wrappedCommand]): .success(
                        stdout: "\(executablePath.path(percentEncoded: false))\n"),
                    .init(executable: "/bin/csh", arguments: ["-i", "-c", wrappedVersionCommand]): .success(
                        stdout: "1.2.3\n"),
                ]),
                localShellCommandBuilder: shellBuilder,
                codexReadinessProbe: readinessProbe
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
            #expect(readinessProbe.invocations.count == 1)
            #expect(readinessProbe.invocations.first?.executable == executablePath.path(percentEncoded: false))
            #expect(readinessProbe.invocations.first?.workingDirectory == workspaceFolder.path(percentEncoded: false))
        }

        @Test func remoteCodexHealthUsesShellAwareDiscoveryForHomeInstalledExecutable() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(
                stdout: "/home/tester/.local/bin/codex\n1.2.3\n"
            )
            let readinessProbe = RecordingRemoteCodexReadinessProbe()
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remoteCodexReadinessProbe: readinessProbe
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
            #expect(runner.lastInvocation?.arguments.last?.contains("/bin/csh") == true)
            #expect(runner.lastInvocation?.arguments.last?.contains("source ~/.login") == true)
            #expect(runner.lastInvocation?.arguments.last?.contains("/opt/homebrew/bin/fish") == true)
            #expect(runner.lastInvocation?.arguments.last?.contains("tmux") == false)
            #expect(runner.lastInvocation?.arguments.last?.contains("--help") == false)
            #expect(readinessProbe.invocations.count == 1)
            #expect(readinessProbe.invocations.first?.hostID == hostID)
            #expect(readinessProbe.invocations.first?.executable == "/home/tester/.local/bin/codex")
            #expect(readinessProbe.invocations.first?.workingDirectory == "/srv/api")
        }

        @Test func remoteCodexReadinessProbeLaunchesDirectSSHAppServerWithoutPTY() async throws {
            let recorder = RecordingRemoteCodexTransportFactory()
            let probe = SSHRemoteCodexAppServerReadinessProbe(transportFactory: recorder.makeTransport)
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)

            let outcome = try await probe.probe(
                host: host,
                executable: "/home/tester/.local/bin/codex",
                workingDirectory: "/srv/api"
            )

            #expect(outcome == .ready)
            #expect(recorder.lastInvocation?.executable == "/usr/bin/ssh")
            #expect(
                recorder.lastInvocation?.arguments.prefix(6) == [
                    "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p",
                ])
            #expect(recorder.lastInvocation?.arguments.dropFirst(6).first == "2222")
            #expect(
                recorder.lastInvocation?.arguments.last
                    == "cd '/srv/api' || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec '/home/tester/.local/bin/codex' app-server"
            )
            #expect(recorder.lastInvocation?.arguments.last?.contains("tmux") == false)
            #expect(recorder.transport.sentLines.count == 1)
            #expect(recorder.transport.sentLines.first?.contains("\"method\":\"initialize\"") == true)
        }

        @Test func remotePiHealthUsesShellAwareDiscoveryAndDirectRPCReadinessProbe() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(
                stdout: "/home/tester/.local/bin/pi\n0.9.0\n"
            )
            let readinessProbe = RecordingRemotePiReadinessProbe()
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remotePiReadinessProbe: readinessProbe
            )

            let health = evaluator.healthSummary(
                for: .pi,
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
            #expect(health.summary == "Pi 0.9.0 is available")
            #expect(health.resolvedExecutable == "/home/tester/.local/bin/pi")
            #expect(health.version == "0.9.0")
            #expect(health.launchability == .launchable)
            #expect(runner.lastInvocation?.executable == "/usr/bin/ssh")
            #expect(runner.lastInvocation?.arguments.last?.contains("command -v pi") == true)
            #expect(runner.lastInvocation?.arguments.last?.contains("$HOME/.local/bin/pi") == true)
            #expect(runner.lastInvocation?.arguments.last?.contains("tmux") == false)
            #expect(runner.lastInvocation?.arguments.last?.contains("--help") == false)
            #expect(readinessProbe.invocations.count == 1)
            #expect(readinessProbe.invocations.first?.hostID == hostID)
            #expect(readinessProbe.invocations.first?.executable == "/home/tester/.local/bin/pi")
            #expect(readinessProbe.invocations.first?.workingDirectory == "/srv/api")
        }

        @Test func remotePiReadinessProbeLaunchesDirectSSHRPCWithoutPTY() async throws {
            let recorder = RecordingRemotePiTransportFactory()
            let probe = SSHRemotePiRPCReadinessProbe(transportFactory: recorder.makeTransport)
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)

            let outcome = try await probe.probe(
                host: host,
                executable: "/home/tester/.local/bin/pi",
                workingDirectory: "/srv/api"
            )

            #expect(outcome == .ready)
            #expect(recorder.lastInvocation?.executable == "/usr/bin/ssh")
            #expect(
                recorder.lastInvocation?.arguments.prefix(6) == [
                    "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p",
                ])
            #expect(recorder.lastInvocation?.arguments.dropFirst(6).first == "2222")
            #expect(
                recorder.lastInvocation?.arguments.last
                    == "cd '/srv/api' || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec '/home/tester/.local/bin/pi' --mode rpc"
            )
            #expect(recorder.lastInvocation?.arguments.last?.contains("tmux") == false)
            #expect(recorder.transport.sentLines.count == 1)
            #expect(recorder.transport.sentLines.first?.contains("\"id\":\"nexus-pi-readiness-get-state\"") == true)
            #expect(recorder.transport.sentLines.first?.contains("\"type\":\"get_state\"") == true)
        }

        @Test func remotePiHealthMarksExplicitAuthFailureAsNotLaunchable() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(stdout: "/home/tester/.local/bin/pi\n0.9.0\n")
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remotePiReadinessProbe: StubRemotePiReadinessProbe(
                    outcome: .authenticationRequired("Run `pi auth login` on the Host."))
            )

            let health = evaluator.healthSummary(
                for: .pi,
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

            #expect(health.state == .unavailable)
            #expect(health.summary == "Pi requires authentication on the Remote Workspace")
            #expect(health.resolvedExecutable == "/home/tester/.local/bin/pi")
            #expect(health.version == "0.9.0")
            #expect(health.launchability == .notLaunchable)
            #expect(
                health.diagnostics == [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "remoteAuthRequired",
                        message: "Run `pi auth login` on the Host."
                    )
                ])
        }

        @Test func remotePiHealthKeepsPiLaunchableWhenAuthReadinessIsUncertain() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(stdout: "/home/tester/.local/bin/pi\n0.9.0\n")
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remotePiReadinessProbe: StubRemotePiReadinessProbe(
                    outcome: .authenticationUncertain("Pi auth readiness could not be confirmed."))
            )

            let health = evaluator.healthSummary(
                for: .pi,
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
            #expect(health.summary == "Pi 0.9.0 is available")
            #expect(health.resolvedExecutable == "/home/tester/.local/bin/pi")
            #expect(health.version == "0.9.0")
            #expect(health.launchability == .launchable)
            #expect(
                health.diagnostics == [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote Pi launch prerequisites on Build Server for /srv/api."
                    ),
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "remoteAuthUncertain",
                        message: "Pi auth readiness could not be confirmed."
                    ),
                ])
        }

        @Test func remoteCodexHealthMarksExplicitAuthFailureAsNotLaunchable() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(stdout: "/home/tester/.local/bin/codex\n1.2.3\n")
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remoteCodexReadinessProbe: StubRemoteCodexReadinessProbe(
                    outcome: .authenticationRequired("Run `codex login` on the Host."))
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

            #expect(health.state == .unavailable)
            #expect(health.summary == "Codex requires authentication on the Remote Workspace")
            #expect(health.resolvedExecutable == "/home/tester/.local/bin/codex")
            #expect(health.version == "1.2.3")
            #expect(health.launchability == .notLaunchable)
            #expect(
                health.diagnostics == [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "remoteAuthRequired",
                        message: "Run `codex login` on the Host."
                    )
                ])
        }

        @Test func remoteCodexHealthFailsLaunchabilityButKeepsResolvedExecutableWhenRemoteHandshakeErrors() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(stdout: "/home/tester/.local/bin/codex\n1.2.3\n")
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remoteCodexReadinessProbe: ThrowingRemoteCodexReadinessProbe()
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

            #expect(health.state == .misconfigured)
            #expect(health.summary == "Codex is installed but failed the remote protocol-native readiness probe")
            #expect(health.resolvedExecutable == "/home/tester/.local/bin/codex")
            #expect(health.version == "1.2.3")
            #expect(health.launchability == .notLaunchable)
            #expect(
                health.diagnostics == [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "remoteLaunchProbeFailed",
                        message: "Codex remote handshake failed."
                    )
                ])
        }

        @Test func remoteCodexHealthKeepsCodexLaunchableWhenAuthReadinessIsUncertain() {
            let workspaceID = UUID()
            let hostID = UUID()
            let host = NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box")
            let runner = RecordingRemoteCommandRunner(stdout: "/home/tester/.local/bin/codex\n1.2.3\n")
            let evaluator = ProviderHealthFacts(
                executableResolver: TestExecutableResolver(executables: [:]),
                commandRunner: runner,
                remoteCodexReadinessProbe: StubRemoteCodexReadinessProbe(
                    outcome: .authenticationUncertain("Codex auth readiness could not be confirmed."))
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
            #expect(
                health.diagnostics == [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote Codex launch prerequisites on Build Server for /srv/api."
                    ),
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "remoteAuthUncertain",
                        message: "Codex auth readiness could not be confirmed."
                    ),
                ])
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

    private final class RecordingRemoteCommandRunner: ProviderCommandRunning, @unchecked Sendable {
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
                throw NSError(
                    domain: "TestCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class RecordingCodexReadinessProbe: CodexReadinessProbing, @unchecked Sendable {
        private(set) var invocations: [(executable: String, workingDirectory: String)] = []

        func probe(executable: String, workingDirectory: String) async throws {
            invocations.append((executable, workingDirectory))
        }
    }

    private final class RecordingRemoteCodexReadinessProbe: RemoteCodexReadinessProbing, @unchecked Sendable {
        private(set) var invocations: [(hostID: UUID, executable: String, workingDirectory: String)] = []

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemoteCodexReadinessOutcome
        {
            invocations.append((host.id, executable, workingDirectory))
            return .ready
        }
    }

    private final class RecordingRemotePiReadinessProbe: RemotePiReadinessProbing, @unchecked Sendable {
        private(set) var invocations: [(hostID: UUID, executable: String, workingDirectory: String)] = []

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemotePiReadinessOutcome
        {
            invocations.append((host.id, executable, workingDirectory))
            return .ready
        }
    }

    private struct StubRemoteCodexReadinessProbe: RemoteCodexReadinessProbing {
        let outcome: RemoteCodexReadinessOutcome

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemoteCodexReadinessOutcome
        {
            outcome
        }
    }

    private struct StubRemotePiReadinessProbe: RemotePiReadinessProbing {
        let outcome: RemotePiReadinessOutcome

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemotePiReadinessOutcome
        {
            outcome
        }
    }

    private struct ThrowingRemoteCodexReadinessProbe: RemoteCodexReadinessProbing {
        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemoteCodexReadinessOutcome
        {
            throw NSError(
                domain: "ThrowingRemoteCodexReadinessProbe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Codex remote handshake failed."])
        }
    }

    private final class RecordingRemoteCodexTransportFactory: @unchecked Sendable {
        let transport = ImmediateReadyRemoteCodexTransport()
        private(set) var lastInvocation: (executable: String, arguments: [String])?

        func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws
            -> any CodexAppServerTransporting
        {
            lastInvocation = (executable, arguments)
            return transport
        }
    }

    private final class RecordingRemotePiTransportFactory: @unchecked Sendable {
        let transport = ImmediateReadyRemotePiTransport()
        private(set) var lastInvocation: (executable: String, arguments: [String])?

        func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws
            -> any PiRPCTransporting
        {
            lastInvocation = (executable, arguments)
            return transport
        }
    }

    private final class ImmediateReadyRemoteCodexTransport: CodexAppServerTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (CodexAppServerTermination) -> Void)?
        private(set) var sentLines: [String] = []

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (CodexAppServerTermination) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)
            stdoutLineHandler?(
                "{\"id\":\"nexus-codex-readiness-initialize\",\"result\":{\"userAgent\":\"nexus-test\"}}")
        }

        func terminate() throws {
            terminationHandler?(CodexAppServerTermination(status: 0, stderr: nil))
        }
    }

    private final class ImmediateReadyRemotePiTransport: PiRPCTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private(set) var sentLines: [String] = []

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)
            stdoutLineHandler?(
                "{\"id\":\"nexus-pi-readiness-get-state\",\"type\":\"response\",\"success\":true,\"data\":{\"sessionId\":\"pi-session-1\"}}"
            )
        }

        func terminate() throws {
            terminationHandler?(0)
        }
    }
#endif
