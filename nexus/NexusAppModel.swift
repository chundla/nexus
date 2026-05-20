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
    var workspaceOverviews: [UUID: WorkspaceOverview] = [:]
    var focusedSessionScreen: SessionScreen?

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

            let loadedServiceStatus = try await serviceStatus
            let loadedWorkspaceGroups = try await workspaceGroups
            let loadedWorkspaces = try await workspaces

            var loadedWorkspaceOverviews: [UUID: WorkspaceOverview] = [:]
            for workspace in loadedWorkspaces {
                loadedWorkspaceOverviews[workspace.id] = try await client.getWorkspaceOverview(workspaceID: workspace.id)
            }

            self.serviceStatus = loadedServiceStatus
            self.workspaceGroups = loadedWorkspaceGroups
            self.workspaces = loadedWorkspaces
            self.workspaceOverviews = loadedWorkspaceOverviews
            self.serviceErrorMessage = nil
        } catch {
            serviceStatus = nil
            workspaceGroups = []
            workspaces = []
            workspaceOverviews = [:]
            focusedSessionScreen = nil
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
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        workspaces.append(workspace)
        workspaceOverviews[workspace.id] = overview
        return workspace
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: providerID)
        focusedSessionScreen = try await client.getSessionScreen(sessionID: session.id)
        try await refreshWorkspaceOverview(for: workspaceID)
        return session
    }

    func loadSessionScreen(sessionID: UUID) async throws {
        let screen = try await client.getSessionScreen(sessionID: sessionID)
        let previousState = focusedSessionScreen?.session.id == screen.session.id
            ? focusedSessionScreen?.session.state
            : nil
        focusedSessionScreen = screen

        if let previousState, previousState != screen.session.state {
            try await refreshWorkspaceOverview(for: screen.session.workspaceID)
        }
    }

    func refreshFocusedSession() async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        try await loadSessionScreen(sessionID: sessionID)
    }

    func relaunchFocusedSession() async throws -> Session {
        guard let screen = focusedSessionScreen else {
            throw NSError(domain: "NexusAppModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No focused session to relaunch"])
        }

        return try await launchOrResumeDefaultSession(
            workspaceID: screen.session.workspaceID,
            providerID: screen.session.providerID
        )
    }

    func sendInputToFocusedSession(_ text: String) async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        let screen = try await client.sendSessionInput(sessionID: sessionID, text: text)
        focusedSessionScreen = screen
    }

    func sendTypedTextToFocusedSession(_ text: String) async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        let screen = try await client.sendSessionText(sessionID: sessionID, text: text)
        focusedSessionScreen = screen
    }

    func sendInputKeyToFocusedSession(_ key: SessionInputKey) async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        let screen = try await client.sendSessionInputKey(sessionID: sessionID, key: key)
        focusedSessionScreen = screen
    }

    func resizeFocusedSession(columns: Int, rows: Int) async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        let screen = try await client.resizeSession(sessionID: sessionID, columns: columns, rows: rows)
        focusedSessionScreen = screen
    }

    func workspaceGroupName(for groupID: UUID) -> String? {
        workspaceGroups.first(where: { $0.id == groupID })?.name
    }

    func workspaceOverview(for workspaceID: UUID) -> WorkspaceOverview? {
        workspaceOverviews[workspaceID]
    }

    private func refreshWorkspaceOverview(for workspaceID: UUID) async throws {
        workspaceOverviews[workspaceID] = try await client.getWorkspaceOverview(workspaceID: workspaceID)
    }
}
