import Foundation
import NexusIPC
import NexusService
import Testing
@testable import nexus

@MainActor
struct RemotePairingNetworkTests {
    @Test func fetchesReachablePairedMacStatusOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)

        let remoteClient = RemotePairingHTTPClient()
        let status = try await remoteClient.fetchStatus(host: server.displayHost, port: server.port)

        #expect(status == RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: true))
    }

    @Test func fetchesSummaryFirstRemoteWorkspaceCatalogOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: "/tmp/nexus",
            primaryGroupID: group.id
        )
        try await client.recordNavigation(target: .workspace(workspace.id))

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let catalog = try await remoteClient.fetchCatalog(for: pairedMac)

        #expect(catalog.workspaceGroups == [group])
        #expect(catalog.recentNavigation.map(\.target) == [.workspace(workspace.id)])
        #expect(catalog.workspaceOverviews.map(\.workspace.id) == [workspace.id])
        #expect(catalog.workspaceOverviews.first?.providerCards.isEmpty == false)
    }

    @Test func fetchesRemoteProviderDetailOnDemandOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: "/tmp/nexus",
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(detail.workspace.id == workspace.id)
        #expect(detail.provider.id == .claude)
        #expect(detail.defaultSession == nil)
        #expect(detail.alternateSessions.isEmpty)
        #expect(detail.failedSessions.isEmpty)
    }

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
        #expect(pairedMac.pairedDeviceID != nil)
        #expect(pairedDevices.map(\.name) == ["Chris’s iPhone"])
    }
}
