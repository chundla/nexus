import Foundation
import NexusDomain
import NexusIPC
import NexusService
import Observation

struct SessionPresentationContext: Equatable {
    let workspace: Workspace
    let host: NexusDomain.Host?

    var isRemote: Bool {
        workspace.kind == .remote
    }

    var hostName: String? {
        host?.name
    }

    var remotePath: String? {
        isRemote ? workspace.folderPath : nil
    }

    var targetSummary: String {
        host.map { "\($0.name) • \(workspace.folderPath)" } ?? workspace.folderPath
    }
}

@MainActor
@Observable
final class NexusAppModel {
    var serviceStatus: NexusServiceStatus?
    var serviceErrorMessage: String?
    var workspaceGroups: [WorkspaceGroup] = []
    var workspaces: [Workspace] = []
    var hosts: [NexusDomain.Host] = []
    var workspaceOverviews: [UUID: WorkspaceOverview] = [:]
    var hostDetails: [UUID: HostDetail] = [:]
    var providerDetails: [ProviderDetailKey: ProviderDetail] = [:]
    var recentNavigation: [NavigationItem] = []
    var remoteAccessState: RemoteAccessState?
    var pairedDevices: [PairedDevice] = []
    var focusedSessionScreen: SessionScreen?

    private let client: NexusServiceClient
    private let embeddedService: (any NexusEmbeddedServiceSession)?
    private var focusedSessionObservation: (any SessionScreenObservation)?

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
            async let hosts = client.listHosts()
            async let recentNavigation = client.listRecentNavigation(limit: 10)
            async let remoteAccessState = client.getRemoteAccessState()
            async let pairedDevices = client.listPairedDevices()

            let loadedServiceStatus = try await serviceStatus
            let loadedWorkspaceGroups = try await workspaceGroups
            let loadedWorkspaces = try await workspaces
            let loadedHosts = try await hosts
            let loadedRecentNavigation = try await recentNavigation
            let loadedRemoteAccessState = try await remoteAccessState
            let loadedPairedDevices = try await pairedDevices

            var loadedWorkspaceOverviews: [UUID: WorkspaceOverview] = [:]
            for workspace in loadedWorkspaces {
                loadedWorkspaceOverviews[workspace.id] = try await client.getWorkspaceOverview(workspaceID: workspace.id)
            }

