import Foundation
import NexusIPC
import NexusService
import Testing
@testable import nexus

struct RemotePairingNetworkTests {
    @Test func completesFirstTimePairingOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let pairedDevices = try await client.listPairedDevices()

        #expect(pairedMac.name == "Studio Mac")
        #expect(pairedMac.host == "127.0.0.1")
        #expect(pairedMac.port == server.port)
        #expect(pairedDevices.map(\.name) == ["Chris’s iPhone"])
    }
}
