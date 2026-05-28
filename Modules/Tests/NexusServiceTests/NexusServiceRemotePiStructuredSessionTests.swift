#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceRemotePiStructuredSessionTests {
    @Test func remotePiDefaultSessionLaunchesStructuredSurfaceThroughSSHBridge() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let screen = try service.getSessionScreen(sessionID: session.id)
        let launch = try #require(transportHarness.launches().first)

        #expect(session.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(launch.executable == "/usr/bin/ssh")
        #expect(launch.arguments.prefix(5) == ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
        #expect(launch.arguments.contains("-tt") == false)
        #expect(launch.arguments.contains("2222"))
        #expect(launch.arguments.last?.contains("tmux new-session") == true)
        #expect(launch.arguments.last?.contains("/home/tester/.local/bin/pi") == true)
        #expect(launch.arguments.last?.contains("--mode") == true)
        #expect(launch.arguments.last?.contains("rpc") == true)
    }

    @Test func restartedRemotePiDefaultSessionStaysInterruptedUntilExplicitResumeRecoversExistingRuntime() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let restartedService = try makeService()
        let interruptedScreen = try restartedService.getSessionScreen(sessionID: firstSession.id)
        let launchesAfterInspection = transportHarness.launches()
        let resumedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
        let launches = transportHarness.launches()
        let resumedLaunch = try #require(launches.last)

        #expect(interruptedScreen.session.id == firstSession.id)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(launchesAfterInspection.count == 1)
        #expect(launches.count == 2)
        #expect(firstSession.id == resumedSession.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
        #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
    }

    @Test func remotePiBridgeLossLeavesInterruptedInspectableSessionUntilExplicitResume() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemotePiTransportHarness()
        let service = try makeRemotePiService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Pi",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        transportHarness.disconnectLatestTransport(status: 255)

        let interruptedScreen = try service.getSessionScreen(sessionID: session.id)
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
        let launchesAfterDisconnect = transportHarness.launches()
        let resumedSession = try service.launchOrResumeSession(sessionID: session.id)
        let resumedScreen = try service.getSessionScreen(sessionID: resumedSession.id)
        let resumedLaunch = try #require(transportHarness.launches().last)

        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.primarySurface == .structuredActivityFeed)
        #expect(detail.defaultSession?.state == .interrupted)
        #expect(launchesAfterDisconnect.count == 1)
        #expect(resumedSession.id == session.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
        #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
    }
}

private func makeRemotePiService(rootURL: URL, transportHarness: RemotePiTransportHarness) throws -> NexusService {
    let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: transportHarness.makeTransport)

    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: RemotePiStructuredStubExecutableResolver(),
            commandRunner: RemotePiStructuredStubCommandRunner(),
            remotePiReadinessProbe: RemotePiStructuredReadyReadinessProbe()
        ),
        hostValidationEvaluator: RemotePiStructuredAvailableHostValidationEvaluator(),
        workspaceAvailabilityEvaluator: RemotePiStructuredAvailableWorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
    )
}

private struct RemotePiStructuredStubExecutableResolver: ProviderExecutableResolving {
    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: nil,
            searchedDirectories: [],
            homeDirectories: [],
            pathEnvironment: nil
        )
    }
}

private struct RemotePiStructuredStubCommandRunner: ProviderCommandRunning {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        ProviderCommandResult(
            exitStatus: 0,
            stdout: "/home/tester/.local/bin/pi\n0.9.0\n",
            stderr: ""
        )
    }
}

private struct RemotePiStructuredReadyReadinessProbe: RemotePiReadinessProbing {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) throws -> RemotePiReadinessOutcome {
        .ready
    }
}

private struct RemotePiStructuredAvailableHostValidationEvaluator: HostValidationEvaluating {
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

private struct RemotePiStructuredAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
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

private final class RemotePiTransportHarness: @unchecked Sendable {
    struct Launch: Sendable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var recordedLaunches: [Launch] = []
    private var activeTransports: [RemotePiTransport] = []

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any PiRPCTransporting {
        lock.lock()
        recordedLaunches.append(Launch(executable: executable, arguments: arguments))
        lock.unlock()
        let transport = RemotePiTransport()
        register(transport)
        return transport
    }

    func launches() -> [Launch] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunches
    }

    func disconnectLatestTransport(status: Int32) {
        lock.lock()
        let transport = activeTransports.last
        lock.unlock()
        transport?.disconnect(status: status)
    }

    private func register(_ transport: RemotePiTransport) {
        lock.lock()
        activeTransports.append(transport)
        lock.unlock()
    }
}

private final class RemotePiTransport: PiRPCTransporting, @unchecked Sendable {
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "get_state" else {
            return
        }

        emit([
            "id": object["id"] as? String ?? "state",
            "type": "response",
            "success": true,
            "data": [
                "sessionId": "pi-session-1",
                "sessionFile": "/tmp/pi-session-1.jsonl"
            ]
        ])
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    func disconnect(status: Int32) {
        terminationHandler?(status)
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}
#endif
