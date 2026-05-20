import Foundation
import NexusDomain
import NexusIPC
import NexusService
import Observation

@MainActor
@Observable
final class NexusAppModel {
    var serviceStatus: NexusServiceStatus?
    var serviceErrorMessage: String?
    var workspaceGroups: [WorkspaceGroup] = []
    var workspaces: [Workspace] = []

    private let client: NexusServiceClient
    private let embeddedService: (any NexusEmbeddedServiceSession)?

    init(client: NexusServiceClient, embeddedService: (any NexusEmbeddedServiceSession)? = nil) {
        self.client = client
        self.embeddedService = embeddedService
    }

    static func live() throws -> NexusAppModel {
        let service = try NexusEmbeddedServiceBootstrap.bootstrap()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        return NexusAppModel(client: client, embeddedService: service)
    }

    func refresh() async {
        do {
            async let serviceStatus = client.getServiceStatus()
            async let workspaceGroups = client.listWorkspaceGroups()
            async let workspaces = client.listWorkspaces()

            self.serviceStatus = try await serviceStatus
            self.workspaceGroups = try await workspaceGroups
            self.workspaces = try await workspaces
            self.serviceErrorMessage = nil
        } catch {
            serviceStatus = nil
            workspaceGroups = []
            workspaces = []
            serviceErrorMessage = error.localizedDescription
        }
    }

    func refreshServiceStatus() async {
        await refresh()
    }

    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        let group = try await client.createWorkspaceGroup(name: name)
        workspaceGroups.append(group)
        return group
    }

    func createLocalWorkspace(folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        let workspace = try await client.createLocalWorkspace(name: nil, folderPath: folderPath, primaryGroupID: primaryGroupID)
        workspaces.append(workspace)
        return workspace
    }

    func workspaceGroupName(for groupID: UUID) -> String? {
        workspaceGroups.first(where: { $0.id == groupID })?.name
    }
}
