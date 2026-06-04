import Foundation
import NexusDomain
import NexusIPC
import NexusSessionPresentation
import Observation

protocol RemotePairingClient {
    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus
    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac
    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog
    func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail
    func launchOrResumeDefaultSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session
    func createNamedSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session
    func launchOrResumeSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session
    func stopSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session
    func deleteSessionRecord(for pairedMac: PairedMac, sessionID: UUID) async throws -> Bool
    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen
    func fetchStructuredSessionHistoryPage(
        for pairedMac: PairedMac,
        sessionID: UUID,
        pageSize: Int,
        before cursor: StructuredSessionHistoryCursor?
    ) async throws -> StructuredSessionHistoryPage
    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen
    func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen
    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen
    func respondToApprovalRequest(for pairedMac: PairedMac, sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen
    func respondToExtensionDialog(for pairedMac: PairedMac, sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen
    func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen
    func observeSessionScreen(
        for pairedMac: PairedMac,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void,
        onDisconnect: @escaping @Sendable (any Error) -> Void
    ) async throws -> any SessionScreenObservation
}

extension RemotePairingClient {
    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        if prompt.images.isEmpty == false {
            throw NSError(
                domain: "RemotePairingClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This remote pairing client does not support image-bearing Session prompts."]
            )
        }
        return try await sendSessionInput(for: pairedMac, sessionID: sessionID, text: prompt.text)
    }

    func fetchStructuredSessionHistoryPage(
        for pairedMac: PairedMac,
        sessionID: UUID,
        pageSize: Int,
        before cursor: StructuredSessionHistoryCursor?
    ) async throws -> StructuredSessionHistoryPage {
        _ = pairedMac
        _ = sessionID
        _ = pageSize
        _ = cursor
        throw NSError(
            domain: "RemotePairingClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "This remote pairing client does not support structured Session history paging."]
        )
    }
}

extension RemotePairingHTTPClient: RemotePairingClient {}

protocol PairedMacStore {
    func loadPairedMacs() -> [PairedMac]
    func savePairedMacs(_ pairedMacs: [PairedMac]) throws
    func loadActivePairedMacID() -> PairedMac.ID?
    func saveActivePairedMacID(_ activePairedMacID: PairedMac.ID?)
}

struct UserDefaultsPairedMacStore: PairedMacStore {
    private let defaults: UserDefaults
    private let key: String
    private let activeKey: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "paired-macs",
        activeKey: String = "active-paired-mac-id"
    ) {
        self.defaults = defaults
        self.key = key
        self.activeKey = activeKey
    }

    func loadPairedMacs() -> [PairedMac] {
        guard let data = defaults.data(forKey: key),
              let pairedMacs = try? JSONDecoder().decode([PairedMac].self, from: data) else {
            return []
        }

        return pairedMacs
    }

    func savePairedMacs(_ pairedMacs: [PairedMac]) throws {
        let data = try JSONEncoder().encode(pairedMacs)
        defaults.set(data, forKey: key)
    }

    func loadActivePairedMacID() -> PairedMac.ID? {
        defaults.string(forKey: activeKey)
    }

    func saveActivePairedMacID(_ activePairedMacID: PairedMac.ID?) {
        defaults.set(activePairedMacID, forKey: activeKey)
    }
}

enum PairedMacAvailability: Equatable {
    case unknown
    case available
    case unavailablePairedMac
    case remoteAccessDisabled

    var summary: String {
        switch self {
        case .unknown:
            "Checking availability…"
        case .available:
            "Available on this network"
        case .unavailablePairedMac:
            "Nexus is unavailable. Make sure this Mac is awake, on the same network, and Nexus Remote Access is running."
        case .remoteAccessDisabled:
            "Remote Access is turned off on this Mac"
        }
    }
}

enum RemoteBrowseDestination: Hashable, Identifiable {
    case workspace(UUID)
    case provider(UUID, ProviderID)
    case session(workspaceID: UUID, providerID: ProviderID, sessionID: UUID)

    var id: String {
        switch self {
        case .workspace(let workspaceID):
            "workspace:\(workspaceID.uuidString)"
        case .provider(let workspaceID, let providerID):
            "provider:\(workspaceID.uuidString):\(providerID.rawValue)"
        case .session(let workspaceID, let providerID, let sessionID):
            "session:\(workspaceID.uuidString):\(providerID.rawValue):\(sessionID.uuidString)"
        }
    }
}

enum RemoteBrowseNavigationError: LocalizedError {
    case catalogUnavailable
    case itemUnavailable

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            "Reconnect to this Paired Mac before opening recents."
        case .itemUnavailable:
            "This recent item is no longer available on this Paired Mac."
        }
    }
}

struct RemoteWorkspaceBrowsePresentation: Equatable {
    let availableWorkspaceGroups: [WorkspaceGroup]
    let workspaceOverviews: [WorkspaceOverview]

    var availableWorkspaceGroupIDs: [UUID] {
        availableWorkspaceGroups.map(\.id)
    }
}

