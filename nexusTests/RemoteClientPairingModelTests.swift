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

    @Test func forgetsRevokedPairedMacAfterUnauthorizedCatalogRefresh() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                catalogResult: .failure(RemotePairingHTTPError.requestFailed("Pair this iPhone again to browse this Paired Mac"))
            ),
            store: store
        )

        await model.refreshActivePairedMacCatalog()

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
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

    @Test func forgetsRevokedPairedMacAfterUnauthorizedObservedSessionDisconnect() async throws {
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
        await client.disconnectObservedSession(RemotePairingHTTPError.requestFailed("Pair this iPhone again to browse this Paired Mac"))
        await Task.yield()

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
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

    @Test func launchingDefaultRemoteSessionRefreshesProviderDetailAndFocusesSession() async throws {
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
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: session,
            alternateSessions: [],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                providerDetail: refreshedDetail,
                providerDetailResults: [initialDetail, refreshedDetail],
                sessionScreen: SessionScreen(session: session, transcript: "Claude ready"),
                launchedDefaultSession: session
            ),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let launchedSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        await Task.yield()

        #expect(launchedSession.id == session.id)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.defaultSession?.id == session.id)
    }

    @Test func creatingNamedRemoteSessionRefreshesCatalogProviderDetailAndFocusesSession() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: groupID
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let refreshedCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Client Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .claude),
                            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .notCreated,
                                summary: "No default session yet",
                                actionTitle: "Launch"
                            ),
                            alternateSessionCount: 1
                        )
                    ]
                )
            ]
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [session],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                catalog: refreshedCatalog,
                providerDetail: refreshedDetail,
                sessionScreen: SessionScreen(session: session, transcript: "Claude ready"),
                createdNamedSession: session
            ),
            store: store
        )

        let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
        await Task.yield()

        #expect(createdSession.id == session.id)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.map { $0.id } == [session.id])
    }

    @Test func creatingNamedRemoteSessionReturnsBeforeBrowseRefreshCompletesAndStaysViewerByDefault() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: groupID
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let refreshedCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Client Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .claude),
                            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .notCreated,
                                summary: "No default session yet",
                                actionTitle: "Launch"
                            ),
                            alternateSessionCount: 1
                        )
                    ]
                )
            ]
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [session],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let catalogGate = AsyncGate()
        let providerDetailGate = AsyncGate()
        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: refreshedCatalog,
            providerDetail: refreshedDetail,
            sessionScreen: SessionScreen(session: session, controller: .mac, transcript: "Claude ready"),
            createdNamedSession: session,
            catalogFetchGate: catalogGate,
            providerDetailFetchGate: providerDetailGate
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        let capture = SessionCapture()

        let createTask = Task {
            let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
            await capture.store(createdSession)
        }

        for _ in 0..<20 where client.catalogFetchStarted == false {
            await Task.yield()
        }
        await Task.yield()

        #expect(await capture.value()?.id == session.id)
        #expect(model.focusedSessionID == session.id)
        #expect(client.requestLog == [
            "createNamedSession",
            "observeSessionScreen",
            "fetchSessionScreen",
            "fetchCatalog"
        ])

        await catalogGate.open()

        for _ in 0..<20 where client.providerDetailFetchStarted == false {
            await Task.yield()
        }

        #expect(client.requestLog == [
            "createNamedSession",
            "observeSessionScreen",
            "fetchSessionScreen",
            "fetchCatalog",
            "fetchProviderDetail"
        ])

        await providerDetailGate.open()
        try await createTask.value
        await Task.yield()

        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.controller == .mac)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.map(\.id) == [session.id])
    }

    @Test func stoppingRemoteSessionRefreshesProviderDetailAndFocusedScreen() async throws {
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
        let readySession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let stoppedSession = Session(
            id: readySession.id,
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: readySession,
            alternateSessions: [],
            failedSessions: []
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: stoppedSession,
            alternateSessions: [],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                providerDetail: refreshedDetail,
                providerDetailResults: [initialDetail, refreshedDetail],
                sessionScreen: SessionScreen(session: readySession, transcript: "Claude ready"),
                sessionScreenResults: [
                    .success(SessionScreen(session: readySession, transcript: "Claude ready")),
                    .success(SessionScreen(session: stoppedSession, transcript: "Session exited. Relaunch to start a new live runtime."))
                ],
                stoppedSession: stoppedSession
            ),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        await model.focusRemoteSession(sessionID: readySession.id)
        let result = try await model.stopSession(sessionID: readySession.id, workspaceID: workspace.id, providerID: .claude)
        await Task.yield()

        #expect(result.state == .exited)
        #expect(model.focusedSessionScreen?.session.state == .exited)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.defaultSession?.state == .exited)
    }

    @Test func creatingFailedNamedRemoteSessionStillFocusesInspectableSessionRecord() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: groupID
        )
        let failedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .failed,
            failureMessage: "Claude is unavailable on this Workspace."
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(
                state: .unavailable,
                summary: "Claude is unavailable on this Workspace.",
                launchability: .notLaunchable
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: [failedSession]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                providerDetail: refreshedDetail,
                sessionScreen: SessionScreen(session: failedSession, transcript: failedSession.failureMessage ?? ""),
                createdNamedSession: failedSession
            ),
            store: store
        )

        let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
        await Task.yield()

        #expect(createdSession.state == .failed)
        #expect(model.focusedSessionID == failedSession.id)
        #expect(model.focusedSessionScreen?.session.state == .failed)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.failedSessions.map { $0.id } == [failedSession.id])
    }

    @Test func relaunchingRemoteSessionRecordRefreshesProviderDetailAndFocusesSession() async throws {
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
        let exitedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        let readySession = Session(
            id: exitedSession.id,
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .ready
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [exitedSession],
            failedSessions: []
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [readySession],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                providerDetail: refreshedDetail,
                providerDetailResults: [initialDetail, refreshedDetail],
                sessionScreen: SessionScreen(session: readySession, transcript: "Claude ready"),
                launchedSession: readySession
            ),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let result = try await model.launchOrResumeSession(sessionID: exitedSession.id, workspaceID: workspace.id, providerID: .claude)
        await Task.yield()

        #expect(result.state == .ready)
        #expect(model.focusedSessionID == readySession.id)
        #expect(model.focusedSessionScreen?.session.state == .ready)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.first?.state == .ready)
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
    let catalogResult: Result<RemoteWorkspaceCatalog, any Error>?
    let providerDetail: ProviderDetail
    let launchedDefaultSession: Session
    let createdNamedSession: Session
    let launchedSession: Session
    let stoppedSession: Session
    let catalogFetchGate: AsyncGate?
    let providerDetailFetchGate: AsyncGate?
    private let defaultSessionScreen: SessionScreen
    private var providerDetailResults: [ProviderDetail]
    private var sessionScreenResults: [Result<SessionScreen, any Error>]
    private var observationRegistration: ObservationRegistration?
    private(set) var takeSessionControlRequests: [TakeSessionControlRequest] = []
    private(set) var releaseSessionControlRequests: [UUID] = []
    private(set) var requestLog: [String] = []
    private(set) var catalogFetchStarted = false
    private(set) var providerDetailFetchStarted = false

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
        catalogResult: Result<RemoteWorkspaceCatalog, any Error>? = nil,
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
        providerDetailResults: [ProviderDetail] = [],
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
        sessionScreenResults: [Result<SessionScreen, any Error>] = [],
        launchedDefaultSession: Session? = nil,
        createdNamedSession: Session? = nil,
        launchedSession: Session? = nil,
        stoppedSession: Session? = nil,
        catalogFetchGate: AsyncGate? = nil,
        providerDetailFetchGate: AsyncGate? = nil
    ) {
        self.result = result
        self.status = status
        self.catalog = catalog
        self.catalogResult = catalogResult
        self.providerDetail = providerDetail
        self.launchedDefaultSession = launchedDefaultSession ?? sessionScreen.session
        self.createdNamedSession = createdNamedSession ?? sessionScreen.session
        self.launchedSession = launchedSession ?? sessionScreen.session
        self.stoppedSession = stoppedSession ?? sessionScreen.session
        self.catalogFetchGate = catalogFetchGate
        self.providerDetailFetchGate = providerDetailFetchGate
        self.providerDetailResults = providerDetailResults
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
        requestLog.append("fetchCatalog")
        catalogFetchStarted = true
        await catalogFetchGate?.wait()

        if let catalogResult {
            return try catalogResult.get()
        }

        return catalog
    }

    func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        requestLog.append("fetchProviderDetail")
        providerDetailFetchStarted = true
        await providerDetailFetchGate?.wait()

        if providerDetailResults.isEmpty == false {
            return providerDetailResults.removeFirst()
        }

        return providerDetail
    }

    func launchOrResumeDefaultSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        requestLog.append("launchOrResumeDefaultSession")
        return launchedDefaultSession
    }

    func createNamedSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        requestLog.append("createNamedSession")
        return createdNamedSession
    }

    func launchOrResumeSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
        requestLog.append("launchOrResumeSession")
        return launchedSession
    }

    func stopSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
        requestLog.append("stopSession")
        return stoppedSession
    }

    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        requestLog.append("fetchSessionScreen")

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
        requestLog.append("observeSessionScreen")
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

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard isOpen == false else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard isOpen == false else {
            return
        }

        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor SessionCapture {
    private var session: Session?

    func store(_ session: Session) {
        self.session = session
    }

    func value() -> Session? {
        session
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

