#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServicePiSessionGraphTests {
    @Test func piNewSessionCreatesNamedSessionRecordAndMovesRemoteController() async throws {
        let fixture = try PiSessionGraphFixture()
        let pairedDeviceID = UUID()

        let defaultSession = try await fixture.service.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let initialMetadata = try fixture.metadataStore.sessionRecordAdapterMetadata(sessionID: defaultSession.id)
        let detachedSession = fixture.harness.makeDetachedSession()
        fixture.harness.setPromptTransition(
            prompt: "branch",
            eventType: "new_session",
            targetSessionID: detachedSession.sessionID,
            targetSessionFile: detachedSession.sessionFile,
            responseText: "Branch ready"
        )

        _ = try await fixture.service.takeRemoteSessionControl(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            columns: 90,
            rows: 28
        )

        _ = try await fixture.service.sendRemoteSessionInput(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "branch"
        )

        let detail = try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)
        let namedSession = try #require(detail.alternateSessions.only)
        let namedMetadata = try fixture.metadataStore.sessionRecordAdapterMetadata(sessionID: namedSession.id)
        let namedScreen = try fixture.service.getSessionScreen(sessionID: namedSession.id)
        let defaultScreen = try fixture.service.getSessionScreen(sessionID: defaultSession.id)

        #expect(detail.defaultSession?.id == defaultSession.id)
        #expect(namedSession.isDefault == false)
        #expect(namedMetadata?.piSessionLinkage?.piSessionID == detachedSession.sessionID)
        #expect(namedMetadata?.piSessionLinkage?.sessionFile == detachedSession.sessionFile)
        #expect(initialMetadata?.piSessionLinkage?.piSessionID == "pi-session-1")
        #expect(namedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(defaultScreen.controller == .mac)

        let followedScreen = try await fixture.service.sendRemoteSessionInput(
            sessionID: namedSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "after branch"
        )
        #expect(followedScreen.session.id == namedSession.id)
        #expect(followedScreen.activityItems.suffix(2).map(\.text) == [
            "You: after branch",
            "Pi: after branch"
        ])
    }

    @Test func piSwitchSessionReusesKnownSessionRecordAndReturnsFollowedScreen() async throws {
        let fixture = try PiSessionGraphFixture()

        let defaultSession = try await fixture.service.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let reviewSession = try await fixture.service.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi,
            name: "Review"
        )
        let reviewLinkage = try #require(
            fixture.metadataStore.sessionRecordAdapterMetadata(sessionID: reviewSession.id)?.piSessionLinkage
        )

        fixture.harness.setPromptTransition(
            prompt: "switch-review",
            eventType: "switch_session",
            targetSessionID: try #require(reviewLinkage.piSessionID),
            targetSessionFile: try #require(reviewLinkage.sessionFile),
            responseText: "Review ready"
        )
        let switchedScreen = try await fixture.service.sendSessionInput(
            sessionID: defaultSession.id,
            text: "switch-review"
        )
        let detail = try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)
        let reviewScreen = try fixture.service.getSessionScreen(sessionID: reviewSession.id)

        #expect(switchedScreen.session.id == reviewSession.id)
        #expect(detail.defaultSession?.id == defaultSession.id)
        #expect(detail.alternateSessions.map(\.id) == [reviewSession.id])
        #expect(reviewScreen.activityItems.suffix(2).map(\.text) == [
            "You: switch-review",
            "Pi: Review ready"
        ])
    }

    @Test func piSwitchSessionCreatesNamedSessionRecordWhenTargetIsUnknown() async throws {
        let fixture = try PiSessionGraphFixture()

        let defaultSession = try await fixture.service.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let detachedSession = fixture.harness.makeDetachedSession()
        fixture.harness.setPromptTransition(
            prompt: "switch-unknown",
            eventType: "switch_session",
            targetSessionID: detachedSession.sessionID,
            targetSessionFile: detachedSession.sessionFile,
            responseText: "Unknown ready"
        )

        let switchedScreen = try await fixture.service.sendSessionInput(
            sessionID: defaultSession.id,
            text: "switch-unknown"
        )
        let detail = try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)
        let namedSession = try #require(detail.alternateSessions.only)
        let namedMetadata = try fixture.metadataStore.sessionRecordAdapterMetadata(sessionID: namedSession.id)

        #expect(switchedScreen.session.id == namedSession.id)
        #expect(detail.defaultSession?.id == defaultSession.id)
        #expect(namedSession.isDefault == false)
        #expect(namedMetadata?.piSessionLinkage?.piSessionID == detachedSession.sessionID)
        #expect(namedMetadata?.piSessionLinkage?.sessionFile == detachedSession.sessionFile)
    }

    @Test func piSetSessionNameKeepsNamedSessionRecordInSync() async throws {
        let fixture = try PiSessionGraphFixture()

        let namedSession = try await fixture.service.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi,
            name: "Review"
        )
        _ = try await fixture.service.launchOrResumeSession(sessionID: namedSession.id)

        let renamedScreen = try await fixture.service.sendSessionInput(
            sessionID: namedSession.id,
            text: "/session-name Branch Review"
        )
        let detail = try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)
        let persistedScreen = try fixture.service.getSessionScreen(sessionID: namedSession.id)
        let renamedSession = try #require(detail.alternateSessions.only)

        #expect(renamedScreen.session.name == "Branch Review")
        #expect(renamedSession.name == "Branch Review")
        #expect(persistedScreen.session.name == "Branch Review")
    }

    @Test func piForkCreatesNamedSessionRecordAndMovesRemoteController() async throws {
        let fixture = try PiSessionGraphFixture()
        let pairedDeviceID = UUID()

        let defaultSession = try await fixture.service.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let forkedPiSession = fixture.harness.makeDetachedSession()
        fixture.harness.setForkTransition(
            entryID: "entry-1",
            targetSessionID: forkedPiSession.sessionID,
            targetSessionFile: forkedPiSession.sessionFile,
            selectedText: "Original prompt"
        )

        _ = try await fixture.service.takeRemoteSessionControl(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            columns: 90,
            rows: 28
        )

        let forkedScreen = try await fixture.service.sendRemoteSessionInput(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "/fork entry-1"
        )
        let detail = try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)
        let namedSession = try #require(detail.alternateSessions.only)
        let namedMetadata = try fixture.metadataStore.sessionRecordAdapterMetadata(sessionID: namedSession.id)
        let namedScreen = try fixture.service.getSessionScreen(sessionID: namedSession.id)
        let defaultScreen = try fixture.service.getSessionScreen(sessionID: defaultSession.id)

        #expect(forkedScreen.session.id == namedSession.id)
        #expect(namedMetadata?.piSessionLinkage?.piSessionID == forkedPiSession.sessionID)
        #expect(namedMetadata?.piSessionLinkage?.sessionFile == forkedPiSession.sessionFile)
        #expect(namedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(defaultScreen.controller == .mac)

        let followedScreen = try await fixture.service.sendRemoteSessionInput(
            sessionID: namedSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "after fork"
        )
        #expect(followedScreen.activityItems.suffix(2).map(\.text) == [
            "You: after fork",
            "Pi: after fork"
        ])
    }

    @Test func piCloneCreatesNamedSessionRecordAndMovesRemoteController() async throws {
        let fixture = try PiSessionGraphFixture()
        let pairedDeviceID = UUID()

        let defaultSession = try await fixture.service.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let clonedPiSession = fixture.harness.makeDetachedSession()
        fixture.harness.setCloneTransition(
            targetSessionID: clonedPiSession.sessionID,
            targetSessionFile: clonedPiSession.sessionFile
        )

        _ = try await fixture.service.takeRemoteSessionControl(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            columns: 90,
            rows: 28
        )

        let clonedScreen = try await fixture.service.sendRemoteSessionInput(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "/clone"
        )
        let detail = try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)
        let namedSession = try #require(detail.alternateSessions.only)
        let namedMetadata = try fixture.metadataStore.sessionRecordAdapterMetadata(sessionID: namedSession.id)
        let namedScreen = try fixture.service.getSessionScreen(sessionID: namedSession.id)
        let defaultScreen = try fixture.service.getSessionScreen(sessionID: defaultSession.id)

        #expect(clonedScreen.session.id == namedSession.id)
        #expect(namedMetadata?.piSessionLinkage?.piSessionID == clonedPiSession.sessionID)
        #expect(namedMetadata?.piSessionLinkage?.sessionFile == clonedPiSession.sessionFile)
        #expect(namedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(defaultScreen.controller == .mac)
    }

    @Test func piSessionTransitionLeavesExistingObserversOnTheirCurrentSession() async throws {
        let fixture = try PiSessionGraphFixture()
        let pairedDeviceID = UUID()
        let sink = PiObservedScreenSink()

        let defaultSession = try await fixture.service.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .pi
        )
        let observation = try fixture.service.observeSessionScreen(observationID: UUID(), sessionID: defaultSession.id) { screen in
            Task {
                await sink.record(screen)
            }
        }
        let detachedSession = fixture.harness.makeDetachedSession()
        fixture.harness.setPromptTransition(
            prompt: "branch-observed",
            eventType: "new_session",
            targetSessionID: detachedSession.sessionID,
            targetSessionFile: detachedSession.sessionFile,
            responseText: "Observed branch ready"
        )
        _ = try await fixture.service.takeRemoteSessionControl(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            columns: 90,
            rows: 28
        )
        _ = try await fixture.service.sendRemoteSessionInput(
            sessionID: defaultSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "branch-observed"
        )
        while await sink.nextScreen(timeoutNanoseconds: 20_000_000) != nil {}

        let namedSession = try #require(
            (try await fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .pi)).alternateSessions.only
        )
        _ = try await fixture.service.sendRemoteSessionInput(
            sessionID: namedSession.id,
            pairedDeviceID: pairedDeviceID,
            text: "after observer split"
        )

        #expect(observation.screen.session.id == defaultSession.id)
        #expect(await sink.nextScreen(timeoutNanoseconds: 100_000_000) == nil)
    }
}

