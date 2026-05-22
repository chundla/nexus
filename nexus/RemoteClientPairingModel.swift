import Foundation
import NexusDomain
import NexusIPC
import Observation

protocol RemotePairingClient {
    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus
    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac
    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog
    func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail
    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen
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
    case unavailable(String)

    var summary: String {
        switch self {
        case .unknown:
            "Checking availability…"
        case .available:
            "Available on this network"
        case .unavailable(let message):
            message
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
    var providerDetails: [RemoteProviderDetailKey: ProviderDetail] = [:]
    var providerDetailErrorMessages: [RemoteProviderDetailKey: String] = [:]
    var focusedSessionID: UUID?
    var focusedSessionScreen: SessionScreen?
    var focusedSessionIsStale = false
    var focusedSessionErrorMessage: String?
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
                    : .unavailable("Remote Access is turned off on this Mac")
            } catch {
                nextAvailability[pairedMac.id] = .unavailable(
                    "Nexus is unavailable. Make sure this Mac is awake, on the same network, and Nexus Remote Access is running."
                )
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
        } catch {
            catalog = nil
            catalogErrorMessage = error.localizedDescription
        }
    }

    func providerDetail(for workspaceID: UUID, providerID: ProviderID) -> ProviderDetail? {
        providerDetails[RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)]
    }

    func providerDetailErrorMessage(for workspaceID: UUID, providerID: ProviderID) -> String? {
        providerDetailErrorMessages[RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)]
    }

    func loadProviderDetail(workspaceID: UUID, providerID: ProviderID) async {
        let key = RemoteProviderDetailKey(workspaceID: workspaceID, providerID: providerID)
        guard let pairedMac = activePairedMac else {
            providerDetails[key] = nil
            providerDetailErrorMessages[key] = nil
            return
        }

        do {
            providerDetails[key] = try await client.fetchProviderDetail(
                for: pairedMac,
                workspaceID: workspaceID,
                providerID: providerID
            )
            providerDetailErrorMessages[key] = nil
        } catch {
            providerDetails[key] = nil
            providerDetailErrorMessages[key] = error.localizedDescription
        }
    }

    func focusRemoteSession(sessionID: UUID) async {
        focusedSessionID = sessionID
        await startFocusedSessionObservation(forceRestart: true)
    }

    func refreshFocusedSessionScreen() async {
        await startFocusedSessionObservation(forceRestart: true)
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
        store.saveActivePairedMacID(activePairedMacID)
    }

    func selectActivePairedMac(id: PairedMac.ID) throws {
        guard pairedMacs.contains(where: { $0.id == id }) else {
            throw RemoteClientPairingModelError.pairedMacNotFound
        }

        activePairedMacID = id
        clearRemoteBrowseState()
        store.saveActivePairedMacID(activePairedMacID)
    }

    func forgetPairedMac(id: PairedMac.ID) throws {
        pairedMacs.removeAll { $0.id == id }
        pairedMacAvailability[id] = nil
        activePairedMacID = Self.resolveActivePairedMacID(preferredID: activePairedMacID, pairedMacs: pairedMacs)
        clearRemoteBrowseState()
        try store.savePairedMacs(pairedMacs)
        store.saveActivePairedMacID(activePairedMacID)
    }

    private func clearRemoteBrowseState() {
        catalog = nil
        catalogErrorMessage = nil
        providerDetails = [:]
        providerDetailErrorMessages = [:]
        stopFocusingRemoteSession()
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
                            await applyUpdate()
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
            focusedSessionReconnectTask?.cancel()
            focusedSessionReconnectTask = nil
        } catch {
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

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "Enter a valid Mac port"
        case .pairedMacNotFound:
            "Select a Paired Mac that is still stored on this iPhone"
        }
    }
}
