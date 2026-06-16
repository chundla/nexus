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
            #expect(launcher.makeCount == 1)

            manager.remove(session: session)
            launcher.resetMakeCount()
            launcher.nextRuntime = StubExitedSessionRuntime()
            try await manager.launchOrResume(session: session, workspace: workspace, launchConfiguration: config(false))
            #expect(launcher.makeCount == 1)

            try await manager.launchOrResume(session: session, workspace: workspace, launchConfiguration: config(true))
            #expect(launcher.makeCount == 2)
            #expect(manager.hasRuntime(for: session))
            #expect(manager.runtimeState(for: session) == .ready)
        }
    }

    private final class CountingSessionRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
        private(set) var makeCount = 0
        var nextRuntime: (any SessionRuntime)?

        func resetMakeCount() {
            makeCount = 0
        }

        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            makeCount += 1
            if let nextRuntime {
                let runtime = nextRuntime
                self.nextRuntime = nil
                return runtime
            }
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
        func sendInput(_ prompt: SessionPrompt) throws {}
        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
        func resize(columns: Int, rows: Int) throws {}
    }

    private final class StubExitedSessionRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .exited
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            SessionScreen(session: session, primarySurface: .terminal, transcript: "Exited")
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
        func stop() throws {}
        func sendInput(_ text: String) throws {}
        func sendInput(_ prompt: SessionPrompt) throws {}
        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
        func resize(columns: Int, rows: Int) throws {}
    }
#endif