private actor PiObservedScreenSink {
    private var screens: [SessionScreen] = []

    func record(_ screen: SessionScreen) {
        screens.append(screen)
    }

    func nextScreen(timeoutNanoseconds: UInt64) async -> SessionScreen? {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let screen = screens.first {
                screens.removeFirst()
                return screen
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }
}

private final class PiSessionGraphFixture {
    let rootURL: URL
    let service: NexusService
    let workspace: Workspace
    let metadataStore: NexusMetadataStore
    let harness = PiSessionGraphHarness()

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { [harness] _, arguments, _ in
            harness.makeTransport(arguments: arguments)
        })

        service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: PiGraphStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: PiGraphStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        metadataStore = try NexusMetadataStore(storeURL: service.storeURL)
    }
}

private final class PiSessionGraphHarness: @unchecked Sendable {
    struct SessionState {
        let sessionID: String
        let sessionFile: String
        var sessionName: String?
    }

    private struct PromptTransition {
        let eventType: String
        let targetSessionID: String
        let targetSessionFile: String
        let responseText: String
    }

    private struct ForkTransition {
        let targetSessionID: String
        let targetSessionFile: String
        let selectedText: String
    }

    private let lock = NSLock()
    private var nextSessionNumber = 0
    private var sessionsByFile: [String: SessionState] = [:]
    private var promptTransitions: [String: PromptTransition] = [:]
    private var forkTransitions: [String: ForkTransition] = [:]
    private var cloneTransition: SessionState?

