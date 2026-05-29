#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ServiceSessionInteractionScenariosTests {
    @Test func observingSessionScreenYieldsCurrentScreenBeforeLaterUpdates() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = ObservationRuntimeLauncher()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: StubProviderHealthEvaluator(
                summariesByProvider: [
                    .claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: "/tmp/claude",
                        launchability: .launchable
                    )
                ]
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let sink = SessionScreenSink()

        let start = try service.observeSessionScreen(observationID: UUID(), sessionID: session.id) { screen in
            Task {
                await sink.record(screen)
            }
        }

        #expect(start.screen.transcript == "Ready")
        launcher.runtime.appendOutput("\nUpdated")
        let updatedScreen = try #require(await sink.nextScreen())

        #expect(updatedScreen.transcript.contains("Updated"))
        service.cancelSessionScreenObservation(observationID: start.observationID)
    }

    @Test func remoteControllerGatesStructuredSessionInputAndApprovalDecisions() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = StructuredControllerRuntimeLauncher()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: StubProviderHealthEvaluator(
                summariesByProvider: [
                    .pi: ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: "/tmp/pi",
                        launchability: .launchable
                    )
                ]
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let pairedDeviceID = UUID()

        do {
            _ = try await service.sendRemoteSessionInput(sessionID: session.id, pairedDeviceID: pairedDeviceID, text: "deploy")
            Issue.record("Expected controller-gated structured input to fail")
        } catch let error as NexusSessionControlError {
            guard case .remoteSessionInputControllerRequired = error else {
                Issue.record("Unexpected controller error: \(error.localizedDescription)")
                return
            }
        }

        _ = try await service.takeRemoteSessionControl(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            columns: 44,
            rows: 12
        )
        let pendingScreen = try await service.sendRemoteSessionInput(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            text: "deploy"
        )
        let approvalRequest = try #require(pendingScreen.approvalRequests.first)

        #expect(pendingScreen.primarySurface == .structuredActivityFeed)
        #expect(pendingScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(pendingScreen.activityItems.map(\.text) == [
            "Pi ready",
            "You: deploy",
            "Approval Request: Deploy?"
        ])

        _ = try service.releaseRemoteSessionControl(sessionID: session.id, pairedDeviceID: pairedDeviceID)
        do {
            _ = try await service.respondToRemoteApprovalRequest(
                sessionID: session.id,
                pairedDeviceID: pairedDeviceID,
                approvalRequestID: approvalRequest.id,
                decision: .approve
            )
            Issue.record("Expected controller-gated approval decision to fail")
        } catch let error as NexusSessionControlError {
            guard case .remoteApprovalRequestControllerRequired = error else {
                Issue.record("Unexpected controller error: \(error.localizedDescription)")
                return
            }
        }

        _ = try await service.takeRemoteSessionControl(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            columns: 44,
            rows: 12
        )
        let approvedScreen = try await service.respondToRemoteApprovalRequest(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            approvalRequestID: approvalRequest.id,
            decision: .approve
        )

        #expect(approvedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(approvedScreen.approvalRequests.first?.state == .approved)
        #expect(approvedScreen.activityItems.suffix(2).map(\.text) == [
            "Approved: Deploy?",
            "Pi: Deployment approved"
        ])
    }

    @Test func remoteControllerGatesTerminalTextAndInputKey() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let launcher = TerminalControllerRuntimeLauncher()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: StubProviderHealthEvaluator(
                summariesByProvider: [
                    .claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: "/tmp/claude",
                        launchability: .launchable
                    )
                ]
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let pairedDeviceID = UUID()

        do {
            _ = try await service.sendRemoteSessionText(sessionID: session.id, pairedDeviceID: pairedDeviceID, text: "ls")
            Issue.record("Expected controller-gated terminal text to fail")
        } catch let error as NexusSessionControlError {
            guard case .remoteControllerRequired = error else {
                Issue.record("Unexpected controller error: \(error.localizedDescription)")
                return
            }
        }

        _ = try await service.takeRemoteSessionControl(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            columns: 44,
            rows: 12
        )
        let typedScreen = try await service.sendRemoteSessionText(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            text: "ls"
        )
        let executedScreen = try await service.sendRemoteSessionInputKey(
            sessionID: session.id,
            pairedDeviceID: pairedDeviceID,
            key: .enter
        )

        #expect(typedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(typedScreen.transcript == "prompt> ls")
        #expect(executedScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(executedScreen.transcript.contains("prompt> ls\nran"))
    }
}

