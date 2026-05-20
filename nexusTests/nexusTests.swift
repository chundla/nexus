import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import Testing
@testable import nexus

struct nexusTests {

    @Test func embeddedServiceBootstrapStartsBackgroundServiceReachableOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let status = try await client.getServiceStatus()

        #expect(status.state == .running)
        #expect(status.store.kind == .sqlite)
        #expect(status.store.owner == .backgroundService)
        #expect(status.store.location.path(percentEncoded: false).hasSuffix("Nexus.sqlite"))
    }

    @Test func backgroundServiceCreatesAndListsWorkspaceGroupsOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let createdGroup = try await client.createWorkspaceGroup(name: "Client Work")
        let groups = try await client.listWorkspaceGroups()

        #expect(createdGroup.name == "Client Work")
        #expect(groups == [createdGroup])
    }

    @Test func localWorkspaceInheritsOnlyWorkspaceGroupAndPersistsAcrossServiceBootstrap() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let firstService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: "/tmp/example-workspace",
            primaryGroupID: nil
        )

        let secondService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedGroups = try await secondClient.listWorkspaceGroups()
        let persistedWorkspaces = try await secondClient.listWorkspaces()

        #expect(workspace.name == "example-workspace")
        #expect(workspace.primaryGroupID == group.id)
        #expect(persistedGroups == [group])
        #expect(persistedWorkspaces == [workspace])
    }

    @Test func localWorkspaceRequiresExplicitPrimaryWorkspaceGroupWhenMultipleGroupsExist() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        _ = try await client.createWorkspaceGroup(name: "Alpha")
        _ = try await client.createWorkspaceGroup(name: "Beta")

        await #expect(throws: (any Error).self) {
            _ = try await client.createLocalWorkspace(
                name: nil,
                folderPath: "/tmp/multi-group-workspace",
                primaryGroupID: nil
            )
        }
    }

    @Test func workspaceOverviewShowsAllSupportedProvidersOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(name: nil, folderPath: "/tmp/provider-overview-workspace", primaryGroupID: nil)

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)

        #expect(overview.workspace == workspace)
        #expect(overview.providerCards.map(\.provider.id) == [.codex, .claude, .ibmBob, .pi])
        #expect(overview.providerCards.map(\.defaultSession.state) == [.notCreated, .notCreated, .notCreated, .notCreated])
        #expect(overview.providerCards.filter { $0.provider.id != .claude }.map(\.health.state) == [.notChecked, .notChecked, .notChecked])
    }

    @Test func workspaceOverviewShowsLaunchableClaudeHealthFromServiceOwnedAdapter() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager()
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(claudeCard.health.state == .available)
        #expect(claudeCard.health.summary == "Claude 9.9.9 (Claude Code) is available")
        #expect(claudeCard.health.resolvedExecutable == "/tmp/fake-claude")
        #expect(claudeCard.health.version == "9.9.9 (Claude Code)")
        #expect(claudeCard.health.launchability == .launchable)
        #expect(claudeCard.health.diagnostics.isEmpty)
    }

    @Test func workspaceOverviewShowsUnavailableClaudeHealthWhenExecutableCannotBeResolved() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(claudeCard.health.state == .unavailable)
        #expect(claudeCard.health.summary == "Claude executable was not found")
        #expect(claudeCard.health.resolvedExecutable == nil)
        #expect(claudeCard.health.version == nil)
        #expect(claudeCard.health.launchability == .notLaunchable)
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0 == ProviderHealthDiagnostic(
                severity: .error,
                code: "executableNotFound",
                message: "Claude executable was not found in the service search paths."
            )
        }))
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0.code == "searchedDirectories" && $0.message.contains("/tmp/search-a")
        }))
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0.code == "homeDirectories" && $0.message.contains("/tmp/home")
        }))
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0.code == "pathEnvironment" && $0.message.contains("/tmp/search-a:/tmp/search-b")
        }))
    }

    @Test func launchOrResumeDefaultSessionCreatesAndReusesClaudeSessionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager()
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let firstSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let secondSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(firstSession.state == .ready)
        #expect(firstSession.providerID == .claude)
        #expect(firstSession.workspaceID == workspace.id)
        #expect(firstSession.isDefault)
        #expect(secondSession == firstSession)
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
        #expect(claudeCard.defaultSession.sessionID == firstSession.id)
    }

    @Test func launchedSessionReturnsFocusedTranscriptAndAcceptsInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "Claude ready")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let firstScreen = try await client.getSessionScreen(sessionID: session.id)
        let updatedScreen = try await client.sendSessionInput(sessionID: session.id, text: "help")

        #expect(firstScreen.session == session)
        #expect(firstScreen.transcript == "Claude ready")
        #expect(firstScreen.terminalColumns == 80)
        #expect(firstScreen.terminalRows == 24)
        #expect(updatedScreen.transcript.contains("> help"))
        #expect(updatedScreen.transcript.contains("Claude acknowledged: help"))
    }

    @Test func launchedSessionNormalizesTerminalControlTranscriptOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "progress 0%\rprogress 100%\n\u{001B}[32mClaude ready\u{001B}[0m\n")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: session.id)

        #expect(screen.transcript.contains("progress 100%"))
        #expect(screen.transcript.contains("Claude ready"))
        #expect(screen.transcript.contains("progress 0%") == false)
        #expect(screen.transcript.contains("\u{001B}") == false)
        #expect(screen.transcript.contains("\r") == false)
    }

    @Test func launchedSessionCanBeResizedOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "Claude ready")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let resizedScreen = try await client.resizeSession(sessionID: session.id, columns: 132, rows: 40)

        #expect(resizedScreen.session == session)
        #expect(resizedScreen.transcript == "Claude ready")
        #expect(resizedScreen.terminalColumns == 132)
        #expect(resizedScreen.terminalRows == 40)
    }

    @Test func sessionScreenExposesVisibleTerminalLinesOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\n123456789\nomega")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.visibleLines == ["12345", "6789", "omega"])
    }

    @Test func sessionScreenExposesViewportCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\n123456789\nom")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.visibleLines == ["12345", "6789", "om"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenTracksCursorLeftControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abc\u{001B}[2D")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.transcript == "abc")
        #expect(screen.visibleLines == ["abc"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenTracksCursorUpOverwriteOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1A\u{001B}[2DXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.transcript == "alXYa\nbeta")
        #expect(screen.visibleLines == ["alXYa", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenClearsLineSuffixWithEraseInLineControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "loading...\rdone\u{001B}[K")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "done")
        #expect(screen.visibleLines == ["done"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenTracksAbsoluteCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1;3HXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.transcript == "alXYa\nbeta")
        #expect(screen.visibleLines == ["alXYa", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenClearsEntireDisplayOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[2J\u{001B}[Hdone")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "done")
        #expect(screen.visibleLines == ["done"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenDeletesCharacterAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[2D\u{001B}[P")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "abce")
        #expect(screen.visibleLines == ["abce"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func liveClaudeRuntimeStartsOnPseudoTerminalOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import fcntl
        import struct
        import sys
        import termios
        
        try:
            rows, cols, _, _ = struct.unpack(
                "HHHH",
                fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
            )
            print(f"TTY {rows} {cols}", flush=True)
        except OSError:
            print("TTY no-tty", flush=True)

        while True:
            line = sys.stdin.readline()
            if not line:
                break
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("TTY 24 80") || currentScreen.transcript.contains("TTY no-tty")
        }

        #expect(screen.terminalColumns == 80)
        #expect(screen.terminalRows == 24)
        #expect(screen.transcript.contains("TTY 24 80"))
    }

    @Test func liveClaudeRuntimeNormalizesTerminalControlOutputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import sys
        import time

        sys.stdout.write("progress 0%")
        sys.stdout.flush()
        time.sleep(0.05)
        sys.stdout.write("\\rprogress 100%\\n")
        sys.stdout.write("\\x1b[32mClaude ready\\x1b[0m\\n")
        sys.stdout.flush()
        time.sleep(2)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("progress 100%") && currentScreen.transcript.contains("Claude ready")
        }

        #expect(screen.transcript.contains("progress 100%"))
        #expect(screen.transcript.contains("Claude ready"))
        #expect(screen.transcript.contains("progress 0%") == false)
        #expect(screen.transcript.contains("\u{001B}") == false)
    }

    @Test func exitedClaudeRuntimeBecomesInspectableAndRelaunchableOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let exitedScreen = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.session.state == .exited
        }
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(exitedScreen.session.id == session.id)
        #expect(exitedScreen.session.state == .exited)
        #expect(exitedScreen.transcript.contains("Claude finished work"))
        #expect(exitedScreen.transcript.contains("Claude exited"))
        #expect(claudeCard.defaultSession.state == .exited)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(claudeCard.defaultSession.sessionID == session.id)
    }

    @Test func persistedReadySessionBecomesRelaunchableAfterServiceRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let healthEvaluator = ProviderHealthEvaluator(
            executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
            commandRunner: StubCommandRunner(results: [
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
            ])
        )

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let overviewAfterRestart = try await restartedClient.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overviewAfterRestart.providerCards.first(where: { $0.provider.id == .claude }))
        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(claudeCard.defaultSession.state == .interrupted)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(claudeCard.defaultSession.sessionID == launchedSession.id)
        #expect(interruptedScreen.session.id == launchedSession.id)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.transcript.contains("service restarted"))
    }

    @Test func interruptedDefaultSessionCanBeRelaunchedAfterServiceRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let healthEvaluator = ProviderHealthEvaluator(
            executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
            commandRunner: StubCommandRunner(results: [
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
            ])
        )

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        _ = try await restartedClient.getWorkspaceOverview(workspaceID: workspace.id)

        let relaunchedSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(relaunchedSession.id == launchedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(relaunchedScreen.session.state == .ready)
        #expect(relaunchedScreen.transcript == "Claude ready")
    }

    @Test func launchOrResumeDefaultSessionPersistsFailedClaudeSessionWhenLaunchabilityFails() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(session.state == .failed)
        #expect(session.failureMessage == "Claude executable was not found in the service search paths.")
        #expect(claudeCard.defaultSession.state == .failed)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(claudeCard.defaultSession.summary == "Claude executable was not found in the service search paths.")
        #expect(claudeCard.defaultSession.sessionID == session.id)
    }

    @MainActor
    @Test func appModelLoadsWorkspaceCatalogFromIPCClient() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        _ = try await client.createLocalWorkspace(name: nil, folderPath: "/tmp/app-model-workspace", primaryGroupID: nil)
        let model = NexusAppModel(client: client)

        await model.refresh()

        #expect(model.serviceStatus?.state == .running)
        #expect(model.workspaceGroups.map(\.name) == ["Solo Group"])
        #expect(model.workspaces.map(\.name) == ["app-model-workspace"])
        #expect(model.workspaceOverview(for: try #require(model.workspaces.first).id)?.providerCards.map(\.provider.displayName) == ["Codex", "Claude", "IBM Bob", "Pi"])
    }

    @MainActor
    @Test func appModelLaunchOrResumeDefaultSessionRefreshesWorkspaceOverview() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let session = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.transcript == "Claude ready")
    }

    @MainActor
    @Test func appModelRefreshesExitedFocusedSessionAndWorkspaceOverview() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import time
        time.sleep(0.2)
        print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let session = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let readyCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(readyCard.defaultSession.state == .ready)

        let exitedScreen = try await waitForFocusedSessionScreen(model: model, sessionID: session.id) { screen in
            screen.session.state == .exited
        }

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(exitedScreen.session.id == session.id)
        #expect(exitedScreen.session.state == .exited)
        #expect(exitedScreen.transcript.contains("Claude finished work"))
        #expect(claudeCard.defaultSession.state == .exited)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
    }

    @MainActor
    @Test func appModelCanRelaunchExitedFocusedSession() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import os
        import pathlib
        import time

        state_path = pathlib.Path(os.environ["NEXUS_RELAUNCH_STATE_FILE"])
        if state_path.exists():
            print("Claude relaunched", flush=True)
            time.sleep(2)
        else:
            state_path.write_text("relaunched")
            print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        setenv("NEXUS_RELAUNCH_STATE_FILE", stateFileURL.path(percentEncoded: false), 1)
        defer { unsetenv("NEXUS_RELAUNCH_STATE_FILE") }

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let firstSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForFocusedSessionScreen(model: model, sessionID: firstSession.id) { screen in
            screen.session.state == .exited
        }

        let relaunchedSession = try await model.relaunchFocusedSession()
        let readyScreen = try await waitForFocusedSessionScreen(model: model, sessionID: relaunchedSession.id) { screen in
            screen.session.state == .ready && screen.transcript.contains("Claude relaunched")
        }

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(relaunchedSession.id == firstSession.id)
        #expect(readyScreen.session.state == .ready)
        #expect(readyScreen.transcript.contains("Claude relaunched"))
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
    }

    @MainActor
    @Test func appModelSendInputUpdatesFocusedSessionTranscript() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        try await model.sendInputToFocusedSession("status")

        #expect(model.focusedSessionScreen?.transcript.contains("> status") == true)
        #expect(model.focusedSessionScreen?.transcript.contains("Claude acknowledged: status") == true)
    }

    @MainActor
    @Test func appModelResizeFocusedSessionUpdatesTerminalDimensions() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        try await model.resizeFocusedSession(columns: 100, rows: 30)

        #expect(model.focusedSessionScreen?.terminalColumns == 100)
        #expect(model.focusedSessionScreen?.terminalRows == 30)
        #expect(model.focusedSessionScreen?.transcript == "Claude ready")
    }

    @MainActor
    @Test func appModelReportsUnavailableServiceWhenStatusRefreshFails() async {
        let model = NexusAppModel(client: FailingServiceClient())

        await model.refreshServiceStatus()

        #expect(model.serviceStatus == nil)
        #expect(model.serviceErrorMessage == "Background Service unavailable")
        #expect(model.workspaceGroups.isEmpty)
        #expect(model.workspaces.isEmpty)
        #expect(model.workspaceOverviews.isEmpty)
    }

    @MainActor
    @Test func liveAppModelBootstrapsEmbeddedBackgroundServiceAndLoadsStatus() async throws {
        let model = try NexusAppModel.live()

        await model.refreshServiceStatus()

        let status = try #require(model.serviceStatus)
        #expect(status.state == .running)
        #expect(status.store.kind == .sqlite)
        #expect(status.store.owner == .backgroundService)
        #expect(status.store.location.path(percentEncoded: false).contains("Application Support"))
        #expect(status.store.location.lastPathComponent == "Nexus.sqlite")
        #expect(model.serviceErrorMessage == nil)
    }
}

