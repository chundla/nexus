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

        #expect(model.availability(for: pairedMac) == .unavailablePairedMac)
    }

    @Test func marksPairedMacWithRemoteAccessDisabledAfterRefresh() async throws {
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
                status: .success(RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: false))
            ),
            store: store
        )

        await model.refreshPairedMacAvailability()

        #expect(model.availability(for: pairedMac) == .remoteAccessDisabled)
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

    @Test func resolvesWorkspaceRecentIntoCanonicalWorkspaceDestination() async throws {
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
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, catalog: catalog),
            store: store
        )
        await model.refreshActivePairedMacCatalog()

        let destination = try await model.browseDestination(for: .workspace(workspace.id))

        #expect(destination == .workspace(workspace.id))
    }

    @Test func resolvesProviderRecentIntoCanonicalProviderDestination() async throws {
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
            recentNavigation: [NavigationItem(target: .provider(workspaceID: workspace.id, providerID: .claude), title: "Claude", subtitle: "Nexus")],
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

        let destination = try await model.browseDestination(for: .provider(workspaceID: workspace.id, providerID: .claude))

        #expect(destination == .provider(workspace.id, .claude))
    }

    @Test func resolvesSessionRecentIntoCanonicalSessionDestinationByLoadingProviderDetail() async throws {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [group],
            recentNavigation: [NavigationItem(target: .session(session.id), title: "Session 1", subtitle: "Nexus • Claude")],
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
        let detail = ProviderDetail(
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

        let client = StubRemotePairingClient(result: pairedMac, catalog: catalog, providerDetail: detail)
        let model = RemoteClientPairingModel(client: client, store: store)
        await model.refreshActivePairedMacCatalog()

        let destination = try await model.browseDestination(for: .session(session.id))

        #expect(destination == .session(workspaceID: workspace.id, providerID: .claude, sessionID: session.id))
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.map(\.id) == [session.id])
        #expect(client.requestLog == ["fetchCatalog", "fetchProviderDetail"])
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
                catalogResult: .failure(RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
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

    @Test func reloadingModelKeepsActivePairedMacWithoutReopeningFocusedSession() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                sessionScreen: SessionScreen(session: session, transcript: "Claude ready")
            ),
            store: store
        )
        await model.focusRemoteSession(sessionID: session.id)
        await Task.yield()

        let reloadedModel = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac),
            store: store
        )

        #expect(reloadedModel.activePairedMac == pairedMac)
        #expect(reloadedModel.focusedSessionID == nil)
        #expect(reloadedModel.focusedSessionScreen == nil)
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

    @Test func focusedRemoteSessionSurfaceSupportAllowsExistingStructuredLocalPiSessionsOnIPhone() async throws {
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
            providerID: .pi,
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
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")],
            approvalRequests: [SessionApprovalRequest(title: "Deploy", text: "Deploy to production?", state: .pending)]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, sessionScreen: screen),
            store: store
        )
        model.catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )

        await model.focusRemoteSession(sessionID: session.id)
        await Task.yield()

        #expect(model.focusedSessionScreen == screen)
        #expect(model.focusedSessionScreen?.approvalRequests == screen.approvalRequests)
        #expect(model.focusedSessionSurfaceSupport == .supported)
    }

    @Test func focusedRemoteSessionSurfaceSupportAllowsExistingStructuredLocalIBMBobSessionsOnIPhone() async throws {
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
            providerID: .ibmBob,
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
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "IBM Bob Session ready. Send a prompt to start IBM Bob.")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, sessionScreen: screen),
            store: store
        )
        model.catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )

        await model.focusRemoteSession(sessionID: session.id)
        await Task.yield()

        #expect(model.focusedSessionScreen == screen)
        #expect(model.focusedSessionSurfaceSupport == .supported)
    }

    @Test func focusedRemoteSessionSurfaceSupportSupportsExistingStructuredRemotePiSessionsOnIPhone() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workspace = Workspace(
            id: UUID(),
            name: "Nexus Remote",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
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
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(result: pairedMac, sessionScreen: screen),
            store: store
        )
        model.catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )

        await model.focusRemoteSession(sessionID: session.id)
        await Task.yield()

        #expect(model.focusedSessionScreen == screen)
        #expect(model.focusedSessionSurfaceSupport == .supported)
    }

    @Test func sendingStructuredPromptUsesGenericSessionInputRouteAndUpdatesFocusedScreen() async throws {
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
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Codex shared Session stream connected",
            activityItems: [SessionActivityItem(kind: .status, text: "Codex shared Session stream connected")]
        )
        let controlledScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Codex shared Session stream connected",
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: [SessionActivityItem(kind: .status, text: "Codex shared Session stream connected")]
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Codex shared Session stream connected\nYou: Ship it",
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: [
                SessionActivityItem(kind: .status, text: "Codex shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: Ship it")
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            sendSessionInputResult: .success(updatedScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        model.catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendInputToFocusedRemoteSession("Ship it")

        #expect(client.requestLog.contains("sendSessionInput"))
        #expect(client.requestLog.contains("sendSessionText") == false)
        #expect(model.focusedSessionScreen == updatedScreen)
    }

    @Test func controllerCanRespondToFocusedRemoteSessionApprovalRequest() async throws {
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
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let approvalRequest = SessionApprovalRequest(
            title: "deploy --prod",
            text: "Codex needs approval to deploy to production.",
            state: .pending
        )
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Codex shared Session stream connected\nApproval Request: deploy --prod",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Codex shared Session stream connected"),
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: deploy --prod")
            ],
            approvalRequests: [approvalRequest]
        )
        let controlledScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: initialScreen.transcript,
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: initialScreen.activityItems,
            approvalRequests: initialScreen.approvalRequests
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.respondToFocusedRemoteSessionApprovalRequest(approvalRequest.id, decision: .approve)

        #expect(client.requestLog.contains("respondToApprovalRequest"))
        #expect(model.focusedSessionScreen?.approvalRequests.first?.state == .approved)
        #expect(model.focusedSessionScreen?.activityItems.map(\.text) == [
            "Codex shared Session stream connected",
            "Approval Request: deploy --prod",
            "Approved: deploy --prod"
        ])
    }

    @Test func sendingStructuredPromptToFocusedRemotePiSessionUsesGenericSessionInputRouteAndUpdatesFocusedScreen() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript: "Pi shared Session stream connected",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let controlledScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: initialScreen.transcript,
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: initialScreen.activityItems
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "> deploy\nRemote deploy",
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: deploy"),
                SessionActivityItem(kind: .message, text: "Pi: Remote deploy")
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            sendSessionInputResult: .success(updatedScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        model.catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendInputToFocusedRemoteSession("deploy")

        #expect(client.requestLog.contains("sendSessionInput"))
        #expect(client.requestLog.contains("sendSessionText") == false)
        #expect(model.focusedSessionScreen == updatedScreen)
    }

    @Test func controllerCanRespondToFocusedRemotePiApprovalRequest() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let approvalRequest = SessionApprovalRequest(
            title: "Deploy to production?",
            text: "Pi wants to run deploy --prod.",
            state: .pending
        )
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected\nApproval Request: Deploy to production?",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy to production?")
            ],
            approvalRequests: [approvalRequest]
        )
        let controlledScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: initialScreen.transcript,
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: initialScreen.activityItems,
            approvalRequests: initialScreen.approvalRequests
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.respondToFocusedRemoteSessionApprovalRequest(approvalRequest.id, decision: .approve)

        #expect(client.requestLog.contains("respondToApprovalRequest"))
        #expect(model.focusedSessionScreen?.approvalRequests.first?.state == .approved)
        #expect(model.focusedSessionScreen?.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "Approval Request: Deploy to production?",
            "Approved: Deploy to production?"
        ])
    }

    @Test func respondingToFocusedRemoteSessionApprovalRequestRequiresController() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let approvalRequest = SessionApprovalRequest(
            title: "deploy --prod",
            text: "Codex needs approval to deploy to production.",
            state: .pending
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Codex shared Session stream connected\nApproval Request: deploy --prod",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Codex shared Session stream connected"),
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: deploy --prod")
            ],
            approvalRequests: [approvalRequest]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(result: pairedMac, sessionScreen: screen)
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)

        do {
            try await model.respondToFocusedRemoteSessionApprovalRequest(approvalRequest.id, decision: .deny)
            Issue.record("Expected responding to an Approval Request as a Viewer to require taking Controller first")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before responding to Approval Requests")
        }
    }

    @Test func focusingRemoteSessionFetchesInitialScreenWhenObservationStartsWithoutSnapshot() async throws {
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
            sessionScreen: screen,
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await Task.yield()

        #expect(model.focusedSessionScreen == screen)
        #expect(client.requestLog == [
            "observeSessionScreen",
            "fetchSessionScreen"
        ])
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
        await client.disconnectObservedSession(RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        await Task.yield()

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
    }

    @Test func automaticallyReconnectsFocusedRemoteSessionAfterObservedDisconnect() async throws {
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
                .success(recoveredScreen)
            ]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await client.disconnectObservedSession(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        await Task.yield()

        #expect(model.focusedSessionScreen == initialScreen)
        #expect(model.focusedSessionIsStale)
        #expect(model.focusedSessionErrorMessage == "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)")

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()

        #expect(model.focusedSessionScreen == recoveredScreen)
        #expect(model.focusedSessionIsStale == false)
        #expect(model.focusedSessionErrorMessage == nil)
        #expect(client.requestLog == [
            "observeSessionScreen",
            "fetchSessionScreen",
            "observeSessionScreen",
            "fetchSessionScreen"
        ])
    }

    @Test func reconnectedFocusedRemotePiSessionKeepsStaleStructuredContentAndRequiresExplicitControllerRetake() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript: "Pi shared Session stream connected",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let controlledScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: initialScreen.transcript,
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: initialScreen.activityItems
        )
        let recoveredViewerScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript: initialScreen.transcript,
            activityItems: initialScreen.activityItems
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            sessionScreenResults: [
                .success(initialScreen),
                .success(recoveredViewerScreen)
            ],
            takeSessionControlResult: .success(controlledScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        await client.disconnectObservedSession(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        await Task.yield()

        #expect(model.focusedSessionScreen == controlledScreen)
        #expect(model.focusedSessionIsStale)
        #expect(model.focusedSessionSurfaceSupport == .supported)

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()

        #expect(model.focusedSessionScreen == recoveredViewerScreen)
        #expect(model.focusedSessionIsStale == false)
        #expect(model.focusedSessionIsController == false)
        #expect(model.focusedSessionSurfaceSupport == .supported)

        do {
            try await model.sendInputToFocusedRemoteSession("deploy")
            Issue.record("Expected reconnected remote Pi Session to require taking Controller again before sending a structured prompt")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before sending Session input")
        }
    }

    @Test func recordsReconnectFailureBreadcrumbWhenObservedSessionDisconnects() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreenResults: [.success(initialScreen)]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await client.disconnectObservedSession(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        await Task.yield()

        let breadcrumb = try #require(model.remoteFailureBreadcrumbs.last)
        #expect(breadcrumb.kind == .reconnectFailure)
        #expect(breadcrumb.operation == .observeSessionScreen)
        #expect(breadcrumb.message == "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)")
        #expect(breadcrumb.pairedMacID == pairedMac.id)
        #expect(breadcrumb.sessionID == session.id)
    }

    @Test func stoppingFocusedRemoteSessionCancelsAutomaticReconnectAfterObservedDisconnect() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreenResults: [.success(initialScreen)]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await client.disconnectObservedSession(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        await Task.yield()
        model.stopFocusingRemoteSession()

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()

        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
        #expect(model.focusedSessionIsStale == false)
        #expect(client.requestLog == [
            "observeSessionScreen",
            "fetchSessionScreen"
        ])
    }

    @Test func unauthorizedObservedSessionDisconnectStopsReconnectAndShowsPairingRecovery() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreenResults: [.success(initialScreen)]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await client.disconnectObservedSession(RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        await Task.yield()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
        #expect(model.pairingRecoveryMessage == "Pair this iPhone again to browse this Paired Mac")
        #expect(client.requestLog == [
            "observeSessionScreen",
            "fetchSessionScreen"
        ])
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

    @Test func takingFocusedRemoteSessionControlForgetsRevokedPairingAndShowsRecoveryMessage() async throws {
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
            sessionScreen: screen,
            takeSessionControlResult: .failure(RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)

        do {
            try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
            Issue.record("Expected taking Controller to fail when Pairing is revoked")
        } catch {
            #expect(error.localizedDescription == "Pair this iPhone again to browse this Paired Mac")
        }

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
        #expect(model.pairingRecoveryMessage == "Pair this iPhone again to browse this Paired Mac")
        #expect(model.focusedSessionID == nil)
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

    @Test func backgroundingFocusedSessionScreenPreservesAttachedSessionWhenViewDisappears() async throws {
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
        await model.handleFocusedSessionScreenDisappeared(preserveAttachment: true)

        #expect(client.releaseSessionControlRequests == [session.id])
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.controller == .mac)
        #expect(model.focusedSessionIsController == false)
    }

    @Test func returningToFocusedSessionAfterBackgroundStaysViewerUntilTakeControllerAgain() async throws {
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
        await model.focusRemoteSession(sessionID: session.id)

        #expect(client.takeSessionControlRequests == [.init(sessionID: session.id, columns: 44, rows: 12)])
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionIsController == false)
        #expect(model.focusedSessionScreen?.controller == .mac)

        do {
            try await model.sendTextToFocusedRemoteSession("still viewer")
            Issue.record("Expected returning from background to keep this iPhone in Viewer mode until Controller is explicitly retaken")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before sending terminal input")
        }
    }

    @Test func macControllerReclaimKeepsFocusedSessionAttachedAsViewerAndBlocksInput() async throws {
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

        let reclaimedScreen = SessionScreen(
            session: session,
            controller: .mac,
            transcript: "Claude ready\nLOCAL:mac reclaim",
            terminalColumns: 132,
            terminalRows: 40
        )
        await client.emitObservedScreen(reclaimedScreen)

        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionIsController == false)
        #expect(model.focusedSessionScreen == reclaimedScreen)

        do {
            try await model.sendTextToFocusedRemoteSession("still remote")
            Issue.record("Expected Mac reclaim to leave this iPhone attached as a Viewer until Controller is explicitly retaken")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before sending terminal input")
        }
    }

    @Test func sendingTextAppliesActionResponseWhenObservationDoesNotDeliverUpdateDuringRequest() async throws {
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
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let controlledScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude ready",
            terminalColumns: 44,
            terminalRows: 12
        )
        let actionResponseScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude readytyped",
            terminalColumns: 44,
            terminalRows: 12
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            sendSessionTextResult: .success(actionResponseScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendTextToFocusedRemoteSession("typed")

        #expect(model.focusedSessionScreen == actionResponseScreen)
    }

    @Test func sendingTextDoesNotOverwriteNewerObservedScreenWithStaleActionResponse() async throws {
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
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let controlledScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude ready",
            terminalColumns: 44,
            terminalRows: 12
        )
        let observedScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude readytyped",
            terminalColumns: 44,
            terminalRows: 12
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            sendSessionTextResult: .success(controlledScreen),
            observedScreenBeforeSendSessionTextResponse: observedScreen
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendTextToFocusedRemoteSession("typed")

        #expect(model.focusedSessionScreen == observedScreen)
    }

    @Test func sendingInputKeyAppliesActionResponseWhenObservationDoesNotDeliverUpdateDuringRequest() async throws {
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
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let controlledScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude ready",
            terminalColumns: 44,
            terminalRows: 12
        )
        let actionResponseScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude ready\nAUTH:654321",
            terminalColumns: 44,
            terminalRows: 12
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            sendSessionInputKeyResult: .success(actionResponseScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendInputKeyToFocusedRemoteSession(.enter)

        #expect(model.focusedSessionScreen == actionResponseScreen)
    }

    @Test func sendingInputKeyDoesNotOverwriteNewerObservedScreenWithStaleActionResponse() async throws {
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
        let pairedDeviceID = UUID()
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: pairedDeviceID
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let controlledScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude ready",
            terminalColumns: 44,
            terminalRows: 12
        )
        let observedScreen = SessionScreen(
            session: session,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "Claude ready\nAUTH:654321",
            terminalColumns: 44,
            terminalRows: 12
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            sendSessionInputKeyResult: .success(controlledScreen),
            observedScreenBeforeSendSessionInputKeyResponse: observedScreen
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendInputKeyToFocusedRemoteSession(.enter)

        #expect(model.focusedSessionScreen == observedScreen)
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

    @Test func launchingCodexDefaultRemoteSessionRefreshesCatalogProviderDetailAndFocusesSession() async throws {
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
            providerID: .codex,
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
        let refreshedCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Client Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .codex),
                            health: ProviderHealthSummary(state: .available, summary: "Codex available"),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
                            ),
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .ready,
                                summary: "Default session ready",
                                actionTitle: "Resume",
                                sessionID: session.id
                            )
                        )
                    ]
                )
            ]
        )
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .codex),
            health: ProviderHealthSummary(state: .available, summary: "Codex available"),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .codex),
            health: ProviderHealthSummary(state: .available, summary: "Codex available"),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            defaultSession: session,
            alternateSessions: [],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let launchedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Codex ready",
            activityItems: [SessionActivityItem(kind: .status, text: "Codex ready")]
        )
        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                catalog: refreshedCatalog,
                providerDetail: refreshedDetail,
                providerDetailResults: [initialDetail, refreshedDetail],
                sessionScreen: launchedScreen,
                launchedDefaultSession: session
            ),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .codex)
        let launchedSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        await Task.yield()

        #expect(launchedSession.id == session.id)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen == launchedScreen)
        #expect(model.focusedSessionScreen?.controller == nil)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: .codex)?.defaultSession?.id == session.id)
    }

    @Test func launchingRemotePiDefaultRemoteSessionRefreshesCatalogProviderDetailAndKeepsViewerByDefault() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Remote Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: groupID,
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
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
        let refreshedCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Remote Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .pi),
                            health: ProviderHealthSummary(state: .available, summary: "Pi 0.9.0 is available"),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
                            ),
                            prelaunchPrimarySurface: .structuredActivityFeed,
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .ready,
                                summary: "Default session ready",
                                actionTitle: "Resume",
                                sessionID: session.id
                            )
                        )
                    ]
                )
            ]
        )
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .pi),
            health: ProviderHealthSummary(state: .available, summary: "Pi 0.9.0 is available"),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            prelaunchPrimarySurface: .structuredActivityFeed,
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .pi),
            health: ProviderHealthSummary(state: .available, summary: "Pi 0.9.0 is available"),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            prelaunchPrimarySurface: .structuredActivityFeed,
            defaultSession: session,
            alternateSessions: [],
            failedSessions: []
        )
        let launchedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                catalog: refreshedCatalog,
                providerDetail: refreshedDetail,
                providerDetailResults: [initialDetail, refreshedDetail],
                sessionScreen: launchedScreen,
                launchedDefaultSession: session
            ),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: ProviderID.pi)
        let launchedSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: ProviderID.pi)
        await Task.yield()

        #expect(launchedSession.id == session.id)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen == launchedScreen)
        #expect(model.focusedSessionSurfaceSupport == SessionSurfaceSupport.supported)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: ProviderID.pi)?.defaultSession?.id == session.id)
    }

    @Test func creatingRemotePiNamedSessionRefreshesCatalogProviderDetailAndKeepsViewerByDefault() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Remote Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: groupID,
            remoteHostID: UUID()
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
            name: "Review",
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
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Remote Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .pi),
                            health: ProviderHealthSummary(state: .available, summary: "Pi 0.9.0 is available"),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
                            ),
                            prelaunchPrimarySurface: .structuredActivityFeed,
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
            provider: Provider(id: .pi),
            health: ProviderHealthSummary(state: .available, summary: "Pi 0.9.0 is available"),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            prelaunchPrimarySurface: .structuredActivityFeed,
            defaultSession: nil,
            alternateSessions: [session],
            failedSessions: []
        )
        let createdScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                catalog: refreshedCatalog,
                providerDetail: refreshedDetail,
                sessionScreen: createdScreen,
                createdNamedSession: session
            ),
            store: store
        )

        let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: ProviderID.pi)
        await Task.yield()

        #expect(createdSession.id == session.id)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen == createdScreen)
        #expect(model.focusedSessionSurfaceSupport == SessionSurfaceSupport.supported)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: ProviderID.pi)?.alternateSessions.map { $0.id } == [session.id])
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

    @Test func creatingCodexNamedRemoteSessionRefreshesCatalogProviderDetailAndFocusesSession() async throws {
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
            providerID: .codex,
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
                            provider: Provider(id: .codex),
                            health: ProviderHealthSummary(state: .available, summary: "Codex available"),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
                            ),
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
            provider: Provider(id: .codex),
            health: ProviderHealthSummary(state: .available, summary: "Codex available"),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
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
                sessionScreen: SessionScreen(
                    session: session,
                    primarySurface: .structuredActivityFeed,
                    controller: .mac,
                    transcript: "Codex ready",
                    activityItems: [SessionActivityItem(kind: .status, text: "Codex ready")]
                ),
                createdNamedSession: session
            ),
            store: store
        )

        let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .codex)
        await Task.yield()

        #expect(createdSession.id == session.id)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.primarySurface == .structuredActivityFeed)
        #expect(model.focusedSessionScreen?.controller == .mac)
        #expect(model.focusedSessionSurfaceSupport == .supported)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: .codex)?.alternateSessions.map { $0.id } == [session.id])
    }

    @Test func creatingNamedRemoteSessionPropagatesRequestFailuresWithoutOpeningSession() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            createdNamedSessionResult: .failure(RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        do {
            _ = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
            Issue.record("Expected createNamedSession to fail")
        } catch {
            #expect(error.localizedDescription == "The connection to this Paired Mac was lost.")
        }

        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
        #expect(client.requestLog == ["createNamedSession"])
    }

    @Test func creatingNamedRemoteSessionForgetsRevokedPairingAndShowsRecoveryMessage() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            createdNamedSessionResult: .failure(RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        do {
            _ = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
            Issue.record("Expected createNamedSession to fail when Pairing is revoked")
        } catch {
            #expect(error.localizedDescription == "Pair this iPhone again to browse this Paired Mac")
        }

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
        #expect(model.pairingRecoveryMessage == "Pair this iPhone again to browse this Paired Mac")
        #expect(model.focusedSessionID == nil)
    }

    @Test func creatingNamedRemoteSessionUsesPairedMacRecoveryMessageForTransportFailure() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            createdNamedSessionResult: .failure(RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        model.pairedMacAvailability[pairedMac.id] = .unavailablePairedMac

        do {
            _ = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
            Issue.record("Expected createNamedSession to fail when the Paired Mac is unavailable")
        } catch {
            #expect(error.localizedDescription == PairedMacAvailability.unavailablePairedMac.summary)
        }

        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
    }

    @Test func recordsActionFailureBreadcrumbWhenCreatingNamedRemoteSessionFails() async throws {
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
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            createdNamedSessionResult: .failure(RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await #expect(throws: (any Error).self) {
            _ = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
        }

        let breadcrumb = try #require(model.remoteFailureBreadcrumbs.last)
        #expect(breadcrumb.kind == .actionFailure)
        #expect(breadcrumb.operation == .createNamedSession)
        #expect(breadcrumb.message == "The connection to this Paired Mac was lost.")
        #expect(breadcrumb.pairedMacID == pairedMac.id)
        #expect(breadcrumb.workspaceID == workspace.id)
        #expect(breadcrumb.providerID == .claude)
    }

    @Test func creatingNamedRemoteSessionUsesWorkspaceAvailabilitySummaryForTransportFailure() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: groupID
        )
        let workspaceAvailability = WorkspaceAvailabilitySnapshot(
            workspaceID: workspace.id,
            state: .broken,
            summary: "Workspace requires repair.",
            checkedAt: Date(timeIntervalSince1970: 600)
        )
        let providerHealth = ProviderHealthSummary(
            state: .blocked,
            summary: "Provider Health is blocked by Workspace Availability",
            launchability: .notLaunchable
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Client Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .claude),
                            health: providerHealth,
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .notCreated,
                                summary: "No default session yet",
                                actionTitle: "Launch"
                            )
                        )
                    ],
                    remoteTarget: RemoteWorkspaceTargetOverview(
                        host: Host(id: UUID(), name: "Build Server", sshTarget: "build.example.com"),
                        hostValidation: nil,
                        workspaceAvailability: workspaceAvailability
                    )
                )
            ]
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: providerHealth,
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            providerDetail: detail,
            createdNamedSessionResult: .failure(RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        model.pairedMacAvailability[pairedMac.id] = .available

        await model.refreshActivePairedMacCatalog()
        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)

        do {
            _ = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
            Issue.record("Expected createNamedSession to fail when Workspace Availability blocks launch")
        } catch {
            #expect(error.localizedDescription == workspaceAvailability.summary)
        }
    }

    @Test func creatingNamedRemoteSessionUsesProviderHealthSummaryForTransportFailure() async throws {
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
        let providerHealth = ProviderHealthSummary(
            state: .unavailable,
            summary: "Claude is unavailable on this Workspace.",
            launchability: .notLaunchable
        )
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [WorkspaceGroup(id: groupID, name: "Client Work")],
            recentNavigation: [],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .claude),
                            health: providerHealth,
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .notCreated,
                                summary: "No default session yet",
                                actionTitle: "Launch"
                            )
                        )
                    ]
                )
            ]
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: providerHealth,
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            providerDetail: detail,
            createdNamedSessionResult: .failure(RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        model.pairedMacAvailability[pairedMac.id] = .available

        await model.refreshActivePairedMacCatalog()
        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)

        do {
            _ = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)
            Issue.record("Expected createNamedSession to fail when Provider Health blocks launch")
        } catch {
            #expect(error.localizedDescription == providerHealth.summary)
        }
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

    @Test func deletingDefaultRemoteSessionRecordRefreshesCatalogBackToNoDefaultState() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: groupID
        )
        let exitedSession = Session(
            id: UUID(),
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
            defaultSession: exitedSession,
            alternateSessions: [],
            failedSessions: []
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
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
                            alternateSessionCount: 0
                        )
                    ]
                )
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: refreshedCatalog,
            providerDetail: refreshedDetail,
            providerDetailResults: [initialDetail, refreshedDetail]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let deleted = try await model.deleteSessionRecord(
            sessionID: exitedSession.id,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(deleted)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.defaultSession == nil)
        #expect(model.catalog?.workspaceOverviews.first?.providerCards.first?.defaultSession.state == .notCreated)
        #expect(model.catalog?.workspaceOverviews.first?.providerCards.first?.defaultSession.actionTitle == "Launch")
        #expect(client.requestLog == [
            "fetchProviderDetail",
            "deleteSessionRecord",
            "fetchCatalog",
            "fetchProviderDetail"
        ])
    }

    @Test func deletingFailedRemoteSessionRecordRefreshesCatalogAndProviderDetail() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let groupID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: groupID
        )
        let failedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Review",
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
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .unavailable, summary: "Claude is unavailable on this Workspace."),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: [failedSession]
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .unavailable, summary: "Claude is unavailable on this Workspace."),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
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
                            health: ProviderHealthSummary(state: .unavailable, summary: "Claude is unavailable on this Workspace."),
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .notCreated,
                                summary: "No default session yet",
                                actionTitle: "Launch"
                            ),
                            alternateSessionCount: 0
                        )
                    ]
                )
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: refreshedCatalog,
            providerDetail: refreshedDetail,
            providerDetailResults: [initialDetail, refreshedDetail]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let deleted = try await model.deleteSessionRecord(
            sessionID: failedSession.id,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(deleted)
        #expect(model.focusedSessionID == nil)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.providerDetail(for: workspace.id, providerID: .claude)?.failedSessions.isEmpty == true)
        #expect(client.requestLog == [
            "fetchProviderDetail",
            "deleteSessionRecord",
            "fetchCatalog",
            "fetchProviderDetail"
        ])
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

    @Test func creatingFailedRemotePiNamedSessionStillFocusesInspectableStructuredViewer() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workspace = Workspace(
            id: UUID(),
            name: "Remote Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let failedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
            name: "Review",
            isDefault: false,
            state: .failed,
            failureMessage: "Pi RPC startup failed"
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
            provider: Provider(id: .pi),
            health: ProviderHealthSummary(
                state: .available,
                summary: "Pi 0.9.0 is available"
            ),
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            prelaunchPrimarySurface: .structuredActivityFeed,
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: [failedSession]
        )
        let failedScreen = SessionScreen(
            session: failedSession,
            primarySurface: .structuredActivityFeed,
            transcript: failedSession.failureMessage ?? "",
            activityItems: [SessionActivityItem(kind: .error, text: failedSession.failureMessage ?? "")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                providerDetail: refreshedDetail,
                sessionScreen: failedScreen,
                createdNamedSession: failedSession
            ),
            store: store
        )

        let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: ProviderID.pi)
        await Task.yield()

        #expect(createdSession.state == Session.State.failed)
        #expect(model.focusedSessionID == failedSession.id)
        #expect(model.focusedSessionScreen?.session.state == Session.State.failed)
        #expect(model.focusedSessionScreen?.primarySurface == SessionSurface.structuredActivityFeed)
        #expect(model.focusedSessionScreen?.activityItems.map(\.kind) == [SessionActivityItem.Kind.error])
        #expect(model.focusedSessionSurfaceSupport == SessionSurfaceSupport.supported)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: ProviderID.pi)?.failedSessions.map { $0.id } == [failedSession.id])
    }

    @Test func creatingFailedStructuredNamedRemoteSessionStillFocusesInspectableSessionRecord() async throws {
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
        let failedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .codex,
            name: "Session 1",
            isDefault: false,
            state: .failed,
            failureMessage: "Codex executable was not found in the service search paths."
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
            provider: Provider(id: .codex),
            health: ProviderHealthSummary(
                state: .unavailable,
                summary: "Codex executable was not found in the service search paths.",
                launchability: .notLaunchable
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: [failedSession]
        )
        let failedScreen = SessionScreen(
            session: failedSession,
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript: failedSession.failureMessage ?? "",
            activityItems: [SessionActivityItem(kind: .error, text: failedSession.failureMessage ?? "")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMac,
                providerDetail: refreshedDetail,
                sessionScreen: failedScreen,
                createdNamedSession: failedSession
            ),
            store: store
        )

        let createdSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .codex)
        await Task.yield()

        #expect(createdSession.state == .failed)
        #expect(model.focusedSessionID == failedSession.id)
        #expect(model.focusedSessionScreen?.session.state == .failed)
        #expect(model.focusedSessionScreen?.primarySurface == .structuredActivityFeed)
        #expect(model.focusedSessionScreen?.activityItems.map(\.kind) == [.error])
        #expect(model.focusedSessionSurfaceSupport == .supported)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: .codex)?.failedSessions.map { $0.id } == [failedSession.id])
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

    @Test func relaunchingFailedStructuredRemoteSessionKeepsInspectableIPhoneSurfaceSupport() async throws {
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
        let failedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .codex,
            name: "Review",
            isDefault: false,
            state: .failed,
            failureMessage: "Codex executable was not found in the service search paths."
        )
        let readySession = Session(
            id: failedSession.id,
            workspaceID: workspace.id,
            providerID: .codex,
            name: "Review",
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
        let failedScreen = SessionScreen(
            session: failedSession,
            primarySurface: .structuredActivityFeed,
            transcript: failedSession.failureMessage ?? "",
            activityItems: [SessionActivityItem(kind: .error, text: failedSession.failureMessage ?? "")]
        )
        let readyScreen = SessionScreen(
            session: readySession,
            primarySurface: .structuredActivityFeed,
            transcript: "Codex shared Session stream connected",
            activityItems: [SessionActivityItem(kind: .status, text: "Codex shared Session stream connected")]
        )
        let initialDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .codex),
            health: ProviderHealthSummary(state: .unavailable, summary: "Codex executable was not found in the service search paths."),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: [failedSession]
        )
        let refreshedDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .codex),
            health: ProviderHealthSummary(state: .available, summary: "Codex available"),
            defaultSession: nil,
            alternateSessions: [readySession],
            failedSessions: []
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            providerDetail: refreshedDetail,
            providerDetailResults: [initialDetail, refreshedDetail],
            sessionScreen: readyScreen,
            sessionScreenResults: [.success(failedScreen), .success(readyScreen)],
            launchedSession: readySession
        )
        let model = RemoteClientPairingModel(client: client, store: store)
        model.catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .codex)
        await model.focusRemoteSession(sessionID: failedSession.id)
        await Task.yield()

        #expect(model.focusedSessionSurfaceSupport == .supported)
        #expect(model.focusedSessionScreen?.activityItems.map(\.kind) == [.error])

        let relaunchedSession = try await model.launchOrResumeSession(
            sessionID: failedSession.id,
            workspaceID: workspace.id,
            providerID: .codex
        )
        try await Task.sleep(nanoseconds: 20_000_000)
        await Task.yield()

        #expect(relaunchedSession.state == .ready)
        #expect(model.focusedSessionSurfaceSupport == .supported)
        #expect(model.focusedSessionScreen?.session.state == .ready)
        #expect(model.focusedSessionScreen?.primarySurface == .structuredActivityFeed)
        #expect(model.providerDetail(for: workspace.id, providerID: .codex)?.failedSessions.isEmpty == true)
        #expect(model.providerDetail(for: workspace.id, providerID: .codex)?.alternateSessions.first?.state == .ready)
    }

    @Test func defaultSessionSectionAllowsDeletingNonRunningDefaultSessionRecord() {
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: UUID()
        )
        let exitedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: exitedSession,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteDefaultSessionSectionState(detail: detail)

        #expect(section.session == exitedSession)
        #expect(section.canDeleteSessionRecord)
    }

    @Test func defaultSessionSectionKeepsRunningDefaultSessionRecordNonDeletable() {
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
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: readySession,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteDefaultSessionSectionState(detail: detail)

        #expect(section.session == readySession)
        #expect(section.canDeleteSessionRecord == false)
    }

    @Test func defaultSessionSectionAllowsIdleReadyLocalIBMBobSessionRecordDeletion() {
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
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .ibmBob),
            health: ProviderHealthSummary(state: .available, summary: "IBM Bob available"),
            defaultSession: readySession,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteDefaultSessionSectionState(detail: detail)

        #expect(section.session == readySession)
        #expect(section.canDeleteSessionRecord)
    }

    @Test func namedSessionSectionShowsEmptyStateAndEnabledCreateActionForLaunchableClaudeProvider() {
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: UUID()
        )
        let health = ProviderHealthSummary(
            state: .available,
            summary: "Claude available",
            launchability: .launchable
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: health,
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteNamedSessionsSectionState(
            capabilities: detail.capabilities,
            detail: detail,
            errorMessage: nil
        )

        #expect(section.content == .empty)
        #expect(section.canCreateSession)
        #expect(section.createDisabledReason == nil)
    }

    @Test func namedSessionSectionUsesProviderHealthSummaryWhenCreateIsBlocked() {
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: UUID()
        )
        let health = ProviderHealthSummary(
            state: .blocked,
            summary: "Claude blocked by Host Validation",
            launchability: .notLaunchable
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: health,
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: false, disabledReason: "Claude blocked by Host Validation"),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: false, disabledReason: "Claude blocked by Host Validation")
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteNamedSessionsSectionState(
            capabilities: detail.capabilities,
            detail: detail,
            errorMessage: nil
        )

        #expect(section.content == .empty)
        #expect(section.canCreateSession == false)
        #expect(section.createDisabledReason == "Claude blocked by Host Validation")
    }

    @Test func namedSessionSectionKeepsNonRunningSessionsDeletableWhenCreateIsBlocked() {
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .remote,
            folderPath: "/srv/nexus",
            primaryGroupID: UUID()
        )
        let health = ProviderHealthSummary(
            state: .unavailable,
            summary: "Claude is unavailable on this Workspace.",
            launchability: .notLaunchable
        )
        let readySession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Live Review",
            isDefault: false,
            state: .ready
        )
        let exitedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Exited Review",
            isDefault: false,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        let interruptedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Interrupted Review",
            isDefault: false,
            state: .interrupted,
            failureMessage: "Session interrupted. Relaunch to resume work."
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: health,
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: false, disabledReason: "Claude is unavailable on this Workspace."),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: false, disabledReason: "Claude is unavailable on this Workspace.")
            ),
            defaultSession: nil,
            alternateSessions: [readySession, exitedSession, interruptedSession],
            failedSessions: []
        )

        let section = RemoteNamedSessionsSectionState(
            capabilities: detail.capabilities,
            detail: detail,
            errorMessage: nil
        )

        #expect(section.content == .sessions([readySession, exitedSession, interruptedSession]))
        #expect(section.canCreateSession == false)
        #expect(section.createDisabledReason == "Claude is unavailable on this Workspace.")
        #expect(section.deletableSessionIDs == [exitedSession.id, interruptedSession.id])
    }

    @Test func namedSessionSectionAllowsIdleReadyLocalIBMBobSessionRecordDeletion() {
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
            providerID: .ibmBob,
            name: "Review",
            isDefault: false,
            state: .ready
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .ibmBob),
            health: ProviderHealthSummary(state: .available, summary: "IBM Bob available"),
            defaultSession: nil,
            alternateSessions: [readySession],
            failedSessions: []
        )

        let section = RemoteNamedSessionsSectionState(
            capabilities: detail.capabilities,
            detail: detail,
            errorMessage: nil
        )

        #expect(section.content == .sessions([readySession]))
        #expect(section.deletableSessionIDs == [readySession.id])
    }

    @Test func namedSessionSectionKeepsUnsupportedProvidersVisibleButDisabled() {
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: UUID()
        )
        let health = ProviderHealthSummary(
            state: .notChecked,
            summary: "Health checks coming soon",
            launchability: .notChecked
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .pi),
            health: health,
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession,
                    isSupported: false,
                    isEnabled: false,
                    disabledReason: "Pi cannot launch a Default Session on this Workspace yet."
                ),
                createNamedSession: ProviderCapability(
                    action: .createNamedSession,
                    isSupported: false,
                    isEnabled: false,
                    disabledReason: "Pi cannot create Named Sessions on this Workspace yet."
                )
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteNamedSessionsSectionState(
            capabilities: detail.capabilities,
            detail: detail,
            errorMessage: nil
        )

        #expect(section.content == .empty)
        #expect(section.canCreateSession == false)
        #expect(section.createDisabledReason == "Pi cannot create Named Sessions on this Workspace yet.")
    }

    @Test func namedSessionSectionUsesServiceOwnedCapabilitiesInsteadOfProviderIDChecks() {
        let workspace = Workspace(
            id: UUID(),
            name: "Nexus",
            kind: .local,
            folderPath: "/tmp/nexus",
            primaryGroupID: UUID()
        )
        let health = ProviderHealthSummary(
            state: .notChecked,
            summary: "Health checks coming soon",
            launchability: .notChecked
        )
        let detail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .codex),
            health: health,
            capabilities: ProviderCapabilities(
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession,
                    isSupported: true,
                    isEnabled: true
                ),
                createNamedSession: ProviderCapability(
                    action: .createNamedSession,
                    isSupported: true,
                    isEnabled: true
                )
            ),
            defaultSession: nil,
            alternateSessions: [],
            failedSessions: []
        )

        let section = RemoteNamedSessionsSectionState(
            capabilities: detail.capabilities,
            detail: detail,
            errorMessage: nil
        )

        #expect(section.content == .empty)
        #expect(section.canCreateSession)
        #expect(section.createDisabledReason == nil)
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
    let createdNamedSessionResult: Result<Session, any Error>?
    let launchedSession: Session
    let stoppedSession: Session
    let deletedSessionRecord: Bool
    let catalogFetchGate: AsyncGate?
    let providerDetailFetchGate: AsyncGate?
    let takeSessionControlResult: Result<SessionScreen, any Error>?
    let releaseSessionControlResult: Result<SessionScreen, any Error>?
    let sendSessionInputResult: Result<SessionScreen, any Error>?
    let sendSessionTextResult: Result<SessionScreen, any Error>?
    let sendSessionInputKeyResult: Result<SessionScreen, any Error>?
    private let defaultSessionScreen: SessionScreen
    private var providerDetailResults: [ProviderDetail]
    private var sessionScreenResults: [Result<SessionScreen, any Error>]
    private let emitsInitialObservedScreen: Bool
    private let observedScreenBeforeSendSessionTextResponse: SessionScreen?
    private let observedScreenBeforeSendSessionInputKeyResponse: SessionScreen?
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
        createdNamedSessionResult: Result<Session, any Error>? = nil,
        launchedSession: Session? = nil,
        stoppedSession: Session? = nil,
        deletedSessionRecord: Bool = true,
        catalogFetchGate: AsyncGate? = nil,
        providerDetailFetchGate: AsyncGate? = nil,
        takeSessionControlResult: Result<SessionScreen, any Error>? = nil,
        releaseSessionControlResult: Result<SessionScreen, any Error>? = nil,
        sendSessionInputResult: Result<SessionScreen, any Error>? = nil,
        sendSessionTextResult: Result<SessionScreen, any Error>? = nil,
        sendSessionInputKeyResult: Result<SessionScreen, any Error>? = nil,
        emitsInitialObservedScreen: Bool = true,
        observedScreenBeforeSendSessionTextResponse: SessionScreen? = nil,
        observedScreenBeforeSendSessionInputKeyResponse: SessionScreen? = nil
    ) {
        self.result = result
        self.status = status
        self.catalog = catalog
        self.catalogResult = catalogResult
        self.providerDetail = providerDetail
        self.launchedDefaultSession = launchedDefaultSession ?? sessionScreen.session
        self.createdNamedSession = createdNamedSession ?? sessionScreen.session
        self.createdNamedSessionResult = createdNamedSessionResult
        self.launchedSession = launchedSession ?? sessionScreen.session
        self.stoppedSession = stoppedSession ?? sessionScreen.session
        self.deletedSessionRecord = deletedSessionRecord
        self.catalogFetchGate = catalogFetchGate
        self.providerDetailFetchGate = providerDetailFetchGate
        self.takeSessionControlResult = takeSessionControlResult
        self.releaseSessionControlResult = releaseSessionControlResult
        self.sendSessionInputResult = sendSessionInputResult
        self.sendSessionTextResult = sendSessionTextResult
        self.sendSessionInputKeyResult = sendSessionInputKeyResult
        self.providerDetailResults = providerDetailResults
        self.defaultSessionScreen = sessionScreen
        self.sessionScreenResults = sessionScreenResults
        self.emitsInitialObservedScreen = emitsInitialObservedScreen
        self.observedScreenBeforeSendSessionTextResponse = observedScreenBeforeSendSessionTextResponse
        self.observedScreenBeforeSendSessionInputKeyResponse = observedScreenBeforeSendSessionInputKeyResponse
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

        if let createdNamedSessionResult {
            return try createdNamedSessionResult.get()
        }

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

    func deleteSessionRecord(for pairedMac: PairedMac, sessionID: UUID) async throws -> Bool {
        requestLog.append("deleteSessionRecord")
        return deletedSessionRecord
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

        if let takeSessionControlResult {
            return try takeSessionControlResult.get()
        }

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

        if let releaseSessionControlResult {
            return try releaseSessionControlResult.get()
        }

        return SessionScreen(
            session: defaultSessionScreen.session,
            controller: .mac,
            transcript: defaultSessionScreen.transcript,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows
        )
    }

    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        requestLog.append("sendSessionInput")

        if let sendSessionInputResult {
            return try sendSessionInputResult.get()
        }

        return SessionScreen(
            session: defaultSessionScreen.session,
            primarySurface: defaultSessionScreen.primarySurface,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript + text,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows,
            activityItems: defaultSessionScreen.activityItems,
            approvalRequests: defaultSessionScreen.approvalRequests
        )
    }

    func respondToApprovalRequest(
        for pairedMac: PairedMac,
        sessionID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        requestLog.append("respondToApprovalRequest")

        let updatedApprovalRequests = defaultSessionScreen.approvalRequests.map { request in
            guard request.id == approvalRequestID else {
                return request
            }

            return SessionApprovalRequest(
                id: request.id,
                title: request.title,
                text: request.text,
                state: decision == .approve ? .approved : .denied
            )
        }

        return SessionScreen(
            session: defaultSessionScreen.session,
            primarySurface: defaultSessionScreen.primarySurface,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows,
            activityItems: defaultSessionScreen.activityItems + [
                SessionActivityItem(
                    kind: .approvalDecision,
                    text: "\(decision == .approve ? "Approved" : "Denied"): \(defaultSessionScreen.approvalRequests.first(where: { $0.id == approvalRequestID })?.title ?? "Approval Request")"
                )
            ],
            approvalRequests: updatedApprovalRequests
        )
    }

    func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        requestLog.append("sendSessionText")

        if let observedScreenBeforeSendSessionTextResponse {
            observationRegistration?.onUpdate(observedScreenBeforeSendSessionTextResponse)
        }

        if let sendSessionTextResult {
            return try sendSessionTextResult.get()
        }

        return SessionScreen(
            session: defaultSessionScreen.session,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript + text,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows
        )
    }

    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        requestLog.append("sendSessionInputKey")

        if let observedScreenBeforeSendSessionInputKeyResponse {
            observationRegistration?.onUpdate(observedScreenBeforeSendSessionInputKeyResponse)
        }

        if let sendSessionInputKeyResult {
            return try sendSessionInputKeyResult.get()
        }

        return SessionScreen(
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
        if emitsInitialObservedScreen {
            onUpdate(try await fetchSessionScreen(for: pairedMac, sessionID: sessionID))
        }
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