@MainActor
@Observable
final class RemoteClientPairingModel {
    var pairedMacs: [PairedMac]
    var pairedMacAvailability: [PairedMac.ID: PairedMacAvailability] = [:]
    var activePairedMacID: PairedMac.ID?
    var catalog: RemoteWorkspaceCatalog?
    var catalogErrorMessage: String?
    var pairingRecoveryMessage: String?
    var providerDetails: [RemoteProviderDetailKey: ProviderDetail] = [:]
    var providerDetailErrorMessages: [RemoteProviderDetailKey: String] = [:]
    var focusedSessionID: UUID?
    private(set) var focusedSessionWorkspaceID: UUID?
    private(set) var focusedSessionWorkspaceLocation: String?
    var focusedSessionScreen: SessionScreen?
    private(set) var focusedStructuredSessionPresentation: FocusedStructuredSessionPresentation?
    private(set) var focusedStructuredSessionChromePresentation: FocusedStructuredSessionChromePresentation?
    private(set) var canLoadOlderFocusedStructuredSessionHistory = false
    private(set) var isLoadingOlderFocusedStructuredSessionHistory = false
    private(set) var focusedStructuredSessionHistoryErrorMessage: String?
    private(set) var focusedSessionSurfacePresentation: RemoteSessionSurfacePresentation?
    private(set) var focusedSessionIsController = false
    var focusedSessionIsStale = false
    var focusedSessionErrorMessage: String?
    var remoteFailureBreadcrumbs: [RemoteClientDiagnosticBreadcrumb] = []
    var macHost = ""
    var macPort = "9234"
    var pairingCode = ""
    var deviceName = "iPhone"

    private let client: any RemotePairingClient
    private let store: any PairedMacStore
    private let focusedSessionObservationStartupTimeoutNanoseconds: UInt64
    private let structuredSessionHistoryPagingController: StructuredSessionHistoryPagingController
    private let focusedStructuredSessionChromePresenter = FocusedStructuredSessionChromePresenter()
    private var focusedSessionObservation: (any SessionScreenObservation)?
    private var focusedSessionObservationStartupTask: Task<Void, Never>?
    private var focusedSessionReconnectTask: Task<Void, Never>?

    var activePairedMac: PairedMac? {
        guard let activePairedMacID else {
            return nil
        }

        return pairedMacs.first(where: { $0.id == activePairedMacID })
    }

    var focusedSessionSurfaceSupport: SessionSurfaceSupport? {
        focusedSessionSurfacePresentation?.surfaceSupport
    }

    var focusedStructuredSessionDiagnosticSnapshot: StructuredSessionClientDiagnosticSnapshot? {
        guard let screen = focusedSessionScreen,
              screen.primarySurface == .structuredActivityFeed else {
            return nil
        }

        return StructuredSessionClientDiagnosticSnapshot(
            screen: screen,
            presentation: focusedStructuredSessionPresentation
        )
    }

    init(
        client: any RemotePairingClient,
        store: any PairedMacStore,
        focusedSessionObservationStartupTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.client = client
        self.store = store
        self.focusedSessionObservationStartupTimeoutNanoseconds = focusedSessionObservationStartupTimeoutNanoseconds
        self.structuredSessionHistoryPagingController = StructuredSessionHistoryPagingController { sessionID, pageSize, cursor in
            let pairedMac = try await MainActor.run {
                let pairedMacs = store.loadPairedMacs()
                guard pairedMacs.isEmpty == false else {
                    throw RemoteClientPairingModelError.pairedMacNotFound
                }
                if let preferredID = store.loadActivePairedMacID(),
                   let preferredMac = pairedMacs.first(where: { $0.id == preferredID }) {
                    return preferredMac
                }
                return pairedMacs[0]
            }
            return try await client.fetchStructuredSessionHistoryPage(
                for: pairedMac,
                sessionID: sessionID,
                pageSize: pageSize,
                before: cursor
            )
        }
        self.pairedMacs = store.loadPairedMacs()
        self.activePairedMacID = Self.resolveActivePairedMacID(
            preferredID: store.loadActivePairedMacID(),
            pairedMacs: pairedMacs
        )
    }

    func availability(for pairedMac: PairedMac) -> PairedMacAvailability {
        pairedMacAvailability[pairedMac.id] ?? .unknown
    }

    func refreshPairedMacAvailability() async {
        var nextAvailability: [PairedMac.ID: PairedMacAvailability] = [:]

        for pairedMac in pairedMacs {
            do {
                let status = try await client.fetchStatus(host: pairedMac.host, port: pairedMac.port)
                nextAvailability[pairedMac.id] = status.isRemoteAccessEnabled
                    ? .available
                    : .remoteAccessDisabled
            } catch {
                nextAvailability[pairedMac.id] = .unavailablePairedMac
            }
        }

        pairedMacAvailability = nextAvailability
    }

    func refreshActivePairedMacCatalog() async {
        guard let pairedMac = activePairedMac else {
            catalog = nil
            catalogErrorMessage = nil
            return
        }

        do {
            catalog = try await client.fetchCatalog(for: pairedMac)
            syncFocusedSessionWorkspaceLocation()
            catalogErrorMessage = nil
            pairingRecoveryMessage = nil
        } catch {
            let normalizedError = normalizedRemoteActionError(error, pairedMac: pairedMac)
            if activePairedMac == nil {
                return
            }

            recordRemoteFailureBreadcrumb(
                kind: .actionFailure,
                operation: .fetchCatalog,
                pairedMac: pairedMac,
                error: normalizedError
            )
            catalog = nil
            catalogErrorMessage = normalizedError.localizedDescription
        }
    }

