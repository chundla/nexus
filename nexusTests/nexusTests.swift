import Foundation
import NexusDomain
import NexusIPC
import NexusService
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
        #expect(overview.providerCards.map(\.health.state) == [.notChecked, .notChecked, .notChecked, .notChecked])
        #expect(overview.providerCards.map(\.defaultSession.state) == [.notCreated, .notCreated, .notCreated, .notCreated])
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
}
