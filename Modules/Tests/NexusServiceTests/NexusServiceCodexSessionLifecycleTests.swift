#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceCodexSessionLifecycleTests {
    @Test func localCodexRestartedSessionsRemainInspectableAndDefaultRelaunchResumesPersistedThread() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let transportHarness = PersistentCodexTransportHarness()
        func makeService() throws -> NexusService {
            try makeCodexLifecycleService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Codex",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let defaultSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .codex, name: "Review")
        let defaultScreen = try service.getSessionScreen(sessionID: defaultSession.id)
        let namedScreen = try service.getSessionScreen(sessionID: namedSession.id)

        let restartedService = try makeService()
        let overview = try restartedService.getWorkspaceOverview(workspaceID: workspace.id)
        let providerDetail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
        let interruptedDefaultScreen = try restartedService.getSessionScreen(sessionID: defaultSession.id)
        let interruptedNamedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)
        let relaunchedDefaultSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let relaunchedDefaultScreen = try restartedService.getSessionScreen(sessionID: defaultSession.id)

        let launches = transportHarness.launches()
        let expectedMessage = "Codex Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))
        let restartedNamedSession = try #require(providerDetail.alternateSessions.first)
        let firstDefaultLaunch = try #require(launches.first(where: { $0.method == "thread/start" }))
        let resumedDefaultLaunch = try #require(launches.last)

        #expect(defaultScreen.primarySurface == .structuredActivityFeed)
        #expect(defaultScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(namedScreen.primarySurface == .structuredActivityFeed)
        #expect(namedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(namedSession.name == "Review")
        #expect(codexCard.defaultSession.state == .interrupted)
        #expect(codexCard.defaultSession.summary == expectedMessage)
        #expect(codexCard.defaultSession.actionTitle == "Relaunch")
        #expect(providerDetail.defaultSession?.failureMessage == expectedMessage)
        #expect(restartedNamedSession.id == namedSession.id)
        #expect(restartedNamedSession.state == .interrupted)
        #expect(restartedNamedSession.failureMessage == expectedMessage)
        #expect(interruptedDefaultScreen.session.state == .interrupted)
        #expect(interruptedDefaultScreen.activityItems.map(\.text) == [expectedMessage])
        #expect(interruptedNamedScreen.session.state == .interrupted)
        #expect(interruptedNamedScreen.activityItems.map(\.text) == [expectedMessage])
        #expect(relaunchedDefaultSession.id == defaultSession.id)
        #expect(relaunchedDefaultSession.state == .ready)
        #expect(relaunchedDefaultScreen.session.state == .ready)
        #expect(relaunchedDefaultScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(launches.map(\.method) == ["thread/start", "thread/start", "thread/resume"])
        #expect(resumedDefaultLaunch.method == "thread/resume")
        #expect(resumedDefaultLaunch.requestedThreadID == firstDefaultLaunch.resolvedThreadID)
        #expect(resumedDefaultLaunch.resolvedThreadID == firstDefaultLaunch.resolvedThreadID)
    }

    @Test func localCodexNamedSessionCanBeStoppedRelaunchedAndDeletedWhilePreservingThreadLinkage() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let transportHarness = PersistentCodexTransportHarness()
        func makeService() throws -> NexusService {
            try makeCodexLifecycleService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Codex",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .codex, name: "Review")
        let firstScreen = try service.getSessionScreen(sessionID: namedSession.id)
        let stoppedSession = try service.stopSession(sessionID: namedSession.id)
        let stoppedRecord = try service.getSessionRecord(sessionID: namedSession.id)
        let stoppedScreen = try service.getSessionScreen(sessionID: namedSession.id)

        let restartedService = try makeService()
        let relaunchedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
        let relaunchedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)
        _ = try restartedService.stopSession(sessionID: namedSession.id)
        let deleted = try restartedService.deleteSessionRecord(sessionID: namedSession.id)
        let providerDetail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

        let launches = transportHarness.launches()
        let firstLaunch = try #require(launches.first)
        let resumedLaunch = try #require(launches.last)

        #expect(namedSession.providerID == .codex)
        #expect(namedSession.name == "Review")
        #expect(namedSession.isDefault == false)
        #expect(firstScreen.primarySurface == .structuredActivityFeed)
        #expect(firstScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(stoppedSession.id == namedSession.id)
        #expect(stoppedSession.state == .exited)
        #expect(stoppedRecord.id == namedSession.id)
        #expect(stoppedRecord.state == .exited)
        #expect(stoppedScreen.session.state == .exited)
        #expect(stoppedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(relaunchedSession.id == namedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(relaunchedScreen.session.state == .ready)
        #expect(relaunchedScreen.activityItems.map(\.text) == ["Codex shared Session stream connected"])
        #expect(launches.map(\.method) == ["thread/start", "thread/resume"])
        #expect(firstLaunch.requestedThreadID == nil)
        #expect(resumedLaunch.requestedThreadID == firstLaunch.resolvedThreadID)
        #expect(resumedLaunch.resolvedThreadID == firstLaunch.resolvedThreadID)
        #expect(deleted)
        #expect(providerDetail.alternateSessions.isEmpty)

        do {
            _ = try restartedService.getSessionScreen(sessionID: namedSession.id)
            Issue.record("Expected deleted Codex Session Record to be unavailable")
        } catch {
        }
    }
}

