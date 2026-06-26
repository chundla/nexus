#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct NexusServicePiProviderReadinessTests {
        @Test func localPiProviderCardAndDetailBecomeLaunchableWhenPiHealthPasses() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                            stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                            stdout: "Usage: pi\n"),
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                )
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let overview = try service.refreshWorkspaceOverview(workspaceID: workspace.id)
            let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))
            let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

            #expect(providerCard.health.state == .available)
            #expect(providerCard.health.summary == "Pi 0.9.0 is available")
            #expect(providerCard.health.resolvedExecutable == "/tmp/fake-pi")
            #expect(providerCard.health.version == "0.9.0")
            #expect(providerCard.health.launchability == .launchable)
            #expect(providerCard.capabilities.launchDefaultSession.isSupported)
            #expect(providerCard.capabilities.launchDefaultSession.isEnabled)
            #expect(providerCard.capabilities.launchDefaultSession.disabledReason == nil)
            #expect(providerCard.capabilities.createNamedSession.isSupported)
            #expect(providerCard.capabilities.createNamedSession.isEnabled)
            #expect(providerCard.capabilities.createNamedSession.disabledReason == nil)
            #expect(providerDetail.capabilities == providerCard.capabilities)
        }

        @Test func localPiDisabledReasonsComeFromProviderHealthWhenPiIsNotLaunchable() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStubExecutableResolver(executables: [:]),
                    commandRunner: PiStubCommandRunner(results: [:]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                )
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let overview = try service.refreshWorkspaceOverview(workspaceID: workspace.id)
            let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))
            let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

            #expect(providerCard.health.state == .unavailable)
            #expect(providerCard.health.summary == "Pi executable was not found")
            #expect(providerCard.health.launchability == .notLaunchable)
            #expect(providerCard.capabilities.launchDefaultSession.isSupported)
            #expect(providerCard.capabilities.launchDefaultSession.isEnabled == false)
            #expect(providerCard.capabilities.launchDefaultSession.disabledReason == providerCard.health.summary)
            #expect(providerCard.capabilities.createNamedSession.isSupported)
            #expect(providerCard.capabilities.createNamedSession.isEnabled == false)
            #expect(providerCard.capabilities.createNamedSession.disabledReason == providerCard.health.summary)
            #expect(providerDetail.capabilities == providerCard.capabilities)
        }

        @Test func remotePiProviderCardAndDetailBecomeLaunchableOnHealthyRemoteWorkspace() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: RemotePiStubCommandRunner(),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                    remotePiReadinessProbe: ReadyRemotePiReadinessProbe()
                ),
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator()
            )

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Pi",
                hostID: host.id,
                remotePath: "/srv/pi",
                primaryGroupID: group.id
            )

            let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
            let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))
            let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

            #expect(providerCard.health.state == .available)
            #expect(providerCard.health.summary == "Pi 0.9.0 is available")
            #expect(providerCard.health.launchability == .launchable)
            #expect(providerCard.capabilities.launchDefaultSession.isSupported)
            #expect(providerCard.capabilities.launchDefaultSession.isEnabled)
            #expect(providerCard.capabilities.createNamedSession.isSupported)
            #expect(providerCard.capabilities.createNamedSession.isEnabled)
            #expect(providerCard.prelaunchPrimarySurface == .structuredActivityFeed)
            #expect(providerDetail.capabilities == providerCard.capabilities)
            #expect(providerDetail.prelaunchPrimarySurface == .structuredActivityFeed)
        }
    }

    private struct PiStubExecutableResolver: ProviderExecutableResolving {
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

    private struct PiStubCommandRunner: ProviderCommandRunning {
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
                    domain: "PiStubCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private struct ReadyRemotePiReadinessProbe: RemotePiReadinessProbing {
        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemotePiReadinessOutcome
        {
            .ready
        }
    }

    private struct RemotePiStubCommandRunner: ProviderCommandRunning {
        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            ProviderCommandResult(exitStatus: 0, stdout: "/tmp/fake-pi\n0.9.0\n", stderr: "")
        }
    }

    private struct AvailableHostValidationEvaluator: HostValidationEvaluating {
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

    private struct AvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
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
#endif
