#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct NexusServiceClaudeSessionLifecycleTests {
        @Test func localClaudeRestartedSessionsRemainInspectableAndDefaultRelaunchResumesPersistedSessionID()
            async throws
        {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = PersistentClaudeTransportHarness()
            func makeService() throws -> NexusService {
                try makeClaudeLifecycleService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Claude",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let defaultSession = try await service.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .claude)
            let namedSession = try await service.createNamedSession(
                workspaceID: workspace.id, providerID: .claude, name: "Review")
            let defaultScreen = try service.getSessionScreen(sessionID: defaultSession.id)
            let namedScreen = try service.getSessionScreen(sessionID: namedSession.id)

            let restartedService = try makeService()
            let overview = try await restartedService.getWorkspaceOverview(workspaceID: workspace.id)
            let providerDetail = try await restartedService.getProviderDetail(
                workspaceID: workspace.id, providerID: .claude)
            let interruptedDefaultScreen = try restartedService.getSessionScreen(sessionID: defaultSession.id)
            let relaunchedDefaultSession = try await restartedService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .claude)
            let relaunchedDefaultScreen = try restartedService.getSessionScreen(sessionID: defaultSession.id)

            let launches = transportHarness.launches()
            let expectedMessage =
                "Claude Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."
            let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))
            let restartedNamedSession = try #require(providerDetail.alternateSessions.first)
            let firstDefaultLaunch = try #require(launches.first)
            let resumedDefaultLaunch = try #require(launches.last)

            #expect(defaultScreen.primarySurface == .structuredActivityFeed)
            #expect(defaultScreen.activityItems.map(\.text) == ["Claude Session ready. Send a prompt to start Claude."])
            #expect(namedScreen.primarySurface == .structuredActivityFeed)
            #expect(namedSession.name == "Review")
            #expect(claudeCard.defaultSession.state == .interrupted)
            #expect(claudeCard.defaultSession.summary == expectedMessage)
            #expect(providerDetail.defaultSession?.failureMessage == expectedMessage)
            #expect(restartedNamedSession.id == namedSession.id)
            #expect(restartedNamedSession.state == .interrupted)
            #expect(restartedNamedSession.failureMessage == expectedMessage)
            #expect(interruptedDefaultScreen.session.state == .interrupted)
            #expect(
                interruptedDefaultScreen.activityItems.map(\.text) == [
                    "Claude Session ready. Send a prompt to start Claude.",
                    expectedMessage,
                ])
            #expect(relaunchedDefaultSession.id == defaultSession.id)
            #expect(relaunchedDefaultSession.state == .ready)
            #expect(relaunchedDefaultScreen.session.state == .ready)
            #expect(launches.map(\.isResuming) == [false, false, true])
            #expect(firstDefaultLaunch.isResuming == false)
            #expect(resumedDefaultLaunch.isResuming)
            #expect(resumedDefaultLaunch.sessionID == firstDefaultLaunch.sessionID)
        }

        @Test func localClaudeNamedSessionCanBeStoppedRelaunchedAndDeletedWhilePreservingSessionLinkage()
            async throws
        {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = PersistentClaudeTransportHarness()
            func makeService() throws -> NexusService {
                try makeClaudeLifecycleService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Claude",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let namedSession = try await service.createNamedSession(
                workspaceID: workspace.id, providerID: .claude, name: "Review")
            let stoppedSession = try service.stopSession(sessionID: namedSession.id)
            let stoppedRecord = try service.getSessionRecord(sessionID: namedSession.id)

            let restartedService = try makeService()
            let relaunchedSession = try await restartedService.launchOrResumeSession(sessionID: namedSession.id)
            _ = try restartedService.stopSession(sessionID: namedSession.id)
            let deleted = try restartedService.deleteSessionRecord(sessionID: namedSession.id)
            let providerDetail = try await restartedService.getProviderDetail(
                workspaceID: workspace.id, providerID: .claude)

            let launches = transportHarness.launches()
            let firstLaunch = try #require(launches.first)
            let resumedLaunch = try #require(launches.last)

            #expect(namedSession.providerID == .claude)
            #expect(namedSession.isDefault == false)
            #expect(stoppedSession.state == .exited)
            #expect(stoppedRecord.state == .exited)
            #expect(relaunchedSession.id == namedSession.id)
            #expect(relaunchedSession.state == .ready)
            #expect(launches.map(\.isResuming) == [false, true])
            #expect(firstLaunch.isResuming == false)
            #expect(resumedLaunch.isResuming)
            #expect(resumedLaunch.sessionID == firstLaunch.sessionID)
            #expect(deleted)
            #expect(providerDetail.alternateSessions.isEmpty)

            do {
                _ = try restartedService.getSessionScreen(sessionID: namedSession.id)
                Issue.record("Expected deleted Claude Session Record to be unavailable")
            } catch {
            }
        }
    }

    private func makeClaudeLifecycleService(rootURL: URL, transportHarness: PersistentClaudeTransportHarness)
        throws -> NexusService
    {
        let launcher = ProcessSessionRuntimeLauncher(
            localShellEnvironmentResolver: ClaudeLifecycleStubShellEnvironmentResolver(),
            claudeTransportFactory: { _, arguments, _ in transportHarness.makeTransport(arguments: arguments) }
        )

        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: AlwaysReadyClaudeLifecycleProviderHealthFacts(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
    }

    private struct ClaudeLifecycleStubShellEnvironmentResolver: LocalShellEnvironmentResolving {
        func resolvedEnvironment() -> [String: String]? { nil }
    }

    private struct AlwaysReadyClaudeLifecycleProviderHealthFacts: ProviderHealthEvaluating {
        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            ProviderID.allCases.map { providerID in
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: readyHealthSummary(for: providerID),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .notCreated,
                        summary: "No default session yet",
                        actionTitle: "Launch"
                    )
                )
            }
        }

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            readyHealthSummary(for: providerID)
        }

        private func readyHealthSummary(for providerID: ProviderID) -> ProviderHealthSummary {
            ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
                launchability: .launchable
            )
        }
    }

    private final class PersistentClaudeTransportHarness: @unchecked Sendable {
        struct Launch: Sendable {
            let isResuming: Bool
            let sessionID: String
        }

        private let lock = NSLock()
        private var recordedLaunches: [Launch] = []

        func makeTransport(arguments: [String]) -> any ClaudeStreamJSONTransporting {
            if let resumeIndex = arguments.firstIndex(of: "--resume"), arguments.indices.contains(resumeIndex + 1) {
                recordLaunch(Launch(isResuming: true, sessionID: arguments[resumeIndex + 1]))
            } else if let sessionIDIndex = arguments.firstIndex(of: "--session-id"),
                arguments.indices.contains(sessionIDIndex + 1)
            {
                recordLaunch(Launch(isResuming: false, sessionID: arguments[sessionIDIndex + 1]))
            }
            return NoOpClaudeStreamJSONTransport()
        }

        private func recordLaunch(_ launch: Launch) {
            lock.lock()
            recordedLaunches.append(launch)
            lock.unlock()
        }

        func launches() -> [Launch] {
            lock.lock()
            defer { lock.unlock() }
            return recordedLaunches
        }
    }

    private final class NoOpClaudeStreamJSONTransport: ClaudeStreamJSONTransporting, @unchecked Sendable {
        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {}
        func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {}
        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {}
        func start() throws {}
        func sendLine(_ line: String) throws {}
        func terminate() throws {}
    }
#endif
