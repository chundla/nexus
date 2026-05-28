#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceIBMBobProviderReadinessTests {
    @Test func localIBMBobProviderCardAndDetailBecomeLaunchableWhenPassiveHealthProbePasses() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let commandRunner = RecordingBobCommandRunner(results: [
            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(stdout: "[]\n")
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: BobStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))
        let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)
        let probeInvocation = try #require(commandRunner.invocations.first(where: { $0.arguments == ["-lic", "'/tmp/fake-bob' '--list-sessions'"] }))

        #expect(providerCard.health.state == .available)
        #expect(providerCard.health.summary == "IBM Bob 3.4.5 is available")
        #expect(providerCard.health.resolvedExecutable == "/tmp/fake-bob")
        #expect(providerCard.health.version == "3.4.5")
        #expect(providerCard.health.launchability == .launchable)
        #expect(providerCard.capabilities.launchDefaultSession.isSupported)
        #expect(providerCard.capabilities.launchDefaultSession.isEnabled)
        #expect(providerCard.capabilities.createNamedSession.isSupported)
        #expect(providerCard.capabilities.createNamedSession.isEnabled)
        #expect(providerDetail.capabilities == providerCard.capabilities)
        #expect(probeInvocation.currentDirectoryURL?.path(percentEncoded: false) == workspaceFolder.path(percentEncoded: false))
    }

    @Test func localIBMBobBlocksLaunchabilityWhenPassiveProbeReportsLicenseRequirement() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: BobStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: RecordingBobCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                        stdout: "",
                        stderr: "You must accept the IBM Bob license before continuing.\n",
                        exitStatus: 1
                    )
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))

        #expect(providerCard.health.state == .misconfigured)
        #expect(providerCard.health.summary == "IBM Bob requires license acceptance")
        #expect(providerCard.health.launchability == .notLaunchable)
        #expect(providerCard.health.diagnostics == [
            ProviderHealthDiagnostic(
                severity: .error,
                code: "licenseRequired",
                message: "You must accept the IBM Bob license before continuing."
            )
        ])
        #expect(providerCard.capabilities.launchDefaultSession.isSupported)
        #expect(providerCard.capabilities.launchDefaultSession.isEnabled == false)
        #expect(providerCard.capabilities.launchDefaultSession.disabledReason == providerCard.health.summary)
        #expect(providerCard.capabilities.createNamedSession.isSupported)
        #expect(providerCard.capabilities.createNamedSession.isEnabled == false)
        #expect(providerCard.capabilities.createNamedSession.disabledReason == providerCard.health.summary)
    }

    @Test func localIBMBobRequiresAuthenticationWhenPassiveProbeReportsLoginFailure() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: BobStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: RecordingBobCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                        stdout: "",
                        stderr: "bob login required before listing sessions.\n",
                        exitStatus: 1
                    )
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))

        #expect(providerCard.health.state == .unavailable)
        #expect(providerCard.health.summary == "IBM Bob requires authentication")
        #expect(providerCard.health.launchability == .notLaunchable)
        #expect(providerCard.health.diagnostics == [
            ProviderHealthDiagnostic(
                severity: .error,
                code: "authenticationRequired",
                message: "bob login required before listing sessions."
            )
        ])
        #expect(providerCard.capabilities.launchDefaultSession.isEnabled == false)
        #expect(providerCard.capabilities.createNamedSession.isEnabled == false)
    }

    @Test func localIBMBobKeepsLaunchabilityWhenPassiveProbeIsInconclusive() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: BobStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: RecordingBobCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                        stdout: "",
                        stderr: "Could not confirm IBM Bob readiness from the passive session list probe.\n",
                        exitStatus: 1
                    )
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))

        #expect(providerCard.health.state == .available)
        #expect(providerCard.health.summary == "IBM Bob 3.4.5 is available")
        #expect(providerCard.health.launchability == .launchable)
        #expect(providerCard.health.diagnostics == [
            ProviderHealthDiagnostic(
                severity: .warning,
                code: "passiveProbeInconclusive",
                message: "Could not confirm IBM Bob readiness from the passive session list probe."
            )
        ])
        #expect(providerCard.capabilities.launchDefaultSession.isSupported)
        #expect(providerCard.capabilities.launchDefaultSession.isEnabled)
        #expect(providerCard.capabilities.createNamedSession.isSupported)
        #expect(providerCard.capabilities.createNamedSession.isEnabled)
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

private final class RecordingBobCommandRunner: ProviderCommandRunning {
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
        invocations.append(RecordedInvocation(executable: executable, arguments: arguments, currentDirectoryURL: currentDirectoryURL))

        guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
            throw NSError(domain: "RecordingBobCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}
#endif