            self.serviceStatus = loadedServiceStatus
            self.workspaceGroups = loadedWorkspaceGroups
            self.workspaces = loadedWorkspaces
            syncHosts(loadedHosts)
            self.workspaceOverviews = loadedWorkspaceOverviews
            self.providerDetails = [:]
            self.recentNavigation = loadedRecentNavigation
            self.remoteAccessState = loadedRemoteAccessState
            self.pairedDevices = loadedPairedDevices
            self.serviceErrorMessage = nil
        } catch {
            await stopFocusingSession()
            serviceStatus = nil
            workspaceGroups = []
            workspaces = []
            hosts = []
            workspaceOverviews = [:]
            hostDetails = [:]
            providerDetails = [:]
            recentNavigation = []
            remoteAccessState = nil
            pairedDevices = []
            focusedSessionScreen = nil
            serviceErrorMessage = error.localizedDescription
        }
    }

    func refreshServiceStatus() async {
        await refresh()
    }

    func refreshRemoteAccess() async throws {
        async let remoteAccessState = client.getRemoteAccessState()
        async let pairedDevices = client.listPairedDevices()
        self.remoteAccessState = try await remoteAccessState
        self.pairedDevices = try await pairedDevices
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState {
        let state = try await client.setRemoteAccessEnabled(isEnabled)
        remoteAccessState = state
        return state
    }

    func startPairing() async throws -> PairingCeremony {
        let pairing = try await client.startPairing()
        remoteAccessState = RemoteAccessState(isEnabled: remoteAccessState?.isEnabled ?? true, activePairing: pairing)
        return pairing
    }

    func revokePairedDevice(deviceID: UUID) async throws -> Bool {
        let revoked = try await client.revokePairedDevice(deviceID: deviceID)
        guard revoked else {
            return false
        }

        pairedDevices.removeAll { $0.id == deviceID }
        return true
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

    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace {
        let workspace = try await client.createRemoteWorkspace(
            name: name,
            hostID: hostID,
            remotePath: remotePath,
            primaryGroupID: primaryGroupID
        )
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        workspaces.append(workspace)
        workspaceOverviews[workspace.id] = overview
        return workspace
    }

    func refreshHosts() async throws {
        syncHosts(try await client.listHosts())
    }

    func loadHostDetail(hostID: UUID) async throws {
        hostDetails[hostID] = try await client.getHostDetail(hostID: hostID)
    }

    func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        let host = try await client.createHost(name: name, sshTarget: sshTarget, port: port)
        hosts.append(host)
        hostDetails[host.id] = HostDetail(host: host, latestValidation: nil)
        return host
    }

    func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        let host = try await client.updateHost(hostID: hostID, name: name, sshTarget: sshTarget, port: port)
        if let index = hosts.firstIndex(where: { $0.id == hostID }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        hostDetails[hostID] = HostDetail(host: host, latestValidation: nil)
        return host
    }

    func validateHost(hostID: UUID) async throws -> HostValidationSnapshot {
        let snapshot = try await client.validateHost(hostID: hostID)
        if let host = hosts.first(where: { $0.id == hostID }) {
            hostDetails[hostID] = HostDetail(host: host, latestValidation: snapshot)
        } else {
            hostDetails[hostID] = try await client.getHostDetail(hostID: hostID)
        }

        let impactedWorkspaceIDs = workspaces
            .filter { $0.remoteHostID == hostID }
            .map(\.id)
        for workspaceID in impactedWorkspaceIDs {
            try await refreshWorkspaceOverview(for: workspaceID)
        }

        return snapshot
    }

    func deleteHost(hostID: UUID) async throws -> Bool {
        let deleted = try await client.deleteHost(hostID: hostID)
        guard deleted else {
            return false
        }

        hosts.removeAll { $0.id == hostID }
        hostDetails.removeValue(forKey: hostID)
        return true
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: providerID)
        try await focusSession(sessionID: session.id)
        try await refreshWorkspaceOverview(for: workspaceID)
        try await refreshProviderDetailIfLoaded(workspaceID: workspaceID, providerID: providerID)
        return session
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String? = nil) async throws -> Session {
        let session = try await client.createNamedSession(workspaceID: workspaceID, providerID: providerID, name: name)
        try await focusSession(sessionID: session.id)
        try await refreshWorkspaceOverview(for: workspaceID)
        try await refreshProviderDetail(workspaceID: workspaceID, providerID: providerID)
        return session
    }

    func launchOrResumeSession(sessionID: UUID, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let session = try await client.launchOrResumeSession(sessionID: sessionID)
        try await focusSession(sessionID: session.id)
        try await refreshWorkspaceOverview(for: workspaceID)
        try await refreshProviderDetailIfLoaded(workspaceID: workspaceID, providerID: providerID)
        return session
    }

    func stopSession(sessionID: UUID, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let session = try await client.stopSession(sessionID: sessionID)
        if focusedSessionScreen?.session.id == sessionID {
            try await refreshFocusedSession()
        }
        try await refreshWorkspaceOverview(for: workspaceID)
        try await refreshProviderDetail(workspaceID: workspaceID, providerID: providerID)
        return session
    }

    func deleteSessionRecord(sessionID: UUID, workspaceID: UUID, providerID: ProviderID) async throws -> Bool {
        let deleted = try await client.deleteSessionRecord(sessionID: sessionID)
        guard deleted else {
            return false
        }

        if focusedSessionScreen?.session.id == sessionID {
            await stopFocusingSession()
            focusedSessionScreen = nil
        }
        try await refreshWorkspaceOverview(for: workspaceID)
        try await refreshProviderDetail(workspaceID: workspaceID, providerID: providerID)
        return true
    }

    func loadProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws {
        try await refreshProviderDetail(workspaceID: workspaceID, providerID: providerID)
    }

    func focusSession(sessionID: UUID) async throws {
        if focusedSessionScreen?.session.id == sessionID, focusedSessionObservation != nil {
            return
        }

        await stopFocusingSession()
        let observation = try await client.observeSessionScreen(sessionID: sessionID) { [weak self] screen in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                try? await self.applyFocusedSessionScreen(screen)
            }
        }
        focusedSessionObservation = observation
    }

    func stopFocusingSession() async {
        let observation = focusedSessionObservation
        focusedSessionObservation = nil
        if let observation {
            await observation.cancel()
        }
    }

    func detachFocusedSession() async -> Session? {
        let session = focusedSessionScreen?.session
        await stopFocusingSession()
        focusedSessionScreen = nil
        return session
    }

    func loadSessionScreen(sessionID: UUID) async throws {
        let screen = try await client.getSessionScreen(sessionID: sessionID)
        try await applyFocusedSessionScreen(screen)
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

        return try await launchOrResumeSession(
            sessionID: screen.session.id,
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

    func loadRecentNavigation() async throws {
        recentNavigation = try await client.listRecentNavigation(limit: 10)
    }

    func recordNavigation(_ target: NavigationTarget) async throws {
        try await client.recordNavigation(target: target)
        try await loadRecentNavigation()
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        try await client.searchNavigation(query: query)
    }

    func workspaceGroupName(for groupID: UUID) -> String? {
        workspaceGroups.first(where: { $0.id == groupID })?.name
    }

    func workspaceOverview(for workspaceID: UUID) -> WorkspaceOverview? {
        workspaceOverviews[workspaceID]
    }

    func workspaceTargetSummary(for workspace: Workspace) -> String {
        guard let hostName = workspaceHostName(for: workspace) else {
            return workspace.folderPath
        }

        return "\(hostName) • \(workspace.folderPath)"
    }

    func workspaceHostName(for workspace: Workspace) -> String? {
        guard workspace.kind == .remote,
              let hostID = workspace.remoteHostID else {
            return nil
        }

        return hosts.first(where: { $0.id == hostID })?.name
    }

    func hostDetail(for hostID: UUID) -> HostDetail? {
        hostDetails[hostID]
    }

    func providerDetail(for workspaceID: UUID, providerID: ProviderID) -> ProviderDetail? {
        providerDetails[ProviderDetailKey(workspaceID: workspaceID, providerID: providerID)]
    }

    var focusedSessionPresentationContext: SessionPresentationContext? {
        guard let session = focusedSessionScreen?.session else {
            return nil
        }

        return sessionPresentationContext(for: session)
    }

    func sessionPresentationContext(for session: Session) -> SessionPresentationContext? {
        guard let workspace = workspaces.first(where: { $0.id == session.workspaceID }) else {
            return nil
        }

        let host = workspace.remoteHostID.flatMap { hostID in
            hosts.first(where: { $0.id == hostID })
        }
        return SessionPresentationContext(workspace: workspace, host: host)
    }

    private func refreshWorkspaceOverview(for workspaceID: UUID) async throws {
        workspaceOverviews[workspaceID] = try await client.getWorkspaceOverview(workspaceID: workspaceID)
    }

    private func syncHosts(_ loadedHosts: [NexusDomain.Host]) {
        hosts = loadedHosts
        hostDetails = hostDetails.reduce(into: [:]) { result, entry in
            guard let host = loadedHosts.first(where: { $0.id == entry.key }) else {
                return
            }
            result[entry.key] = HostDetail(host: host, latestValidation: entry.value.latestValidation)
        }
    }

    private func refreshProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws {
        providerDetails[ProviderDetailKey(workspaceID: workspaceID, providerID: providerID)] = try await client.getProviderDetail(
            workspaceID: workspaceID,
            providerID: providerID
        )
    }

    private func refreshProviderDetailIfLoaded(workspaceID: UUID, providerID: ProviderID) async throws {
        let key = ProviderDetailKey(workspaceID: workspaceID, providerID: providerID)
        guard providerDetails[key] != nil else {
            return
        }

        try await refreshProviderDetail(workspaceID: workspaceID, providerID: providerID)
    }

    private func applyFocusedSessionScreen(_ screen: SessionScreen) async throws {
        let previousState = focusedSessionScreen?.session.id == screen.session.id
            ? focusedSessionScreen?.session.state
            : nil
        focusedSessionScreen = screen

        if let previousState, previousState != screen.session.state {
            try await refreshWorkspaceOverview(for: screen.session.workspaceID)
            try await refreshProviderDetailIfLoaded(
                workspaceID: screen.session.workspaceID,
                providerID: screen.session.providerID
            )
        }
    }
}

struct ProviderDetailKey: Hashable {
    let workspaceID: UUID
    let providerID: ProviderID
}
