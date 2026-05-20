wrimport Foundation
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
            )
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
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
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
}