    func providerDetail(for workspaceID: UUID, providerID: ProviderID) -> ProviderDetail? {
        providerDetails[RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)]
    }

    func providerDetailErrorMessage(for workspaceID: UUID, providerID: ProviderID) -> String? {
        providerDetailErrorMessages[RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)]
    }

    func workspaceOverview(id workspaceID: UUID) -> WorkspaceOverview? {
        catalog?.workspaceOverviews.first(where: { $0.workspace.id == workspaceID })
    }

    func providerCard(workspaceID: UUID, providerID: ProviderID) -> WorkspaceProviderCard? {
        workspaceOverview(id: workspaceID)?.providerCards.first(where: { $0.provider.id == providerID })
    }

    func resolvedSession(workspaceID: UUID, providerID: ProviderID, sessionID: UUID) -> Session? {
        guard let detail = providerDetail(for: workspaceID, providerID: providerID) else {
            return nil
        }

        return session(in: detail, sessionID: sessionID)
    }

    func workspaceBrowsePresentation(showingGroupsOnly: Bool, selectedGroupID: UUID?) -> RemoteWorkspaceBrowsePresentation? {
        guard let catalog else {
            return nil
        }

        let availableWorkspaceGroups = catalog.workspaceGroups
            .filter { group in
                catalog.workspaceOverviews.contains { $0.workspace.primaryGroupID == group.id }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let ranking = workspaceRecencyRanking(catalog: catalog, currentFocusedWorkspaceID: focusedSessionWorkspaceID)
        let sortedWorkspaceOverviews = catalog.workspaceOverviews.sorted { lhs, rhs in
            let lhsRank = ranking[lhs.workspace.id] ?? Int.max
            let rhsRank = ranking[rhs.workspace.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.workspace.name.localizedCaseInsensitiveCompare(rhs.workspace.name) == .orderedAscending
        }

        let workspaceOverviews: [WorkspaceOverview]
        if showingGroupsOnly, let selectedGroupID {
            workspaceOverviews = sortedWorkspaceOverviews.filter { $0.workspace.primaryGroupID == selectedGroupID }
        } else {
            workspaceOverviews = sortedWorkspaceOverviews
        }

        return RemoteWorkspaceBrowsePresentation(
            availableWorkspaceGroups: availableWorkspaceGroups,
            workspaceOverviews: workspaceOverviews
        )
    }

    func browseDestination(for target: NavigationTarget) async throws -> RemoteBrowseDestination {
        guard let catalog else {
            throw RemoteBrowseNavigationError.catalogUnavailable
        }

        switch target.kind {
        case .workspace:
            guard let workspaceID = target.workspaceID,
                  catalog.workspaceOverviews.contains(where: { $0.workspace.id == workspaceID }) else {
                throw RemoteBrowseNavigationError.itemUnavailable
            }
            return .workspace(workspaceID)
        case .provider:
            guard let workspaceID = target.workspaceID,
                  let providerID = target.providerID,
                  catalog.workspaceOverviews
                    .first(where: { $0.workspace.id == workspaceID })?
                    .providerCards
                    .contains(where: { $0.provider.id == providerID }) == true else {
                throw RemoteBrowseNavigationError.itemUnavailable
            }
            return .provider(workspaceID, providerID)
        case .session:
            guard let sessionID = target.sessionID else {
                throw RemoteBrowseNavigationError.itemUnavailable
            }

            if let destination = browseDestinationForKnownSession(sessionID, catalog: catalog) {
                return destination
            }

            for overview in catalog.workspaceOverviews {
                for providerCard in overview.providerCards {
                    let detail = try await storedOrFetchedProviderDetail(
                        workspaceID: overview.workspace.id,
                        providerID: providerCard.provider.id
                    )
                    if session(in: detail, sessionID: sessionID) != nil {
                        return .session(
                            workspaceID: overview.workspace.id,
                            providerID: providerCard.provider.id,
                            sessionID: sessionID
                        )
                    }
                }
            }

            throw RemoteBrowseNavigationError.itemUnavailable
        }
    }

    func loadProviderDetail(workspaceID: UUID, providerID: ProviderID) async {
        do {
            _ = try await storedOrFetchedProviderDetail(
                workspaceID: workspaceID,
                providerID: providerID,
                forceRefresh: true
            )
        } catch {
            let key = RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)
            providerDetails[key] = nil
            providerDetailErrorMessages[key] = error.localizedDescription
        }
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let pairedMac = try requireActivePairedMac()

        do {
            let session = try await client.launchOrResumeDefaultSession(
                for: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
            openRemoteSessionAndRefreshBrowseState(
                sessionID: session.id,
                workspaceID: workspaceID,
                providerID: providerID
            )
            return session
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .launchDefaultSession,
                pairedMac: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
        }
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let pairedMac = try requireActivePairedMac()

        do {
            let session = try await client.createNamedSession(
                for: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
            openRemoteSessionAndRefreshBrowseState(
                sessionID: session.id,
                workspaceID: workspaceID,
                providerID: providerID
            )
            return session
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .createNamedSession,
                pairedMac: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
        }
    }

    func launchOrResumeSession(sessionID: UUID, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let pairedMac = try requireActivePairedMac()

        do {
            let session = try await client.launchOrResumeSession(for: pairedMac, sessionID: sessionID)
            openRemoteSessionAndRefreshBrowseState(
                sessionID: session.id,
                workspaceID: workspaceID,
                providerID: providerID
            )
            return session
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .launchSession,
                pairedMac: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID
            )
        }
    }

    func stopSession(sessionID: UUID, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let pairedMac = try requireActivePairedMac()

        do {
            let session = try await client.stopSession(for: pairedMac, sessionID: sessionID)
            if focusedSessionID == sessionID {
                await refreshFocusedSessionScreen()
            }
            await refreshActivePairedMacCatalog()
            await loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
            return session
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .stopSession,
                pairedMac: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID
            )
        }
    }

    func deleteSessionRecord(sessionID: UUID, workspaceID: UUID, providerID: ProviderID) async throws -> Bool {
        let pairedMac = try requireActivePairedMac()

        do {
            let deleted = try await client.deleteSessionRecord(for: pairedMac, sessionID: sessionID)
            guard deleted else {
                return false
            }

            if focusedSessionID == sessionID {
                stopFocusingRemoteSession()
            }
            await refreshActivePairedMacCatalog()
            await loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
            return true
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .deleteSessionRecord,
                pairedMac: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID
            )
        }
    }

    func focusRemoteSession(sessionID: UUID, workspaceID: UUID? = nil) async {
        focusedSessionID = sessionID
        setFocusedSessionWorkspaceID(workspaceID ?? resolvedWorkspaceID(for: sessionID))
        await startFocusedSessionObservation(forceRestart: true)
    }

    func refreshFocusedSessionScreen() async {
        await startFocusedSessionObservation(forceRestart: true)
    }

    func loadOlderFocusedStructuredSessionHistory() async {
        guard let screen = focusedSessionScreen else {
            return
        }

        await structuredSessionHistoryPagingController.loadOlderHistory(for: screen)
        syncFocusedStructuredSessionPresentation(for: focusedSessionScreen)
        syncFocusedStructuredSessionHistoryPagingState(for: focusedSessionScreen)
    }

    func takeFocusedRemoteSessionControl(columns: Int, rows: Int) async throws {
        let pairedMac = try requireActivePairedMac()
        guard let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }

        do {
            applyFocusedSessionScreen(
                try await client.takeSessionControl(
                    for: pairedMac,
                    sessionID: sessionID,
                    columns: columns,
                    rows: rows
                )
            )
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .takeSessionControl,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
        }
    }

    func releaseFocusedRemoteSessionControl() async {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID,
              focusedSessionIsController else {
            return
        }

        do {
            applyFocusedSessionScreen(try await client.releaseSessionControl(for: pairedMac, sessionID: sessionID))
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
        } catch {
            let normalizedError = loggedRemoteActionError(
                error,
                operation: .releaseSessionControl,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
            focusedSessionErrorMessage = normalizedError.localizedDescription
        }
    }

    func updateFocusedRemoteSessionViewport(columns: Int, rows: Int) async {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID,
              focusedSessionIsController else {
            return
        }
        guard focusedSessionScreen?.terminalColumns != columns || focusedSessionScreen?.terminalRows != rows else {
            return
        }

        do {
            applyFocusedSessionScreen(
                try await client.takeSessionControl(
                    for: pairedMac,
                    sessionID: sessionID,
                    columns: columns,
                    rows: rows
                )
            )
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
        } catch {
            let normalizedError = loggedRemoteActionError(
                error,
                operation: .takeSessionControl,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
            focusedSessionErrorMessage = normalizedError.localizedDescription
        }
    }

    func handleFocusedSessionBackgrounded() async {
        await handleFocusedSessionScreenDisappeared(preserveAttachment: true)
    }

    func handleFocusedSessionScreenDisappeared(preserveAttachment: Bool) async {
        await releaseFocusedRemoteSessionControl()

        if preserveAttachment == false {
            stopFocusingRemoteSession()
        }
    }

    func sendInputToFocusedRemoteSession(_ text: String) async throws {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }
        guard focusedSessionIsController else {
            throw RemoteClientPairingModelError.sessionInputControllerRequired
        }

        let screenBeforeRequest = focusedSessionScreen

        do {
            let screen = try await client.sendSessionInput(for: pairedMac, sessionID: sessionID, text: text)
            applyFocusedSessionInputResponse(
                screen,
                sessionID: sessionID,
                screenBeforeRequest: screenBeforeRequest
            )
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .sendSessionInput,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
        }
    }

    func respondToFocusedRemoteSessionApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }
        guard focusedSessionIsController else {
            throw RemoteClientPairingModelError.approvalRequestControllerRequired
        }

        let screenBeforeRequest = focusedSessionScreen

        do {
            let screen = try await client.respondToApprovalRequest(
                for: pairedMac,
                sessionID: sessionID,
                approvalRequestID: approvalRequestID,
                decision: decision
            )
            applyFocusedSessionInputResponse(
                screen,
                sessionID: sessionID,
                screenBeforeRequest: screenBeforeRequest
            )
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .respondToApprovalRequest,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
        }
    }

    func respondToFocusedRemoteSessionExtensionDialog(_ dialogID: String, response: SessionExtensionUIDialogResponse) async throws {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }
        guard focusedSessionIsController else {
            throw RemoteClientPairingModelError.extensionDialogControllerRequired
        }

        let screenBeforeRequest = focusedSessionScreen

        do {
            let screen = try await client.respondToExtensionDialog(
                for: pairedMac,
                sessionID: sessionID,
                dialogID: dialogID,
                response: response
            )
            applyFocusedSessionInputResponse(
                screen,
                sessionID: sessionID,
                screenBeforeRequest: screenBeforeRequest
            )
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .respondToExtensionDialog,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
        }
    }

    func sendTextToFocusedRemoteSession(_ text: String) async throws {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }
        guard focusedSessionIsController else {
            throw RemoteClientPairingModelError.controllerRequired
        }

        let screenBeforeRequest = focusedSessionScreen

        do {
            let screen = try await client.sendSessionText(for: pairedMac, sessionID: sessionID, text: text)
            applyFocusedSessionInputResponse(
                screen,
                sessionID: sessionID,
                screenBeforeRequest: screenBeforeRequest
            )
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .sendSessionText,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
        }
    }

    func sendInputKeyToFocusedRemoteSession(_ key: SessionInputKey) async throws {
        guard let pairedMac = activePairedMac,
              let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }
        guard focusedSessionIsController else {
            throw RemoteClientPairingModelError.controllerRequired
        }

        let screenBeforeRequest = focusedSessionScreen

        do {
            let screen = try await client.sendSessionInputKey(for: pairedMac, sessionID: sessionID, key: key)
            applyFocusedSessionInputResponse(
                screen,
                sessionID: sessionID,
                screenBeforeRequest: screenBeforeRequest
            )
        } catch {
            throw loggedRemoteActionError(
                error,
                operation: .sendSessionInputKey,
                pairedMac: pairedMac,
                sessionID: sessionID
            )
        }
    }

    private func applyFocusedSessionInputResponse(
        _ screen: SessionScreen,
        sessionID: UUID,
        screenBeforeRequest: SessionScreen?
    ) {
        guard focusedSessionID == sessionID else {
            return
        }

        let currentScreen = focusedSessionScreen
        let receivedObservedUpdateDuringRequest = currentScreen != nil && currentScreen != screenBeforeRequest

        let shouldApplyResponse = focusedSessionObservation == nil
            || currentScreen?.session.id != sessionID
            || receivedObservedUpdateDuringRequest == false

        if shouldApplyResponse {
            applyFocusedSessionScreen(screen)
        }

        focusedSessionIsStale = false
        focusedSessionErrorMessage = nil
    }

    func stopFocusingRemoteSession() {
        focusedSessionID = nil
        focusedSessionWorkspaceID = nil
        focusedSessionWorkspaceLocation = nil
        focusedSessionScreen = nil
        syncFocusedStructuredSessionPresentation(for: nil)
        syncFocusedStructuredSessionChromePresentation(for: nil)
        syncFocusedStructuredSessionHistoryPagingState(for: nil)
        syncFocusedSessionSurfacePresentation(for: nil)
        syncFocusedSessionControllerStatus()
        focusedSessionIsStale = false
        focusedSessionErrorMessage = nil

        focusedSessionReconnectTask?.cancel()
        focusedSessionReconnectTask = nil

        let observation = focusedSessionObservation
        focusedSessionObservation = nil
        Task {
            await observation?.cancel()
        }
    }

    func completePairing() async throws {
        guard let port = Int(macPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteClientPairingModelError.invalidPort
        }

        let pairedMac = try await client.completePairing(
            host: macHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            pairingCode: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceName: deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        pairedMacs.removeAll { $0.id == pairedMac.id }
        pairedMacs.append(pairedMac)
        pairedMacAvailability[pairedMac.id] = .unknown
        try store.savePairedMacs(pairedMacs)
        activePairedMacID = pairedMac.id
        syncFocusedSessionControllerStatus()
        clearRemoteBrowseState()
        pairingRecoveryMessage = nil
        store.saveActivePairedMacID(activePairedMacID)
    }

    func selectActivePairedMac(id: PairedMac.ID) throws {
        guard pairedMacs.contains(where: { $0.id == id }) else {
            throw RemoteClientPairingModelError.pairedMacNotFound
        }

        activePairedMacID = id
        syncFocusedSessionControllerStatus()
        clearRemoteBrowseState()
        pairingRecoveryMessage = nil
        store.saveActivePairedMacID(activePairedMacID)
    }

    func forgetPairedMac(id: PairedMac.ID) throws {
        pairedMacs.removeAll { $0.id == id }
        pairedMacAvailability[id] = nil
        activePairedMacID = Self.resolveActivePairedMacID(preferredID: activePairedMacID, pairedMacs: pairedMacs)
        syncFocusedSessionControllerStatus()
        clearRemoteBrowseState()
        pairingRecoveryMessage = nil
        try store.savePairedMacs(pairedMacs)
        store.saveActivePairedMacID(activePairedMacID)
    }

    private func requireActivePairedMac() throws -> PairedMac {
        guard let pairedMac = activePairedMac else {
            throw RemoteClientPairingModelError.pairedMacNotFound
        }

        return pairedMac
    }

    private func normalizedRemoteActionError(
        _ error: any Error,
        pairedMac: PairedMac,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil
    ) -> any Error {
        if handleUnauthorizedPairedMac(error, pairedMacID: pairedMac.id) {
            return error
        }

        guard let remoteError = error as? RemotePairingHTTPError,
              case .requestFailed = remoteError else {
            return error
        }

        if let availability = pairedMacAvailability[pairedMac.id],
           availability != .unknown,
           availability != .available {
            return RemoteClientPairingModelError.actionRecovery(availability.summary)
        }

        if let workspaceID,
           let workspaceAvailability = workspaceOverview(id: workspaceID)?.remoteTarget?.workspaceAvailability,
           workspaceAvailability.state != .available {
            return RemoteClientPairingModelError.actionRecovery(workspaceAvailability.summary)
        }

        if let workspaceID, let providerID {
            let providerHealth = providerDetail(for: workspaceID, providerID: providerID)?.health
                ?? providerCard(workspaceID: workspaceID, providerID: providerID)?.health
            if let providerHealth,
               providerHealth.state != .available || providerHealth.launchability != .launchable {
                return RemoteClientPairingModelError.actionRecovery(providerHealth.summary)
            }
        }

        return error
    }

    private func loggedRemoteActionError(
        _ error: any Error,
        operation: RemoteClientDiagnosticOperation,
        pairedMac: PairedMac,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil
    ) -> any Error {
        let normalizedError = normalizedRemoteActionError(
            error,
            pairedMac: pairedMac,
            workspaceID: workspaceID,
            providerID: providerID
        )
        recordRemoteFailureBreadcrumb(
            kind: .actionFailure,
            operation: operation,
            pairedMac: pairedMac,
            workspaceID: workspaceID,
            providerID: providerID,
            sessionID: sessionID,
            error: normalizedError
        )
        return normalizedError
    }

    private func clearRemoteBrowseState() {
        catalog = nil
        catalogErrorMessage = nil
        providerDetails = [:]
        providerDetailErrorMessages = [:]
        stopFocusingRemoteSession()
    }

    private func browseDestinationForKnownSession(
        _ sessionID: UUID,
        catalog: RemoteWorkspaceCatalog
    ) -> RemoteBrowseDestination? {
        for overview in catalog.workspaceOverviews {
            for providerCard in overview.providerCards {
                if providerCard.defaultSession.sessionID == sessionID {
                    return .session(
                        workspaceID: overview.workspace.id,
                        providerID: providerCard.provider.id,
                        sessionID: sessionID
                    )
                }

                let key = RemoteProviderDetailKey(workspaceID: overview.workspace.id, providerID: providerCard.provider.id)
                if let detail = providerDetails[key], session(in: detail, sessionID: sessionID) != nil {
                    return .session(
                        workspaceID: overview.workspace.id,
                        providerID: providerCard.provider.id,
                        sessionID: sessionID
                    )
                }
            }
        }

        return nil
    }

    private func storedOrFetchedProviderDetail(
        workspaceID: UUID,
        providerID: ProviderID,
        forceRefresh: Bool = false
    ) async throws -> ProviderDetail {
        let key = RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)
        if forceRefresh == false, let detail = providerDetails[key] {
            return detail
        }

        guard let pairedMac = activePairedMac else {
            providerDetails[key] = nil
            providerDetailErrorMessages[key] = nil
            throw RemoteClientPairingModelError.pairedMacNotFound
        }

        do {
            let detail = try await client.fetchProviderDetail(
                for: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
            providerDetails[key] = detail
            providerDetailErrorMessages[key] = nil
            return detail
        } catch {
            let normalizedError = loggedRemoteActionError(
                error,
                operation: .fetchProviderDetail,
                pairedMac: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
            throw normalizedError
        }
    }

    private func session(in detail: ProviderDetail, sessionID: UUID) -> Session? {
        if detail.defaultSession?.id == sessionID {
            return detail.defaultSession
        }

        if let session = detail.alternateSessions.first(where: { $0.id == sessionID }) {
            return session
        }

        return detail.failedSessions.first(where: { $0.id == sessionID })
    }

    private func workspaceRecencyRanking(
        catalog: RemoteWorkspaceCatalog,
        currentFocusedWorkspaceID: UUID?
    ) -> [UUID: Int] {
        var workspaceIDs: [UUID] = []

        if let currentFocusedWorkspaceID {
            workspaceIDs.append(currentFocusedWorkspaceID)
        }

        for item in catalog.recentNavigation {
            switch item.target.kind {
            case .workspace, .provider:
                if let workspaceID = item.target.workspaceID {
                    workspaceIDs.append(workspaceID)
                }
            case .session:
                if let sessionID = item.target.sessionID,
                   let workspaceID = browseWorkspaceID(forSessionID: sessionID, catalog: catalog) {
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

    private func browseWorkspaceID(forSessionID sessionID: UUID, catalog: RemoteWorkspaceCatalog) -> UUID? {
        for overview in catalog.workspaceOverviews {
            if overview.providerCards.contains(where: { $0.defaultSession.sessionID == sessionID }) {
                return overview.workspace.id
            }

            for providerCard in overview.providerCards {
                let key = RemoteProviderDetailKey(workspaceID: overview.workspace.id, providerID: providerCard.provider.id)
                if let detail = providerDetails[key], session(in: detail, sessionID: sessionID) != nil {
                    return overview.workspace.id
                }
            }
        }
        return nil
    }

    private func resolvedWorkspaceID(for sessionID: UUID) -> UUID? {
        if let focusedSessionScreen,
           focusedSessionScreen.session.id == sessionID {
            return focusedSessionScreen.session.workspaceID
        }

        if let catalog,
           let workspaceID = browseWorkspaceID(forSessionID: sessionID, catalog: catalog) {
            return workspaceID
        }

        return nil
    }

    private func remoteWorkspaceLocation(for workspaceID: UUID) -> String? {
        guard let overview = workspaceOverview(id: workspaceID) else {
            return nil
        }

        if let remoteTarget = overview.remoteTarget {
            return "\(remoteTarget.host.name) • \(overview.workspace.folderPath)"
        }

        return overview.workspace.folderPath
    }

    private func syncFocusedSessionWorkspaceLocation() {
        guard let focusedSessionWorkspaceID,
              let workspaceLocation = remoteWorkspaceLocation(for: focusedSessionWorkspaceID) else {
            return
        }

        if focusedSessionWorkspaceLocation != workspaceLocation {
            focusedSessionWorkspaceLocation = workspaceLocation
        }
    }

    private func setFocusedSessionWorkspaceID(_ workspaceID: UUID?) {
        if focusedSessionWorkspaceID != workspaceID {
            focusedSessionWorkspaceID = workspaceID
        }

        guard workspaceID != nil else {
            if focusedSessionWorkspaceLocation != nil {
                focusedSessionWorkspaceLocation = nil
            }
            return
        }

        syncFocusedSessionWorkspaceLocation()
    }

    private func applyFocusedSessionScreen(_ screen: SessionScreen) {
        focusedSessionScreen = screen
        syncFocusedStructuredSessionHistoryPagingState(for: screen)
        syncFocusedStructuredSessionPresentation(for: screen)
        syncFocusedStructuredSessionChromePresentation(for: screen)
        syncFocusedSessionSurfacePresentation(for: screen)
        syncFocusedSessionControllerStatus()
        setFocusedSessionWorkspaceID(screen.session.workspaceID)
    }

    private func syncFocusedStructuredSessionPresentation(for screen: SessionScreen?) {
        let presentation = screen.flatMap { structuredSessionHistoryPagingController.presentation(for: $0) }
        if focusedStructuredSessionPresentation != presentation {
            focusedStructuredSessionPresentation = presentation
        }
    }

    private func syncFocusedStructuredSessionHistoryPagingState(for screen: SessionScreen?) {
        structuredSessionHistoryPagingController.applyLiveScreen(screen)

        if canLoadOlderFocusedStructuredSessionHistory != structuredSessionHistoryPagingController.canLoadOlder {
            canLoadOlderFocusedStructuredSessionHistory = structuredSessionHistoryPagingController.canLoadOlder
        }
        if isLoadingOlderFocusedStructuredSessionHistory != structuredSessionHistoryPagingController.isLoading {
            isLoadingOlderFocusedStructuredSessionHistory = structuredSessionHistoryPagingController.isLoading
        }
        if focusedStructuredSessionHistoryErrorMessage != structuredSessionHistoryPagingController.errorMessage {
            focusedStructuredSessionHistoryErrorMessage = structuredSessionHistoryPagingController.errorMessage
        }
    }

    private func syncFocusedStructuredSessionChromePresentation(for screen: SessionScreen?) {
        let presentation = screen.flatMap { focusedStructuredSessionChromePresenter.presentation(for: $0) }
        if focusedStructuredSessionChromePresentation != presentation {
            focusedStructuredSessionChromePresentation = presentation
        }
    }

    private func syncFocusedSessionSurfacePresentation(for screen: SessionScreen?) {
        let presentation = screen.map {
            remoteSessionSurfacePresentation(for: $0, isReady: $0.session.state == .ready)
        }
        if focusedSessionSurfacePresentation != presentation {
            focusedSessionSurfacePresentation = presentation
        }
    }

    private func syncFocusedSessionControllerStatus() {
        let isController: Bool
        if let pairedDeviceID = activePairedMac?.pairedDeviceID {
            isController = focusedSessionScreen?.controller == .pairedDevice(pairedDeviceID)
        } else {
            isController = false
        }

        if focusedSessionIsController != isController {
            focusedSessionIsController = isController
        }
    }

    private func openRemoteSessionAndRefreshBrowseState(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID
    ) {
        focusedSessionID = sessionID
        setFocusedSessionWorkspaceID(workspaceID)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.focusRemoteSession(sessionID: sessionID, workspaceID: workspaceID)
            await self.refreshActivePairedMacCatalog()
            await self.loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
        }
    }

    private func startFocusedSessionObservation(forceRestart: Bool) async {
        guard let sessionID = focusedSessionID else {
            focusedSessionScreen = nil
            syncFocusedStructuredSessionPresentation(for: nil)
            syncFocusedStructuredSessionChromePresentation(for: nil)
            syncFocusedStructuredSessionHistoryPagingState(for: nil)
            syncFocusedSessionSurfacePresentation(for: nil)
            syncFocusedSessionControllerStatus()
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
            await cancelFocusedSessionObservation()
            return
        }

        guard let pairedMac = activePairedMac else {
            focusedSessionScreen = nil
            syncFocusedStructuredSessionPresentation(for: nil)
            syncFocusedStructuredSessionChromePresentation(for: nil)
            syncFocusedStructuredSessionHistoryPagingState(for: nil)
            syncFocusedSessionSurfacePresentation(for: nil)
            syncFocusedSessionControllerStatus()
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
            await cancelFocusedSessionObservation()
            return
        }

        if forceRestart {
            await cancelFocusedSessionObservation()
        } else if focusedSessionObservation != nil || focusedSessionObservationStartupTask != nil {
            return
        }

        let startupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.establishFocusedSessionObservation(sessionID: sessionID, pairedMac: pairedMac)
        }
        focusedSessionObservationStartupTask = startupTask
        await startupTask.value
    }

    private func establishFocusedSessionObservation(sessionID: UUID, pairedMac: PairedMac) async {
        defer {
            focusedSessionObservationStartupTask = nil
        }

        let observationTask = Task<any SessionScreenObservation, Error> {
            try await client.observeSessionScreen(
                for: pairedMac,
                sessionID: sessionID,
                onUpdate: { [weak self] screen in
                    let applyUpdate = { @MainActor [weak self] in
                        guard let self, self.focusedSessionID == sessionID else {
                            return
                        }

                        self.applyFocusedSessionScreen(screen)
                        self.focusedSessionIsStale = false
                        self.focusedSessionErrorMessage = nil
                    }

                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            applyUpdate()
                        }
                    } else {
                        Task { @MainActor in
                            applyUpdate()
                        }
                    }
                },
                onDisconnect: { [weak self] error in
                    let applyDisconnect = { @MainActor [weak self] in
                        await self?.handleFocusedSessionDisconnect(error, sessionID: sessionID)
                    }

                    Task { @MainActor in
                        await applyDisconnect()
                    }
                }
            )
        }

        defer {
            if Task.isCancelled {
                observationTask.cancel()
            }
        }

        do {
            let initialScreen = try await client.fetchSessionScreen(for: pairedMac, sessionID: sessionID)
            if focusedSessionID == sessionID,
               focusedSessionScreen?.session.id != sessionID {
                applyFocusedSessionScreen(initialScreen)
                focusedSessionIsStale = false
                focusedSessionErrorMessage = nil
            }
        } catch {
            if handleUnauthorizedPairedMac(error, pairedMacID: pairedMac.id) {
                observationTask.cancel()
                return
            }
        }

        do {
            let observation = try await awaitFocusedSessionObservationStartup(observationTask)
            guard Task.isCancelled == false else {
                await observation.cancel()
                return
            }
            guard focusedSessionID == sessionID else {
                await observation.cancel()
                return
            }

            focusedSessionObservation = observation
            focusedSessionReconnectTask?.cancel()
            focusedSessionReconnectTask = nil
        } catch is CancellationError {
            observationTask.cancel()
        } catch {
            if handleUnauthorizedPairedMac(error, pairedMacID: pairedMac.id) {
                return
            }

            applyFocusedSessionObservationError(error, sessionID: sessionID)
            scheduleFocusedSessionReconnect(for: sessionID)
        }
    }

    private func awaitFocusedSessionObservationStartup(
        _ observationTask: Task<any SessionScreenObservation, Error>
    ) async throws -> any SessionScreenObservation {
        try await withThrowingTaskGroup(of: (any SessionScreenObservation).self) { group in
            group.addTask {
                try await observationTask.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: self.focusedSessionObservationStartupTimeoutNanoseconds)
                observationTask.cancel()
                throw RemoteClientPairingModelError.sessionObservationTimedOut
            }

            let observation = try await group.next()!
            group.cancelAll()
            return observation
        }
    }

    private func cancelFocusedSessionObservation() async {
        focusedSessionReconnectTask?.cancel()
        focusedSessionReconnectTask = nil

        focusedSessionObservationStartupTask?.cancel()
        focusedSessionObservationStartupTask = nil

        let observation = focusedSessionObservation
        focusedSessionObservation = nil
        if let observation {
            await observation.cancel()
        }
    }

    private func handleFocusedSessionDisconnect(_ error: any Error, sessionID: UUID) async {
        guard focusedSessionID == sessionID else {
            return
        }

        focusedSessionObservation = nil

        if let pairedMac = activePairedMac,
           handleUnauthorizedPairedMac(error, pairedMacID: pairedMac.id) {
            return
        }

        applyFocusedSessionObservationError(error, sessionID: sessionID)
        scheduleFocusedSessionReconnect(for: sessionID)
    }

    private func applyFocusedSessionObservationError(_ error: any Error, sessionID: UUID) {
        let hasSnapshot = focusedSessionScreen?.session.id == sessionID

        if hasSnapshot {
            focusedSessionIsStale = true
        } else {
            focusedSessionScreen = nil
            syncFocusedStructuredSessionPresentation(for: nil)
            syncFocusedStructuredSessionChromePresentation(for: nil)
            syncFocusedStructuredSessionHistoryPagingState(for: nil)
            syncFocusedSessionSurfacePresentation(for: nil)
            syncFocusedSessionControllerStatus()
            focusedSessionIsStale = false
        }

        focusedSessionErrorMessage = error.localizedDescription
        recordRemoteFailureBreadcrumb(
            kind: .reconnectFailure,
            operation: .observeSessionScreen,
            pairedMac: activePairedMac,
            sessionID: sessionID,
            error: error
        )
    }

    private func scheduleFocusedSessionReconnect(for sessionID: UUID) {
        guard focusedSessionReconnectTask == nil, focusedSessionID == sessionID else {
            return
        }

        focusedSessionReconnectTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                self.focusedSessionReconnectTask = nil
            }

            while Task.isCancelled == false,
                  self.focusedSessionID == sessionID,
                  self.focusedSessionObservation == nil {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard Task.isCancelled == false,
                      self.focusedSessionID == sessionID,
                      self.focusedSessionObservation == nil else {
                    break
                }

                await self.startFocusedSessionObservation(forceRestart: false)
            }
        }
    }

    private func handleUnauthorizedPairedMac(_ error: any Error, pairedMacID: PairedMac.ID) -> Bool {
        guard case .pairingRevoked(let message) = error as? RemotePairingHTTPError else {
            return false
        }

        try? forgetPairedMac(id: pairedMacID)
        pairingRecoveryMessage = message
        return true
    }

    private func recordRemoteFailureBreadcrumb(
        kind: RemoteClientDiagnosticKind,
        operation: RemoteClientDiagnosticOperation,
        pairedMac: PairedMac?,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil,
        error: any Error
    ) {
        remoteFailureBreadcrumbs.append(
            RemoteClientDiagnosticBreadcrumb(
                kind: kind,
                operation: operation,
                message: error.localizedDescription,
                pairedMacID: pairedMac?.id,
                pairedDeviceID: pairedMac?.pairedDeviceID,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID
            )
        )

        if remoteFailureBreadcrumbs.count > 20 {
            remoteFailureBreadcrumbs.removeFirst(remoteFailureBreadcrumbs.count - 20)
        }
    }

    private static func resolveActivePairedMacID(
        preferredID: PairedMac.ID?,
        pairedMacs: [PairedMac]
    ) -> PairedMac.ID? {
        if let preferredID,
           pairedMacs.contains(where: { $0.id == preferredID }) {
            return preferredID
        }

        return pairedMacs.first?.id
    }
}

struct RemoteProviderDetailKey: Hashable {
    let workspaceID: UUID
    let providerID: ProviderID
}

enum RemoteClientPairingModelError: LocalizedError {
    case invalidPort
    case pairedMacNotFound
    case focusedSessionUnavailable
    case controllerRequired
    case sessionInputControllerRequired
    case approvalRequestControllerRequired
    case extensionDialogControllerRequired
    case sessionObservationTimedOut
    case actionRecovery(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "Enter a valid Mac port"
        case .pairedMacNotFound:
            "Select a Paired Mac that is still stored on this iPhone"
        case .focusedSessionUnavailable:
            "Open a Session before trying to control it"
        case .controllerRequired:
            "Take Controller on this iPhone before sending terminal input"
        case .sessionInputControllerRequired:
            "Take Controller on this iPhone before sending Session input"
        case .approvalRequestControllerRequired:
            "Take Controller on this iPhone before responding to Approval Requests"
        case .extensionDialogControllerRequired:
            "Take Controller on this iPhone before responding to Extension UI dialogs"
        case .sessionObservationTimedOut:
            "Live Session updates are taking longer than expected on this Paired Mac"
        case .actionRecovery(let message):
            message
        }
    }
}
