import Foundation
import Observation

protocol RemotePairingClient {
    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus
    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac
    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog
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
    var macHost = ""
    var macPort = "9234"
    var pairingCode = ""
    var deviceName = "iPhone"

    private let client: any RemotePairingClient
    private let store: any PairedMacStore

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
        catalog = nil
        catalogErrorMessage = nil
        store.saveActivePairedMacID(activePairedMacID)
    }

    func selectActivePairedMac(id: PairedMac.ID) throws {
        guard pairedMacs.contains(where: { $0.id == id }) else {
            throw RemoteClientPairingModelError.pairedMacNotFound
        }

        activePairedMacID = id
        catalog = nil
        catalogErrorMessage = nil
        store.saveActivePairedMacID(activePairedMacID)
    }

    func forgetPairedMac(id: PairedMac.ID) throws {
        pairedMacs.removeAll { $0.id == id }
        pairedMacAvailability[id] = nil
        activePairedMacID = Self.resolveActivePairedMacID(preferredID: activePairedMacID, pairedMacs: pairedMacs)
        catalog = nil
        catalogErrorMessage = nil
        try store.savePairedMacs(pairedMacs)
        store.saveActivePairedMacID(activePairedMacID)
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
