#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct ProcessSessionRuntimeLauncherTests {
        @Test func providerModulesOwnLocalStructuredRuntimeConstruction() async throws {
            let tracker = RuntimeConstructionTracker()
            let launcher = ProcessSessionRuntimeLauncher(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .pi: RuntimeOwningPiProviderModule(tracker: tracker)
                    ]
                )
            )

            let workspace = Workspace(
                id: UUID(),
                name: "Local Workspace",
                kind: .local,
                folderPath: "/tmp/workspace",
                primaryGroupID: UUID()
            )
            let session = Session(
                id: UUID(), workspaceID: workspace.id, providerID: .pi, isDefault: true, state: .ready)

            let runtime = try await launcher.makeRuntime(
                session: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/tmp/fake-pi",
                    workingDirectory: workspace.folderPath,
                    remoteHost: nil
                )
            )

            #expect(tracker.requests == [.localPiStructured])
            #expect(runtime.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
        }

        @Test func providerModulesOwnRemoteStructuredRuntimeConstruction() async throws {
            let tracker = RuntimeConstructionTracker()
            let launcher = ProcessSessionRuntimeLauncher(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .codex: RuntimeOwningRemoteCodexProviderModule(tracker: tracker)
                    ]
                )
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
            let session = Session(
                id: UUID(), workspaceID: workspace.id, providerID: .codex, isDefault: true, state: .ready)

            let runtime = try await launcher.makeRuntime(
                session: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/home/tester/.local/bin/codex",
                    workingDirectory: workspace.folderPath,
                    remoteHost: host,
                    remoteRuntimeIdentifier: "nexus-runtime-1"
                )
            )

            #expect(tracker.requests == [.remoteCodexStructured])
            #expect(runtime.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
        }

        @Test func claudeProviderModuleOwnsTerminalRuntimeConstructionUsingSharedProcessPath() async throws {
            let tracker = RuntimeConstructionTracker()
            let launcher = ProcessSessionRuntimeLauncher(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .claude: RuntimeOwningClaudeProviderModule(tracker: tracker)
                    ]
                ),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/sh"])
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Local Workspace",
                kind: .local,
                folderPath: "/tmp/workspace",
                primaryGroupID: UUID()
            )
            let session = Session(
                id: UUID(), workspaceID: workspace.id, providerID: .claude, isDefault: true, state: .ready)

            let runtime = try await launcher.makeRuntime(
                session: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/usr/bin/true",
                    workingDirectory: workspace.folderPath,
                    remoteHost: nil
                )
            )

            #expect(tracker.requests == [.localClaudeTerminal])
            #expect(runtime is ProcessSessionRuntime)
            #expect(runtime.sessionScreen(for: session).primarySurface == .terminal)
        }

        @Test func terminalBackedProvidersStillUseProcessRuntimePath() async throws {
            let launcher = ProcessSessionRuntimeLauncher(
                providerModuleRegistry: ProviderModuleRegistry(),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/sh"])
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Local Workspace",
                kind: .local,
                folderPath: "/tmp/workspace",
                primaryGroupID: UUID()
            )
            let session = Session(
                id: UUID(), workspaceID: workspace.id, providerID: .claude, isDefault: true, state: .ready)

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

    private enum RuntimeConstructionRequest: Equatable {
        case localClaudeTerminal
        case localPiStructured
        case remoteCodexStructured
    }

    private final class RuntimeConstructionTracker: @unchecked Sendable {
        var requests: [RuntimeConstructionRequest] = []
    }

    private struct RuntimeOwningClaudeProviderModule: ProviderModule {
        let provider = Provider(id: .claude)
        let tracker: RuntimeConstructionTracker

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
        func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            await providerHealthEvaluator.healthSummary(
                for: .claude, workspace: workspace, remoteContext: remoteContext)
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            makeProviderCapabilities(
                provider: provider,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                health: health,
                defaultSession: defaultSession
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            .terminal
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)? {
            tracker.requests.append(.localClaudeTerminal)
            return try actions.makeLocalTerminalRuntime()
        }
    }

    private struct RuntimeOwningPiProviderModule: ProviderModule {
        let provider = Provider(id: .pi)
        let tracker: RuntimeConstructionTracker

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
        func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            await providerHealthEvaluator.healthSummary(for: .pi, workspace: workspace, remoteContext: remoteContext)
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            makeProviderCapabilities(
                provider: provider,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                health: health,
                defaultSession: defaultSession
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            .structuredActivityFeed
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)? {
            tracker.requests.append(.localPiStructured)
            return StubProtocolNativeRuntime(
                primarySurface: .structuredActivityFeed,
                activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
            )
        }
    }

    private struct RuntimeOwningRemoteCodexProviderModule: ProviderModule {
        let provider = Provider(id: .codex)
        let tracker: RuntimeConstructionTracker

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
        func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            await providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            makeProviderCapabilities(
                provider: provider,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                health: health,
                defaultSession: defaultSession
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            .structuredActivityFeed
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)? {
            tracker.requests.append(.remoteCodexStructured)
            return StubProtocolNativeRuntime(
                primarySurface: .structuredActivityFeed,
                activityItems: [SessionActivityItem(kind: .status, text: "Remote Codex ready")]
            )
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
