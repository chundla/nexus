#if os(macOS)
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

struct SessionControllerSummary: Equatable {
    let label: String
    let message: String
}

@MainActor
@Observable
final class NexusAppModel {
    private enum RemotePairingServerBootstrapError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Remote Access server is unavailable in this Nexus build context."
        }
    }

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
    var focusedStructuredSessionDraft = ""
    private(set) var remotePairingEndpoint: RemotePairingEndpoint?

    private let client: any NexusServiceClient
    private let embeddedService: (any NexusEmbeddedServiceSession)?
    private var remotePairingServer: (any RemotePairingServing)?
    private let remotePairingServerFactory: (() throws -> any RemotePairingServing)?
    private var focusedSessionObservation: (any SessionScreenObservation)?
    private var staleWorkspaceOverviewRefreshTasks: [UUID: Task<Void, Never>] = [:]

    init(
        client: any NexusServiceClient,
        embeddedService: (any NexusEmbeddedServiceSession)? = nil,
        remotePairingServer: (any RemotePairingServing)? = nil,
        remotePairingServerFactory: (() throws -> any RemotePairingServing)? = nil
    ) {
        self.client = client
        self.embeddedService = embeddedService
        self.remotePairingServer = remotePairingServer
        self.remotePairingServerFactory = remotePairingServerFactory
        self.remotePairingEndpoint = remotePairingServer?.endpoint
    }

    nonisolated static let defaultRemoteAccessListeningPort = 9234

    nonisolated static func appBootstrapListeningPort(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int? {
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return nil
        }

        return defaultRemoteAccessListeningPort
    }

    static func live(listeningPort: Int? = 9234) throws -> NexusAppModel {
        let service = try NexusEmbeddedServiceBootstrap.bootstrap()
        let listenerEndpoint = service.listenerEndpoint
        let client = try NexusIPCClient.connect(to: listenerEndpoint)
        return NexusAppModel(client: client, embeddedService: service) {
            let remoteClient = try NexusIPCClient.connect(to: listenerEndpoint)
            return try RemotePairingServer(client: remoteClient, listeningPort: listeningPort)
        }
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

            let currentWorkspaceIDs = Set(loadedWorkspaces.map(\.id))
            self.serviceStatus = loadedServiceStatus
            self.workspaceGroups = loadedWorkspaceGroups
            self.workspaces = loadedWorkspaces
            syncHosts(loadedHosts)
            workspaceOverviews = workspaceOverviews.filter { currentWorkspaceIDs.contains($0.key) }
            providerDetails = providerDetails.filter { currentWorkspaceIDs.contains($0.key.workspaceID) }
            cancelStaleWorkspaceOverviewRefreshTasks(excluding: currentWorkspaceIDs)
            self.recentNavigation = loadedRecentNavigation
            self.remoteAccessState = loadedRemoteAccessState
            self.pairedDevices = loadedPairedDevices
            if loadedRemoteAccessState.isEnabled || loadedRemoteAccessState.activePairing != nil {
                try ensureRemotePairingServerIfAvailable()
            } else {
                stopRemotePairingServer()
            }
            self.serviceErrorMessage = nil

            let client = self.client
            try await withThrowingTaskGroup(of: WorkspaceOverview.self) { group in
                for workspaceID in loadedWorkspaces.map(\.id) {
                    group.addTask {
                        try await client.getWorkspaceOverview(workspaceID: workspaceID)
                    }
                }

                for try await overview in group {
                    applyWorkspaceOverview(overview)
                }
            }
        } catch {
            await stopFocusingSession()
            cancelStaleWorkspaceOverviewRefreshTasks()
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
            focusedStructuredSessionDraft = ""
            serviceErrorMessage = error.localizedDescription
        }
    }

    func refreshServiceStatus() async {
        await refresh()
    }

    func refreshRemoteAccess() async throws {
        async let remoteAccessState = client.getRemoteAccessState()
        async let pairedDevices = client.listPairedDevices()
        let loadedRemoteAccessState = try await remoteAccessState
        let loadedPairedDevices = try await pairedDevices
        self.remoteAccessState = loadedRemoteAccessState
        self.pairedDevices = loadedPairedDevices

        if loadedRemoteAccessState.isEnabled || loadedRemoteAccessState.activePairing != nil {
            try ensureRemotePairingServerIfAvailable()
        } else {
            stopRemotePairingServer()
        }
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState {
        let state = try await client.setRemoteAccessEnabled(isEnabled)
        remoteAccessState = state
        if state.isEnabled {
            try ensureRemotePairingServerIfAvailable()
        } else {
            stopRemotePairingServer()
        }
        return state
    }

    func startPairing() async throws -> PairingCeremony {
        try requireRemotePairingServer()
        let pairing = try await client.startPairing()
        remoteAccessState = RemoteAccessState(isEnabled: remoteAccessState?.isEnabled ?? true, activePairing: pairing)
        return pairing
    }

    private func ensureRemotePairingServerIfAvailable() throws {
        if let remotePairingServer {
            remotePairingEndpoint = remotePairingServer.endpoint
            return
        }
        guard let remotePairingServerFactory else {
            return
        }
        let remotePairingServer = try remotePairingServerFactory()
        self.remotePairingServer = remotePairingServer
        remotePairingEndpoint = remotePairingServer.endpoint
    }

    private func requireRemotePairingServer() throws {
        try ensureRemotePairingServerIfAvailable()
        guard remotePairingServer != nil else {
            throw RemotePairingServerBootstrapError.unavailable
        }
    }

    private func stopRemotePairingServer() {
        remotePairingServer = nil
        remotePairingEndpoint = nil
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
            Self.debugLog("focusSession skip existing observation session=\(sessionID.uuidString)")
            return
        }

        Self.debugLog("focusSession start session=\(sessionID.uuidString)")
        await stopFocusingSession()
        let observation = try await client.observeSessionScreen(sessionID: sessionID) { [weak self] screen in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                Self.debugLog("focusSession onUpdate session=\(screen.session.id.uuidString) items=\(screen.activityItems.count) providerEvents=\(screen.providerEvents.count) inProgress=\(screen.isAgentTurnInProgress) state=\(String(describing: screen.session.state))")
                try? await self.applyFocusedSessionScreen(screen)
            }
        }
        focusedSessionObservation = observation
        Self.debugLog("focusSession observation established session=\(sessionID.uuidString)")
    }

    func stopFocusingSession() async {
        let focusedSessionID = focusedSessionScreen?.session.id.uuidString ?? "nil"
        let hadObservation = focusedSessionObservation != nil
        Self.debugLog("stopFocusingSession session=\(focusedSessionID) hadObservation=\(hadObservation)")
        let observation = focusedSessionObservation
        focusedSessionObservation = nil
        if let observation {
            await observation.cancel()
            Self.debugLog("stopFocusingSession cancelled session=\(focusedSessionID)")
        }
    }

    func detachFocusedSession() async -> Session? {
        let session = focusedSessionScreen?.session
        await stopFocusingSession()
        focusedSessionScreen = nil
        focusedStructuredSessionDraft = ""
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

    func respondToFocusedSessionApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        let screen = try await client.respondToApprovalRequest(
            sessionID: sessionID,
            approvalRequestID: approvalRequestID,
            decision: decision
        )
        focusedSessionScreen = screen
    }

    func respondToFocusedSessionExtensionDialog(_ dialogID: String, response: SessionExtensionUIDialogResponse) async throws {
        guard let sessionID = focusedSessionScreen?.session.id else {
            return
        }

        let screen = try await client.respondToExtensionDialog(
            sessionID: sessionID,
            dialogID: dialogID,
            response: response
        )
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

    var focusedSessionControllerSummary: SessionControllerSummary? {
        guard let controller = focusedSessionScreen?.controller else {
            return nil
        }

        return controllerSummary(for: controller)
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

    func controllerSummary(for controller: SessionController) -> SessionControllerSummary {
        switch controller {
        case .mac:
            return SessionControllerSummary(
                label: "This Mac",
                message: "This Mac is the Controller. Remote Clients can view or take Controller."
            )
        case .pairedDevice(let pairedDeviceID):
            let deviceName = pairedDevices.first(where: { $0.id == pairedDeviceID })?.name ?? "Paired Device"
            return SessionControllerSummary(
                label: deviceName,
                message: "\(deviceName) is the Controller. Input on this Mac reclaims Controller."
            )
        }
    }

    private func refreshWorkspaceOverview(for workspaceID: UUID) async throws {
        let overview = try await client.refreshWorkspaceOverview(workspaceID: workspaceID)
        applyWorkspaceOverview(overview)
    }

    private func applyWorkspaceOverview(_ overview: WorkspaceOverview) {
        workspaceOverviews[overview.workspace.id] = overview
        syncStaleWorkspaceOverviewRefreshTask(for: overview)
    }

    private func syncStaleWorkspaceOverviewRefreshTask(for overview: WorkspaceOverview) {
        let workspaceID = overview.workspace.id

        guard overview.usesStaleBrowseFacts else {
            staleWorkspaceOverviewRefreshTasks[workspaceID]?.cancel()
            staleWorkspaceOverviewRefreshTasks.removeValue(forKey: workspaceID)
            return
        }

        guard staleWorkspaceOverviewRefreshTasks[workspaceID] == nil else {
            return
        }

        staleWorkspaceOverviewRefreshTasks[workspaceID] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { staleWorkspaceOverviewRefreshTasks.removeValue(forKey: workspaceID) }

            guard let refreshedOverview = try? await client.refreshWorkspaceOverview(workspaceID: workspaceID) else {
                return
            }

            applyWorkspaceOverview(refreshedOverview)
        }
    }

    private func cancelStaleWorkspaceOverviewRefreshTasks(excluding workspaceIDs: Set<UUID>) {
        for (workspaceID, task) in staleWorkspaceOverviewRefreshTasks where workspaceIDs.contains(workspaceID) == false {
            task.cancel()
            staleWorkspaceOverviewRefreshTasks.removeValue(forKey: workspaceID)
        }
    }

    private func cancelStaleWorkspaceOverviewRefreshTasks() {
        for task in staleWorkspaceOverviewRefreshTasks.values {
            task.cancel()
        }
        staleWorkspaceOverviewRefreshTasks.removeAll()
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
        let previousScreen = focusedSessionScreen?.session.id == screen.session.id ? focusedSessionScreen : nil
        let previousState = previousScreen?.session.state
        Self.debugLog("applyFocusedSessionScreen session=\(screen.session.id.uuidString) prevItems=\(previousScreen?.activityItems.count ?? -1) items=\(screen.activityItems.count) prevProviderEvents=\(previousScreen?.providerEvents.count ?? -1) providerEvents=\(screen.providerEvents.count) prevState=\(String(describing: previousState)) state=\(String(describing: screen.session.state)) inProgress=\(screen.isAgentTurnInProgress) lastItem=\(Self.debugActivitySummary(screen.activityItems.last))")
        focusedSessionScreen = screen

        if previousScreen?.extensionUI?.editorText != screen.extensionUI?.editorText,
           let editorText = screen.extensionUI?.editorText {
            focusedStructuredSessionDraft = editorText
            Self.debugLog("applyFocusedSessionScreen synced editorText session=\(screen.session.id.uuidString) length=\(editorText.count)")
        }

        if let previousState, previousState != screen.session.state {
            Self.debugLog("applyFocusedSessionScreen state transition session=\(screen.session.id.uuidString) from=\(String(describing: previousState)) to=\(String(describing: screen.session.state))")
            try await refreshWorkspaceOverview(for: screen.session.workspaceID)
            try await refreshProviderDetailIfLoaded(
                workspaceID: screen.session.workspaceID,
                providerID: screen.session.providerID
            )
        }
    }
}

private extension NexusAppModel {
    static func debugLog(_ message: String) {
        NSLog("[DEBUG-MACBLANK] %@", message)
    }

    static func debugActivitySummary(_ item: SessionActivityItem?) -> String {
        guard let item else {
            return "nil"
        }

        let text = item.detailText ?? item.text
        let snippet = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .prefix(80)
        return "\(item.kind.rawValue):\(snippet)"
    }
}

struct ProviderDetailKey: Hashable {
    let workspaceID: UUID
    let providerID: ProviderID
}
#endif
