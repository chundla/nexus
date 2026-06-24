import Foundation
import NexusDomain
import NexusSessionPresentation
import Observation
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
            client: StubRemotePairingClient(
                result: pairedMac,
                status: .success(RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: true))),
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

    @Test func remoteStatusRequestsUseShortLocalNetworkTimeout() async throws {
        StatusRequestTimeoutCapturingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusRequestTimeoutCapturingURLProtocol.self]
        let client = RemotePairingHTTPClient(session: URLSession(configuration: configuration))

        _ = try await client.fetchStatus(host: "studio.local", port: 9234)

        #expect(
            StatusRequestTimeoutCapturingURLProtocol.capturedTimeoutInterval()
                == RemotePairingHTTPClient.statusRequestTimeoutInterval
        )
    }

    @Test func refreshesActiveCatalogWhenActivePairedMacBecomesAvailableBeforeUnavailableMacFinishes() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let activeMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600)
        )
        let unavailableMac = PairedMac(
            name: "Offline Mac",
            host: "offline.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 601)
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([activeMac, unavailableMac])
        store.saveActivePairedMacID(activeMac.id)
        let unavailableGate = AsyncGate()
        let client = StubRemotePairingClient(
            result: activeMac,
            statusResultsByHost: [
                activeMac.host: .success(RemotePairedMacStatus(macName: activeMac.name, isRemoteAccessEnabled: true)),
                unavailableMac.host: .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)),
            ],
            statusProbeGatesByHost: [unavailableMac.host: unavailableGate]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        let refreshTask = Task {
            await model.refreshPairedMacAvailability()
        }
        defer {
            Task {
                await unavailableGate.open()
            }
        }

        try await waitUntilAsync(timeoutNanoseconds: 1_000_000_000) {
            client.catalogFetchStarted
        }

        #expect(model.availability(for: activeMac) == .available)
        #expect(model.availability(for: unavailableMac) == .unknown)
        await unavailableGate.open()
        await refreshTask.value
        #expect(model.availability(for: unavailableMac) == .unavailablePairedMac)
    }

    @Test func refreshesDelayedPairedMacAvailabilityInParallel() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let pairedMacs = (0..<10).map { index in
            PairedMac(
                name: "Studio Mac \(index)",
                host: "studio-\(index).local",
                port: 9234,
                pairedAt: Date(timeIntervalSince1970: TimeInterval(600 + index))
            )
        }
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs(pairedMacs)
        store.saveActivePairedMacID(pairedMacs[0].id)
        let statusProbeRecorder = StatusProbeRecorder()
        let model = RemoteClientPairingModel(
            client: StubRemotePairingClient(
                result: pairedMacs[0],
                statusProbeDelayNanoseconds: 150_000_000,
                statusProbeRecorder: statusProbeRecorder
            ),
            store: store
        )

        await model.refreshPairedMacAvailability()

        let maximumActiveProbeCount = await statusProbeRecorder.maximumActiveProbeCount()
        #expect(maximumActiveProbeCount > 1)
        #expect(maximumActiveProbeCount <= RemoteClientPairingModel.pairedMacAvailabilityProbeConcurrencyLimit)
        #expect(pairedMacs.map { model.availability(for: $0) } == Array(repeating: .available, count: pairedMacs.count))
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
            recentNavigation: [
                NavigationItem(target: .workspace(workspace.id), title: "Nexus", subtitle: "/tmp/nexus")
            ],
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
            recentNavigation: [
                NavigationItem(target: .workspace(workspace.id), title: "Nexus", subtitle: "/tmp/nexus")
            ],
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
            recentNavigation: [
                NavigationItem(
                    target: .provider(workspaceID: workspace.id, providerID: .claude), title: "Claude",
                    subtitle: "Nexus")
            ],
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

        let destination = try await model.browseDestination(
            for: .provider(workspaceID: workspace.id, providerID: .claude))

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
            recentNavigation: [
                NavigationItem(target: .session(session.id), title: "Session 1", subtitle: "Nexus • Claude")
            ],
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.map(\.id) == [session.id])
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
                catalogResult: .failure(
                    RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
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
            activityItems: [
                SessionActivityItem(kind: .status, text: "IBM Bob Session ready. Send a prompt to start IBM Bob.")
            ]
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
                SessionActivityItem(kind: .message, text: "You: Ship it"),
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
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: deploy --prod"),
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
        #expect(
            model.focusedSessionScreen?.activityItems.map(\.text) == [
                "Codex shared Session stream connected",
                "Approval Request: deploy --prod",
                "Approved: deploy --prod",
            ])
    }

    @Test func sendingStructuredPromptToFocusedRemotePiSessionUsesGenericSessionInputRouteAndUpdatesFocusedScreen()
        async throws
    {
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
                SessionActivityItem(kind: .message, text: "Pi: Remote deploy"),
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
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy to production?"),
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
        #expect(
            model.focusedSessionScreen?.activityItems.map(\.text) == [
                "Pi shared Session stream connected",
                "Approval Request: Deploy to production?",
                "Approved: Deploy to production?",
            ])
    }

    @Test func controllerCanRespondToFocusedRemotePiExtensionDialogAndKeepStructuredState() async throws {
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
        let dialog = SessionExtensionUIDialog(
            id: "dialog-1",
            kind: .confirm,
            title: "Deploy to production?",
            message: "Pi wants to run deploy --prod.",
            timeoutMilliseconds: 5000
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
            transcript: "> deploy",
            activityItems: [SessionActivityItem(kind: .message, text: "You: deploy")],
            extensionUI: SessionExtensionUIState(
                title: "Pi Demo",
                pendingDialogs: [dialog],
                notifications: [SessionExtensionUINotification(kind: .info, message: "Editor prefilled")],
                statuses: [SessionExtensionUIStatus(key: "rpc-demo", text: "Turn ready")],
                widgets: [SessionExtensionUIWidget(key: "rpc-demo", lines: ["Ready."], placement: .belowEditor)],
                editorText: "This text was set by the rpc-demo extension."
            ),
            providerEvents: [
                SessionProviderEvent(
                    sequence: 1,
                    providerID: .pi,
                    type: "extension_ui_request",
                    family: .unknown,
                    rawPayload: "{\"type\":\"extension_ui_request\"}"
                )
            ],
            isAgentTurnInProgress: true
        )
        let controlledScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: initialScreen.transcript,
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: initialScreen.activityItems,
            extensionUI: initialScreen.extensionUI,
            providerEvents: initialScreen.providerEvents,
            isAgentTurnInProgress: true
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .pairedDevice(pairedDeviceID),
            transcript: "> deploy\nDeployment approved",
            terminalColumns: 44,
            terminalRows: 12,
            activityItems: initialScreen.activityItems + [
                SessionActivityItem(kind: .message, text: "Pi: Deployment approved")
            ],
            extensionUI: SessionExtensionUIState(
                title: "Pi Demo",
                notifications: [SessionExtensionUINotification(kind: .info, message: "Editor prefilled")],
                statuses: [SessionExtensionUIStatus(key: "rpc-demo", text: "Turn ready")],
                widgets: [SessionExtensionUIWidget(key: "rpc-demo", lines: ["Ready."], placement: .belowEditor)],
                editorText: "This text was set by the rpc-demo extension."
            ),
            providerEvents: initialScreen.providerEvents,
            isAgentTurnInProgress: false
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            takeSessionControlResult: .success(controlledScreen),
            respondToExtensionDialogResult: .success(updatedScreen)
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.respondToFocusedRemoteSessionExtensionDialog(dialog.id, response: .confirmed(true))

        #expect(client.requestLog.contains("respondToExtensionDialog"))
        #expect(model.focusedSessionScreen == updatedScreen)
        #expect(model.focusedSessionScreen?.providerEvents == initialScreen.providerEvents)
        #expect(model.focusedSessionScreen?.extensionUI?.pendingDialogs.isEmpty == true)
    }

    @Test func respondingToFocusedRemotePiExtensionDialogRequiresController() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let dialog = SessionExtensionUIDialog(
            id: "dialog-1",
            kind: .confirm,
            title: "Deploy to production?",
            message: "Pi wants to run deploy --prod."
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
            transcript: "> deploy",
            activityItems: [SessionActivityItem(kind: .message, text: "You: deploy")],
            extensionUI: SessionExtensionUIState(pendingDialogs: [dialog])
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(result: pairedMac, sessionScreen: screen)
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)

        do {
            try await model.respondToFocusedRemoteSessionExtensionDialog(dialog.id, response: .confirmed(true))
            Issue.record(
                "Expected responding to a remote Pi Extension UI dialog as a Viewer to require taking Controller first")
        } catch {
            #expect(
                error.localizedDescription == "Take Controller on this iPhone before responding to Extension UI dialogs"
            )
        }
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
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: deploy --prod"),
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
            #expect(
                error.localizedDescription == "Take Controller on this iPhone before responding to Approval Requests")
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
        #expect(
            client.requestLog == [
                "observeSessionScreen",
                "fetchSessionScreen",
            ])
    }

    @Test func focusRemoteSessionFallsBackToFetchedScreenWhenObservationStartupStalls() async throws {
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
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let observationStartGate = AsyncGate()
        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: screen,
            observeSessionStartGate: observationStartGate
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        let focusTask = Task {
            await model.focusRemoteSession(sessionID: session.id)
        }

        for _ in 0..<20 {
            if model.focusedSessionScreen == screen {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.focusedSessionScreen == screen)
        #expect(
            client.requestLog == [
                "observeSessionScreen",
                "fetchSessionScreen",
            ])

        await observationStartGate.open()
        await focusTask.value
    }

    @Test func focusRemoteSessionKeepsSlowObservationStartupAliveLongEnoughToReceiveUpdates() async throws {
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
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "You: list files\nPi: Done",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: list files"),
                SessionActivityItem(kind: .message, text: "Pi: Done"),
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let observationStartGate = AsyncGate()
        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: initialScreen,
            emitsInitialObservedScreen: false,
            observeSessionStartGate: observationStartGate
        )
        let model = RemoteClientPairingModel(
            client: client,
            store: store,
            focusedSessionObservationStartupTimeoutNanoseconds: 2_000_000_000
        )

        let focusTask = Task {
            await model.focusRemoteSession(sessionID: session.id)
        }

        for _ in 0..<20 {
            if model.focusedSessionScreen == initialScreen {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.focusedSessionScreen == initialScreen)
        #expect(
            client.requestLog == [
                "observeSessionScreen",
                "fetchSessionScreen",
            ])

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await observationStartGate.open()
        await focusTask.value
        await client.emitObservedScreen(updatedScreen)

        for _ in 0..<20 {
            if model.focusedSessionScreen == updatedScreen {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.focusedSessionScreen == updatedScreen)
        let expectedPrefix = ["observeSessionScreen", "fetchSessionScreen"]
        #expect(Array(client.requestLog.prefix(expectedPrefix.count)) == expectedPrefix)
    }

    @Test func workspaceBrowsePresentationStaysStableDuringTranscriptOnlyFocusedSessionUpdates() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let group = WorkspaceGroup(id: UUID(), name: "Client Work")
        let alphaWorkspace = Workspace(
            id: UUID(),
            name: "Alpha",
            kind: .local,
            folderPath: "/tmp/alpha",
            primaryGroupID: group.id
        )
        let zuluWorkspace = Workspace(
            id: UUID(),
            name: "Zulu",
            kind: .local,
            folderPath: "/tmp/zulu",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: zuluWorkspace.id,
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [group],
            recentNavigation: [
                NavigationItem(
                    target: .workspace(alphaWorkspace.id), title: alphaWorkspace.name,
                    subtitle: alphaWorkspace.folderPath)
            ],
            workspaceOverviews: [
                WorkspaceOverview(workspace: alphaWorkspace, providerCards: []),
                WorkspaceOverview(workspace: zuluWorkspace, providerCards: []),
            ]
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let updatedScreen = SessionScreen(session: session, transcript: "Claude ready\nUpdated transcript")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: initialScreen,
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != initialScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let initialPresentation = try #require(
            model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil))
        #expect(initialPresentation.workspaceOverviews.map(\.workspace.id) == [zuluWorkspace.id, alphaWorkspace.id])

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let presentationChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil)
        } onChange: {
            Task { @MainActor in
                presentationChanged.changed = true
            }
        }

        await client.emitObservedScreen(updatedScreen)
        for _ in 0..<20 where model.focusedSessionScreen != updatedScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(presentationChanged.changed == false)
        #expect(
            model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil) == initialPresentation)
    }

    @Test func loadOlderFocusedPiStructuredSessionHistoryPrependsPersistedRowsWithoutDisturbingLiveTailState()
        async throws
    {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let olderActivity = SessionActivityItem(kind: .message, text: "Pi: Older context")
        let liveActivity = SessionActivityItem(kind: .message, text: "Pi: Latest reply")
        let approvalRequest = SessionApprovalRequest(title: "Deploy", text: "Deploy now?", state: .pending)
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [liveActivity],
            approvalRequests: [approvalRequest],
            isAgentTurnInProgress: true
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: screen,
            structuredHistoryPages: [
                StructuredSessionHistoryPage(
                    sessionID: session.id,
                    activityItems: [olderActivity],
                    providerEvents: [],
                    nextCursor: nil
                )
            ]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != screen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.canLoadOlderFocusedStructuredSessionHistory)
        #expect(model.focusedStructuredSessionPresentation?.feed.activityRows.map(\.text) == [liveActivity.text])
        #expect(model.focusedStructuredSessionPresentation?.feed.pendingApprovalRequests == [approvalRequest])
        // Pending approvals suppress the thinking indicator in structured presentation.
        #expect(model.focusedStructuredSessionPresentation?.feed.thinkingIndicator == nil)

        await model.loadOlderFocusedStructuredSessionHistory()

        #expect(model.canLoadOlderFocusedStructuredSessionHistory == false)
        #expect(
            model.focusedStructuredSessionPresentation?.feed.activityRows.map(\.text) == [
                olderActivity.text,
                liveActivity.text,
            ])
        #expect(model.focusedStructuredSessionPresentation?.feed.pendingApprovalRequests == [approvalRequest])
        #expect(model.focusedStructuredSessionPresentation?.feed.thinkingIndicator == nil)
        #expect(client.structuredHistoryPageRequests.map(\.sessionID) == [session.id])
    }

    @Test func focusedStructuredSessionPresentationAutoRecoversObservationGapsFromPersistedHistory() async throws {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let droppedActivity = SessionActivityItem(kind: .message, text: "Pi: thinking step 1")
        let previousTailActivity = SessionActivityItem(kind: .message, text: "Pi: thinking step 2")
        let latestActivity = SessionActivityItem(kind: .message, text: "Pi: thinking step 3")
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [droppedActivity, previousTailActivity],
            isAgentTurnInProgress: true
        )
        let recoveredLiveScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [latestActivity],
            isAgentTurnInProgress: true
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: initialScreen,
            structuredHistoryPages: [
                StructuredSessionHistoryPage(
                    sessionID: session.id,
                    activityItems: [droppedActivity, previousTailActivity],
                    providerEvents: [],
                    nextCursor: nil
                )
            ],
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != initialScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        await client.emitObservedScreen(recoveredLiveScreen)
        for _ in 0..<40
        where model.focusedStructuredSessionPresentation?.feed.activityRows.map(\.text) != [
            droppedActivity.text,
            previousTailActivity.text,
            latestActivity.text,
        ] {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(
            model.focusedStructuredSessionPresentation?.feed.activityRows.map(\.text) == [
                droppedActivity.text,
                previousTailActivity.text,
                latestActivity.text,
            ])
        #expect(model.focusedStructuredSessionPresentation?.feed.pendingApprovalRequests.isEmpty == true)
        #expect(
            model.focusedStructuredSessionPresentation?.feed.thinkingIndicator
                == StructuredSessionThinkingIndicator(text: "Thinking…"))
        #expect(client.structuredHistoryPageRequests.map(\.sessionID) == [session.id])
    }

    @Test func focusedStructuredSessionPresentationStaysStableDuringTranscriptOnlyUpdates() async throws {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let activity = SessionActivityItem(kind: .message, text: "Pi: Ready")
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [activity]
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected\nverbose transcript update",
            activityItems: [activity]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: initialScreen,
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != initialScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let initialPresentation = try #require(model.focusedStructuredSessionPresentation)
        #expect(initialPresentation.feed.activityRows.map(\.text) == [activity.text])

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let presentationChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.focusedStructuredSessionPresentation
        } onChange: {
            Task { @MainActor in
                presentationChanged.changed = true
            }
        }

        await client.emitObservedScreen(updatedScreen)
        for _ in 0..<20 where model.focusedSessionScreen != updatedScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(model.focusedSessionScreen?.transcript == updatedScreen.transcript)
        #expect(presentationChanged.changed == false)
        #expect(model.focusedStructuredSessionPresentation == initialPresentation)
    }

    @Test func focusedStructuredSessionChromePresentationStaysStableDuringAppendOnlyUpdates() async throws {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let initialActivity = SessionActivityItem(kind: .message, text: "Pi: Ready")
        let appendedActivity = SessionActivityItem(kind: .message, text: "Pi: Streaming more output")
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [initialActivity]
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected\nPi: Streaming more output",
            activityItems: [initialActivity, appendedActivity]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: initialScreen,
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != initialScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let initialChrome = try #require(model.focusedStructuredSessionChromePresentation)
        let initialFeed = try #require(model.focusedStructuredSessionPresentation)
        #expect(initialFeed.feed.activityRows.map(\.text) == [initialActivity.text])

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let chromeChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.focusedStructuredSessionChromePresentation
        } onChange: {
            Task { @MainActor in
                chromeChanged.changed = true
            }
        }

        await client.emitObservedScreen(updatedScreen)
        for _ in 0..<20 where model.focusedSessionScreen != updatedScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(
            model.focusedStructuredSessionPresentation?.feed.activityRows.map(\.text) == [
                initialActivity.text,
                appendedActivity.text,
            ])
        #expect(chromeChanged.changed == false)
        #expect(model.focusedStructuredSessionChromePresentation == initialChrome)
    }

    @Test func focusedStructuredSessionPresentationStaysStableDuringChromeOnlyExtensionUpdates() async throws {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let activity = SessionActivityItem(kind: .message, text: "Pi: Ready")
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [activity],
            extensionUI: SessionExtensionUIState(
                title: "Plan",
                statuses: [SessionExtensionUIStatus(key: "status", text: "Planning")],
                widgets: [SessionExtensionUIWidget(key: "summary", lines: ["One"])],
                editorText: "draft"
            )
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [activity],
            extensionUI: SessionExtensionUIState(
                title: "Plan updated",
                statuses: [SessionExtensionUIStatus(key: "status", text: "Ready")],
                widgets: [SessionExtensionUIWidget(key: "summary", lines: ["Two"])],
                editorText: "draft updated"
            )
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: initialScreen,
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != initialScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let initialPresentation = try #require(model.focusedStructuredSessionPresentation)
        let initialChrome = try #require(model.focusedStructuredSessionChromePresentation)

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let presentationChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.focusedStructuredSessionPresentation
        } onChange: {
            Task { @MainActor in
                presentationChanged.changed = true
            }
        }

        await client.emitObservedScreen(updatedScreen)
        for _ in 0..<20 where model.focusedSessionScreen != updatedScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(presentationChanged.changed == false)
        #expect(model.focusedStructuredSessionPresentation == initialPresentation)
        #expect(model.focusedStructuredSessionChromePresentation != initialChrome)
    }

    @Test func focusedSessionSurfacePresentationStaysStableDuringAppendOnlyStructuredUpdates() async throws {
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
        let catalog = RemoteWorkspaceCatalog(
            workspaceGroups: [],
            recentNavigation: [],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let initialActivity = SessionActivityItem(kind: .message, text: "Pi: Ready")
        let appendedActivity = SessionActivityItem(kind: .message, text: "Pi: Streaming more output")
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [initialActivity]
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected\nPi: Streaming more output",
            activityItems: [initialActivity, appendedActivity]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalog: catalog,
            sessionScreen: initialScreen,
            emitsInitialObservedScreen: false
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != initialScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let initialSurfacePresentation = try #require(model.focusedSessionSurfacePresentation)
        #expect(initialSurfacePresentation == remoteSessionSurfacePresentation(for: initialScreen, isReady: true))

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let surfacePresentationChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.focusedSessionSurfacePresentation
        } onChange: {
            Task { @MainActor in
                surfacePresentationChanged.changed = true
            }
        }

        await client.emitObservedScreen(updatedScreen)
        for _ in 0..<20 where model.focusedSessionScreen != updatedScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(surfacePresentationChanged.changed == false)
        #expect(model.focusedSessionSurfacePresentation == initialSurfacePresentation)
    }

    @Test func workspaceBrowsePresentationStaysStableDuringPairedMacAvailabilityRefreshes() async throws {
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
            recentNavigation: [
                NavigationItem(target: .workspace(workspace.id), title: workspace.name, subtitle: workspace.folderPath)
            ],
            workspaceOverviews: [WorkspaceOverview(workspace: workspace, providerCards: [])]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            status: .success(RemotePairedMacStatus(macName: pairedMac.name, isRemoteAccessEnabled: true)),
            catalog: catalog
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        let initialPresentation = try #require(
            model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil))

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let presentationChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil)
        } onChange: {
            Task { @MainActor in
                presentationChanged.changed = true
            }
        }

        await model.refreshPairedMacAvailability()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(presentationChanged.changed == false)
        #expect(
            model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil) == initialPresentation)
    }

    @Test func focusedSessionWorkspaceLocationStaysStableDuringUnrelatedCatalogRefreshes() async throws {
        let suiteName = "RemoteClientPairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let group = WorkspaceGroup(id: UUID(), name: "Client Work")
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 22)
        let workspace = Workspace(
            id: UUID(),
            name: "Remote API",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: group.id,
            remoteHostID: host.id
        )
        let otherWorkspace = Workspace(
            id: UUID(),
            name: "Other",
            kind: .local,
            folderPath: "/tmp/other",
            primaryGroupID: group.id
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
        let workspaceAvailability = WorkspaceAvailabilitySnapshot(
            workspaceID: workspace.id,
            state: .available,
            summary: "Available",
            checkedAt: Date(timeIntervalSince1970: 600)
        )
        let remoteTarget = RemoteWorkspaceTargetOverview(
            host: host,
            hostValidation: nil,
            workspaceAvailability: workspaceAvailability
        )
        let initialCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [group],
            recentNavigation: [
                NavigationItem(
                    target: .workspace(otherWorkspace.id), title: otherWorkspace.name,
                    subtitle: otherWorkspace.folderPath)
            ],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [],
                    remoteTarget: remoteTarget
                ),
                WorkspaceOverview(workspace: otherWorkspace, providerCards: []),
            ]
        )
        let refreshedCatalog = RemoteWorkspaceCatalog(
            workspaceGroups: [group],
            recentNavigation: [
                NavigationItem(target: .workspace(workspace.id), title: workspace.name, subtitle: "/srv/api")
            ],
            workspaceOverviews: [
                WorkspaceOverview(
                    workspace: workspace,
                    providerCards: [],
                    remoteTarget: remoteTarget
                ),
                WorkspaceOverview(
                    workspace: otherWorkspace,
                    providerCards: [
                        WorkspaceProviderCard(
                            provider: Provider(id: .pi),
                            health: ProviderHealthSummary(state: .available, summary: "Pi available"),
                            defaultSession: ProviderDefaultSessionSummary(
                                state: .notCreated, summary: "Not created", actionTitle: "Start")
                        )
                    ]
                ),
            ]
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let client = StubRemotePairingClient(
            result: pairedMac,
            catalogResults: [initialCatalog, refreshedCatalog],
            sessionScreen: screen
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.refreshActivePairedMacCatalog()
        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen != screen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let initialLocation = try #require(model.focusedSessionWorkspaceLocation)
        #expect(initialLocation == "Build Server • /srv/api")

        @MainActor
        final class ObservationChangeState {
            var changed = false
        }

        let locationChanged = ObservationChangeState()
        withObservationTracking {
            _ = model.focusedSessionWorkspaceLocation
        } onChange: {
            Task { @MainActor in
                locationChanged.changed = true
            }
        }

        await model.refreshActivePairedMacCatalog()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(locationChanged.changed == false)
        #expect(model.focusedSessionWorkspaceLocation == initialLocation)
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
        await client.disconnectObservedSession(
            RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
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
                .success(recoveredScreen),
            ]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await client.disconnectObservedSession(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        await Task.yield()

        #expect(model.focusedSessionScreen == initialScreen)
        #expect(model.focusedSessionIsStale)
        #expect(
            model.focusedSessionErrorMessage == "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)")

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()

        #expect(model.focusedSessionScreen == recoveredScreen)
        #expect(model.focusedSessionIsStale == false)
        #expect(model.focusedSessionErrorMessage == nil)
        #expect(
            client.requestLog == [
                "observeSessionScreen",
                "fetchSessionScreen",
                "observeSessionScreen",
                "fetchSessionScreen",
            ])
    }

    @Test func focusRemoteSessionPrefersObservedInitialScreenOverRedundantFetchSnapshot() async throws {
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
        let pairedMac = PairedMac(
            name: "Studio Mac",
            host: "studio.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID()
        )
        let observedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript:
                "Pi shared Session stream connected\nsubagent reviewer: Review the latest diff and summarize issues",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(
                    kind: .message, text: "subagent reviewer: Review the latest diff and summarize issues"),
            ]
        )
        let staleFetchedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript: "Delete the shallow leftover terminal renderer copy and make one seam authoritative",
            activityItems: [
                SessionActivityItem(
                    kind: .message,
                    text: "Pi: Delete the shallow leftover terminal renderer copy and make one seam authoritative")
            ]
        )
        let store = UserDefaultsPairedMacStore(defaults: defaults)
        try store.savePairedMacs([pairedMac])
        store.saveActivePairedMacID(pairedMac.id)

        let fetchGate = AsyncGate()
        let client = StubRemotePairingClient(
            result: pairedMac,
            sessionScreen: observedScreen,
            sessionScreenResults: [.success(staleFetchedScreen)],
            sessionScreenFetchGate: fetchGate,
            emitsInitialObservedScreenAsynchronously: true,
            initialObservedScreen: observedScreen
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        let focusTask = Task {
            await model.focusRemoteSession(sessionID: session.id)
        }

        for _ in 0..<20 {
            if model.focusedSessionScreen == observedScreen {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.focusedSessionScreen == observedScreen)

        await fetchGate.open()
        await focusTask.value
        await Task.yield()

        #expect(model.focusedSessionScreen == observedScreen)
        #expect(client.requestLog == ["observeSessionScreen"])
    }

    @Test func reconnectedFocusedRemotePiSessionKeepsStaleStructuredContentAndRequiresExplicitControllerRetake()
        async throws
    {
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
                .success(recoveredViewerScreen),
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

        try await waitUntilAsync(timeoutNanoseconds: 5_000_000_000, pollIntervalNanoseconds: 50_000_000) {
            model.focusedSessionScreen == recoveredViewerScreen && model.focusedSessionIsStale == false
                && model.focusedSessionIsController == false
        }

        #expect(model.focusedSessionScreen == recoveredViewerScreen)
        #expect(model.focusedSessionIsStale == false)
        #expect(model.focusedSessionIsController == false)
        #expect(model.focusedSessionSurfaceSupport == .supported)

        do {
            try await model.sendInputToFocusedRemoteSession("deploy")
            Issue.record(
                "Expected reconnected remote Pi Session to require taking Controller again before sending a structured prompt"
            )
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
        #expect(
            client.requestLog == [
                "observeSessionScreen",
                "fetchSessionScreen",
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
        await client.disconnectObservedSession(
            RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        await Task.yield()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()

        #expect(model.pairedMacs.isEmpty)
        #expect(model.activePairedMac == nil)
        #expect(model.focusedSessionID == nil)
        #expect(model.focusedSessionScreen == nil)
        #expect(model.pairingRecoveryMessage == "Pair this iPhone again to browse this Paired Mac")
        #expect(
            client.requestLog == [
                "observeSessionScreen",
                "fetchSessionScreen",
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
                .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)),
            ]
        )
        let model = RemoteClientPairingModel(client: client, store: store)

        await model.focusRemoteSession(sessionID: session.id)
        await model.refreshFocusedSessionScreen()

        #expect(model.focusedSessionScreen == screen)
        #expect(model.focusedSessionIsStale)
        #expect(
            model.focusedSessionErrorMessage == "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)")
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
                .success(recoveredScreen),
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
            takeSessionControlResult: .failure(
                RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
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

        #expect(
            client.takeSessionControlRequests == [
                .init(sessionID: session.id, columns: 44, rows: 12),
                .init(sessionID: session.id, columns: 60, rows: 20),
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
            Issue.record(
                "Expected returning from background to keep this iPhone in Viewer mode until Controller is explicitly retaken"
            )
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
        for _ in 0..<30 where model.focusedSessionScreen != reclaimedScreen {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionIsController == false)
        #expect(model.focusedSessionScreen == reclaimedScreen)

        do {
            try await model.sendTextToFocusedRemoteSession("still remote")
            Issue.record(
                "Expected Mac reclaim to leave this iPhone attached as a Viewer until Controller is explicitly retaken")
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
        let launchedSession = try await model.launchOrResumeDefaultSession(
            workspaceID: workspace.id, providerID: .claude)
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
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession, isSupported: true, isEnabled: true)
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
            controller: .mac,
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
        let launchedSession = try await model.launchOrResumeDefaultSession(
            workspaceID: workspace.id, providerID: .codex)
        await Task.yield()

        #expect(launchedSession.id == session.id)
        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionID == session.id)
        #expect(model.focusedSessionScreen == launchedScreen)
        #expect(model.focusedSessionScreen?.controller == .mac)
        #expect(model.focusedSessionIsController == false)
        #expect(model.providerDetail(for: workspace.id, providerID: .codex)?.defaultSession?.id == session.id)
    }

    @Test func launchingRemotePiDefaultRemoteSessionRefreshesCatalogProviderDetailAndKeepsViewerByDefault() async throws
    {
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
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession, isSupported: true, isEnabled: true)
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
        let launchedSession = try await model.launchOrResumeDefaultSession(
            workspaceID: workspace.id, providerID: ProviderID.pi)
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
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession, isSupported: true, isEnabled: true)
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: ProviderID.pi)?.alternateSessions.map { $0.id } == [
                session.id
            ])
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.map { $0.id } == [
                session.id
            ])
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
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession, isSupported: true, isEnabled: true)
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: .codex)?.alternateSessions.map { $0.id } == [session.id]
        )
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
            createdNamedSessionResult: .failure(
                RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
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
            createdNamedSessionResult: .failure(
                RemotePairingHTTPError.pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
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
            createdNamedSessionResult: .failure(
                RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
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
            createdNamedSessionResult: .failure(
                RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
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
            createdNamedSessionResult: .failure(
                RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
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
            createdNamedSessionResult: .failure(
                RemotePairingHTTPError.requestFailed("The connection to this Paired Mac was lost."))
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
        #expect(
            client.requestLog == [
                "createNamedSession",
                "observeSessionScreen",
                "fetchSessionScreen",
                "fetchCatalog",
            ])

        await catalogGate.open()

        for _ in 0..<20 where client.providerDetailFetchStarted == false {
            await Task.yield()
        }

        #expect(
            client.requestLog == [
                "createNamedSession",
                "observeSessionScreen",
                "fetchSessionScreen",
                "fetchCatalog",
                "fetchProviderDetail",
            ])

        await providerDetailGate.open()
        try await createTask.value
        await Task.yield()

        #expect(model.catalog == refreshedCatalog)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.controller == .mac)
        #expect(model.focusedSessionIsController == false)
        #expect(
            model.providerDetail(for: workspace.id, providerID: .claude)?.alternateSessions.map(\.id) == [session.id])
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
                    .success(
                        SessionScreen(
                            session: stoppedSession, transcript: "Session exited. Relaunch to start a new live runtime."
                        )),
                ],
                stoppedSession: stoppedSession
            ),
            store: store
        )

        await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        await model.focusRemoteSession(sessionID: readySession.id)
        let result = try await model.stopSession(
            sessionID: readySession.id, workspaceID: workspace.id, providerID: .claude)
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
        #expect(
            client.requestLog == [
                "fetchProviderDetail",
                "deleteSessionRecord",
                "fetchCatalog",
                "fetchProviderDetail",
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
                            health: ProviderHealthSummary(
                                state: .unavailable, summary: "Claude is unavailable on this Workspace."),
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
        #expect(
            client.requestLog == [
                "fetchProviderDetail",
                "deleteSessionRecord",
                "fetchCatalog",
                "fetchProviderDetail",
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: .claude)?.failedSessions.map { $0.id } == [
                failedSession.id
            ])
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: ProviderID.pi)?.failedSessions.map { $0.id } == [
                failedSession.id
            ])
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
        #expect(
            model.providerDetail(for: workspace.id, providerID: .codex)?.failedSessions.map { $0.id } == [
                failedSession.id
            ])
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
        let result = try await model.launchOrResumeSession(
            sessionID: exitedSession.id, workspaceID: workspace.id, providerID: .claude)
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
            health: ProviderHealthSummary(
                state: .unavailable, summary: "Codex executable was not found in the service search paths."),
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
        for _ in 0..<40 where model.focusedSessionScreen?.session.state != .ready {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(relaunchedSession.state == .ready)
        #expect(model.focusedSessionSurfaceSupport == .supported)
        #expect(model.focusedSessionScreen?.session.state == .ready)
        #expect(model.focusedSessionScreen?.primarySurface == .structuredActivityFeed)
        for _ in 0..<40
        where model.providerDetail(for: workspace.id, providerID: .codex)?.alternateSessions.first?.state != .ready {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: false,
                    disabledReason: "Claude blocked by Host Validation"),
                createNamedSession: ProviderCapability(
                    action: .createNamedSession, isSupported: true, isEnabled: false,
                    disabledReason: "Claude blocked by Host Validation")
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
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: false,
                    disabledReason: "Claude is unavailable on this Workspace."),
                createNamedSession: ProviderCapability(
                    action: .createNamedSession, isSupported: true, isEnabled: false,
                    disabledReason: "Claude is unavailable on this Workspace.")
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
    private var catalogResults: [RemoteWorkspaceCatalog]
    let providerDetail: ProviderDetail
    let launchedDefaultSession: Session
    let createdNamedSession: Session
    let createdNamedSessionResult: Result<Session, any Error>?
    let launchedSession: Session
    let stoppedSession: Session
    let deletedSessionRecord: Bool
    let catalogFetchGate: AsyncGate?
    private var structuredHistoryPages: [StructuredSessionHistoryPage]
    let providerDetailFetchGate: AsyncGate?
    let sessionScreenFetchGate: AsyncGate?
    let takeSessionControlResult: Result<SessionScreen, any Error>?
    let releaseSessionControlResult: Result<SessionScreen, any Error>?
    let sendSessionInputResult: Result<SessionScreen, any Error>?
    let respondToExtensionDialogResult: Result<SessionScreen, any Error>?
    let sendSessionTextResult: Result<SessionScreen, any Error>?
    let sendSessionInputKeyResult: Result<SessionScreen, any Error>?
    private let defaultSessionScreen: SessionScreen
    private var providerDetailResults: [ProviderDetail]
    private var sessionScreenResults: [Result<SessionScreen, any Error>]
    private let emitsInitialObservedScreen: Bool
    private let emitsInitialObservedScreenAsynchronously: Bool
    private let initialObservedScreen: SessionScreen?
    private let observedScreenBeforeSendSessionTextResponse: SessionScreen?
    private let observedScreenBeforeSendSessionInputKeyResponse: SessionScreen?
    private let observeSessionStartGate: AsyncGate?
    private let statusResultsByHost: [String: Result<RemotePairedMacStatus, any Error>]
    private let statusProbeGatesByHost: [String: AsyncGate]
    private let statusProbeDelayNanoseconds: UInt64
    private let statusProbeRecorder: StatusProbeRecorder?
    private var observationRegistration: ObservationRegistration?
    private(set) var takeSessionControlRequests: [TakeSessionControlRequest] = []
    private(set) var releaseSessionControlRequests: [UUID] = []
    private(set) var requestLog: [String] = []
    private(set) var structuredHistoryPageRequests:
        [(sessionID: UUID, pageSize: Int, cursor: StructuredSessionHistoryCursor?)] = []
    private(set) var catalogFetchStarted = false
    private(set) var providerDetailFetchStarted = false
    private(set) var sessionScreenFetchStarted = false

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
        catalogResults: [RemoteWorkspaceCatalog] = [],
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
        structuredHistoryPages: [StructuredSessionHistoryPage] = [],
        providerDetailFetchGate: AsyncGate? = nil,
        sessionScreenFetchGate: AsyncGate? = nil,
        takeSessionControlResult: Result<SessionScreen, any Error>? = nil,
        releaseSessionControlResult: Result<SessionScreen, any Error>? = nil,
        sendSessionInputResult: Result<SessionScreen, any Error>? = nil,
        respondToExtensionDialogResult: Result<SessionScreen, any Error>? = nil,
        sendSessionTextResult: Result<SessionScreen, any Error>? = nil,
        sendSessionInputKeyResult: Result<SessionScreen, any Error>? = nil,
        emitsInitialObservedScreen: Bool = true,
        emitsInitialObservedScreenAsynchronously: Bool = false,
        initialObservedScreen: SessionScreen? = nil,
        observedScreenBeforeSendSessionTextResponse: SessionScreen? = nil,
        observedScreenBeforeSendSessionInputKeyResponse: SessionScreen? = nil,
        observeSessionStartGate: AsyncGate? = nil,
        statusResultsByHost: [String: Result<RemotePairedMacStatus, any Error>] = [:],
        statusProbeGatesByHost: [String: AsyncGate] = [:],
        statusProbeDelayNanoseconds: UInt64 = 0,
        statusProbeRecorder: StatusProbeRecorder? = nil
    ) {
        self.result = result
        self.status = status
        self.catalog = catalog
        self.catalogResult = catalogResult
        self.catalogResults = catalogResults
        self.providerDetail = providerDetail
        self.launchedDefaultSession = launchedDefaultSession ?? sessionScreen.session
        self.createdNamedSession = createdNamedSession ?? sessionScreen.session
        self.createdNamedSessionResult = createdNamedSessionResult
        self.launchedSession = launchedSession ?? sessionScreen.session
        self.stoppedSession = stoppedSession ?? sessionScreen.session
        self.deletedSessionRecord = deletedSessionRecord
        self.catalogFetchGate = catalogFetchGate
        self.structuredHistoryPages = structuredHistoryPages
        self.providerDetailFetchGate = providerDetailFetchGate
        self.sessionScreenFetchGate = sessionScreenFetchGate
        self.takeSessionControlResult = takeSessionControlResult
        self.releaseSessionControlResult = releaseSessionControlResult
        self.sendSessionInputResult = sendSessionInputResult
        self.respondToExtensionDialogResult = respondToExtensionDialogResult
        self.sendSessionTextResult = sendSessionTextResult
        self.sendSessionInputKeyResult = sendSessionInputKeyResult
        self.providerDetailResults = providerDetailResults
        self.defaultSessionScreen = sessionScreen
        self.sessionScreenResults = sessionScreenResults
        self.emitsInitialObservedScreen = emitsInitialObservedScreen
        self.emitsInitialObservedScreenAsynchronously = emitsInitialObservedScreenAsynchronously
        self.initialObservedScreen = initialObservedScreen
        self.observedScreenBeforeSendSessionTextResponse = observedScreenBeforeSendSessionTextResponse
        self.observedScreenBeforeSendSessionInputKeyResponse = observedScreenBeforeSendSessionInputKeyResponse
        self.observeSessionStartGate = observeSessionStartGate
        self.statusResultsByHost = statusResultsByHost
        self.statusProbeGatesByHost = statusProbeGatesByHost
        self.statusProbeDelayNanoseconds = statusProbeDelayNanoseconds
        self.statusProbeRecorder = statusProbeRecorder
    }

    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus {
        await statusProbeRecorder?.begin(host: host)
        do {
            await statusProbeGatesByHost[host]?.wait()
            if statusProbeDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: statusProbeDelayNanoseconds)
            }
            let resolvedStatus = try (statusResultsByHost[host] ?? status).get()
            await statusProbeRecorder?.end(host: host)
            return resolvedStatus
        } catch {
            await statusProbeRecorder?.end(host: host)
            throw error
        }
    }

    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac {
        result
    }

    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog {
        requestLog.append("fetchCatalog")
        catalogFetchStarted = true
        await catalogFetchGate?.wait()

        if catalogResults.isEmpty == false {
            return catalogResults.removeFirst()
        }

        if let catalogResult {
            return try catalogResult.get()
        }

        return catalog
    }

    func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws
        -> ProviderDetail
    {
        requestLog.append("fetchProviderDetail")
        providerDetailFetchStarted = true
        await providerDetailFetchGate?.wait()

        if providerDetailResults.isEmpty == false {
            return providerDetailResults.removeFirst()
        }

        return providerDetail
    }

    func launchOrResumeDefaultSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws
        -> Session
    {
        requestLog.append("launchOrResumeDefaultSession")
        return launchedDefaultSession
    }

    func createNamedSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session
    {
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
        sessionScreenFetchStarted = true
        await sessionScreenFetchGate?.wait()

        if sessionScreenResults.isEmpty == false {
            return try sessionScreenResults.removeFirst().get()
        }

        return defaultSessionScreen
    }

    func fetchStructuredSessionHistoryPage(
        for pairedMac: PairedMac,
        sessionID: UUID,
        pageSize: Int,
        before cursor: StructuredSessionHistoryCursor?
    ) async throws -> StructuredSessionHistoryPage {
        requestLog.append("fetchStructuredSessionHistoryPage")
        structuredHistoryPageRequests.append((sessionID: sessionID, pageSize: pageSize, cursor: cursor))

        if structuredHistoryPages.isEmpty == false {
            return structuredHistoryPages.removeFirst()
        }

        return StructuredSessionHistoryPage(
            sessionID: sessionID, activityItems: [], providerEvents: [], nextCursor: nil)
    }

    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws
        -> SessionScreen
    {
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
                    text:
                        "\(decision == .approve ? "Approved" : "Denied"): \(defaultSessionScreen.approvalRequests.first(where: { $0.id == approvalRequestID })?.title ?? "Approval Request")"
                )
            ],
            approvalRequests: updatedApprovalRequests
        )
    }

    func respondToExtensionDialog(
        for pairedMac: PairedMac,
        sessionID: UUID,
        dialogID: String,
        response: SessionExtensionUIDialogResponse
    ) async throws -> SessionScreen {
        requestLog.append("respondToExtensionDialog")

        if let respondToExtensionDialogResult {
            return try respondToExtensionDialogResult.get()
        }

        let extensionUI = defaultSessionScreen.extensionUI.map {
            SessionExtensionUIState(
                title: $0.title,
                pendingDialogs: $0.pendingDialogs.filter { $0.id != dialogID },
                notifications: $0.notifications,
                statuses: $0.statuses,
                widgets: $0.widgets,
                editorText: $0.editorText
            )
        }

        return SessionScreen(
            session: defaultSessionScreen.session,
            primarySurface: defaultSessionScreen.primarySurface,
            controller: .pairedDevice(pairedMac.pairedDeviceID ?? UUID()),
            transcript: defaultSessionScreen.transcript,
            terminalColumns: defaultSessionScreen.terminalColumns,
            terminalRows: defaultSessionScreen.terminalRows,
            activityItems: defaultSessionScreen.activityItems,
            approvalRequests: defaultSessionScreen.approvalRequests,
            extensionUI: extensionUI,
            slashCommands: defaultSessionScreen.slashCommands,
            providerEvents: defaultSessionScreen.providerEvents,
            isAgentTurnInProgress: defaultSessionScreen.isAgentTurnInProgress
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

    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws
        -> SessionScreen
    {
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
        await observeSessionStartGate?.wait()
        if emitsInitialObservedScreen {
            let initialScreen: SessionScreen
            if let providedInitialObservedScreen = initialObservedScreen {
                initialScreen = providedInitialObservedScreen
            } else {
                initialScreen = try await fetchSessionScreen(for: pairedMac, sessionID: sessionID)
            }
            if emitsInitialObservedScreenAsynchronously {
                Task {
                    onUpdate(initialScreen)
                }
            } else {
                onUpdate(initialScreen)
            }
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

private final class StatusRequestTimeoutCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var capturedRequestTimeoutInterval: TimeInterval?

    static func reset() {
        capturedRequestTimeoutInterval = nil
    }

    static func capturedTimeoutInterval() -> TimeInterval? {
        capturedRequestTimeoutInterval
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequestTimeoutInterval = request.timeoutInterval
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(#"{"macName":"Studio Mac","isRemoteAccessEnabled":true}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor StatusProbeRecorder {
    private var activeProbeCount = 0
    private var recordedMaximumActiveProbeCount = 0

    func begin(host: String) {
        _ = host
        activeProbeCount += 1
        recordedMaximumActiveProbeCount = max(recordedMaximumActiveProbeCount, activeProbeCount)
    }

    func end(host: String) {
        _ = host
        activeProbeCount -= 1
    }

    func maximumActiveProbeCount() -> Int {
        recordedMaximumActiveProbeCount
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

@MainActor
private func waitUntilAsync(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

    while await predicate() == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(
                domain: "RemoteClientPairingModelTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for async condition"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}