private actor SessionScreenSink {
    private var screens: [SessionScreen] = []

    func record(_ screen: SessionScreen) {
        screens.append(screen)
    }

    func nextScreen(timeoutNanoseconds: UInt64 = 1_000_000_000) async -> SessionScreen? {
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

private final class ObservationRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    let runtime = ObservationRuntime()

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        runtime
    }
}

private final class ObservationRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let lock = NSLock()
    private var transcript = "Ready"
    private var changeHandler: (@Sendable () -> Void)?

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let transcript = self.transcript
        lock.unlock()
        return SessionScreen(session: session, transcript: transcript)
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func stop() throws {}
    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}

    func appendOutput(_ suffix: String) {
        lock.lock()
        transcript += suffix
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }
}

private final class TerminalControllerRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    let runtime = TerminalControllerRuntime()

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        runtime
    }
}

private final class TerminalControllerRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let lock = NSLock()
    private var transcript = "prompt> "
    private var changeHandler: (@Sendable () -> Void)?
    private var columns = 80
    private var rows = 24

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let transcript = self.transcript
        let columns = self.columns
        let rows = self.rows
        lock.unlock()
        return SessionScreen(
            session: session,
            transcript: transcript,
            terminalColumns: columns,
            terminalRows: rows
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func stop() throws {}
    func sendInput(_ text: String) throws {}

    func sendText(_ text: String) throws {
        lock.lock()
        transcript += text
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {
        lock.lock()
        if key == .enter {
            transcript += "\nran"
        }
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}

    func resize(columns: Int, rows: Int) throws {
        lock.lock()
        self.columns = columns
        self.rows = rows
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }
}

private final class StructuredControllerRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    let runtime = StructuredControllerRuntime()

    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        runtime
    }
}

private final class StructuredControllerRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let lock = NSLock()
    private var approvalRequest = SessionApprovalRequest(id: UUID(), title: "Deploy?", text: "Deploy?", state: .pending)
    private var hasPendingApproval = false
    private var hasApproved = false
    private var changeHandler: (@Sendable () -> Void)?
    private var columns = 80
    private var rows = 24

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let hasPendingApproval = self.hasPendingApproval
        let hasApproved = self.hasApproved
        let approvalRequest = self.approvalRequest
        let columns = self.columns
        let rows = self.rows
        lock.unlock()

        var items = [SessionActivityItem(kind: .status, text: "Pi ready")]
        var approvalRequests: [SessionApprovalRequest] = []
        var transcript = ""

        if hasPendingApproval || hasApproved {
            items.append(SessionActivityItem(kind: .message, text: "You: deploy"))
            transcript = "> deploy"
        }
        if hasPendingApproval {
            items.append(SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy?"))
            approvalRequests = [approvalRequest]
        }
        if hasApproved {
            items.append(SessionActivityItem(kind: .approvalDecision, text: "Approved: Deploy?"))
            items.append(SessionActivityItem(kind: .message, text: "Pi: Deployment approved"))
            transcript = "> deploy\nDeployment approved"
            approvalRequests = [approvalRequest]
        }

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: transcript,
            terminalColumns: columns,
            terminalRows: rows,
            activityItems: items,
            approvalRequests: approvalRequests
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
        if text == "deploy" {
            hasPendingApproval = true
            hasApproved = false
            approvalRequest = SessionApprovalRequest(id: approvalRequest.id, title: "Deploy?", text: "Deploy?", state: .pending)
        }
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }

    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {
        lock.lock()
        if approvalRequest.id == approvalRequestID, decision == .approve {
            hasPendingApproval = false
            hasApproved = true
            approvalRequest = SessionApprovalRequest(id: approvalRequest.id, title: "Deploy?", text: "Deploy?", state: .approved)
        }
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }

    func resize(columns: Int, rows: Int) throws {
        lock.lock()
        self.columns = columns
        self.rows = rows
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }
}

private struct StubProviderHealthEvaluator: ProviderHealthEvaluating {
    let summariesByProvider: [ProviderID: ProviderHealthSummary]

    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        ProviderID.allCases.map { providerID in
            WorkspaceProviderCard(
                provider: Provider(id: providerID),
                health: healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext),
                defaultSession: ProviderDefaultSessionSummary(
                    state: .notCreated,
                    summary: "No default session yet",
                    actionTitle: "Launch"
                )
            )
        }
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        summariesByProvider[providerID] ?? ProviderHealthSummary(state: .notChecked, summary: "Health checks coming soon")
    }
}
#endif
