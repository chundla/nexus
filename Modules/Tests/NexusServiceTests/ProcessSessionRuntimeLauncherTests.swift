#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ProcessSessionRuntimeLauncherTests {
    @Test func localProtocolNativeProvidersUseSharedFactoryRegistry() throws {
        let launchRecorder = ProtocolNativeLaunchRecorder()
        let launcher = ProcessSessionRuntimeLauncher(
            localProtocolNativeRuntimeFactories: [
                .pi: { launchConfiguration, session, workspace in
                    launchRecorder.record(session: session, workspace: workspace, launchConfiguration: launchConfiguration)
                    return StubProtocolNativeRuntime(
                        primarySurface: .structuredActivityFeed,
                        activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
                    )
                },
                .codex: { launchConfiguration, session, workspace in
                    launchRecorder.record(session: session, workspace: workspace, launchConfiguration: launchConfiguration)
                    return StubProtocolNativeRuntime(
                        primarySurface: .structuredActivityFeed,
                        transcript: "Codex ready"
                    )
                }
            ]
        )

        let workspace = Workspace(
            id: UUID(),
            name: "Local Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: UUID()
        )
        let piSession = Session(id: UUID(), workspaceID: workspace.id, providerID: .pi, isDefault: true, state: .ready)
        let codexSession = Session(id: UUID(), workspaceID: workspace.id, providerID: .codex, isDefault: false, state: .ready)

        let piRuntime = try launcher.makeRuntime(
            session: piSession,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/tmp/fake-pi",
                workingDirectory: workspace.folderPath,
                remoteHost: nil,
                sessionRecordAdapterMetadata: SessionRecordAdapterMetadata(providerID: .pi, values: ["piSessionID": "pi-session-1"])
            )
        )
        let codexRuntime = try launcher.makeRuntime(
            session: codexSession,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/tmp/fake-codex",
                workingDirectory: workspace.folderPath,
                remoteHost: nil,
                sessionRecordAdapterMetadata: SessionRecordAdapterMetadata(providerID: .codex, values: ["conversationID": "codex-session-1"])
            )
        )

        let piScreen = piRuntime.sessionScreen(for: piSession)
        let codexScreen = codexRuntime.sessionScreen(for: codexSession)

        #expect(launchRecorder.records.map { $0.session.providerID } == [.pi, .codex])
        #expect(launchRecorder.records.map { $0.launchConfiguration.executable } == ["/tmp/fake-pi", "/tmp/fake-codex"])
        #expect(launchRecorder.records.map { $0.launchConfiguration.sessionRecordAdapterMetadata?.providerID } == [.some(.pi), .some(.codex)])
        #expect(piScreen.primarySurface == SessionSurface.structuredActivityFeed)
        #expect(piScreen.activityItems.map { $0.text } == ["Pi ready"])
        #expect(codexScreen.primarySurface == SessionSurface.structuredActivityFeed)
        #expect(codexScreen.transcript == "Codex ready")
    }

    @Test func terminalBackedProvidersStillUseProcessRuntimePath() throws {
        let launcher = ProcessSessionRuntimeLauncher(
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/sh"])
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Local Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: UUID()
        )
        let session = Session(id: UUID(), workspaceID: workspace.id, providerID: .claude, isDefault: true, state: .ready)

        let runtime = try launcher.makeRuntime(
            session: session,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/usr/bin/true",
                workingDirectory: workspace.folderPath,
                remoteHost: nil
            )
        )

        #expect(runtime is ProcessSessionRuntime)
        #expect(runtime.sessionScreen(for: session).primarySurface == .terminal)
    }
}

private final class ProtocolNativeLaunchRecorder: @unchecked Sendable {
    struct Record {
        let session: Session
        let workspace: Workspace
        let launchConfiguration: SessionRuntimeLaunchConfiguration
    }

    private let lock = NSLock()
    private(set) var records: [Record] = []

    func record(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) {
        lock.lock()
        records.append(Record(session: session, workspace: workspace, launchConfiguration: launchConfiguration))
        lock.unlock()
    }
}

private final class StubProtocolNativeRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let primarySurface: SessionSurface
    private let transcript: String
    private let activityItems: [SessionActivityItem]

    init(primarySurface: SessionSurface, transcript: String = "", activityItems: [SessionActivityItem] = []) {
        self.primarySurface = primarySurface
        self.transcript = transcript
        self.activityItems = activityItems
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: session,
            primarySurface: primarySurface,
            transcript: transcript,
            activityItems: activityItems
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
    func stop() throws {}
    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}
}
#endif
