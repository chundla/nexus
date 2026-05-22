import Foundation
import Testing
@testable import nexus

@MainActor
struct RemoteClientPairingModelTests {
    @Test func storesSuccessfulPairingForLaterReconnect() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600)
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac),
            store: store
        )

        model.macHost = "studio.local"
        model.macPort = "9234"
        model.pairingCode = "123456"
        model.deviceName = "Chris’s iPhone"

        try await model.completePairing()

        #expect(model.pairedMacs == [pairedMac])

        let reloadedModel = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac),
            store: store
        )
        #expect(reloadedModel.pairedMacs == [pairedMac])
    }
}

private struct StubRemotePairingClient: RemotePairingClient {
    let result: PairedMac

    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac {
        result
    }
}

