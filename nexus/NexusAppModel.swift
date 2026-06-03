#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
import NexusService
import NexusSessionPresentation
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

struct WorkspaceBrowseWorkspaceSummary: Equatable, Identifiable {
    let workspace: Workspace
    let targetSummary: String

    var id: UUID { workspace.id }
}

struct WorkspaceBrowseGroupSummary: Equatable, Identifiable {
    let group: WorkspaceGroup
    let workspaceCount: Int

    var id: UUID { group.id }
}

struct WorkspaceBrowseSidebarPresentation: Equatable {
    let workspaces: [WorkspaceBrowseWorkspaceSummary]
    let workspaceGroups: [WorkspaceBrowseGroupSummary]
}

struct WorkspaceBrowseDetailPresentation: Equatable {
    let workspace: Workspace?
    let hostName: String?
    let groupName: String?
    let overview: WorkspaceOverview?
}

struct WorkspaceGroupDetailPresentation: Equatable {
    let group: WorkspaceGroup?
    let workspaces: [WorkspaceBrowseWorkspaceSummary]
}

struct WorkspaceHomePresentation: Equatable {
    let recentWorkspaces: [WorkspaceBrowseWorkspaceSummary]
    let serviceStatus: NexusServiceStatus?
    let serviceErrorMessage: String?
    let workspaceCount: Int
    let workspaceGroupCount: Int
    let hostCount: Int
}

enum WorkspaceBrowseInitialSelection: Equatable {
    case workspace(UUID)
    case workspaceGroup(UUID)
}

struct WorkspaceBrowseNavigationPresentation: Equatable {
    let initialSelection: WorkspaceBrowseInitialSelection?
    let quickSwitchItems: [NavigationItem]
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
    private(set) var focusedStructuredSessionPresentation: FocusedStructuredSessionPresentation?
    private(set) var focusedStructuredSessionChromePresentation: FocusedStructuredSessionChromePresentation?
    private(set) var focusedSessionID: UUID?
    private(set) var focusedSessionWorkspaceID: UUID?
    private(set) var remotePairingEndpoint: RemotePairingEndpoint?
    private var recentNavigationSessionWorkspaceIDs: [UUID: UUID] = [:]

    private let client: any NexusServiceClient
    private let embeddedService: (any NexusEmbeddedServiceSession)?
    private var remotePairingServer: (any RemotePairingServing)?
    private let focusedStructuredSessionPresenter = FocusedStructuredSessionPresenter()
    private let remotePairingServerFactory: (() throws -> any RemotePairingServing)?
    private var focusedSessionObservation: (any SessionScreenObservation)?
    private var staleWorkspaceOverviewRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var backgroundWorkspaceOverviewLoadTask: Task<Void, Never>?
    private var workspaceOverviewRefreshGeneration: UInt64 = 0

    private static let initialWorkspaceOverviewLoadCount = 3

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
            let refreshGeneration = startWorkspaceOverviewRefresh()

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
            applyRecentNavigation(loadedRecentNavigation)
            self.remoteAccessState = loadedRemoteAccessState
            self.pairedDevices = loadedPairedDevices
            if loadedRemoteAccessState.isEnabled || loadedRemoteAccessState.activePairing != nil {
                try ensureRemotePairingServerIfAvailable()
            } else {
                stopRemotePairingServer()
            }
            self.serviceErrorMessage = nil

            let orderedWorkspaceIDs = prioritizedWorkspaceOverviewIDs(
                for: loadedWorkspaces,
                recentNavigation: loadedRecentNavigation
            )
            let immediateWorkspaceIDs = Array(orderedWorkspaceIDs.prefix(Self.initialWorkspaceOverviewLoadCount))
            let backgroundWorkspaceIDs = Array(orderedWorkspaceIDs.dropFirst(immediateWorkspaceIDs.count))

            try await loadWorkspaceOverviews(
                for: immediateWorkspaceIDs,
                refreshGeneration: refreshGeneration
            )

            guard backgroundWorkspaceIDs.isEmpty == false else {
                return
            }

            backgroundWorkspaceOverviewLoadTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                defer {
                    if self.workspaceOverviewRefreshGeneration == refreshGeneration {
                        self.backgroundWorkspaceOverviewLoadTask = nil
                    }
                }

