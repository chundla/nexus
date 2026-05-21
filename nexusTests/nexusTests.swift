import AppKit
import Foundation
import NexusDomain
import SwiftUI
import NexusIPC
@testable import NexusService
import Testing
@testable import nexus

struct nexusTests {

    @Test func terminalKeyMappingConvertsControlTIntoTerminalControlText() {
        let input = mapSessionTerminalInput(
            modifierFlags: [.control],
            keyCode: 17,
            characters: "t",
            charactersIgnoringModifiers: "t"
        )

        #expect(input == .text("\u{0014}"))
    }

    @Test func terminalKeyMappingMapsForwardDeleteToDeleteKey() {
        let input = mapSessionTerminalInput(
            modifierFlags: [],
            keyCode: 117,
            characters: nil,
            charactersIgnoringModifiers: nil
        )

        #expect(input == .key(.deleteForward))
    }

    @Test func terminalKeyMappingMapsHomeAndEndKeys() {
        let homeInput = mapSessionTerminalInput(
            modifierFlags: [],
            keyCode: 115,
            characters: nil,
            charactersIgnoringModifiers: nil
        )
        let endInput = mapSessionTerminalInput(
            modifierFlags: [],
            keyCode: 119,
            characters: nil,
            charactersIgnoringModifiers: nil
        )

        #expect(homeInput == .key(.home))
        #expect(endInput == .key(.end))
    }

    @Test func utf8StreamDecoderBuffersSplitMultibyteTerminalGlyphs() {
        var decoder = UTF8StreamDecoder()

        let firstChunk = decoder.decode(Data([0xE2, 0x95]))
        let secondChunk = decoder.decode(Data([0xAD, 0xE2, 0x94]))
        let thirdChunk = decoder.decode(Data([0x80, 0xE2, 0x9D]))
        let fourthChunk = decoder.decode(Data([0xAF]))

        #expect(firstChunk.isEmpty)
        #expect(secondChunk == "╭")
        #expect(thirdChunk == "─")
        #expect(fourthChunk == "❯")
    }

    @Test func terminalRendererPreservesClaudeAnsiColorsAndInverseVideo() {
        let renderState = TerminalRenderer.renderState(
            from: "\u{001B}[38;5;153m/add-dir\u{001B}[39m\n/\u{001B}[7m \u{001B}[27m",
            terminalColumns: 40,
            terminalRows: 4
        )

        #expect(renderState.visibleLines == ["/add-dir", "/ "])
        #expect(renderState.styledVisibleLines[0].cells.allSatisfy { $0.style.foregroundColor == .ansi256(153) })
        #expect(renderState.styledVisibleLines[1].cells[0].style.isInverse == false)
        #expect(renderState.styledVisibleLines[1].cells[1].style.isInverse == true)
    }

    @Test func terminalRendererWrapsSequentialTextAtTerminalWidth() {
        let renderState = TerminalRenderer.renderState(
            from: "123456789",
            terminalColumns: 5,
            terminalRows: 3
        )

        #expect(renderState.visibleLines == ["12345", "6789"])
        #expect(renderState.cursorRow == 1)
        #expect(renderState.cursorColumn == 4)
    }

    @Test func terminalRendererDoesNotSoftWrapAbsolutePositionedOffscreenCells() {
        let renderState = TerminalRenderer.renderState(
            from: "a\u{001B}[143G|",
            terminalColumns: 139,
            terminalRows: 10
        )

        #expect(renderState.styledVisibleLines.count == 1)
        #expect(renderState.visibleLines[0].hasPrefix("a"))
    }

    @Test func terminalViewportLayoutUsesContentAreaInsteadOfOuterFrame() {
        let layout = TerminalViewportLayout(
            font: .system(size: 13, design: .monospaced),
            cellWidth: 8,
            cellHeight: 16,
            contentPadding: CGSize(width: 12, height: 12),
            minimumColumns: 40,
            minimumRows: 12
        )

        let gridSize = layout.gridSize(fitting: CGSize(width: 1_148, height: 344))

        #expect(gridSize.columns == 140)
        #expect(gridSize.rows == 20)
    }

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

    @Test func quickSwitchPrioritizesWorkspaceMatchesBeforeProviderAndSessionMatchesOverIPC() async throws {
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
            name: "Claude Lab",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        _ = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let results = try await client.searchNavigation(query: "claude")

        #expect(results.map(\.kind).prefix(3).elementsEqual([.workspace, .provider, .session]))
        #expect(results.first?.title == "Claude Lab")
        #expect(results.dropFirst().first?.subtitle.contains("Claude Lab") == true)
    }

    @Test func recentNavigationPersistsWorkspaceAndSessionContextsOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: "Recents Workspace",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        try await firstClient.recordNavigation(target: .workspace(workspace.id))
        try await Task.sleep(nanoseconds: 20_000_000)
        try await firstClient.recordNavigation(target: .session(session.id))

        let initialRecents = try await firstClient.listRecentNavigation(limit: 10)
        #expect(initialRecents.map(\.kind).prefix(2).elementsEqual([.session, .workspace]))
        #expect(initialRecents.first?.title == "Default Session")
        #expect(initialRecents.dropFirst().first?.title == "Recents Workspace")

        let secondService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedRecents = try await secondClient.listRecentNavigation(limit: 10)