private func waitForSessionScreen(
    client: any NexusServiceClient,
    sessionID: UUID,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    var latestScreen = try await client.getSessionScreen(sessionID: sessionID)

    while predicate(latestScreen) == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for session screen update: \(latestScreen.transcript)"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        latestScreen = try await client.getSessionScreen(sessionID: sessionID)
    }

    return latestScreen
}

@MainActor
private func waitForFocusedSessionScreen(
    model: NexusAppModel,
    sessionID: UUID,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    try await model.loadSessionScreen(sessionID: sessionID)
    var latestScreen = try #require(model.focusedSessionScreen)

    while predicate(latestScreen) == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for focused session screen update: \(latestScreen.transcript)"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        try await model.loadSessionScreen(sessionID: sessionID)
        latestScreen = try #require(model.focusedSessionScreen)
    }

    return latestScreen
}

private struct StubExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]
    var searchedDirectories: [String] = ["/tmp/search-a", "/tmp/search-b"]
    var homeDirectories: [String] = ["/tmp/home"]
    var pathEnvironment: String? = "/tmp/search-a:/tmp/search-b"

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: searchedDirectories,
            homeDirectories: homeDirectories,
            pathEnvironment: pathEnvironment
        )
    }
}

private struct StubCommandRunner: ProviderCommandRunning {
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
            throw NSError(domain: "StubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(arguments)"])
        }

        switch result {
        case .success(let stdout, let stderr, let exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private final class StubSessionRuntimeManager: SessionRuntimeManaging {
    private let initialTranscript: String
    private var transcripts: [UUID: String] = [:]
    private var sizes: [UUID: (columns: Int, rows: Int)] = [:]

    init(initialTranscript: String = "") {
        self.initialTranscript = initialTranscript
    }

    func launchOrResume(session: Session, workspace: Workspace, executable: String) throws {
        if transcripts[session.id] == nil {
            transcripts[session.id] = initialTranscript
        }
        if sizes[session.id] == nil {
            sizes[session.id] = (80, 24)
        }
    }

    func hasRuntime(for session: Session) -> Bool {
        transcripts[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        transcripts[session.id] == nil ? nil : .ready
    }

    func sessionScreen(for session: Session) throws -> SessionScreen {
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id, default: initialTranscript],
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        let separator = prefix.isEmpty ? "" : "\n"
        transcripts[session.id] = prefix + separator + "> \(text)\nClaude acknowledged: \(text)"
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id] ?? "",
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen {
        sizes[session.id] = (columns, rows)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id, default: initialTranscript],
            terminalColumns: columns,
            terminalRows: rows
        )
    }
}

private struct FailingServiceClient: NexusServiceClient {
    func getServiceStatus() async throws -> NexusServiceStatus {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func listWorkspaceGroups() async throws -> [WorkspaceGroup] {
        []
    }

    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func listWorkspaces() async throws -> [Workspace] {
        []
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }
}
