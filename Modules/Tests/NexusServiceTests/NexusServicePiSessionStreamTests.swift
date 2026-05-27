#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServicePiSessionStreamTests {
    @Test func localPiDefaultSessionLaunchAndResumePreserveSharedActivity() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launchCounter = LaunchCounter()
        let launcher = ProcessSessionRuntimeLauncher(piRuntimeFactory: { launchConfiguration, _, _ in
            launchCounter.increment()
            return try PiRPCSessionRuntime(
                executable: launchConfiguration.executable,
                workingDirectory: launchConfiguration.workingDirectory,
                terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                transportFactory: { _, _, _ in
                    TestPiRPCTransport()
                }
            )
        })

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: PiStreamStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let firstScreen = try service.getSessionScreen(sessionID: firstSession.id)
        let resumedSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        #expect(firstSession.providerID == .pi)
        #expect(firstSession.isDefault)
        #expect(resumedSession.id == firstSession.id)
        #expect(firstScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
        #expect(firstScreen.activityItems.map(\.kind) == [.status])
        #expect(firstScreen.transcript.isEmpty)
        #expect(launchCounter.value == 1)
    }

    @Test func localPiDefaultSessionRelaunchKeepsPiConversationLinkageAcrossServiceRestart() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let transportHarness = PersistentPiTransportHarness()
        func makeService() throws -> NexusService {
            let launcher = ProcessSessionRuntimeLauncher(piRuntimeFactory: { launchConfiguration, _, _ in
                try PiRPCSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.piSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    transportFactory: { _, arguments, _ in
                        transportHarness.makeTransport(arguments: arguments)
                    }
                )
            })

            return try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthEvaluator(
                    executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStreamStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        _ = try service.sendSessionText(sessionID: firstSession.id, text: "alpha")
        let firstTurn = try service.sendSessionInputKey(sessionID: firstSession.id, key: .enter)

        let restartedService = try makeService()
        let relaunchedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        _ = try restartedService.sendSessionText(sessionID: relaunchedSession.id, text: "what was my last message?")
        let resumedTurn = try restartedService.sendSessionInputKey(sessionID: relaunchedSession.id, key: .enter)

        #expect(firstTurn.activityItems.suffix(2).map(\.text) == ["You: alpha", "Pi: alpha"])
        #expect(relaunchedSession.id == firstSession.id)
        #expect(resumedTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: alpha"])
    }

    @Test func localPiNamedSessionCanBeStoppedRelaunchedAndDeletedWhilePreservingConversationLinkage() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let transportHarness = PersistentPiTransportHarness()
        func makeService() throws -> NexusService {
            let launcher = ProcessSessionRuntimeLauncher(piRuntimeFactory: { launchConfiguration, _, _ in
                try PiRPCSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.piSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    transportFactory: { _, arguments, _ in
                        transportHarness.makeTransport(arguments: arguments)
                    }
                )
            })

            return try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthEvaluator(
                    executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStreamStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")
        _ = try service.sendSessionText(sessionID: namedSession.id, text: "alpha")
        let firstTurn = try service.sendSessionInputKey(sessionID: namedSession.id, key: .enter)
        let stoppedSession = try service.stopSession(sessionID: namedSession.id)
        let stoppedRecord = try service.getSessionRecord(sessionID: namedSession.id)

        let restartedService = try makeService()
        let relaunchedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
        _ = try restartedService.sendSessionText(sessionID: relaunchedSession.id, text: "what was my last message?")
        let resumedTurn = try restartedService.sendSessionInputKey(sessionID: relaunchedSession.id, key: .enter)
        _ = try restartedService.stopSession(sessionID: namedSession.id)
        let deleted = try restartedService.deleteSessionRecord(sessionID: namedSession.id)
        let providerDetail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

        #expect(namedSession.providerID == .pi)
        #expect(namedSession.name == "Review")
        #expect(namedSession.isDefault == false)
        #expect(firstTurn.activityItems.suffix(2).map(\.text) == ["You: alpha", "Pi: alpha"])
        #expect(stoppedSession.id == namedSession.id)
        #expect(stoppedSession.state == .exited)
        #expect(stoppedRecord.id == namedSession.id)
        #expect(stoppedRecord.state == .exited)
        #expect(relaunchedSession.id == namedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(resumedTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: alpha"])
        #expect(deleted)
        #expect(providerDetail.alternateSessions.isEmpty)

        do {
            _ = try restartedService.getSessionScreen(sessionID: namedSession.id)
            Issue.record("Expected deleted Pi Session Record to be unavailable")
        } catch {
        }
    }

    @Test func localPiRuntimeStreamsPromptAndAssistantMessageIntoSharedSessionActivity() throws {
        let runtime = try PiRPCSessionRuntime(
            executable: "/tmp/fake-pi",
            workingDirectory: "/tmp",
            terminationStatusMessageBuilder: { _ in "" },
            transportFactory: { _, _, _ in
                TestPiRPCTransport(promptResponseText: "world")
            }
        )

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )

        try runtime.sendText("hello")
        try runtime.sendInputKey(.enter, applicationCursorMode: false)
        let screen = runtime.sessionScreen(for: session)

        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: world"
        ])
        #expect(screen.activityItems.map(\.kind) == [.status, .message, .message])
        #expect(screen.transcript == "> hello\nworld")
    }

    @Test func localPiSessionScreenShowsPendingApprovalRequestInSharedSessionStream() throws {
        let runtime = try PiRPCSessionRuntime(
            executable: "/tmp/fake-pi",
            workingDirectory: "/tmp",
            terminationStatusMessageBuilder: { _ in "" },
            transportFactory: { _, _, _ in
                ApprovalRequestTestPiRPCTransport()
            }
        )

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )

        try runtime.sendText("deploy")
        try runtime.sendInputKey(.enter, applicationCursorMode: false)
        let screen = runtime.sessionScreen(for: session)

        #expect(screen.activityItems.map(\.kind) == [.status, .message, .approvalRequest])
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: deploy",
            "Approval Request: Deploy to production?"
        ])
        #expect(screen.approvalRequests == [
            SessionApprovalRequest(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "Deploy to production?",
                text: "Pi wants to run deploy --prod.",
                state: .pending
            )
        ])
    }

    @Test func localPiApprovalDecisionContinuesSessionWithoutChangingProviderHealth() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = ProcessSessionRuntimeLauncher(piRuntimeFactory: { launchConfiguration, _, _ in
            try PiRPCSessionRuntime(
                executable: launchConfiguration.executable,
                workingDirectory: launchConfiguration.workingDirectory,
                terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                transportFactory: { _, _, _ in
                    ApprovalRequestTestPiRPCTransport()
                }
            )
        })

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: PiStreamStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let pendingScreen = try service.sendSessionInput(sessionID: session.id, text: "deploy")
        let approvalRequest = try #require(pendingScreen.approvalRequests.first)

        let approvedScreen = try service.respondToApprovalRequest(
            sessionID: session.id,
            approvalRequestID: approvalRequest.id,
            decision: .approve
        )
        let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

        #expect(approvedScreen.activityItems.suffix(3).map(\.text) == [
            "Approval Request: Deploy to production?",
            "Approved: Deploy to production?",
            "Pi: Deployment approved"
        ])
        #expect(approvedScreen.approvalRequests == [
            SessionApprovalRequest(
                id: approvalRequest.id,
                title: "Deploy to production?",
                text: "Pi wants to run deploy --prod.",
                state: .approved
            )
        ])
        #expect(approvedScreen.transcript == "> deploy\nDeployment approved")
        #expect(providerDetail.health.state == .available)
        #expect(providerDetail.health.summary == "Pi 0.9.0 is available")
    }

    @Test func localPiDeniedApprovalRequestKeepsDeniedDecisionInSharedSessionState() throws {
        let runtime = try PiRPCSessionRuntime(
            executable: "/tmp/fake-pi",
            workingDirectory: "/tmp",
            terminationStatusMessageBuilder: { _ in "" },
            transportFactory: { _, _, _ in
                ApprovalRequestTestPiRPCTransport()
            }
        )

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )

        try runtime.sendInput("deploy")
        let approvalRequest = try #require(runtime.sessionScreen(for: session).approvalRequests.first)
        try runtime.respondToApprovalRequest(approvalRequest.id, decision: .deny)
        let deniedScreen = runtime.sessionScreen(for: session)

        #expect(deniedScreen.activityItems.suffix(3).map(\.text) == [
            "Approval Request: Deploy to production?",
            "Denied: Deploy to production?",
            "Pi: Deployment denied"
        ])
        #expect(deniedScreen.approvalRequests == [
            SessionApprovalRequest(
                id: approvalRequest.id,
                title: approvalRequest.title,
                text: approvalRequest.text,
                state: .denied
            )
        ])
    }
}