        #expect(persistedRecents.map(\.kind).prefix(2).elementsEqual([.session, .workspace]))
        #expect(persistedRecents.first?.subtitle.contains("Recents Workspace") == true)
        #expect(persistedRecents.dropFirst().first?.title == "Recents Workspace")
    }

    @Test func createNamedSessionAddsAlternateSessionToProviderDetailOverIPC() async throws {
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

        let defaultSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(defaultSession.isDefault)
        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Session 1")
        #expect(providerDetail.defaultSession?.id == defaultSession.id)
        #expect(providerDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(providerDetail.alternateSessions.first?.name == "Session 1")
        #expect(providerDetail.failedSessions.isEmpty)
        #expect(claudeCard.alternateSessionCount == 1)
    }

    @Test func stopSessionKeepsAlternateSessionRecordInspectableOverIPC() async throws {
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

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)
        let stoppedSession = try await client.stopSession(sessionID: namedSession.id)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: namedSession.id)

        #expect(stoppedSession.id == namedSession.id)
        #expect(stoppedSession.state == .exited)
        #expect(providerDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(providerDetail.alternateSessions.first?.state == .exited)
        #expect(providerDetail.failedSessions.isEmpty)
        #expect(screen.session.state == .exited)
        #expect(screen.transcript == "Claude ready")
    }

    @Test func deleteStoppedSessionRecordRemovesItFromProviderDetailOverIPC() async throws {
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

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)
        _ = try await client.stopSession(sessionID: namedSession.id)
        let deleted = try await client.deleteSessionRecord(sessionID: namedSession.id)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(deleted)
        #expect(providerDetail.alternateSessions.isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await client.getSessionScreen(sessionID: namedSession.id)
        }
    }

    @Test func deleteRunningSessionRecordIsRejectedOverIPC() async throws {
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

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)

        await #expect(throws: (any Error).self) {
            _ = try await client.deleteSessionRecord(sessionID: namedSession.id)
        }
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

    @Test func launchedSessionTreatsCRLFAsLineBreakOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\r\r\nbeta")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "alpha\nbeta")
        #expect(screen.visibleLines == ["alpha", "beta"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 4)
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

    @Test func sessionScreenClearsDisplayPrefixWithoutShiftingTextOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[3G\u{001B}[1J")
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

        #expect(screen.transcript == "   de")
        #expect(screen.visibleLines == ["   de"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 2)
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

    @Test func sessionScreenTracksVerticalAbsoluteCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1dXY")
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

        #expect(screen.transcript == "alphXY\nbeta")
        #expect(screen.visibleLines == ["alphXY", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 6)
    }

    @Test func sessionScreenTracksHorizontalAbsoluteCursorAliasOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[3`XY")
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

        #expect(screen.transcript == "alpha\nbeXY")
        #expect(screen.visibleLines == ["alpha", "beXY"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenTracksHorizontalRelativeCursorAliasOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "ab\u{001B}[2aXY")
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

        #expect(screen.transcript == "ab  XY")
        #expect(screen.visibleLines == ["ab  XY"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 6)
    }

    @Test func sessionScreenTracksVerticalRelativeCursorAliasOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nmid\nbot\u{001B}[1;1H\u{001B}[2eXY")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 4)

        #expect(screen.transcript == "top\nmid\nXYt")
        #expect(screen.visibleLines == ["top", "mid", "XYt"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenSwitchesToAlternateBufferOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "main\u{001B}[?1049halt")
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

        #expect(screen.transcript == "alt")
        #expect(screen.visibleLines == ["alt"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenRestoresPrimaryScrollStateAfterAlternateBufferExitOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[?6h\u{001B}[?1049halt\u{001B}[?6l\u{001B}[r\u{001B}[?1049l\u{001B}[1;1HX")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 4)

        #expect(screen.transcript == "top\nXlpha\nbeta\nbottom")
        #expect(screen.visibleLines == ["top", "Xlpha", "beta", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 1)
    }

    @Test func alternateBufferRestoresPrimaryApplicationCursorModeForInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "main\u{001B}[?1049halt\u{001B}[?1h\u{001B}[?1049l")
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
        let screen = try await client.sendSessionInputKey(sessionID: session.id, key: .upArrow)

        #expect(screen.transcript.contains("[key: upArrow]"))
        #expect(screen.transcript.contains("[key: upArrow:application]") == false)
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

    @Test func sessionScreenInsertsCharacterAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abde\u{001B}[2D\u{001B}[@c")
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

        #expect(screen.transcript == "abcde")
        #expect(screen.visibleLines == ["abcde"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenDeletesCurrentLineOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[2;1H\u{001B}[M")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 4)

        #expect(screen.transcript == "alpha\ngamma")
        #expect(screen.visibleLines == ["alpha", "gamma"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenInsertsBlankLineAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[2;1H\u{001B}[L")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 5)

        #expect(screen.transcript == "alpha\n\nbeta\ngamma")
        #expect(screen.visibleLines == ["alpha", "", "beta", "gamma"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenErasesCharacterAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[2D\u{001B}[X")
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

        #expect(screen.transcript == "abc e")
        #expect(screen.visibleLines == ["abc e"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenClearsEntireLineWithoutMovingCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[2D\u{001B}[2KZ")
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

        #expect(screen.transcript == "   Z")
        #expect(screen.visibleLines == ["   Z"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenExpandsHorizontalTabsOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "ab\tc")
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

        #expect(screen.transcript == "ab      c")
        #expect(screen.visibleLines == ["ab      c"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 9)
    }

    @Test func sessionScreenTracksCursorNextLineControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\u{001B}[Ec")
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

        #expect(screen.transcript == "alpha\nc")
        #expect(screen.visibleLines == ["alpha", "c"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenHidesCursorWhenTerminalRequestsItOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abc\u{001B}[?25l")
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

        #expect(screen.transcript == "abc")
        #expect(screen.visibleLines == ["abc"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
        #expect(screen.cursorVisible == false)
    }

    @Test func sessionScreenRestoresSavedCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1;1H\u{001B}[sXY\u{001B}[uZ")
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

        #expect(screen.transcript == "ZYpha\nbeta")
        #expect(screen.visibleLines == ["ZYpha", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenRestoresDecSavedCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1;1H\u{001B}7\u{001B}[2;1HXY\u{001B}8Z")
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

        #expect(screen.transcript == "Zlpha\nXYta")
        #expect(screen.visibleLines == ["Zlpha", "XYta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenStripsOscWindowTitleControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{001B}]0;Claude working\u{0007}world")
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

        #expect(screen.transcript == "helloworld")
        #expect(screen.visibleLines == ["helloworld"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 10)
    }

    @Test func sessionScreenStripsOscHyperlinkControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "pre\u{001B}]8;;https://example.com\u{001B}\\link\u{001B}]8;;\u{001B}\\post")
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

        #expect(screen.transcript == "prelinkpost")
        #expect(screen.visibleLines == ["prelinkpos", "t"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenIgnoresKittyKeyboardProtocolControlsOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{001B}[<uworld\u{001B}[>1u!")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "helloworld!")
        #expect(screen.visibleLines == ["helloworld!"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 11)
    }

    @Test func sessionScreenStripsDeviceControlStringOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{001B}P$qm\u{001B}\\world")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "helloworld")
        #expect(screen.visibleLines == ["helloworld"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 10)
    }

    @Test func sessionScreenStripsBellControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{0007}world")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "helloworld")
        #expect(screen.visibleLines == ["helloworld"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 10)
    }

    @Test func sessionScreenRendersVt100LineDrawingCharactersOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "\u{001B}(0lqqk\u{001B}(B")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "┌──┐")
        #expect(screen.visibleLines == ["┌──┐"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenRepeatsPreviousCharacterOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "q\u{001B}[3b")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "qqqq")
        #expect(screen.visibleLines == ["qqqq"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenScrollsDisplayUpOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[S")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "beta\ngamma\n")
        #expect(screen.visibleLines == ["beta", "gamma", ""])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 5)
    }

    @Test func sessionScreenMovesCursorToScrollingRegionOriginOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[?6h\u{001B}[HXY")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nXYpha\nbeta\nbottom")
        #expect(screen.visibleLines == ["top", "XYpha", "beta", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenScrollsDisplayUpWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[S")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nbeta\n\nbottom")
        #expect(screen.visibleLines == ["top", "beta", "", "bottom"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenScrollsDisplayDownWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[T")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\n\nalpha\nbottom")
        #expect(screen.visibleLines == ["top", "", "alpha", "bottom"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenScrollsDisplayDownWithinScrollingRegionWithReverseIndexOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[3;1H\u{001B}D")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nbeta\n\nbottom")
        #expect(screen.visibleLines == ["top", "beta", "", "bottom"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenInsertsBlankLineWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[2;1H\u{001B}[L")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\n\nalpha\nbottom")
        #expect(screen.visibleLines == ["top", "", "alpha", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenDeletesLineWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[2;1H\u{001B}[M")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nbeta\n\nbottom")
        #expect(screen.visibleLines == ["top", "beta", "", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenScrollsDisplayDownOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[T")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "\nalpha\nbeta")
        #expect(screen.visibleLines == ["", "alpha", "beta"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 5)
    }

    @Test func sessionScreenReverseIndexesDisplayDownOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[1;1H\u{001B}M")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "\nalpha\nbeta")
        #expect(screen.visibleLines == ["", "alpha", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenIndexesDisplayUpOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[3;3H\u{001B}D")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "beta\ngamma\n")
        #expect(screen.visibleLines == ["beta", "gamma", ""])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenMovesToNextLineAndScrollsOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[3;3H\u{001B}E")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "beta\ngamma\n")
        #expect(screen.visibleLines == ["beta", "gamma", ""])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenBackspaceOnlyMovesCursorLeftOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abc\u{0008}")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "abc")
        #expect(screen.visibleLines == ["abc"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenErasesLinePrefixWithoutShiftingTextOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[3D\u{001B}[1K")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "   de")
        #expect(screen.visibleLines == ["   de"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenResetsDisplayWithFullResetControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\u{001B}cdone")
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
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "done")
        #expect(screen.visibleLines == ["done"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
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

    @Test func liveClaudeRuntimeStreamsSessionScreenUpdatesOverXPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import time

        print("Claude ready", flush=True)
        time.sleep(0.2)
        print("Claude streamed update", flush=True)
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
        let collector = SessionScreenCollector()
        let observation = try await client.observeSessionScreen(sessionID: session.id) { screen in
            Task {
                await collector.record(screen)
            }
        }

        let streamedScreen = try await collector.waitForScreen { screen in
            screen.transcript.contains("Claude streamed update") && screen.session.state == .exited
        }

        #expect(streamedScreen.transcript.contains("Claude ready"))
        #expect(streamedScreen.transcript.contains("Claude streamed update"))
        #expect(streamedScreen.session.state == .exited)
        await observation.cancel()
    }

    @Test func liveClaudeRuntimeAcceptsEmptyInputAsEnterOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import sys

        print("Press enter to continue", flush=True)
        line = sys.stdin.readline()
        if line == "\\n":
            print("Enter received", flush=True)
        else:
            print(f"Unexpected input: {line!r}", flush=True)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("Press enter to continue")
        }

        _ = try await client.sendSessionInput(sessionID: session.id, text: "")
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("Enter received")
        }

        #expect(screen.transcript.contains("Enter received"))
    }

    @Test func liveClaudeRuntimeSendsCarriageReturnForEnterKeyOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 1)
        if data == b'\r':
            print("CR", flush=True)
        elif data == b'\n':
            print("LF", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }

        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .enter)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("CR") || currentScreen.transcript.contains("LF")
        }

        #expect(screen.transcript.contains("CR"))
        #expect(screen.transcript.contains("LF") == false)
    }

    @Test func liveClaudeRuntimeAcceptsSpecialArrowKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 3)
        if data == b'\x1b[A':
            print("UP", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .upArrow)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("UP")
        }

        #expect(screen.transcript.contains("UP"))
    }

    @Test func liveClaudeRuntimeAcceptsEndOfTransmissionKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 1)
        if data == b'\x04':
            print("EOT", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .endOfTransmission)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("EOT")
        }

        #expect(screen.transcript.contains("EOT"))
    }

    @Test func liveClaudeRuntimeAcceptsInterruptKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 1)
        if data == b'\x03':
            print("INTERRUPT", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .interrupt)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("INTERRUPT")
        }

        #expect(screen.transcript.contains("INTERRUPT"))
    }

    @Test func liveClaudeRuntimeUsesApplicationCursorKeysWhenTerminalRequestsThemOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        sys.stdout.write("\x1b[?1h")
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 3)
        if data == b'\x1bOA':
            print("APPLICATION-UP", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .upArrow)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("APPLICATION-UP") || currentScreen.transcript.contains("\\x1b[A")
        }

        #expect(screen.transcript.contains("APPLICATION-UP"))
    }

    @Test func liveClaudeRuntimeRespondsToCursorPositionReportQueryOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        sys.stdout.write('abc\r\x1b[2B\x1b[5C\x1b[6n')
        sys.stdout.flush()

        data = b''
        while not data.endswith(b'R'):
            data += os.read(sys.stdin.fileno(), 1)

        if data == b'\x1b[3;6R':
            print('CPR', flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
            currentScreen.transcript.contains("CPR") || currentScreen.transcript.contains("\\x1b[3;6R")
        }

        #expect(screen.transcript.contains("CPR"))
        #expect(screen.transcript.contains("\\x1b[3;6R") == false)
    }

    @Test func liveClaudeRuntimeReceivesTypedTextAndBackspaceOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = b''
        while len(data) < 3:
            data += os.read(sys.stdin.fileno(), 3 - len(data))
        if data == b'ab\x7f':
            print("BACKSPACE", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionText(sessionID: session.id, text: "ab")
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .backspace)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("BACKSPACE")
        }

        #expect(screen.transcript.contains("BACKSPACE"))
    }

    @Test func liveClaudeRuntimeAcceptsForwardDeleteKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = b''
        while len(data) < 4:
            data += os.read(sys.stdin.fileno(), 4 - len(data))
        if data == b'\x1b[3~':
            print("DELETE", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .deleteForward)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("DELETE")
        }

        #expect(screen.transcript.contains("DELETE"))
    }

    @Test func liveClaudeRuntimeAcceptsHomeAndEndKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        first = os.read(sys.stdin.fileno(), 3)
        second = os.read(sys.stdin.fileno(), 3)
        if first == b'\x1b[H' and second == b'\x1b[F':
            print("HOME-END", flush=True)
        else:
            print(repr((first, second)), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
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
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .home)
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .end)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("HOME-END")
        }

        #expect(screen.transcript.contains("HOME-END"))
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

    @Test func interruptedSessionRetainsLastTerminalSizeAfterServiceRestart() async throws {
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
        let resizedScreen = try await firstClient.resizeSession(sessionID: launchedSession.id, columns: 132, rows: 40)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(resizedScreen.terminalColumns == 132)
        #expect(resizedScreen.terminalRows == 40)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.terminalColumns == 132)
        #expect(interruptedScreen.terminalRows == 40)
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

    @Test func interruptedDefaultSessionRelaunchesFromPersistedLaunchSnapshotWhenCurrentHealthIsUnavailable() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let firstRuntimeManager = StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
            "launched with \(executable)"
        })
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/claude-a"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: firstRuntimeManager
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
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
                "launched with \(executable)"
            })
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(interruptedScreen.session.state == .interrupted)

        let relaunchedSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(relaunchedSession.id == launchedSession.id)
        #expect(relaunchedScreen.session.state == .ready)
        #expect(relaunchedScreen.transcript == "launched with /tmp/claude-a")
    }

    @Test func newSessionsUseUpdatedLaunchConfigWithoutMutatingPersistedLaunchSnapshots() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/claude-a"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
                "launched with \(executable)"
            })
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let defaultSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/claude-b"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/claude-b", arguments: ["--version"]): .success(stdout: "9.9.10 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/claude-b", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
                "launched with \(executable)"
            })
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)

        let relaunchedDefaultSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let defaultSessionScreen = try await restartedClient.getSessionScreen(sessionID: defaultSession.id)
        let namedSession = try await restartedClient.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Fresh Session")
        let namedSessionScreen = try await restartedClient.getSessionScreen(sessionID: namedSession.id)

        #expect(relaunchedDefaultSession.id == defaultSession.id)
        #expect(defaultSessionScreen.transcript == "launched with /tmp/claude-a")
        #expect(namedSessionScreen.transcript == "launched with /tmp/claude-b")
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
    @Test func appModelLoadsAndUpdatesRecentNavigation() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let workspaceItem = NavigationItem(
            target: .workspace(workspace.id),
            title: workspace.name,
            subtitle: workspace.folderPath
        )
        let sessionItem = NavigationItem(
            target: .session(session.id),
            title: "Default Session",
            subtitle: "\(workspace.name) • Claude"
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            recentNavigation: [workspaceItem],
            searchResults: [sessionItem]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        #expect(model.recentNavigation == [workspaceItem])

        try await model.recordNavigation(.session(session.id))
        #expect(model.recentNavigation == [sessionItem, workspaceItem])
        #expect(client.recordedNavigationTargets == [.session(session.id)])

        let searchResults = try await model.searchNavigation(query: "claude")
        #expect(searchResults == [sessionItem])
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
    @Test func appModelCreateNamedSessionRefreshesProviderDetailAndFocusesNewSession() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let defaultSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let workspaceOverview = WorkspaceOverview(
            workspace: workspace,
            providerCards: [
                WorkspaceProviderCard(
                    provider: Provider(id: .claude),
                    health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .ready,
                        summary: "Default session ready",
                        actionTitle: "Resume",
                        sessionID: defaultSession.id
                    )
                )
            ]
        )
        let providerDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: defaultSession,
            alternateSessions: [],
            failedSessions: []
        )
        let client = TrackingServiceClient(
            workspaceOverview: workspaceOverview,
            session: defaultSession,
            screen: SessionScreen(session: defaultSession, transcript: "Claude ready"),
            providerDetail: providerDetail
        )
        let model = NexusAppModel(client: client)

        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let namedSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)

        let refreshedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first)
        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Session 1")
        #expect(model.focusedSessionScreen?.session.id == namedSession.id)
        #expect(refreshedDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(claudeCard.alternateSessionCount == 1)
    }

    @MainActor
    @Test func appModelStopSessionRefreshesProviderDetail() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let defaultSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let namedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .ready
        )
        let workspaceOverview = WorkspaceOverview(
            workspace: workspace,
            providerCards: [
                WorkspaceProviderCard(
                    provider: Provider(id: .claude),
                    health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .ready,
                        summary: "Default session ready",
                        actionTitle: "Resume",
                        sessionID: defaultSession.id
                    ),
                    alternateSessionCount: 1
                )
            ]
        )
        let providerDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: defaultSession,
            alternateSessions: [namedSession],
            failedSessions: []
        )
        let client = TrackingServiceClient(
            workspaceOverview: workspaceOverview,
            session: namedSession,
            screen: SessionScreen(session: namedSession, transcript: "Claude ready"),
            providerDetail: providerDetail
        )
        let model = NexusAppModel(client: client)

        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let stoppedSession = try await model.stopSession(sessionID: namedSession.id, workspaceID: workspace.id, providerID: .claude)

        let refreshedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        #expect(stoppedSession.state == .exited)
        #expect(refreshedDetail.alternateSessions.first?.id == namedSession.id)
        #expect(refreshedDetail.alternateSessions.first?.state == .exited)
    }

    @MainActor
    @Test func appModelDeleteSessionRecordRefreshesProviderDetailAndWorkspaceOverview() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let defaultSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let stoppedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        let workspaceOverview = WorkspaceOverview(
            workspace: workspace,
            providerCards: [
                WorkspaceProviderCard(
                    provider: Provider(id: .claude),
                    health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .ready,
                        summary: "Default session ready",
                        actionTitle: "Resume",
                        sessionID: defaultSession.id
                    ),
                    alternateSessionCount: 1
                )
            ]
        )
        let providerDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: defaultSession,
            alternateSessions: [stoppedSession],
            failedSessions: []
        )
        let client = TrackingServiceClient(
            workspaceOverview: workspaceOverview,
            session: stoppedSession,
            screen: SessionScreen(session: stoppedSession, transcript: "Claude ready"),
            providerDetail: providerDetail
        )
        let model = NexusAppModel(client: client)

        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let deleted = try await model.deleteSessionRecord(sessionID: stoppedSession.id, workspaceID: workspace.id, providerID: .claude)

        let refreshedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        let refreshedCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first)
        #expect(deleted)
        #expect(refreshedDetail.alternateSessions.isEmpty)
        #expect(refreshedCard.alternateSessionCount == 0)
    }

    @MainActor
    @Test func appModelLaunchOrResumeFailedSessionShowsInspectableFailureScreen() async throws {
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
        let model = NexusAppModel(client: client)

        await model.refresh()
        let session = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(session.state == .failed)
        #expect(claudeCard.defaultSession.state == .failed)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.session.state == .failed)
        #expect(model.focusedSessionScreen?.transcript == "Claude executable was not found in the service search paths.")
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
    @Test func appModelSendInputKeyUpdatesFocusedSessionTranscript() async throws {
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
        try await model.sendInputKeyToFocusedSession(.tab)

        #expect(model.focusedSessionScreen?.transcript.contains("[key: tab]") == true)
    }

    @MainActor
    @Test func appModelSendTypedTextUpdatesFocusedSessionTranscript() async throws {
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
        try await model.sendTypedTextToFocusedSession("abc")

        #expect(model.focusedSessionScreen?.transcript.contains("[typed: abc]") == true)
    }

    @MainActor
    @Test func appModelFocusSessionStreamRefreshesWorkspaceOverviewOnlyOnStateChanges() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let readySession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let initialScreen = SessionScreen(session: readySession, transcript: "Claude ready")
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: readySession,
            screen: initialScreen
        )
        let model = NexusAppModel(client: client)

        try await model.focusSession(sessionID: readySession.id)
        #expect(model.focusedSessionScreen == initialScreen)
        #expect(client.workspaceOverviewRequestCount == 0)

        await client.emitObservedScreen(SessionScreen(session: readySession, transcript: "Claude ready[typed: abc]"))
        let readyScreen = try await waitForObservedFocusedSessionScreen(model: model) { screen in
            screen.transcript.contains("[typed: abc]")
        }

        #expect(readyScreen.session.state == .ready)
        #expect(client.workspaceOverviewRequestCount == 0)

        let exitedSession = Session(
            id: readySession.id,
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        await client.emitObservedScreen(SessionScreen(session: exitedSession, transcript: "Claude streamed update"))
        let exitedScreen = try await waitForObservedFocusedSessionScreen(model: model) { screen in
            screen.session.state == .exited
        }
        try await waitUntil {
            client.workspaceOverviewRequestCount == 1
        }

        #expect(exitedScreen.transcript == "Claude streamed update")
        #expect(client.workspaceOverviewRequestCount == 1)
    }

    @MainActor
    @Test func appModelLoadSessionScreenDoesNotRefreshWorkspaceOverviewDuringTerminalPolling() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let client = TrackingServiceClient(workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []), session: session, screen: screen)
        let model = NexusAppModel(client: client)

        try await model.loadSessionScreen(sessionID: session.id)

        #expect(model.focusedSessionScreen == screen)
        #expect(client.workspaceOverviewRequestCount == 0)
    }

    @MainActor
    @Test func appModelSendTypedTextDoesNotRefreshWorkspaceOverviewWhileTyping() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let client = TrackingServiceClient(workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []), session: session, screen: initialScreen)
        let model = NexusAppModel(client: client)
        model.focusedSessionScreen = initialScreen

        try await model.sendTypedTextToFocusedSession("abc")

        #expect(model.focusedSessionScreen?.transcript == "Claude ready[typed: abc]")
        #expect(client.workspaceOverviewRequestCount == 0)
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

@MainActor
private func waitForObservedFocusedSessionScreen(
    model: NexusAppModel,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    var latestScreen = try #require(model.focusedSessionScreen)

    while predicate(latestScreen) == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for observed focused session update: \(latestScreen.transcript)"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        latestScreen = try #require(model.focusedSessionScreen)
    }

    return latestScreen
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

    while predicate() == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

private actor SessionScreenCollector {
    private var screens: [SessionScreen] = []

    func record(_ screen: SessionScreen) {
        screens.append(screen)
    }

    func waitForScreen(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        until predicate: @escaping (SessionScreen) -> Bool
    ) async throws -> SessionScreen {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

        while true {
            if let matchingScreen = screens.last(where: predicate) {
                return matchingScreen
            }

            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for streamed session screen update"])
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }
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
    private let launchTranscriptForExecutable: ((String) -> String)?
    private var transcripts: [UUID: String] = [:]
    private var states: [UUID: Session.State] = [:]
    private var sizes: [UUID: (columns: Int, rows: Int)] = [:]
    private var updateObservers: [UUID: [UUID: @Sendable () -> Void]] = [:]
    private var observedSessionIDs: [UUID: UUID] = [:]

    init(initialTranscript: String = "", launchTranscriptForExecutable: ((String) -> String)? = nil) {
        self.initialTranscript = initialTranscript
        self.launchTranscriptForExecutable = launchTranscriptForExecutable
    }

    func launchOrResume(session: Session, workspace: Workspace, executable: String) throws {
        if let launchTranscriptForExecutable {
            transcripts[session.id] = launchTranscriptForExecutable(executable)
        } else if transcripts[session.id] == nil {
            transcripts[session.id] = initialTranscript
        }
        states[session.id] = .ready
        if sizes[session.id] == nil {
            sizes[session.id] = (80, 24)
        }
        notifyObservers(for: session.id)
    }

    func stop(session: Session) throws {
        transcripts[session.id] = transcripts[session.id, default: initialTranscript]
        states[session.id] = .exited
        notifyObservers(for: session.id)
    }

    func remove(session: Session) {
        transcripts.removeValue(forKey: session.id)
        states.removeValue(forKey: session.id)
        sizes.removeValue(forKey: session.id)
        updateObservers.removeValue(forKey: session.id)
        observedSessionIDs = observedSessionIDs.filter { $0.value != session.id }
    }

    func hasRuntime(for session: Session) -> Bool {
        transcripts[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        states[session.id]
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

    func addUpdateObserver(id observationID: UUID, for session: Session, observer: @escaping @Sendable () -> Void) {
        updateObservers[session.id, default: [:]][observationID] = observer
        observedSessionIDs[observationID] = session.id
    }

    func removeUpdateObserver(id: UUID) {
        guard let sessionID = observedSessionIDs.removeValue(forKey: id) else {
            return
        }
        updateObservers[sessionID]?.removeValue(forKey: id)
        if updateObservers[sessionID]?.isEmpty == true {
            updateObservers.removeValue(forKey: sessionID)
        }
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        let separator = prefix.isEmpty ? "" : "\n"
        transcripts[session.id] = prefix + separator + "> \(text)\nClaude acknowledged: \(text)"
        notifyObservers(for: session.id)
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id] ?? "",
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func sendText(_ text: String, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        transcripts[session.id] = prefix + "[typed: \(text)]"
        notifyObservers(for: session.id)
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id] ?? "",
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        let separator = prefix.isEmpty ? "" : "\n"
        let modeSuffix = applicationCursorMode ? ":application" : ""
        transcripts[session.id] = prefix + separator + "[key: \(key.rawValue)\(modeSuffix)]"
        notifyObservers(for: session.id)
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
        notifyObservers(for: session.id)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id, default: initialTranscript],
            terminalColumns: columns,
            terminalRows: rows
        )
    }

    private func notifyObservers(for sessionID: UUID) {
        for observer in updateObservers[sessionID, default: [:]].values {
            observer()
        }
    }
}

private final class TrackingServiceClient: NexusServiceClient {
    private var workspaceOverviewValue: WorkspaceOverview
    private var providerDetailValue: ProviderDetail
    private var sessionValue: Session
    private var screenValue: SessionScreen
    private var recentNavigationValue: [NavigationItem]
    private var searchResultsValue: [NavigationItem]
    private var observedScreenHandlers: [UUID: @Sendable (SessionScreen) -> Void] = [:]

    var workspaceOverviewRequestCount = 0
    var recordedNavigationTargets: [NavigationTarget] = []

    init(
        workspaceOverview: WorkspaceOverview,
        session: Session,
        screen: SessionScreen,
        providerDetail: ProviderDetail? = nil,
        recentNavigation: [NavigationItem] = [],
        searchResults: [NavigationItem] = []
    ) {
        self.workspaceOverviewValue = workspaceOverview
        self.providerDetailValue = providerDetail ?? ProviderDetail(
            workspace: workspaceOverview.workspace,
            provider: Provider(id: session.providerID),
            health: workspaceOverview.providerCards.first(where: { $0.provider.id == session.providerID })?.health
                ?? ProviderHealthSummary(state: .notChecked, summary: "Not checked"),
            defaultSession: session.isDefault ? session : nil,
            alternateSessions: session.isDefault ? [] : [session],
            failedSessions: session.state == .failed && session.isDefault == false ? [session] : []
        )
        self.sessionValue = session
        self.screenValue = screen
        self.recentNavigationValue = recentNavigation
        self.searchResultsValue = searchResults
    }

    func getServiceStatus() async throws -> NexusServiceStatus {
        NexusServiceStatus(state: .running, store: .init(kind: .sqlite, owner: .backgroundService, location: URL(fileURLWithPath: "/tmp/Nexus.sqlite")))
    }

    func listWorkspaceGroups() async throws -> [WorkspaceGroup] {
        [WorkspaceGroup(id: workspaceOverviewValue.workspace.primaryGroupID, name: "Group")]
    }

    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        WorkspaceGroup(id: UUID(), name: name)
    }

    func listWorkspaces() async throws -> [Workspace] {
        [workspaceOverviewValue.workspace]
    }

    func listRecentNavigation(limit: Int) async throws -> [NavigationItem] {
        Array(recentNavigationValue.prefix(limit))
    }

    func recordNavigation(target: NavigationTarget) async throws {
        recordedNavigationTargets.append(target)
        switch target.kind {
        case .workspace:
            if let workspaceID = target.workspaceID, workspaceID == workspaceOverviewValue.workspace.id {
                recentNavigationValue.removeAll { $0.target == target }
                recentNavigationValue.insert(
                    NavigationItem(
                        target: .workspace(workspaceID),
                        title: workspaceOverviewValue.workspace.name,
                        subtitle: workspaceOverviewValue.workspace.folderPath
                    ),
                    at: 0
                )
            }
        case .session:
            if let sessionID = target.sessionID, sessionID == sessionValue.id {
                recentNavigationValue.removeAll { $0.target == target }
                recentNavigationValue.insert(
                    NavigationItem(
                        target: .session(sessionID),
                        title: sessionValue.isDefault ? "Default Session" : (sessionValue.name ?? "Session"),
                        subtitle: "\(workspaceOverviewValue.workspace.name) • \(sessionValue.providerID.displayName)"
                    ),
                    at: 0
                )
            }
        case .provider:
            if let workspaceID = target.workspaceID, let providerID = target.providerID {
                recentNavigationValue.removeAll { $0.target == target }
                recentNavigationValue.insert(
                    NavigationItem(
                        target: .provider(workspaceID: workspaceID, providerID: providerID),
                        title: providerID.displayName,
                        subtitle: workspaceOverviewValue.workspace.name
                    ),
                    at: 0
                )
            }
        }
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        searchResultsValue
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        workspaceOverviewRequestCount += 1
        return workspaceOverviewValue
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        providerDetailValue
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        workspaceOverviewValue.workspace
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        sessionValue
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        let namedSession = Session(
            id: UUID(),
            workspaceID: workspaceID,
            providerID: providerID,
            name: name ?? "Session 1",
            isDefault: false,
            state: .ready
        )
        sessionValue = namedSession
        screenValue = SessionScreen(session: namedSession, transcript: screenValue.transcript)
        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions + [namedSession],
            failedSessions: providerDetailValue.failedSessions
        )
        if let index = workspaceOverviewValue.providerCards.firstIndex(where: { $0.provider.id == providerID }) {
            let card = workspaceOverviewValue.providerCards[index]
            var providerCards = workspaceOverviewValue.providerCards
            providerCards[index] = WorkspaceProviderCard(
                provider: card.provider,
                health: card.health,
                defaultSession: card.defaultSession,
                alternateSessionCount: card.alternateSessionCount + 1
            )
            workspaceOverviewValue = WorkspaceOverview(workspace: workspaceOverviewValue.workspace, providerCards: providerCards)
        }
        return namedSession
    }

    func stopSession(sessionID: UUID) async throws -> Session {
        let stoppedSession = Session(
            id: sessionValue.id,
            workspaceID: sessionValue.workspaceID,
            providerID: sessionValue.providerID,
            name: sessionValue.name,
            isDefault: sessionValue.isDefault,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        sessionValue = stoppedSession
        screenValue = SessionScreen(session: stoppedSession, transcript: screenValue.transcript)
        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: stoppedSession.isDefault ? stoppedSession : providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions.map { $0.id == stoppedSession.id ? stoppedSession : $0 },
            failedSessions: providerDetailValue.failedSessions
        )
        return stoppedSession
    }

    func deleteSessionRecord(sessionID: UUID) async throws -> Bool {
        guard sessionValue.id == sessionID, sessionValue.state != .ready else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stop the session before deleting its record"])
        }

        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: sessionValue.isDefault ? nil : providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions.filter { $0.id != sessionID },
            failedSessions: providerDetailValue.failedSessions.filter { $0.id != sessionID }
        )
        if let index = workspaceOverviewValue.providerCards.firstIndex(where: { $0.provider.id == sessionValue.providerID }) {
            let card = workspaceOverviewValue.providerCards[index]
            var providerCards = workspaceOverviewValue.providerCards
            providerCards[index] = WorkspaceProviderCard(
                provider: card.provider,
                health: card.health,
                defaultSession: card.defaultSession,
                alternateSessionCount: max(0, card.alternateSessionCount - 1)
            )
            workspaceOverviewValue = WorkspaceOverview(workspace: workspaceOverviewValue.workspace, providerCards: providerCards)
        }
        return true
    }

    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        guard sessionValue.id == sessionID else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        return screenValue
    }

    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation {
        let observationID = UUID()
        observedScreenHandlers[observationID] = onUpdate
        onUpdate(screenValue)
        return TestSessionScreenObservation { [weak self] in
            self?.observedScreenHandlers.removeValue(forKey: observationID)
        }
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        screenValue = SessionScreen(session: sessionValue, transcript: screenValue.transcript + "\n> \(text)")
        return screenValue
    }

    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        screenValue = SessionScreen(session: sessionValue, transcript: screenValue.transcript + "[typed: \(text)]")
        return screenValue
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        screenValue = SessionScreen(session: sessionValue, transcript: screenValue.transcript + "[key: \(key.rawValue)]")
        return screenValue
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            transcript: screenValue.transcript,
            terminalColumns: columns,
            terminalRows: rows
        )
        return screenValue
    }

    func emitObservedScreen(_ screen: SessionScreen) async {
        sessionValue = screen.session
        screenValue = screen
        let handlers = observedScreenHandlers.values
        for handler in handlers {
            handler(screen)
        }
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

    func listRecentNavigation(limit: Int) async throws -> [NavigationItem] {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func recordNavigation(target: NavigationTarget) async throws {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func stopSession(sessionID: UUID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func deleteSessionRecord(sessionID: UUID) async throws -> Bool {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }
}

private final class TestSessionScreenObservation: SessionScreenObservation, @unchecked Sendable {
    private let onCancel: @Sendable () -> Void
    private let cancellationState = TestObservationCancellationState()

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() async {
        guard await cancellationState.beginCancellation() else {
            return
        }

        onCancel()
    }
}

private actor TestObservationCancellationState {
    private var isCancelled = false

    func beginCancellation() -> Bool {
        guard isCancelled == false else {
            return false
        }

        isCancelled = true
        return true
    }
}