                do {
                    try await self.loadWorkspaceOverviews(
                        for: backgroundWorkspaceIDs,
                        refreshGeneration: refreshGeneration
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        } catch {
            backgroundWorkspaceOverviewLoadTask?.cancel()
            backgroundWorkspaceOverviewLoadTask = nil
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
            recentNavigationSessionWorkspaceIDs = [:]
            remoteAccessState = nil
            pairedDevices = []
            focusedSessionScreen = nil
            syncFocusedStructuredSessionPresentation(for: nil)
            syncFocusedStructuredSessionChromePresentation(for: nil)
            focusedSessionID = nil
            focusedSessionWorkspaceID = nil
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
            syncFocusedStructuredSessionPresentation(for: nil)
            syncFocusedStructuredSessionChromePresentation(for: nil)
            focusedSessionID = nil
            focusedSessionWorkspaceID = nil
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
        focusedSessionID = sessionID
        if focusedSessionScreen?.session.id != sessionID {
            focusedSessionWorkspaceID = nil
        }
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
        syncFocusedStructuredSessionPresentation(for: nil)
        syncFocusedStructuredSessionChromePresentation(for: nil)
        focusedSessionID = nil
        focusedSessionWorkspaceID = nil
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
        guard let baselineScreen = focusedSessionScreen else {
            return
        }

        let screen = try await client.sendSessionInput(sessionID: baselineScreen.session.id, text: text)
        try await applyFocusedSessionActionResponse(screen, ifCurrentScreenMatches: baselineScreen)
    }

    func sendTypedTextToFocusedSession(_ text: String) async throws {
        guard let baselineScreen = focusedSessionScreen else {
            return
        }

        let screen = try await client.sendSessionText(sessionID: baselineScreen.session.id, text: text)
        try await applyFocusedSessionActionResponse(screen, ifCurrentScreenMatches: baselineScreen)
    }

    func sendInputKeyToFocusedSession(_ key: SessionInputKey) async throws {
        guard let baselineScreen = focusedSessionScreen else {
            return
        }

        let screen = try await client.sendSessionInputKey(sessionID: baselineScreen.session.id, key: key)
        try await applyFocusedSessionActionResponse(screen, ifCurrentScreenMatches: baselineScreen)
    }

    func respondToFocusedSessionApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws {
        guard let baselineScreen = focusedSessionScreen else {
            return
        }

        let screen = try await client.respondToApprovalRequest(
            sessionID: baselineScreen.session.id,
            approvalRequestID: approvalRequestID,
            decision: decision
        )
        try await applyFocusedSessionActionResponse(screen, ifCurrentScreenMatches: baselineScreen)
    }

    func respondToFocusedSessionExtensionDialog(_ dialogID: String, response: SessionExtensionUIDialogResponse) async throws {
        guard let baselineScreen = focusedSessionScreen else {
            return
        }

        let screen = try await client.respondToExtensionDialog(
            sessionID: baselineScreen.session.id,
            dialogID: dialogID,
            response: response
        )
        try await applyFocusedSessionActionResponse(screen, ifCurrentScreenMatches: baselineScreen)
    }

    func resizeFocusedSession(columns: Int, rows: Int) async throws {
        guard let baselineScreen = focusedSessionScreen else {
            return
        }

        let screen = try await client.resizeSession(sessionID: baselineScreen.session.id, columns: columns, rows: rows)
        try await applyFocusedSessionActionResponse(screen, ifCurrentScreenMatches: baselineScreen)
    }

    func loadRecentNavigation() async throws {
        applyRecentNavigation(try await client.listRecentNavigation(limit: 10))
    }

    func recordNavigation(_ target: NavigationTarget) async throws {
        try await client.recordNavigation(target: target)
        try await loadRecentNavigation()
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        try await client.searchNavigation(query: query)
    }

    func workspaceBrowseSidebarPresentation(currentWorkspaceID: UUID?) -> WorkspaceBrowseSidebarPresentation {
        let ranking = workspaceBrowseRecencyRanking(currentWorkspaceID: currentWorkspaceID)
        let workspaceSummaries = workspaces
            .sorted { lhs, rhs in
                let lhsRank = ranking[lhs.id] ?? Int.max
                let rhsRank = ranking[rhs.id] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { workspace in
                WorkspaceBrowseWorkspaceSummary(
                    workspace: workspace,
                    targetSummary: workspaceTargetSummary(for: workspace)
                )
            }
        let groupSummaries = workspaceGroups
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { group in
                WorkspaceBrowseGroupSummary(
                    group: group,
                    workspaceCount: workspaces.filter { $0.primaryGroupID == group.id }.count
                )
            }

        return WorkspaceBrowseSidebarPresentation(
            workspaces: workspaceSummaries,
            workspaceGroups: groupSummaries
        )
    }

    func workspaceBrowseDetailPresentation(workspaceID: UUID) -> WorkspaceBrowseDetailPresentation {
        let workspace = workspaces.first(where: { $0.id == workspaceID })
        return WorkspaceBrowseDetailPresentation(
            workspace: workspace,
            hostName: workspace.flatMap { workspaceHostName(for: $0) },
            groupName: workspace.flatMap { workspaceGroupName(for: $0.primaryGroupID) },
            overview: workspaceOverview(for: workspaceID)
        )
    }

    func workspaceGroupDetailPresentation(groupID: UUID) -> WorkspaceGroupDetailPresentation {
        WorkspaceGroupDetailPresentation(
            group: workspaceGroups.first(where: { $0.id == groupID }),
            workspaces: workspaces
                .filter { $0.primaryGroupID == groupID }
                .map { workspace in
                    WorkspaceBrowseWorkspaceSummary(
                        workspace: workspace,
                        targetSummary: workspaceTargetSummary(for: workspace)
                    )
                }
        )
    }

    func workspaceHomePresentation() -> WorkspaceHomePresentation {
        WorkspaceHomePresentation(
            recentWorkspaces: workspaceBrowseSidebarPresentation(currentWorkspaceID: nil).workspaces,
            serviceStatus: serviceStatus,
            serviceErrorMessage: serviceErrorMessage,
            workspaceCount: workspaces.count,
            workspaceGroupCount: workspaceGroups.count,
            hostCount: hosts.count
        )
    }

    func workspaceBrowseNavigationPresentation(currentWorkspaceID: UUID?) -> WorkspaceBrowseNavigationPresentation {
        let sidebarPresentation = workspaceBrowseSidebarPresentation(currentWorkspaceID: currentWorkspaceID)
        let initialSelection = sidebarPresentation.workspaces.first.map { WorkspaceBrowseInitialSelection.workspace($0.workspace.id) }
            ?? sidebarPresentation.workspaceGroups.first.map { WorkspaceBrowseInitialSelection.workspaceGroup($0.group.id) }
        let quickSwitchItems = sidebarPresentation.workspaces.map { summary in
            NavigationItem(
                target: .workspace(summary.workspace.id),
                title: summary.workspace.name,
                subtitle: summary.targetSummary
            )
        }

        return WorkspaceBrowseNavigationPresentation(
            initialSelection: initialSelection,
            quickSwitchItems: quickSwitchItems
        )
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
        guard let workspaceID = focusedSessionWorkspaceID,
              let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return nil
        }

        let host = workspace.remoteHostID.flatMap { hostID in
            hosts.first(where: { $0.id == hostID })
        }
        return SessionPresentationContext(workspace: workspace, host: host)
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

    private func startWorkspaceOverviewRefresh() -> UInt64 {
        backgroundWorkspaceOverviewLoadTask?.cancel()
        backgroundWorkspaceOverviewLoadTask = nil
        workspaceOverviewRefreshGeneration &+= 1
        return workspaceOverviewRefreshGeneration
    }

    private func loadWorkspaceOverviews(
        for workspaceIDs: [UUID],
        refreshGeneration: UInt64
    ) async throws {
        let overviews = try await client.getWorkspaceOverviews(workspaceIDs: workspaceIDs)
        applyWorkspaceOverviews(overviews, refreshGeneration: refreshGeneration)
    }

    private func prioritizedWorkspaceOverviewIDs(
        for loadedWorkspaces: [Workspace],
        recentNavigation: [NavigationItem]
    ) -> [UUID] {
        let knownWorkspacesByID = Dictionary(uniqueKeysWithValues: loadedWorkspaces.map { ($0.id, $0) })
        var orderedWorkspaceIDs: [UUID] = []
        var seenWorkspaceIDs = Set<UUID>()

        func appendWorkspaceID(_ workspaceID: UUID?) {
            guard let workspaceID,
                  knownWorkspacesByID[workspaceID] != nil,
                  seenWorkspaceIDs.insert(workspaceID).inserted else {
                return
            }
            orderedWorkspaceIDs.append(workspaceID)
        }

        appendWorkspaceID(focusedSessionWorkspaceID)

        for key in providerDetails.keys.sorted(by: { lhs, rhs in
            lhs.workspaceID.uuidString < rhs.workspaceID.uuidString
        }) {
            appendWorkspaceID(key.workspaceID)
        }

        for item in recentNavigation {
            switch item.target.kind {
            case .workspace, .provider:
                appendWorkspaceID(item.target.workspaceID)
            case .session:
                continue
            }
        }

        for workspace in loadedWorkspaces.sorted(by: { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }) {
            appendWorkspaceID(workspace.id)
        }

        return orderedWorkspaceIDs
    }

    private func applyWorkspaceOverview(
        _ overview: WorkspaceOverview,
        refreshGeneration: UInt64? = nil
    ) {
        applyWorkspaceOverviews([overview], refreshGeneration: refreshGeneration)
    }

    private func applyWorkspaceOverviews(
        _ overviews: [WorkspaceOverview],
        refreshGeneration: UInt64? = nil
    ) {
        let applicableOverviews = overviews.filter { shouldApplyWorkspaceOverview($0, refreshGeneration: refreshGeneration) }
        guard applicableOverviews.isEmpty == false else {
            return
        }

        var updatedWorkspaceOverviews = workspaceOverviews
        for overview in applicableOverviews {
            updatedWorkspaceOverviews[overview.workspace.id] = overview
        }
        workspaceOverviews = updatedWorkspaceOverviews

        for overview in applicableOverviews {
            syncRecentNavigationSessionWorkspaceIDs(for: overview)
            syncStaleWorkspaceOverviewRefreshTask(for: overview)
        }
    }

    private func shouldApplyWorkspaceOverview(
        _ overview: WorkspaceOverview,
        refreshGeneration: UInt64?
    ) -> Bool {
        guard let refreshGeneration else {
            return true
        }

        return workspaceOverviewRefreshGeneration == refreshGeneration
            && workspaces.contains(where: { $0.id == overview.workspace.id })
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

    private func applyRecentNavigation(_ items: [NavigationItem]) {
        recentNavigation = items
        syncRecentNavigationSessionWorkspaceIDs()
    }

    private func workspaceBrowseRecencyRanking(currentWorkspaceID: UUID?) -> [UUID: Int] {
        var workspaceIDs: [UUID] = []

        if let currentWorkspaceID {
            workspaceIDs.append(currentWorkspaceID)
        }

        for item in recentNavigation {
            switch item.target.kind {
            case .workspace, .provider:
                if let workspaceID = item.target.workspaceID {
                    workspaceIDs.append(workspaceID)
                }
            case .session:
                if let sessionID = item.target.sessionID,
                   let workspaceID = recentNavigationSessionWorkspaceID(for: sessionID) {
                    workspaceIDs.append(workspaceID)
                }
            }
        }

        var ranking: [UUID: Int] = [:]
        for (index, workspaceID) in workspaceIDs.enumerated() where ranking[workspaceID] == nil {
            ranking[workspaceID] = index
        }
        return ranking
    }

    private func recentNavigationSessionWorkspaceID(for sessionID: UUID) -> UUID? {
        if focusedSessionID == sessionID {
            return focusedSessionWorkspaceID
        }

        return recentNavigationSessionWorkspaceIDs[sessionID]
    }

    private func syncRecentNavigationSessionWorkspaceIDs() {
        let sessionIDs = Set(recentNavigation.compactMap(\.target.sessionID))
        recentNavigationSessionWorkspaceIDs = recentNavigationSessionWorkspaceIDs.filter { sessionIDs.contains($0.key) }

        if let focusedSessionID, let focusedSessionWorkspaceID, sessionIDs.contains(focusedSessionID) {
            recentNavigationSessionWorkspaceIDs[focusedSessionID] = focusedSessionWorkspaceID
        }

        for overview in workspaceOverviews.values {
            for sessionID in overview.providerCards.compactMap(\.defaultSession.sessionID) where sessionIDs.contains(sessionID) {
                recentNavigationSessionWorkspaceIDs[sessionID] = overview.workspace.id
            }
        }

        for detail in providerDetails.values {
            let sessionIDsInDetail = [detail.defaultSession].compactMap { $0 } + detail.alternateSessions + detail.failedSessions
            for session in sessionIDsInDetail where sessionIDs.contains(session.id) {
                recentNavigationSessionWorkspaceIDs[session.id] = detail.workspace.id
            }
        }
    }

    private func syncRecentNavigationSessionWorkspaceIDs(for overview: WorkspaceOverview) {
        let relevantSessionIDs = Set(recentNavigation.compactMap(\.target.sessionID))
        for sessionID in overview.providerCards.compactMap(\.defaultSession.sessionID) where relevantSessionIDs.contains(sessionID) {
            recentNavigationSessionWorkspaceIDs[sessionID] = overview.workspace.id
        }
    }

    private func syncRecentNavigationSessionWorkspaceIDs(for detail: ProviderDetail) {
        let relevantSessionIDs = Set(recentNavigation.compactMap(\.target.sessionID))
        let sessionIDsInDetail = [detail.defaultSession].compactMap { $0 } + detail.alternateSessions + detail.failedSessions
        for session in sessionIDsInDetail where relevantSessionIDs.contains(session.id) {
            recentNavigationSessionWorkspaceIDs[session.id] = detail.workspace.id
        }
    }

    private func refreshProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws {
        let detail = try await client.getProviderDetail(
            workspaceID: workspaceID,
            providerID: providerID
        )
        providerDetails[ProviderDetailKey(workspaceID: workspaceID, providerID: providerID)] = detail
        syncRecentNavigationSessionWorkspaceIDs(for: detail)
    }

    private func refreshProviderDetailIfLoaded(workspaceID: UUID, providerID: ProviderID) async throws {
        let key = ProviderDetailKey(workspaceID: workspaceID, providerID: providerID)
        guard providerDetails[key] != nil else {
            return
        }

        try await refreshProviderDetail(workspaceID: workspaceID, providerID: providerID)
    }

    private func applyFocusedSessionActionResponse(
        _ screen: SessionScreen,
        ifCurrentScreenMatches baselineScreen: SessionScreen
    ) async throws {
        guard let currentScreen = focusedSessionScreen,
              currentScreen.session.id == baselineScreen.session.id else {
            return
        }

        if currentScreen == baselineScreen {
            try await applyFocusedSessionScreen(screen)
            return
        }

        if let refreshedScreen = try? await client.getSessionScreen(sessionID: currentScreen.session.id) {
            guard focusedSessionScreen?.session.id == currentScreen.session.id else {
                return
            }

            try await applyFocusedSessionScreen(refreshedScreen)
            return
        }

        let advances = actionResponseAppearsToAdvanceFocusedSession(screen, beyond: currentScreen)
        guard advances else {
            return
        }

        try await applyFocusedSessionScreen(screen)
    }

    private func actionResponseAppearsToAdvanceFocusedSession(
        _ candidateScreen: SessionScreen,
        beyond currentScreen: SessionScreen
    ) -> Bool {
        guard candidateScreen.session.id == currentScreen.session.id else {
            return false
        }

        if candidateScreen == currentScreen {
            return true
        }

        if currentScreen.isAgentTurnInProgress, candidateScreen.isAgentTurnInProgress == false {
            return true
        }

        if candidateScreen.activityItems.count > currentScreen.activityItems.count {
            return true
        }

        if candidateScreen.transcript.count > currentScreen.transcript.count {
            return true
        }

        if candidateScreen.providerEvents.count > currentScreen.providerEvents.count {
            return true
        }

        return false
    }

    private func applyFocusedSessionScreen(_ screen: SessionScreen) async throws {
        let previousScreen = focusedSessionScreen?.session.id == screen.session.id ? focusedSessionScreen : nil
        let previousState = previousScreen?.session.state
        focusedSessionScreen = screen
        syncFocusedStructuredSessionPresentation(for: screen)
        syncFocusedStructuredSessionChromePresentation(for: screen)
        focusedSessionID = screen.session.id
        focusedSessionWorkspaceID = screen.session.workspaceID
        if recentNavigation.contains(where: { $0.target.sessionID == screen.session.id }) {
            recentNavigationSessionWorkspaceIDs[screen.session.id] = screen.session.workspaceID
        }

        if let previousState, previousState != screen.session.state {
            try await refreshWorkspaceOverview(for: screen.session.workspaceID)
            try await refreshProviderDetailIfLoaded(
                workspaceID: screen.session.workspaceID,
                providerID: screen.session.providerID
            )
        }
    }

    private func syncFocusedStructuredSessionPresentation(for screen: SessionScreen?) {
        let presentation = screen.flatMap { focusedStructuredSessionPresenter.presentation(for: $0) }
        if focusedStructuredSessionPresentation != presentation {
            focusedStructuredSessionPresentation = presentation
        }
    }

    private func syncFocusedStructuredSessionChromePresentation(for screen: SessionScreen?) {
        let presentation = screen.flatMap { NexusSessionPresentation.focusedStructuredSessionChromePresentation(for: $0) }
        if focusedStructuredSessionChromePresentation != presentation {
            focusedStructuredSessionChromePresentation = presentation
        }
    }
}

struct ProviderDetailKey: Hashable {
    let workspaceID: UUID
    let providerID: ProviderID
}
#endif
