#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceRemoteIBMBobStructuredSessionTests {
    @Test func remoteIBMBobDefaultSessionLaunchCreatesStructuredIdleSessionFromSharedProviderCapabilities() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness()
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)
        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let screen = try service.getSessionScreen(sessionID: session.id)

        #expect(providerCard.health.summary == "IBM Bob 3.4.5 is available")
        #expect(providerCard.capabilities.launchDefaultSession.isEnabled)
        #expect(providerCard.capabilities.createNamedSession.isEnabled)
        #expect(providerCard.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(detail.capabilities == providerCard.capabilities)
        #expect(detail.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(session.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(transportHarness.launches().isEmpty)
    }

    @Test func restartedRemoteIBMBobDefaultSessionStaysReadyAndResumableWithoutRemoteRuntimeRecovery() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let restartedService = try makeService()
        let restartedScreen = try restartedService.getSessionScreen(sessionID: firstSession.id)
        let resumedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)

        #expect(restartedScreen.session.state == .ready)
        #expect(restartedScreen.primarySurface == .structuredActivityFeed)
        #expect(restartedScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(resumedSession.id == firstSession.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(transportHarness.launches().isEmpty)
    }

    @Test func remoteIBMBobNamedSessionUsesSharedNamingAndStructuredIdleScreen() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness()
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let firstSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: nil)
        let secondSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: nil)
        let firstScreen = try service.getSessionScreen(sessionID: firstSession.id)
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

        #expect(firstSession.name == "Session 1")
        #expect(secondSession.name == "Session 2")
        #expect(firstScreen.primarySurface == .structuredActivityFeed)
        #expect(firstScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(detail.alternateSessions.map(\.name) == ["Session 1", "Session 2"])
        #expect(transportHarness.launches().isEmpty)
    }
}

private func makeRemoteIBMBobService(rootURL: URL, transportHarness: RemoteIBMBobTransportHarness) throws -> NexusService {
    let launcher = ProcessSessionRuntimeLauncher(ibmBobTransportFactory: transportHarness.makeTransport)

    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: RemoteIBMBobStubExecutableResolver(executables: [:]),
            commandRunner: RemoteIBMBobCommandRunner(),
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
        ),
        hostValidationEvaluator: RemoteIBMBobAvailableHostValidationEvaluator(),
        workspaceAvailabilityEvaluator: RemoteIBMBobAvailableWorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
    )
}

private struct RemoteIBMBobStubExecutableResolver: ProviderExecutableResolving {
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

private final class RemoteIBMBobCommandRunner: ProviderCommandRunning, @unchecked Sendable {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        guard let script = arguments.last else {
            throw NSError(domain: "RemoteIBMBobCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SSH script for \(executable) \(arguments)"])
        }

        if script.contains("--list-sessions") {
            return ProviderCommandResult(exitStatus: 0, stdout: "[]\n", stderr: "")
        }

        if script.contains("--version") {
            return ProviderCommandResult(exitStatus: 0, stdout: "/tmp/fake-bob\n3.4.5\n", stderr: "")
        }

        throw NSError(domain: "RemoteIBMBobCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected SSH script: \(script)"])
    }
}

private struct RemoteIBMBobAvailableHostValidationEvaluator: HostValidationEvaluating {
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

private struct RemoteIBMBobAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult {
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

private final class RemoteIBMBobTransportHarness: @unchecked Sendable {
    struct Launch: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    private let lock = NSLock()
    private var recordedLaunches: [Launch] = []

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any IBMBobTransporting {
        lock.lock()
        recordedLaunches.append(Launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        lock.unlock()
        return RemoteIBMBobSynchronousTransport()
    }

    func launches() -> [Launch] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunches
    }
}

private final class RemoteIBMBobSynchronousTransport: IBMBobTransporting, @unchecked Sendable {
    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {}
    func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {}
    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {}
    func start() throws {}
    func terminate() throws {}
}
#endif
