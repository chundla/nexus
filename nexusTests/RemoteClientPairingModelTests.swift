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

    @Test func loadsFocusedRemoteSessionScreenForActivePairedMac() async throws {
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
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, sessionScreen: screen),
            store: store
        )

        await model.focusRemoteSession(sessionID: session.id)
        await Task.yield()

        #expect(model.focusedSessionScreen == screen)
        #expect(model.focusedSessionIsStale == false)
        #expect(model.focusedSessionErrorMessage == nil)
    }

    @Test func preservesStaleFocusedRemoteSessionScreenWhenRefreshFails() async throws {
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
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreenResults: [
                .success(screen),
                .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
            ]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await model.refreshFocusedSessionScreen()

        #expect(model.focusedSessionScreen == screen)
        #expect(model.focusedSessionIsStale)
        #expect(model.focusedSessionErrorMessage == "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)")
    }

    @Test func recoversFocusedRemoteSessionFromStaleSnapshotAfterRefreshSucceeds() async throws {
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
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let recoveredScreen = SessionScreen(session: session, transcript: "Claude ready\nReconnected update")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreenResults: [
                .success(initialScreen),
                .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)),
                .success(recoveredScreen)
            ]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await model.refreshFocusedSessionScreen()

        #expect(model.focusedSessionScreen == initialScreen)
        #expect(model.focusedSessionIsStale)

        await model.refreshFocusedSessionScreen()

        #expect(model.focusedSessionScreen == recoveredScreen)
        #expect(model.focusedSessionIsStale == false)
        #expect(model.focusedSessionErrorMessage == nil)
    }

    @Test func updatesFocusedRemoteSessionViewportWhileThisIphoneIsController() async throws {
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
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(result: pairedMac, sessionScreen: screen)
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        await model.updateFocusedRemoteSessionViewport(columns: 60, rows: 20)

        #expect(client.takeSessionControlRequests == [
            .init(sessionID: session.id, columns: 44, rows: 12),
            .init(sessionID: session.id, columns: 60, rows: 20)
        ])
        #expect(model.focusedSessionScreen?.terminalColumns == 60)
        #expect(model.focusedSessionScreen?.terminalRows == 20)
    }

    @Test func backgroundingFocusedSessionDropsControllerStatusOnThisIphone() async throws {
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
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(result: pairedMac, sessionScreen: screen)
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        await model.handleFocusedSessionBackgrounded()

        #expect(client.releaseSessionControlRequests == [session.id])
        #expect(model.focusedSessionScreen?.controller == .mac)
        #expect(model.focusedSessionIsController == false)
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

private final class StubRemotePairingClient: RemotePairingClient, @unchecked Sendable {
    struct TakeSessionControlRequest: Equatable {
        let sessionID: UUID
        let columns: Int
        let rows: Int
    }

    private struct ObservationRegistration {
        let onUpdate: @Sendable (SessionScreen) -> Void
        let onDisconnect: @Sendable (any Error) -> Void
    }

    let result: PairedMac
    let status: Result<RemotePairedMacStatus, any Error>
    let catalog: RemoteWorkspaceCatalog
    let providerDetail: ProviderDetail
    private let defaultSessionScreen: SessionScreen
    private var sessionScreenResults: [Result<SessionScreen, any Error>]
    private var observationRegistration: ObservationRegistration?
    private(set) var takeSessionControlRequests: [TakeSessionControlRequest] = []
    private(set) var releaseSessionControlRequests: [UUID] = []

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
        ),
        sessionScreen: SessionScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            transcript: "Claude ready"
        ),
        sessionScreenResults: [Result<SessionScreen, any Error>] = []
    ) {
        self.result = result
        self.status = status
        self.catalog = catalog
        self.providerDetail = providerDetail
        self.defaultSessionScreen = sessionScreen
        self.sessionScreenResults = sessionScreenResults
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

    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        if sessionScreenResults.isEmpty == false {
            return try sessionScreenResults.removeFirst().get()
        }

        return defaultSessionScreen
    }

    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        takeSessionControlRequests.append(.init(sessionID: sessionID, columns: columns, rows: rows))
        return SessionScreen(
            session: defaultSessionScreen.session,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript,
            terminalColumns: columns,
            terminalRows: rows
        )
    }

    func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        releaseSessionControlRequests.append(sessionID)
        return SessionScreen(
            session: defaultSessionScreen.session,
            controller: .mac,
            transcript: defaultSessionScreen.transcript,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows
        )
    }

    func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        SessionScreen(
            session: defaultSessionScreen.session,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript + text,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows
        )
    }

    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        SessionScreen(
            session: defaultSessionScreen.session,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript + "[key: \(key.rawValue)]",
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows
        )
    }

    func observeSessionScreen(
        for pairedMac: PairedMac,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void,
        onDisconnect: @escaping @Sendable (any Error) -> Void
    ) async throws -> any SessionScreenObservation {
        observationRegistration = ObservationRegistration(onUpdate: onUpdate, onDisconnect: onDisconnect)
        onUpdate(try await fetchSessionScreen(for: pairedMac, sessionID: sessionID))
        return TestRemoteSessionScreenObservation { [weak self] in
            self?.observationRegistration = nil
        }
    }

    func emitObservedScreen(_ screen: SessionScreen) async {
        observationRegistration?.onUpdate(screen)
    }

    func disconnectObservedSession(_ error: any Error) async {
        observationRegistration?.onDisconnect(error)
    }
}

private final class TestRemoteSessionScreenObservation: SessionScreenObservation, @unchecked Sendable {
    private let onCancel: @Sendable () -> Void

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() async {
        onCancel()
    }
}