    func makeTransport(arguments: [String]) -> any PiRPCTransporting {
        PiSessionGraphTransport(harness: self, arguments: arguments)
    }

    func makeDetachedSession() -> (sessionID: String, sessionFile: String) {
        lock.lock()
        defer { lock.unlock() }
        nextSessionNumber += 1
        let session = SessionState(
            sessionID: "pi-session-detached-\(nextSessionNumber)",
            sessionFile: "/tmp/pi-session-detached-\(nextSessionNumber).jsonl",
            sessionName: nil
        )
        sessionsByFile[session.sessionFile] = session
        return (session.sessionID, session.sessionFile)
    }

    func setPromptTransition(
        prompt: String,
        eventType: String,
        targetSessionID: String,
        targetSessionFile: String,
        responseText: String
    ) {
        lock.lock()
        promptTransitions[prompt] = PromptTransition(
            eventType: eventType,
            targetSessionID: targetSessionID,
            targetSessionFile: targetSessionFile,
            responseText: responseText
        )
        sessionsByFile[targetSessionFile] = SessionState(sessionID: targetSessionID, sessionFile: targetSessionFile)
        lock.unlock()
    }

    func initialSession(for arguments: [String]) -> SessionState {
        lock.lock()
        defer { lock.unlock() }

        if let sessionFile = sessionArgument(in: arguments),
           let existing = sessionsByFile[sessionFile] {
            return existing
        }

        nextSessionNumber += 1
        let session = SessionState(
            sessionID: "pi-session-\(nextSessionNumber)",
            sessionFile: "/tmp/pi-session-\(nextSessionNumber).jsonl",
            sessionName: nil
        )
        sessionsByFile[session.sessionFile] = session
        return session
    }