private func makeCodexLifecycleService(rootURL: URL, transportHarness: PersistentCodexTransportHarness) throws -> NexusService {
    let launcher = ProcessSessionRuntimeLauncher(localProtocolNativeRuntimeFactories: [.codex: { launchConfiguration, _, _ in
        try CodexAppServerRuntime(
            executable: launchConfiguration.executable,
            workingDirectory: launchConfiguration.workingDirectory,
            sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.codexSessionLinkage,
            terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
            transportFactory: { _, _, _ in transportHarness.makeTransport() }
        )
    }])

    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: CodexLifecycleStubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
            commandRunner: CodexLifecycleStubCommandRunner(results: [
                .init(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n")
            ]),
            codexReadinessProbe: NoOpCodexLifecycleReadinessProbe()
        ),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
    )
}

private struct CodexLifecycleStubExecutableResolver: ProviderExecutableResolving {
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

private struct CodexLifecycleStubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "CodexLifecycleStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private struct NoOpCodexLifecycleReadinessProbe: CodexReadinessProbing {
    func probe(executable: String, workingDirectory: String) async throws {}
}

private final class PersistentCodexTransportHarness: @unchecked Sendable {
    struct Launch: Sendable {
        let method: String
        let requestedThreadID: String?
        let resolvedThreadID: String
    }

    private let lock = NSLock()
    private var nextThreadNumber = 0
    private var recordedLaunches: [Launch] = []

    func makeTransport() -> any CodexAppServerTransporting {
        PersistentTestCodexAppServerTransport(harness: self)
    }

    func recordLaunch(method: String, requestedThreadID: String?) -> String {
        lock.lock()
        defer { lock.unlock() }

        let resolvedThreadID: String
        if method == "thread/resume", let requestedThreadID, requestedThreadID.isEmpty == false {
            resolvedThreadID = requestedThreadID
        } else {
            nextThreadNumber += 1
            resolvedThreadID = "codex-thread-\(nextThreadNumber)"
        }

        recordedLaunches.append(Launch(method: method, requestedThreadID: requestedThreadID, resolvedThreadID: resolvedThreadID))
        return resolvedThreadID
    }

    func launches() -> [Launch] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunches
    }
}

private final class PersistentTestCodexAppServerTransport: CodexAppServerTransporting, @unchecked Sendable {
    private let harness: PersistentCodexTransportHarness
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (CodexAppServerTermination) -> Void)?

    init(harness: PersistentCodexTransportHarness) {
        self.harness = harness
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (CodexAppServerTermination) -> Void)?) {
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
                "result": [
                    "userAgent": "nexus-test",
                    "codexHome": "/tmp/codex-home",
                    "platformFamily": "unix",
                    "platformOs": "macos"
                ]
            ])
        case "thread/start", "thread/resume":
            let params = object["params"] as? [String: Any]
            let requestedThreadID = params?["threadId"] as? String
            let method = object["method"] as? String ?? "thread/start"
            let threadID = harness.recordLaunch(method: method, requestedThreadID: requestedThreadID)
            emit([
                "id": object["id"] ?? 0,
                "result": [
                    "thread": [
                        "id": threadID,
                        "sessionId": threadID,
                        "preview": "",
                        "ephemeral": false,
                        "modelProvider": "openai",
                        "createdAt": 0,
                        "updatedAt": 0,
                        "status": ["type": "idle"],
                        "path": "/tmp/\(threadID).jsonl",
                        "cwd": "/tmp/workspace",
                        "cliVersion": "0.132.0",
                        "source": "appServer",
                        "turns": []
                    ],
                    "model": "gpt-5.5",
                    "modelProvider": "openai",
                    "cwd": "/tmp/workspace",
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user",
                    "sandbox": ["type": "readOnly", "networkAccess": false]
                ]
            ])
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(CodexAppServerTermination(status: 0, stderr: nil))
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
