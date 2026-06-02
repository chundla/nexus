#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import Testing

struct NexusServiceSessionInteractionDelegationTests {
    @Test func getSessionScreenDelegatesToSessionInteractionModule() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let expectedScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            transcript: "Ready"
        )
        spy.getSessionScreenResult = expectedScreen

        let screen = try service.getSessionScreen(sessionID: expectedScreen.session.id)

        #expect(screen == expectedScreen)
        #expect(spy.getSessionScreenCalls == [expectedScreen.session.id])
    }

    @Test func observeSessionScreenDelegatesToSessionInteractionModule() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let observationID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            transcript: "Ready"
        )
        spy.observeSessionScreenResult = SessionScreenObservationStart(
            observationID: observationID,
            screen: expectedScreen
        )

        let start = try service.observeSessionScreen(observationID: observationID, sessionID: expectedScreen.session.id) { _ in }

        #expect(start.observationID == spy.observeSessionScreenResult.observationID)
        #expect(start.screen == spy.observeSessionScreenResult.screen)
        #expect(spy.observeSessionScreenCalls == [
            .init(observationID: observationID, sessionID: expectedScreen.session.id)
        ])
    }

    @Test func sendSessionInputDelegatesToSessionInteractionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let sessionID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: sessionID,
                workspaceID: workspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "updated"
        )
        spy.sendSessionInputResult = expectedScreen

        let screen = try await service.sendSessionInput(sessionID: sessionID, text: "hello")

        #expect(screen == expectedScreen)
        #expect(spy.sendSessionInputCalls == [
            .init(sessionID: sessionID, text: "hello")
        ])
    }

    @Test func sendRemoteSessionInputDelegatesToSessionInteractionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let sessionID = UUID()
        let pairedDeviceID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: sessionID,
                workspaceID: workspace.id,
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            transcript: "updated"
        )
        spy.sendRemoteSessionInputResult = expectedScreen

        let screen = try await service.sendRemoteSessionInput(
            sessionID: sessionID,
            pairedDeviceID: pairedDeviceID,
            text: "hello"
        )

        #expect(screen == expectedScreen)
        #expect(spy.sendRemoteSessionInputCalls == [
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: "hello")
        ])
    }

    @Test func respondToApprovalRequestDelegatesToSessionInteractionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let sessionID = UUID()
        let approvalRequestID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: sessionID,
                workspaceID: workspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "approved"
        )
        spy.respondToApprovalRequestResult = expectedScreen

        let screen = try await service.respondToApprovalRequest(
            sessionID: sessionID,
            approvalRequestID: approvalRequestID,
            decision: .approve
        )

        #expect(screen == expectedScreen)
        #expect(spy.respondToApprovalRequestCalls == [
            .init(sessionID: sessionID, approvalRequestID: approvalRequestID, decision: .approve)
        ])
    }

    @Test func sendRemoteSessionTextDelegatesToSessionInteractionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let sessionID = UUID()
        let pairedDeviceID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: sessionID,
                workspaceID: workspace.id,
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            transcript: "typed"
        )
        spy.sendRemoteSessionTextResult = expectedScreen

        let screen = try await service.sendRemoteSessionText(
            sessionID: sessionID,
            pairedDeviceID: pairedDeviceID,
            text: "ls"
        )

        #expect(screen == expectedScreen)
        #expect(spy.sendRemoteSessionTextCalls == [
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: "ls")
        ])
    }

    @Test func respondToRemoteApprovalRequestDelegatesToSessionInteractionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let sessionID = UUID()
        let pairedDeviceID = UUID()
        let approvalRequestID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: sessionID,
                workspaceID: workspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "approved"
        )
        spy.respondToRemoteApprovalRequestResult = expectedScreen

        let screen = try await service.respondToRemoteApprovalRequest(
            sessionID: sessionID,
            pairedDeviceID: pairedDeviceID,
            approvalRequestID: approvalRequestID,
            decision: .approve
        )

        #expect(screen == expectedScreen)
        #expect(spy.respondToRemoteApprovalRequestCalls == [
            .init(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                approvalRequestID: approvalRequestID,
                decision: .approve
            )
        ])
    }

    @Test func sendRemoteSessionInputKeyDelegatesToSessionInteractionModule() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionInteractionSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionInteraction: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let sessionID = UUID()
        let pairedDeviceID = UUID()
        let expectedScreen = SessionScreen(
            session: Session(
                id: sessionID,
                workspaceID: workspace.id,
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            transcript: "enter"
        )
        spy.sendRemoteSessionInputKeyResult = expectedScreen

        let screen = try await service.sendRemoteSessionInputKey(
            sessionID: sessionID,
            pairedDeviceID: pairedDeviceID,
            key: .enter
        )

        #expect(screen == expectedScreen)
        #expect(spy.sendRemoteSessionInputKeyCalls == [
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, key: .enter)
        ])
    }
}

