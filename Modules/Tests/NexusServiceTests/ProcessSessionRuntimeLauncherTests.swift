#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ProcessSessionRuntimeLauncherTests {
    @Test func localProtocolNativeProvidersUseSharedFactoryRegistry() async throws {
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

        let piRuntime = try await launcher.makeRuntime(
            session: piSession,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/tmp/fake-pi",
                workingDirectory: workspace.folderPath,
                remoteHost: nil,
                sessionRecordAdapterMetadata: SessionRecordAdapterMetadata(providerID: .pi, values: ["piSessionID": "pi-session-1"])
            )
        )
        let codexRuntime = try await launcher.makeRuntime(
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

    @Test func remoteProtocolNativeProvidersUseSharedFactoryRegistry() async throws {
        let launchRecorder = ProtocolNativeLaunchRecorder()
        let launcher = ProcessSessionRuntimeLauncher(
            remoteProtocolNativeRuntimeFactories: [
                .codex: { launchConfiguration, session, workspace in
                    launchRecorder.record(session: session, workspace: workspace, launchConfiguration: launchConfiguration)
                    return StubProtocolNativeRuntime(
                        primarySurface: .structuredActivityFeed,
                        activityItems: [SessionActivityItem(kind: .status, text: "Remote Codex ready")]
                    )
                }
            ]
        )

        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let workspace = Workspace(
            id: UUID(),
            name: "Remote Workspace",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: host.id
        )
        let session = Session(id: UUID(), workspaceID: workspace.id, providerID: .codex, isDefault: true, state: .ready)

        let runtime = try await launcher.makeRuntime(
            session: session,
            workspace: workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration(
                executable: "/home/tester/.local/bin/codex",
                workingDirectory: workspace.folderPath,
                remoteHost: host,
                remoteRuntimeIdentifier: "nexus-runtime-1",
                sessionRecordAdapterMetadata: SessionRecordAdapterMetadata(providerID: .codex, values: ["threadID": "codex-thread-1"])
            )
        )

        let screen = runtime.sessionScreen(for: session)

        #expect(launchRecorder.records.count == 1)
        #expect(launchRecorder.records.first?.session.providerID == .codex)
        #expect(launchRecorder.records.first?.workspace.kind == .remote)
        #expect(launchRecorder.records.first?.launchConfiguration.remoteHost?.id == host.id)
        #expect(screen.primarySurface == SessionSurface.structuredActivityFeed)
        #expect(screen.activityItems.map { $0.text } == ["Remote Codex ready"])
    }

    @Test func terminalBackedProvidersStillUseProcessRuntimePath() async throws {
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

        let runtime = try await launcher.makeRuntime(
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