private struct PiStreamStubExecutableResolver: ProviderExecutableResolving {
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

private struct PiStreamStubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "PiStreamStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private final class LaunchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class PersistentPiTransportHarness: @unchecked Sendable {
    private struct SessionState {
        let sessionID: String
        let sessionFile: String
        var lastPrompt: String?
    }

    private let lock = NSLock()
    private var nextSessionNumber = 0
    private var sessionsByFile: [String: SessionState] = [:]

    func makeTransport(arguments: [String]) -> any PiRPCTransporting {
        PersistentTestPiRPCTransport(harness: self, arguments: arguments)
    }

    fileprivate func currentSession(for arguments: [String]) -> (sessionID: String, sessionFile: String) {
        lock.lock()
        defer { lock.unlock() }

        if let sessionFile = sessionArgument(in: arguments),
           let state = sessionsByFile[sessionFile] {
            return (state.sessionID, state.sessionFile)
        }

        nextSessionNumber += 1
        let sessionID = "pi-session-\(nextSessionNumber)"
        let sessionFile = "/tmp/\(sessionID).jsonl"
        sessionsByFile[sessionFile] = SessionState(sessionID: sessionID, sessionFile: sessionFile, lastPrompt: nil)
        return (sessionID, sessionFile)
    }

    fileprivate func responseText(for prompt: String, sessionFile: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var state = sessionsByFile[sessionFile] ?? SessionState(
            sessionID: UUID().uuidString,
            sessionFile: sessionFile,
            lastPrompt: nil
        )

        let response: String
        if trimmedPrompt == "what was my last message?" {
            response = state.lastPrompt ?? "(none)"
        } else {
            state.lastPrompt = trimmedPrompt
            response = trimmedPrompt
        }

        sessionsByFile[sessionFile] = state
        return response
    }

