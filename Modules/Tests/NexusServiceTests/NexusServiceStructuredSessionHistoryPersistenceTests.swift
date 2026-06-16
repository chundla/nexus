#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    @Suite(.serialized)
    struct NexusServiceStructuredSessionHistoryPersistenceTests {
        @Test func deletingStructuredSessionRecordRemovesPersistedStructuredHistoryFiles() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = CodexHistoryPersistenceTransportHarness(
                completedAgentMessages: ["Reply 0"]
            )

            func makeService() throws -> NexusService {
                try makeCodexHistoryPersistenceService(
                    rootURL: rootURL,
                    transportHarness: transportHarness
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Codex",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
            _ = try await service.sendSessionInput(sessionID: session.id, text: "first")
            _ = try service.stopSession(sessionID: session.id)

            let historyDirectory =
                rootURL
                .appendingPathComponent("PiStructuredSessionHistory", isDirectory: true)
                .appendingPathComponent(session.id.uuidString, isDirectory: true)

            #expect(FileManager.default.fileExists(atPath: historyDirectory.path))

            let deleted = try service.deleteSessionRecord(sessionID: session.id)

            #expect(deleted)
            #expect(FileManager.default.fileExists(atPath: historyDirectory.path) == false)

            do {
                _ = try service.getStructuredSessionHistoryPage(sessionID: session.id, pageSize: 40, before: nil)
                Issue.record("Expected deleted structured Session history to be unavailable")
            } catch {
            }
        }

        @Test func localCodexPersistsStructuredHistoryOverflowOnDiskAndReopensFromPersistedHistoryPages() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let messageCount = StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + 100
            let transportHarness = CodexHistoryPersistenceTransportHarness(
                completedAgentMessages: (0..<messageCount).map { index in "Reply \(index)" }
            )

            func makeService() throws -> NexusService {
                try makeCodexHistoryPersistenceService(
                    rootURL: rootURL,
                    transportHarness: transportHarness
                )
            }

            let session: Session
            let liveScreen: SessionScreen
            do {
                let service = try makeService()
                let group = try service.createWorkspaceGroup(name: "Solo Group")
                let workspace = try service.createLocalWorkspace(
                    name: "Local Codex",
                    folderPath: workspaceFolder.path(percentEncoded: false),
                    primaryGroupID: group.id
                )
                session = try await service.launchOrResumeDefaultSession(
                    workspaceID: workspace.id, providerID: .codex)
                _ = try await service.sendSessionInput(sessionID: session.id, text: "first")
                liveScreen = try service.getSessionScreen(sessionID: session.id)
            }

            let restartedService = try makeService()
            let interruptedScreen = try restartedService.getSessionScreen(sessionID: session.id)
            let firstPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 40, before: nil)
            let secondPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 40, before: firstPage.nextCursor)
            let finalPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 40, before: secondPage.nextCursor)

            let historyDirectory =
                rootURL
                .appendingPathComponent("PiStructuredSessionHistory", isDirectory: true)
                .appendingPathComponent(session.id.uuidString, isDirectory: true)
            let snapshotData = try Data(
                contentsOf: historyDirectory.appendingPathComponent("current.json", isDirectory: false))
            let persistedState = try JSONDecoder().decode(PiStructuredSessionPersistedState.self, from: snapshotData)

            #expect(liveScreen.activityItems.count == StructuredSessionLiveHistoryRetention.maxRetainedActivityItems)
            #expect(liveScreen.activityItems.first?.text == "Codex: Reply 100")
            #expect(liveScreen.activityItems.last?.text == "Codex: Reply 2099")
            #expect(persistedState.activityItems == liveScreen.activityItems)
            #expect(interruptedScreen.activityItems.dropLast() == liveScreen.activityItems)
            #expect(interruptedScreen.activityItems.last?.kind == .error)
            #expect(firstPage.activityItems.count == 40)
            #expect(firstPage.activityItems.first?.text == "Codex: Reply 60")
            #expect(firstPage.activityItems.last?.text == "Codex: Reply 99")
            #expect(secondPage.activityItems.count == 40)
            #expect(secondPage.activityItems.first?.text == "Codex: Reply 20")
            #expect(secondPage.activityItems.last?.text == "Codex: Reply 59")
            #expect(
                finalPage.activityItems.map(\.text) == [
                    "Codex shared Session stream connected",
                    "You: first",
                    "Codex: Reply 0",
                    "Codex: Reply 1",
                    "Codex: Reply 2",
                    "Codex: Reply 3",
                    "Codex: Reply 4",
                    "Codex: Reply 5",
                    "Codex: Reply 6",
                    "Codex: Reply 7",
                    "Codex: Reply 8",
                    "Codex: Reply 9",
                    "Codex: Reply 10",
                    "Codex: Reply 11",
                    "Codex: Reply 12",
                    "Codex: Reply 13",
                    "Codex: Reply 14",
                    "Codex: Reply 15",
                    "Codex: Reply 16",
                    "Codex: Reply 17",
                    "Codex: Reply 18",
                    "Codex: Reply 19",
                ])
            #expect(finalPage.nextCursor?.activityItemOffset == 0)
            #expect(finalPage.nextCursor?.providerEventOffset != nil)
        }

        @Test func localIBMBobPersistsStructuredHistoryOverflowOnDiskWhileKeepingSessionRecordLinkageSeparate() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let messageCount = StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + 100
            let transportHarness = IBMBobHistoryPersistenceTransportHarness(
                stdoutLines: [
                    #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#
                ]
                    + (0..<messageCount).map { index in
                        #"{"type":"message","text":"Reply \#(index)"}"#
                    }
                    + [#"{"type":"completion","text":"Turn complete"}"#]
            )

            func makeService() throws -> NexusService {
                try makeIBMBobHistoryPersistenceService(
                    rootURL: rootURL,
                    transportHarness: transportHarness
                )
            }

            let session: Session
            let liveScreen: SessionScreen
            let metadata: SessionRecordAdapterMetadata?
            do {
                let service = try makeService()
                let group = try service.createWorkspaceGroup(name: "Solo Group")
                let workspace = try service.createLocalWorkspace(
                    name: "Local Bob",
                    folderPath: workspaceFolder.path(percentEncoded: false),
                    primaryGroupID: group.id
                )
                session = try await service.launchOrResumeDefaultSession(
                    workspaceID: workspace.id, providerID: .ibmBob)
                _ = try await service.sendSessionInput(sessionID: session.id, text: "first")
                liveScreen = try service.getSessionScreen(sessionID: session.id)
                let metadataStore = try NexusMetadataStore(storeURL: service.storeURL)
                metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)
            }

            let restartedService = try makeService()
            let reopenedSession = try restartedService.getSessionRecord(sessionID: session.id)
            let reopenedScreen = try restartedService.getSessionScreen(sessionID: session.id)
            let firstPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 40, before: nil)
            let secondPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 40, before: firstPage.nextCursor)
            let finalPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 40, before: secondPage.nextCursor)

            let historyDirectory =
                rootURL
                .appendingPathComponent("PiStructuredSessionHistory", isDirectory: true)
                .appendingPathComponent(session.id.uuidString, isDirectory: true)
            let snapshotData = try Data(
                contentsOf: historyDirectory.appendingPathComponent("current.json", isDirectory: false))
            let persistedState = try JSONDecoder().decode(PiStructuredSessionPersistedState.self, from: snapshotData)

            #expect(metadata?.providerID == .ibmBob)
            #expect(metadata?.ibmBobSessionLinkage?.sessionID == "bob-session-1")
            #expect(metadata?.ibmBobPersistedActivityItems?.isEmpty == false)
            #expect(liveScreen.activityItems.count == StructuredSessionLiveHistoryRetention.maxRetainedActivityItems)
            #expect(liveScreen.activityItems.first?.text == "Reply 101")
            #expect(liveScreen.activityItems.last?.text == "Turn complete")
            #expect(persistedState.activityItems == liveScreen.activityItems)
            #expect(reopenedSession.state == .ready)
            #expect(reopenedScreen.activityItems == liveScreen.activityItems)
            #expect(firstPage.activityItems.count == 40)
            #expect(firstPage.activityItems.first?.text == "Reply 61")
            #expect(firstPage.activityItems.last?.text == "Reply 100")
            #expect(secondPage.activityItems.count == 40)
            #expect(secondPage.activityItems.first?.text == "Reply 21")
            #expect(secondPage.activityItems.last?.text == "Reply 60")
            #expect(
                finalPage.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: first",
                    "Bob turn started",
                    "Reply 0",
                    "Reply 1",
                    "Reply 2",
                    "Reply 3",
                    "Reply 4",
                    "Reply 5",
                    "Reply 6",
                    "Reply 7",
                    "Reply 8",
                    "Reply 9",
                    "Reply 10",
                    "Reply 11",
                    "Reply 12",
                    "Reply 13",
                    "Reply 14",
                    "Reply 15",
                    "Reply 16",
                    "Reply 17",
                    "Reply 18",
                    "Reply 19",
                    "Reply 20",
                ])
            #expect(finalPage.nextCursor == nil)
        }

        @Test func localPiPersistsStructuredHistoryDuringInFlightTurnWhilePreservingOverflowRecovery() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let runtime = DeferredPiHistoryPersistenceRuntime()

            func makeService(withRuntime: Bool) throws -> NexusService {
                try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: DeferredPiHistoryPersistenceProviderHealthFacts(),
                    sessionRuntimeManager: withRuntime
                        ? InMemorySessionRuntimeManager(
                            launcher: DeferredPiHistoryPersistenceRuntimeLauncher(runtime: runtime))
                        : nil
                )
            }

            let service = try makeService(withRuntime: true)
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

            let stateURL =
                rootURL
                .appendingPathComponent("PiStructuredSessionHistory", isDirectory: true)
                .appendingPathComponent(session.id.uuidString, isDirectory: true)
                .appendingPathComponent("current.json", isDirectory: false)
            let initialState = try persistedStructuredState(at: stateURL)

            #expect(initialState.activityItems.map(\.text) == ["Pi ready"])

            let activeScreen = try await service.sendSessionInput(sessionID: session.id, text: "deploy")

            #expect(activeScreen.isAgentTurnInProgress)
            let activeTurnState = try persistedStructuredState(at: stateURL)
            #expect(activeTurnState.activityItems.map(\.text).contains("You: deploy"))

            let streamedReplyCount = StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + 5
            for index in 0..<streamedReplyCount {
                runtime.recordAssistantReply("Reply \(index)")
            }

            let midTurnState = try persistedStructuredState(at: stateURL)
            #expect(midTurnState.activityItems.count == StructuredSessionLiveHistoryRetention.maxRetainedActivityItems)
            #expect(midTurnState.activityItems.last?.text == "Pi: Reply \(streamedReplyCount - 1)")

            runtime.finishTurn(with: "Done")

            let liveScreen = try service.getSessionScreen(sessionID: session.id)
            let completedState = try persistedStructuredState(at: stateURL)
            do {
                _ = service
            }
            let restartedService = try makeService(withRuntime: false)
            let reopenedScreen = try restartedService.getSessionScreen(sessionID: session.id)
            let overflowPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id, pageSize: 20, before: nil)

            #expect(liveScreen.isAgentTurnInProgress == false)
            #expect(liveScreen.activityItems.count == StructuredSessionLiveHistoryRetention.maxRetainedActivityItems)
            #expect(liveScreen.activityItems.first?.text == "Pi: Reply 6")
            #expect(liveScreen.activityItems.last?.text == "Pi: Done")
            #expect(completedState.activityItems == liveScreen.activityItems)
            #expect(reopenedScreen.activityItems.dropLast() == liveScreen.activityItems)
            #expect(reopenedScreen.activityItems.last?.kind == .error)
            #expect(
                overflowPage.activityItems.map(\.text) == [
                    "Pi ready",
                    "You: deploy",
                    "Pi: Reply 0",
                    "Pi: Reply 1",
                    "Pi: Reply 2",
                    "Pi: Reply 3",
                    "Pi: Reply 4",
                    "Pi: Reply 5",
                ])
            #expect(overflowPage.nextCursor == nil)
        }
    }

    private func makeCodexHistoryPersistenceService(
        rootURL: URL,
        transportHarness: CodexHistoryPersistenceTransportHarness
    ) throws -> NexusService {
        let launcher = ProcessSessionRuntimeLauncher(
            localShellEnvironmentResolver: StructuredHistoryPersistenceStubShellEnvironmentResolver(),
            codexTransportFactory: { _, _, _ in transportHarness.makeTransport() }
        )

        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: CodexHistoryPersistenceExecutableResolver(executables: [
                    "codex": "/tmp/fake-codex",
                ]),
                commandRunner: CodexHistoryPersistenceCommandRunner(results: [
                    .init(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-codex' '--version'"]): .success(
                        stdout: "1.2.3\n"),
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                codexReadinessProbe: CodexHistoryPersistenceReadinessProbe()
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
    }

    private func makeIBMBobHistoryPersistenceService(
        rootURL: URL,
        transportHarness: IBMBobHistoryPersistenceTransportHarness
    ) throws -> NexusService {
        let launcher = ProcessSessionRuntimeLauncher(
            localShellEnvironmentResolver: StructuredHistoryPersistenceStubShellEnvironmentResolver(),
            ibmBobTransportFactory: { executable, arguments, workingDirectory in
                try transportHarness.makeTransport(
                    executable: executable, arguments: arguments, workingDirectory: workingDirectory)
            }
        )
        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: IBMBobHistoryPersistenceExecutableResolver(executables: [
                    "bob": "/tmp/fake-bob",
                ]),
                commandRunner: IBMBobHistoryPersistenceCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(
                        stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]):
                        .success(stdout: "[]\n"),
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
    }

    private struct StructuredHistoryPersistenceStubShellEnvironmentResolver: LocalShellEnvironmentResolving {
        func resolvedEnvironment() -> [String: String]? {
            ["SHELL": "/bin/zsh", "PATH": "/tmp/bin"]
        }
    }

    private func persistedStructuredState(at url: URL) throws -> PiStructuredSessionPersistedState {
        try JSONDecoder().decode(PiStructuredSessionPersistedState.self, from: Data(contentsOf: url))
    }

    private struct DeferredPiHistoryPersistenceProviderHealthFacts: ProviderHealthEvaluating {
        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            _ = workspace
            _ = remoteContext
            if providerID == .pi {
                return ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: "/tmp/fake-pi",
                    launchability: .launchable
                )
            }
            return ProviderHealthSummary(state: .notChecked, summary: "Health checks coming soon")
        }
    }

    private final class DeferredPiHistoryPersistenceRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
        private let runtime: DeferredPiHistoryPersistenceRuntime

        init(runtime: DeferredPiHistoryPersistenceRuntime) {
            self.runtime = runtime
        }

        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            _ = session
            _ = workspace
            _ = launchConfiguration
            return runtime
        }
    }

    private final class DeferredPiHistoryPersistenceRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State { .ready }
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        private let lock = NSLock()
        private var changeHandler: (@Sendable () -> Void)?
        private var transcriptEntries = ["Pi ready"]
        private var activityItems = [SessionActivityItem(kind: .status, text: "Pi ready")]
        private var persistedActivityItemOverflow: [SessionActivityItem] = []
        private var isTurnInProgress = false

        func consumeStructuredHistoryOverflow() -> StructuredSessionPersistedHistoryOverflow {
            lock.lock()
            defer { lock.unlock() }
            let overflow = StructuredSessionPersistedHistoryOverflow(
                activityItems: persistedActivityItemOverflow,
                providerEvents: []
            )
            persistedActivityItemOverflow.removeAll(keepingCapacity: true)
            return overflow
        }

        func sessionScreen(for session: Session) -> SessionScreen {
            lock.lock()
            let transcript = transcriptEntries.joined(separator: "\n")
            let activityItems = self.activityItems
            let isTurnInProgress = self.isTurnInProgress
            lock.unlock()

            return SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: transcript,
                activityItems: activityItems,
                isAgentTurnInProgress: isTurnInProgress
            )
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
            lock.lock()
            changeHandler = handler
            lock.unlock()
        }

        func stop() throws {}

        func sendInput(_ text: String) throws {
            lock.lock()
            transcriptEntries.append("> \(text)")
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "You: \(text)"))
            isTurnInProgress = true
            let changeHandler = self.changeHandler
            lock.unlock()
            changeHandler?()
        }

        func sendText(_ text: String) throws { _ = text }
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {
            _ = key
            _ = applicationCursorMode
        }
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {
            _ = approvalRequestID
            _ = decision
        }
        func resize(columns: Int, rows: Int) throws {
            _ = columns
            _ = rows
        }

        func recordAssistantReply(_ text: String) {
            lock.lock()
            transcriptEntries.append("Pi: \(text)")
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(text)"))
            let changeHandler = self.changeHandler
            lock.unlock()
            changeHandler?()
        }

        func finishTurn(with text: String) {
            lock.lock()
            transcriptEntries.append("Pi: \(text)")
            appendActivityItemLocked(SessionActivityItem(kind: .message, text: "Pi: \(text)"))
            isTurnInProgress = false
            let changeHandler = self.changeHandler
            lock.unlock()
            changeHandler?()
        }

        private func appendActivityItemLocked(_ item: SessionActivityItem) {
            activityItems.append(item)
            if activityItems.count > StructuredSessionLiveHistoryRetention.maxRetainedActivityItems {
                let removedCount = activityItems.count - StructuredSessionLiveHistoryRetention.maxRetainedActivityItems
                persistedActivityItemOverflow.append(contentsOf: activityItems.prefix(removedCount))
                activityItems.removeFirst(removedCount)
            }
        }
    }

    private struct CodexHistoryPersistenceExecutableResolver: ProviderExecutableResolving {
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

    private struct CodexHistoryPersistenceCommandRunner: ProviderCommandRunning {
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
                    domain: "CodexHistoryPersistenceCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private struct CodexHistoryPersistenceReadinessProbe: CodexReadinessProbing {
        func probe(executable: String, workingDirectory: String) async throws {}
    }

    private final class CodexHistoryPersistenceTransportHarness: @unchecked Sendable {
        private let completedAgentMessages: [String]

        init(completedAgentMessages: [String]) {
            self.completedAgentMessages = completedAgentMessages
        }

        func makeTransport() -> any CodexAppServerTransporting {
            CodexHistoryPersistenceTransport(completedAgentMessages: completedAgentMessages)
        }
    }

    private final class CodexHistoryPersistenceTransport: CodexAppServerTransporting, @unchecked Sendable {
        private let completedAgentMessages: [String]
        private let threadID = "codex-thread-1"
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (CodexAppServerTermination) -> Void)?

        init(completedAgentMessages: [String]) {
            self.completedAgentMessages = completedAgentMessages
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
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                Issue.record("Invalid JSON line: \(line)")
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
                        "platformOs": "macos",
                    ],
                ])
            case "thread/start", "thread/resume":
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
                            "path": "/tmp/codex-thread.jsonl",
                            "cwd": "/tmp/workspace",
                            "cliVersion": "0.132.0",
                            "source": "appServer",
                            "turns": [],
                        ],
                        "model": "gpt-5.5",
                        "modelProvider": "openai",
                        "cwd": "/tmp/workspace",
                        "approvalPolicy": "on-request",
                        "approvalsReviewer": "user",
                        "sandbox": ["type": "readOnly", "networkAccess": false],
                    ],
                ])
            case "turn/start":
                emit([
                    "id": object["id"] ?? 0,
                    "result": [
                        "turn": [
                            "id": "turn-1",
                            "items": [],
                            "itemsView": "notLoaded",
                            "status": "inProgress",
                        ]
                    ],
                ])
                for (index, message) in completedAgentMessages.enumerated() {
                    emit([
                        "jsonrpc": "2.0",
                        "method": "item/completed",
                        "params": [
                            "item": [
                                "type": "agentMessage",
                                "id": "agent-message-\(index)",
                                "text": message,
                                "phase": "final_answer",
                            ],
                            "threadId": threadID,
                            "turnId": "turn-1",
                            "completedAtMs": index + 1,
                        ],
                    ])
                }
            case "model/list":
                emit([
                    "id": object["id"] ?? 0,
                    "result": ["data": []],
                ])
            default:
                break
            }
        }

        func terminate() throws {
            terminationHandler?(CodexAppServerTermination(status: 0, stderr: nil))
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    private struct IBMBobHistoryPersistenceExecutableResolver: ProviderExecutableResolving {
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

    private struct IBMBobHistoryPersistenceCommandRunner: ProviderCommandRunning {
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
                    domain: "IBMBobHistoryPersistenceCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class IBMBobHistoryPersistenceTransportHarness: @unchecked Sendable {
        private let stdoutLines: [String]

        init(stdoutLines: [String]) {
            self.stdoutLines = stdoutLines
        }

        func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws
            -> any IBMBobTransporting
        {
            _ = executable
            _ = arguments
            _ = workingDirectory
            return IBMBobHistoryPersistenceTransport(stdoutLines: stdoutLines)
        }
    }

    private final class IBMBobHistoryPersistenceTransport: IBMBobTransporting, @unchecked Sendable {
        private let stdoutLines: [String]
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(stdoutLines: [String]) {
            self.stdoutLines = stdoutLines
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stderrLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {
            _ = stderrLineHandler
            for line in stdoutLines {
                stdoutLineHandler?(line)
            }
            terminationHandler?(0)
        }

        func terminate() throws {
            terminationHandler?(0)
        }
    }
#endif
