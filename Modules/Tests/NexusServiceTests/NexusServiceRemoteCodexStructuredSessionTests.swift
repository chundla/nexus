#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceRemoteCodexStructuredSessionTests {
    @Test func remoteCodexDefaultSessionLaunchesStructuredSurfaceThroughSSHBridge() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteCodexTransportHarness()
        let service = try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Codex",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let screen = try service.getSessionScreen(sessionID: session.id)
        let launch = try #require(transportHarness.launches().first)

        #expect(session.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(launch.executable == "/usr/bin/ssh")
        #expect(launch.arguments.prefix(5) == ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
        #expect(launch.arguments.contains("-tt") == false)
        #expect(launch.arguments.contains("2222"))
        #expect(launch.arguments.last?.contains("tmux") == true)
        #expect(launch.arguments.last?.contains("app-server") == true)
    }

    @Test func restartedRemoteCodexDefaultSessionRecoversThroughAttachExistingBridgeAndThreadResume() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteCodexTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Codex",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let restartedService = try makeService()
        let resumedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
        let launches = transportHarness.launches()
        let firstLaunch = try #require(launches.first)
        let resumedLaunch = try #require(launches.last)

        #expect(firstSession.id == resumedSession.id)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(launches.count == 2)
        #expect(firstLaunch.method == "thread/start")
        #expect(firstLaunch.requestedThreadID == nil)
        #expect(resumedLaunch.method == "thread/resume")
        #expect(resumedLaunch.requestedThreadID == firstLaunch.resolvedThreadID)
        #expect(resumedLaunch.resolvedThreadID == firstLaunch.resolvedThreadID)
        #expect(firstLaunch.arguments.last?.contains("tmux new-session") == true)
        #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
        #expect(resumedLaunch.arguments.last?.contains("attach-session") == false)
    }

    @Test func remoteCodexNamedSessionUsesStructuredSurfaceAndOwnThreadLinkageAlongsideDefaultSession() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteCodexTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemoteCodexService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Codex",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let defaultSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .codex, name: "Review")
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
        let namedScreen = try service.getSessionScreen(sessionID: namedSession.id)

        let restartedService = try makeService()
        let resumedNamedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
        let resumedNamedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)
        let launches = transportHarness.launches()
        let defaultLaunch = try #require(launches.first)
        let namedLaunch = try #require(launches.dropFirst().first)
        let resumedNamedLaunch = try #require(launches.last)

        #expect(detail.defaultSession?.id == defaultSession.id)
        #expect(detail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(detail.failedSessions.isEmpty)
        #expect(namedScreen.primarySurface == .structuredActivityFeed)
        #expect(namedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(resumedNamedSession.id == namedSession.id)
        #expect(resumedNamedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedNamedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(launches.count == 3)
        #expect(defaultLaunch.method == "thread/start")
        #expect(namedLaunch.method == "thread/start")
        #expect(namedLaunch.resolvedThreadID != defaultLaunch.resolvedThreadID)
        #expect(resumedNamedLaunch.method == "thread/resume")
        #expect(resumedNamedLaunch.requestedThreadID == namedLaunch.resolvedThreadID)
        #expect(resumedNamedLaunch.resolvedThreadID == namedLaunch.resolvedThreadID)
        #expect(resumedNamedLaunch.resolvedThreadID != defaultLaunch.resolvedThreadID)
    }
}

private func makeRemoteCodexService(rootURL: URL, transportHarness: RemoteCodexTransportHarness) throws -> NexusService {
    let launcher = ProcessSessionRuntimeLauncher(codexTransportFactory: transportHarness.makeTransport)

    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: RemoteCodexStubExecutableResolver(),
            commandRunner: RemoteCodexStubCommandRunner(),
            remoteCodexReadinessProbe: RemoteCodexReadyReadinessProbe()
        ),
        hostValidationEvaluator: RemoteCodexAvailableHostValidationEvaluator(),
        workspaceAvailabilityEvaluator: RemoteCodexAvailableWorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
    )
}

private struct RemoteCodexStubExecutableResolver: ProviderExecutableResolving {
    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: nil,
            searchedDirectories: [],
            homeDirectories: [],
            pathEnvironment: nil
        )
    }
}

private struct RemoteCodexStubCommandRunner: ProviderCommandRunning {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        ProviderCommandResult(
            exitStatus: 0,
            stdout: "/home/tester/.local/bin/codex\n1.2.3\n",
            stderr: ""
        )
    }
}

private struct RemoteCodexReadyReadinessProbe: RemoteCodexReadinessProbing {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) throws -> RemoteCodexReadinessOutcome {
        .ready
    }
}

private struct RemoteCodexAvailableHostValidationEvaluator: HostValidationEvaluating {
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

private struct RemoteCodexAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
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

private final class RemoteCodexTransportHarness: @unchecked Sendable {
    struct Launch: Sendable {
        let executable: String
        let arguments: [String]
        let method: String
        let requestedThreadID: String?
        let resolvedThreadID: String
    }

    private let lock = NSLock()
    private var recordedLaunches: [Launch] = []
    private var pendingTransportArguments: [[String]] = []
    private var nextThreadNumber = 0

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any CodexAppServerTransporting {
        lock.lock()
        pendingTransportArguments.append(arguments)
        lock.unlock()
        return RemoteCodexTransport(executable: executable, harness: self)
    }

    func recordLaunch(executable: String, method: String, requestedThreadID: String?) -> Launch {
        lock.lock()
        defer { lock.unlock() }

        let resolvedThreadID: String
        if method == "thread/resume", let requestedThreadID, requestedThreadID.isEmpty == false {
            resolvedThreadID = requestedThreadID
        } else {
            nextThreadNumber += 1
            resolvedThreadID = "codex-thread-\(nextThreadNumber)"
        }

        let launch = Launch(
            executable: executable,
            arguments: pendingTransportArguments.removeFirst(),
            method: method,
            requestedThreadID: requestedThreadID,
            resolvedThreadID: resolvedThreadID
        )
        recordedLaunches.append(launch)
        return launch
    }

    func launches() -> [Launch] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunches
    }
}

private final class RemoteCodexTransport: CodexAppServerTransporting, @unchecked Sendable {
    private let executable: String
    private let harness: RemoteCodexTransportHarness
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(executable: String, harness: RemoteCodexTransportHarness) {
        self.executable = executable
        self.harness = harness
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch object["method"] as? String {
        case "initialize":
            emit([
                "id": object["id"] ?? 0,
                "result": ["userAgent": "nexus-test"]
            ])
        case "thread/start", "thread/resume":
            let params = object["params"] as? [String: Any]
            let method = object["method"] as? String ?? "thread/start"
            let launch = harness.recordLaunch(
                executable: executable,
                method: method,
                requestedThreadID: params?["threadId"] as? String
            )
            emit([
                "id": object["id"] ?? 0,
                "result": [
                    "thread": ["id": launch.resolvedThreadID]
                ]
            ])
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
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
