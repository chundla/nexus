import Foundation
import NexusDomain
import NexusIPC
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
    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen
    func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen
    func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen
    func observeSessionScreen(
        for pairedMac: PairedMac,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void,
        onDisconnect: @escaping @Sendable (any Error) -> Void
    ) async throws -> any SessionScreenObservation
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
    var focusedSessionScreen: SessionScreen?
    var focusedSessionIsStale = false
    var focusedSessionErrorMessage: String?
    var remoteFailureBreadcrumbs: [RemoteClientDiagnosticBreadcrumb] = []
    var macHost = ""
    var macPort = "9234"
    var pairingCode = ""
    var deviceName = "iPhone"

    private let client: any RemotePairingClient
    private let store: any PairedMacStore
    private var focusedSessionObservation: (any SessionScreenObservation)?
    private var focusedSessionReconnectTask: Task<Void, Never>?

    var activePairedMac: PairedMac? {
        guard let activePairedMacID else {
            return nil
        }

        return pairedMacs.first(where: { $0.id == activePairedMacID })
    }

    var focusedSessionIsController: Bool {
        guard let pairedDeviceID = activePairedMac?.pairedDeviceID else {
            return false
        }

        return focusedSessionScreen?.controller == .pairedDevice(pairedDeviceID)
    }

    init(client: any RemotePairingClient, store: any PairedMacStore) {
        self.client = client
        self.store = store
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

    func focusRemoteSession(sessionID: UUID) async {
        focusedSessionID = sessionID
        await startFocusedSessionObservation(forceRestart: true)
    }

    func refreshFocusedSessionScreen() async {
        await startFocusedSessionObservation(forceRestart: true)
    }

    func takeFocusedRemoteSessionControl(columns: Int, rows: Int) async throws {
        let pairedMac = try requireActivePairedMac()
        guard let sessionID = focusedSessionID else {
            throw RemoteClientPairingModelError.focusedSessionUnavailable
        }

        do {
            focusedSessionScreen = try await client.takeSessionControl(
                for: pairedMac,
                sessionID: sessionID,
                columns: columns,
                rows: rows
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
            focusedSessionScreen = try await client.releaseSessionControl(for: pairedMac, sessionID: sessionID)
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
            focusedSessionScreen = try await client.takeSessionControl(
                for: pairedMac,
                sessionID: sessionID,
                columns: columns,
                rows: rows
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
            focusedSessionScreen = screen
        }

        focusedSessionIsStale = false
        focusedSessionErrorMessage = nil
    }

    func stopFocusingRemoteSession() {
        focusedSessionID = nil
        focusedSessionScreen = nil
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
        clearRemoteBrowseState()
        pairingRecoveryMessage = nil
        store.saveActivePairedMacID(activePairedMacID)
    }

    func selectActivePairedMac(id: PairedMac.ID) throws {
        guard pairedMacs.contains(where: { $0.id == id }) else {
            throw RemoteClientPairingModelError.pairedMacNotFound
        }

        activePairedMacID = id
        clearRemoteBrowseState()
        pairingRecoveryMessage = nil
        store.saveActivePairedMacID(activePairedMacID)
    }

    func forgetPairedMac(id: PairedMac.ID) throws {
        pairedMacs.removeAll { $0.id == id }
        pairedMacAvailability[id] = nil
        activePairedMacID = Self.resolveActivePairedMacID(preferredID: activePairedMacID, pairedMacs: pairedMacs)
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

    private func openRemoteSessionAndRefreshBrowseState(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID
    ) {
        focusedSessionID = sessionID

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.focusRemoteSession(sessionID: sessionID)
            await self.refreshActivePairedMacCatalog()
            await self.loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
        }
    }

    private func startFocusedSessionObservation(forceRestart: Bool) async {
        guard let sessionID = focusedSessionID else {
            focusedSessionScreen = nil
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
            await cancelFocusedSessionObservation()
            return
        }

        guard let pairedMac = activePairedMac else {
            focusedSessionScreen = nil
            focusedSessionIsStale = false
            focusedSessionErrorMessage = nil
            await cancelFocusedSessionObservation()
            return
        }

        if forceRestart {
            await cancelFocusedSessionObservation()
        } else if focusedSessionObservation != nil {
            return
        }

        do {
            let observation = try await client.observeSessionScreen(
                for: pairedMac,
                sessionID: sessionID,
                onUpdate: { [weak self] screen in
                    let applyUpdate = { @MainActor [weak self] in
                        guard let self, self.focusedSessionID == sessionID else {
                            return
                        }

                        self.focusedSessionScreen = screen
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
            focusedSessionObservation = observation

            if focusedSessionScreen?.session.id != sessionID {
                do {
                    let initialScreen = try await client.fetchSessionScreen(for: pairedMac, sessionID: sessionID)
                    if focusedSessionID == sessionID {
                        focusedSessionScreen = initialScreen
                        focusedSessionIsStale = false
                        focusedSessionErrorMessage = nil
                    }
                } catch {
                    if focusedSessionScreen?.session.id != sessionID {
                        await cancelFocusedSessionObservation()
                        if handleUnauthorizedPairedMac(error, pairedMacID: pairedMac.id) {
                            return
                        }

                        applyFocusedSessionObservationError(error, sessionID: sessionID)
                        scheduleFocusedSessionReconnect(for: sessionID)
                        return
                    }
                }
            }

            focusedSessionReconnectTask?.cancel()
            focusedSessionReconnectTask = nil
        } catch {
            if handleUnauthorizedPairedMac(error, pairedMacID: pairedMac.id) {
                return
            }

            applyFocusedSessionObservationError(error, sessionID: sessionID)
            scheduleFocusedSessionReconnect(for: sessionID)
        }
    }

    private func cancelFocusedSessionObservation() async {
        focusedSessionReconnectTask?.cancel()
        focusedSessionReconnectTask = nil

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
        case .actionRecovery(let message):
            message
        }
    }
}