    func promptTransition(for prompt: String) -> (eventType: String, session: SessionState, responseText: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let transition = promptTransitions[prompt],
              let session = sessionsByFile[transition.targetSessionFile] else {
            return nil
        }
        return (transition.eventType, session, transition.responseText)
    }

    func renameCurrentSession(sessionFile: String, name: String) -> SessionState? {
        lock.lock()
        defer { lock.unlock() }
        guard var session = sessionsByFile[sessionFile] else {
            return nil
        }
        session.sessionName = name
        sessionsByFile[sessionFile] = session
        return session
    }

    func setForkTransition(entryID: String, targetSessionID: String, targetSessionFile: String, selectedText: String) {
        lock.lock()
        forkTransitions[entryID] = ForkTransition(
            targetSessionID: targetSessionID,
            targetSessionFile: targetSessionFile,
            selectedText: selectedText
        )
        sessionsByFile[targetSessionFile] = SessionState(
            sessionID: targetSessionID,
            sessionFile: targetSessionFile,
            sessionName: nil
        )
        lock.unlock()
    }

    func forkTransition(for entryID: String) -> (session: SessionState, selectedText: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let transition = forkTransitions[entryID],
              let session = sessionsByFile[transition.targetSessionFile] else {
            return nil
        }
        return (session, transition.selectedText)
    }

    func setCloneTransition(targetSessionID: String, targetSessionFile: String) {
        lock.lock()
        let session = SessionState(
            sessionID: targetSessionID,
            sessionFile: targetSessionFile,
            sessionName: nil
        )
        cloneTransition = session
        sessionsByFile[targetSessionFile] = session
        lock.unlock()
    }

    func cloneTransitionState() -> SessionState? {
        lock.lock()
        defer { lock.unlock() }
        return cloneTransition
    }

    private func sessionArgument(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--session"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

private final class PiSessionGraphTransport: PiRPCTransporting, @unchecked Sendable {
    private let harness: PiSessionGraphHarness
    private var currentSession: PiSessionGraphHarness.SessionState
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(harness: PiSessionGraphHarness, arguments: [String]) {
        self.harness = harness
        currentSession = harness.initialSession(for: arguments)
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
                "data": {
                    var data: [String: Any] = [
                        "sessionId": currentSession.sessionID,
                        "sessionFile": currentSession.sessionFile
                    ]
                    if let sessionName = currentSession.sessionName {
                        data["sessionName"] = sessionName
                    }
                    return data
                }()
            ])
        case "set_session_name":
            let sessionName = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard sessionName.isEmpty == false,
                  let renamedSession = harness.renameCurrentSession(sessionFile: currentSession.sessionFile, name: sessionName) else {
                emit([
                    "id": object["id"] as? String ?? "set-session-name",
                    "type": "response",
                    "command": "set_session_name",
                    "success": false,
                    "error": "Session name cannot be empty"
                ])
                return
            }
            currentSession = renamedSession
            emit([
                "id": object["id"] as? String ?? "set-session-name",
                "type": "response",
                "command": "set_session_name",
                "success": true
            ])
        case "fork":
            let entryID = object["entryId"] as? String ?? ""
            guard let transition = harness.forkTransition(for: entryID) else {
                return
            }
            currentSession = transition.session
            emit([
                "id": object["id"] as? String ?? "fork",
                "type": "response",
                "command": "fork",
                "success": true,
                "data": [
                    "text": transition.selectedText,
                    "cancelled": false
                ]
            ])
        case "clone":
            guard let transition = harness.cloneTransitionState() else {
                return
            }
            currentSession = transition
            emit([
                "id": object["id"] as? String ?? "clone",
                "type": "response",
                "command": "clone",
                "success": true,
                "data": [
                    "cancelled": false
                ]
            ])
        case "prompt":
            let prompt = object["message"] as? String ?? ""
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])

            if let transition = harness.promptTransition(for: prompt) {
                currentSession = transition.session
                emit([
                    "type": transition.eventType,
                    "sessionId": transition.session.sessionID,
                    "sessionFile": transition.session.sessionFile
                ])
                emitTurnEnd(text: transition.responseText)
                return
            }

            emitTurnEnd(text: prompt)
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    private func emitTurnEnd(text: String) {
        emit([
            "type": "turn_end",
            "message": [
                "content": [[
                    "type": "text",
                    "text": text
                ]]
            ]
        ])
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}

private struct PiGraphStubExecutableResolver: ProviderExecutableResolving {
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

private struct PiGraphStubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "PiGraphStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
#endif
