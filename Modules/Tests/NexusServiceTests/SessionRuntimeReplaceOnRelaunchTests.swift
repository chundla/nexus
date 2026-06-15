#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    @Suite struct SessionRuntimeReplaceOnRelaunchTests {
        @Test func replaceExistingRuntimeSwapsInMemoryRuntime() async throws {
            let launcher = CountingSessionRuntimeLauncher()
            let manager = InMemorySessionRuntimeManager(launcher: launcher)
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let workspace = Workspace(
                id: session.workspaceID,
                name: "w",
                kind: .local,
                folderPath: "/tmp",
                primaryGroupID: UUID()
            )
            let config = { (replace: Bool) in
                SessionRuntimeLaunchConfiguration(
                    executable: "/tmp/fake",
                    workingDirectory: "/tmp",
                    remoteHost: nil,
                    replaceExistingRuntime: replace
                )
            }

            try await manager.launchOrResume(session: session, workspace: workspace, launchConfiguration: config(false))
            #expect(launcher.makeCount == 1)
            #expect(manager.hasRuntime(for: session))

            try await manager.launchOrResume(session: session, workspace: workspace, launchConfiguration: config(false))
            #expect(launcher.makeCount == 1)

            try await manager.launchOrResume(session: session, workspace: workspace, launchConfiguration: config(true))
            #expect(launcher.makeCount == 2)
            #expect(manager.hasRuntime(for: session))
        }
    }

    private final class CountingSessionRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
        private(set) var makeCount = 0

        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            makeCount += 1
            return StubReadySessionRuntime()
        }
    }

    private final class StubReadySessionRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .ready
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            SessionScreen(session: session, primarySurface: .terminal, transcript: "Ready")
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
        func stop() throws { state = .exited }
        func sendInput(_ text: String) throws {}
        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
        func resize(columns: Int, rows: Int) throws {}
    }
#endif