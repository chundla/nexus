import Foundation
import Observation

protocol RemotePairingClient {
    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac
}

extension RemotePairingHTTPClient: RemotePairingClient {}

protocol PairedMacStore {
    func loadPairedMacs() -> [PairedMac]
    func savePairedMacs(_ pairedMacs: [PairedMac]) throws
}

struct UserDefaultsPairedMacStore: PairedMacStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "paired-macs") {
        self.defaults = defaults
        self.key = key
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
}

@MainActor
@Observable
final class RemoteClientPairingModel {
    var pairedMacs: [PairedMac]
    var macHost = ""
    var macPort = "9234"
    var pairingCode = ""
    var deviceName = "iPhone"

    private let client: any RemotePairingClient
    private let store: any PairedMacStore

    init(client: any RemotePairingClient, store: any PairedMacStore) {
        self.client = client
        self.store = store
        self.pairedMacs = store.loadPairedMacs()
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
        try store.savePairedMacs(pairedMacs)
    }

    func forgetPairedMac(id: PairedMac.ID) throws {
        pairedMacs.removeAll { $0.id == id }
        try store.savePairedMacs(pairedMacs)
    }
}

enum RemoteClientPairingModelError: LocalizedError {
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "Enter a valid Mac port"
        }
    }
}
