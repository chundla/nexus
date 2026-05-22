import Foundation
import NexusDomain
import Testing
@testable import nexus

@MainActor
struct RemoteClientPairingModelTests {
    @Test func marksReachablePairedMacAsAvailableAfterRefresh() async throws {
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
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, status: .success(RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: true))),
            store: store
        )

        await model.refreshPairedMacAvailability()

        #expect(model.availability(for: pairedMac) == .available)
    }

    @Test func marksUnreachablePairedMacAsUnavailableAfterRefresh() async throws {
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
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                status: .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
            ),
            store: store
        )

        await model.refreshPairedMacAvailability()

        #expect(
            model.availability(for: pairedMac)
                == .unavailable("Nexus is unavailable. Make sure this Mac is awake, on the same network, and Nexus Remote Access is running.")
        )
    }

    @Test func storesSuccessfulPairingAsLastUsedMacForLaterReconnect() async throws {
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
        #expect(model.activePairedMac == pairedMac)

        let reloadedModel = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac),
            store: store
        )
        #expect(reloadedModel.pairedMacs == [pairedMac])
        #expect(reloadedModel.activePairedMac == pairedMac)
    }

    @Test func forgetsPairedMacFromDurableStore() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let firstMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600)
        )
        let secondMac = PairedMac(
            name: "Travel Mac",
            host: "travel.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 900)
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([firstMac, secondMac])
        store.saveActivePairedMacID(firstMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: firstMac),
            store: store
        )

        try model.forgetPairedMac(id: firstMac.id)

        #expect(model.pairedMacs == [secondMac])
        #expect(model.activePairedMac == secondMac)

        let reloadedModel = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: firstMac),
            store: store
        )
        #expect(reloadedModel.pairedMacs == [secondMac])
        #expect(reloadedModel.activePairedMac == secondMac)
    }

    @Test func loadsActivePairedMacWorkspaceCatalog() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let group = WorkspaceGroup(id: UUID(), name: "Client Work")
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: group.id
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [group],
            recentNavigation: [NavigationItem(target: .workspace(workspace.id), title: "Nexus", subtitle: "/tmp/nexus")],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .claude),
                            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .ready,
                                summary: "Default session ready",
                                actionTitle: "Resume"
                            )
                        )
                    ]
                )
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, catalog: catalog),
            store: store
        )

        await model.refreshActivePairedMacCatalog()

        #expect(model.catalog == catalog)
        #expect(model.catalogErrorMessage == nil)
    }

    @Test func switchesActivePairedMacForLaterReconnect() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let firstMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600)
        )
        let secondMac = PairedMac(
            name: "Travel Mac",
            host: "travel.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 900)
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([firstMac, secondMac])
        store.saveActivePairedMacID(firstMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: firstMac),
            store: store
        )

        try model.selectActivePairedMac(id: secondMac.id)

        #expect(model.activePairedMac == secondMac)

        let reloadedModel = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: firstMac),
            store: store
        )
        #expect(reloadedModel.activePairedMac == secondMac)
    }

    @Test func loadsActivePairedMacProviderDetailOnDemand() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: UUID()
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, providerDetail: detail),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(model.providerDetail(for: workspace.id, providerID: .claude) == detail)
        #expect(model.providerDetailErrorMessage(for: workspace.id, providerID: .claude) == nil)
    }
}

private struct StubRemotePairingClient: RemotePairingClient {
    let result: PairedMac
    let status: Result<RemotePairedMacStatus, any Error>
    let catalog: RemoteWorkspaceCatalog
    let providerDetail: ProviderDetail

    init(
        result: PairedMac,
        status: Result<RemotePairedMacStatus, any Error> = .success(
            RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: true)
        ),
        catalog: RemoteWorkspaceCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: []
        ),
        providerDetail: ProviderDetail = ProviderDetail(
            workspace: Workspace(
                id: UUID(),
                name: "Nexus",
                kind: .local,
                folderPath: "/tmp/nexus",
                primaryGroupID: UUID()
            ),
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
    ) {
        self.result = result
        self.status = status
        self.catalog = catalog
        self.providerDetail = providerDetail
    }

    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus {
        try status.get()
    }

    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac {
        result
    }

    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog {
        catalog
    }

    func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        providerDetail
    }
}