    private func sessionArgument(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--session"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

private final class PersistentTestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private let harness: PersistentPiTransportHarness
    private let sessionID: String
    private let sessionFile: String
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(harness: PersistentPiTransportHarness, arguments: [String]) {
        self.harness = harness
        let session = harness.currentSession(for: arguments)
        sessionID = session.sessionID
        sessionFile = session.sessionFile
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
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": [
                    "sessionId": sessionID,
                    "sessionFile": sessionFile
                ]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            let prompt = object["message"] as? String ?? ""
            let responseText = harness.responseText(for: prompt, sessionFile: sessionFile)
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": responseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": responseText
                        ]
                    ]
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

private final class ApprovalRequestTestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
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
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": [
                    "sessionId": "pi-session-1"
                ]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            emit([
                "type": "approval_request",
                "id": "11111111-1111-1111-1111-111111111111",
                "title": "Deploy to production?",
                "text": "Pi wants to run deploy --prod."
            ])
        case "approval_response":
            let decision = object["decision"] as? String ?? "deny"
            let responseText = decision == "approve" ? "Deployment approved" : "Deployment denied"
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": responseText
                        ]
                    ]
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

private final class TestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private let promptResponseText: String
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(promptResponseText: String = "") {
        self.promptResponseText = promptResponseText
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
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": [
                    "sessionId": "pi-session-1"
                ]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            guard promptResponseText.isEmpty == false else {
                return
            }
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": promptResponseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": promptResponseText
                        ]
                    ]
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