private final class SessionInteractionSpy: SessionInteractionManaging, @unchecked Sendable {
    var getSessionScreenResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready),
        transcript: ""
    )
    struct ObserveCall: Equatable {
        let observationID: UUID
        let sessionID: UUID
    }

    struct SessionInputCall: Equatable {
        let sessionID: UUID
        let text: String
    }

    struct RemoteInputCall: Equatable {
        let sessionID: UUID
        let pairedDeviceID: UUID
        let text: String
    }

    struct ApprovalCall: Equatable {
        let sessionID: UUID
        let approvalRequestID: UUID
        let decision: ApprovalRequestDecision
    }

    struct RemoteApprovalCall: Equatable {
        let sessionID: UUID
        let pairedDeviceID: UUID
        let approvalRequestID: UUID
        let decision: ApprovalRequestDecision
    }

    struct RemoteInputKeyCall: Equatable {
        let sessionID: UUID
        let pairedDeviceID: UUID
        let key: SessionInputKey
    }

    struct RemoteExtensionDialogCall: Equatable {
        let sessionID: UUID
        let pairedDeviceID: UUID
        let dialogID: String
        let response: SessionExtensionUIDialogResponse
    }

    private(set) var getSessionScreenCalls: [UUID] = []
    var observeSessionScreenResult = SessionScreenObservationStart(
        observationID: UUID(),
        screen: SessionScreen(
            session: Session(id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready),
            transcript: ""
        )
    )
    private(set) var observeSessionScreenCalls: [ObserveCall] = []
    var sendSessionInputResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
        primarySurface: .structuredActivityFeed,
        transcript: ""
    )
    private(set) var sendSessionInputCalls: [SessionInputCall] = []
    var respondToApprovalRequestResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
        primarySurface: .structuredActivityFeed,
        transcript: ""
    )
    private(set) var respondToApprovalRequestCalls: [ApprovalCall] = []
    var sendRemoteSessionInputResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready),
        transcript: ""
    )
    private(set) var sendRemoteSessionInputCalls: [RemoteInputCall] = []
    var sendRemoteSessionTextResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready),
        transcript: ""
    )
    private(set) var sendRemoteSessionTextCalls: [RemoteInputCall] = []
    var respondToRemoteApprovalRequestResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
        primarySurface: .structuredActivityFeed,
        transcript: ""
    )
    private(set) var respondToRemoteApprovalRequestCalls: [RemoteApprovalCall] = []
    var sendRemoteSessionInputKeyResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready),
        transcript: ""
    )
    private(set) var sendRemoteSessionInputKeyCalls: [RemoteInputKeyCall] = []
    var respondToRemoteExtensionDialogResult = SessionScreen(
        session: Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
        primarySurface: .structuredActivityFeed,
        transcript: ""
    )
    private(set) var respondToRemoteExtensionDialogCalls: [RemoteExtensionDialogCall] = []

    func getSessionScreen(sessionID: UUID) throws -> SessionScreen {
        getSessionScreenCalls.append(sessionID)
        return getSessionScreenResult
    }

    func observeSessionScreen(
        observationID: UUID,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreenObservationUpdate) -> Void
    ) throws -> SessionScreenObservationStart {
        observeSessionScreenCalls.append(.init(observationID: observationID, sessionID: sessionID))
        return observeSessionScreenResult
    }

    func cancelSessionScreenObservation(observationID: UUID) {}

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        sendSessionInputCalls.append(.init(sessionID: sessionID, text: text))
        return sendSessionInputResult
    }

    func respondToApprovalRequest(
        sessionID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        respondToApprovalRequestCalls.append(
            .init(sessionID: sessionID, approvalRequestID: approvalRequestID, decision: decision)
        )
        return respondToApprovalRequestResult
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        sendRemoteSessionInputCalls.append(
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: text)
        )
        return sendRemoteSessionInputResult
    }

    func respondToRemoteApprovalRequest(
        sessionID: UUID,
        pairedDeviceID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        respondToRemoteApprovalRequestCalls.append(
            .init(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                approvalRequestID: approvalRequestID,
                decision: decision
            )
        )
        return respondToRemoteApprovalRequestResult
    }

    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        sendRemoteSessionTextCalls.append(
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: text)
        )
        return sendRemoteSessionTextResult
    }

    func respondToRemoteExtensionDialog(
        sessionID: UUID,
        pairedDeviceID: UUID,
        dialogID: String,
        response: SessionExtensionUIDialogResponse
    ) async throws -> SessionScreen {
        respondToRemoteExtensionDialogCalls.append(
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, dialogID: dialogID, response: response)
        )
        return respondToRemoteExtensionDialogResult
    }

    func sendRemoteSessionInputKey(
        sessionID: UUID,
        pairedDeviceID: UUID,
        key: SessionInputKey
    ) async throws -> SessionScreen {
        sendRemoteSessionInputKeyCalls.append(
            .init(sessionID: sessionID, pairedDeviceID: pairedDeviceID, key: key)
        )
        return sendRemoteSessionInputKeyResult
    }
}
#endif
