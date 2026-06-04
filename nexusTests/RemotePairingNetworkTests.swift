import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
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

    @Test func pairedRemoteClientReconnectsAfterMacAppRestartOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixedPort = 49_234

        let firstService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        var firstServer: RemotePairingServer? = try RemotePairingServer(
            client: firstClient,
            displayHost: "127.0.0.1",
            macName: "Studio Mac",
            listeningPort: fixedPort
        )

        _ = try await firstClient.setRemoteAccessEnabled(true)
        let pairing = try await firstClient.startPairing()
        let group = try await firstClient.createWorkspaceGroup(name: "Client Work")
        let workspace = try await firstClient.createLocalWorkspace(
            name: "Nexus",
            folderPath: "/tmp/nexus",
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: try #require(firstServer).displayHost,
            port: try #require(firstServer).port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let firstStatus = try await remoteClient.fetchStatus(host: pairedMac.host, port: pairedMac.port)
        #expect(firstStatus == RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: true))

        firstServer = nil
        try await Task.sleep(nanoseconds: 100_000_000)

        let restartedService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let restartedServer = try RemotePairingServer(
            client: restartedClient,
            displayHost: "127.0.0.1",
            macName: "Studio Mac",
            listeningPort: fixedPort
        )

        #expect(restartedServer.port == fixedPort)

        let restartedStatus = try await remoteClient.fetchStatus(host: pairedMac.host, port: pairedMac.port)
        #expect(restartedStatus == RemotePairedMacStatus(macName: "Studio Mac", isRemoteAccessEnabled: true))

        let catalog = try await remoteClient.fetchCatalog(for: pairedMac)
        #expect(catalog.workspaceGroups == [group])
        #expect(catalog.workspaceOverviews.map(\.workspace.id) == [workspace.id])
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
        let claudeCard = try #require(
            catalog.workspaceOverviews
                .first(where: { $0.workspace.id == workspace.id })?
                .providerCards
                .first(where: { $0.provider.id == .claude })
        )

        #expect(catalog.workspaceGroups == [group])
        #expect(catalog.recentNavigation.map(\.target) == [.workspace(workspace.id)])
        #expect(catalog.workspaceOverviews.map(\.workspace.id) == [workspace.id])
        #expect(catalog.workspaceOverviews.first?.providerCards.isEmpty == false)
        #expect(claudeCard.capabilities.launchDefaultSession.isEnabled == false)
        #expect(claudeCard.capabilities.launchDefaultSession.disabledReason == claudeCard.health.summary)
    }

    @Test func fetchesCatalogWithPlaceholderOverviewsBeforeSlowHealthChecksTimeoutOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: AvailableRemotePairingProviderHealthEvaluator(),
            providerModuleRegistry: ProviderModuleRegistry(
                modules: Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { providerID in
                    (providerID, SlowCatalogReadProviderModule(providerID: providerID, delayNanoseconds: 1_500_000_000))
                })
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )

        let clock = ContinuousClock()
        let start = clock.now
        let catalog = try await remoteClient.fetchCatalog(for: pairedMac)
        let elapsed = start.duration(to: clock.now)
        let overview = try #require(catalog.workspaceOverviews.first(where: { $0.workspace.id == workspace.id }))
        let piCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))

        #expect(catalog.workspaceGroups == [group])
        #expect(elapsed < .seconds(10))
        #expect(overview.usesStaleBrowseFacts)
        #expect(piCard.health.state == .notChecked)
        #expect(piCard.capabilities.launchDefaultSession.isSupported)
        #expect(piCard.capabilities.launchDefaultSession.isEnabled == false)
        #expect(piCard.capabilities.launchDefaultSession.disabledReason == piCard.health.summary)
    }

    @Test func revokedPairingReturnsProductShapedRecoveryErrorOverDedicatedNetworkAPI() async throws {
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
        _ = try await client.revokePairedDevice(deviceID: try #require(pairedMac.pairedDeviceID))

        do {
            _ = try await remoteClient.fetchCatalog(for: pairedMac)
            Issue.record("Expected revoked Pairing to require pairing again before browsing this Paired Mac")
        } catch let error as RemotePairingHTTPError {
            #expect(error == .pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
            #expect(error.localizedDescription == "Pair this iPhone again to browse this Paired Mac")
        }
    }

    @Test func persistsRemoteUnauthorizedCatalogBreadcrumbForDedicatedNetworkAPI() async throws {
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
        _ = try await client.revokePairedDevice(deviceID: try #require(pairedMac.pairedDeviceID))

        do {
            _ = try await remoteClient.fetchCatalog(for: pairedMac)
            Issue.record("Expected revoked Pairing to require pairing again before browsing this Paired Mac")
        } catch let error as RemotePairingHTTPError {
            #expect(error == .pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        }

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        let store = try NexusMetadataStore(storeURL: storeURL)
        let breadcrumb = try #require(store.listRemoteClientDiagnosticBreadcrumbs(limit: 1).first)
        #expect(breadcrumb.kind == .actionFailure)
        #expect(breadcrumb.operation == .fetchCatalog)
        #expect(breadcrumb.message == "Pair this iPhone again to browse this Paired Mac")
        #expect(breadcrumb.pairedMacID == pairedMac.id)
        #expect(breadcrumb.pairedDeviceID == pairedMac.pairedDeviceID)
        #expect(breadcrumb.workspaceID == nil)
        #expect(breadcrumb.providerID == nil)
        #expect(breadcrumb.sessionID == nil)
    }

    @Test func persistsRemoteActionFailureBreadcrumbForDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )

        do {
            _ = try await remoteClient.deleteSessionRecord(for: pairedMac, sessionID: session.id)
            Issue.record("Expected deleting a running Session Record over the dedicated remote API to fail")
        } catch let error as RemotePairingHTTPError {
            #expect(error == .requestFailed("Stop the session before deleting its record"))
        }

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        let store = try NexusMetadataStore(storeURL: storeURL)
        let breadcrumb = try #require(store.listRemoteClientDiagnosticBreadcrumbs(limit: 1).first)
        #expect(breadcrumb.kind == .actionFailure)
        #expect(breadcrumb.operation == .deleteSessionRecord)
        #expect(breadcrumb.message == "Stop the session before deleting its record")
        #expect(breadcrumb.pairedMacID == pairedMac.id)
        #expect(breadcrumb.pairedDeviceID == pairedMac.pairedDeviceID)
        #expect(breadcrumb.workspaceID == workspace.id)
        #expect(breadcrumb.providerID == .claude)
        #expect(breadcrumb.sessionID == session.id)
    }

    @Test func persistsRemoteReconnectFailureBreadcrumbForDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        _ = try await client.revokePairedDevice(deviceID: try #require(pairedMac.pairedDeviceID))

        do {
            _ = try await remoteClient.observeSessionScreen(
                for: pairedMac,
                sessionID: session.id,
                onUpdate: { _ in },
                onDisconnect: { _ in }
            )
            Issue.record("Expected revoked Pairing to fail before starting Session screen observation")
        } catch let error as RemotePairingHTTPError {
            #expect(error == .pairingRevoked("Pair this iPhone again to browse this Paired Mac"))
        }

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        let store = try NexusMetadataStore(storeURL: storeURL)
        let breadcrumb = try #require(store.listRemoteClientDiagnosticBreadcrumbs(limit: 1).first)
        #expect(breadcrumb.kind == .reconnectFailure)
        #expect(breadcrumb.operation == .observeSessionScreen)
        #expect(breadcrumb.message == "Pair this iPhone again to browse this Paired Mac")
        #expect(breadcrumb.pairedMacID == pairedMac.id)
        #expect(breadcrumb.pairedDeviceID == pairedMac.pairedDeviceID)
        #expect(breadcrumb.sessionID == session.id)
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
        #expect(detail.capabilities.launchDefaultSession.isEnabled == false)
        #expect(detail.capabilities.launchDefaultSession.disabledReason == detail.health.summary)
        #expect(detail.capabilities.createNamedSession.isEnabled == false)
        #expect(detail.capabilities.createNamedSession.disabledReason == detail.health.summary)
    }

    @Test func fetchesLaunchableCodexCapabilitiesInCatalogAndProviderDetailOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let catalog = try await remoteClient.fetchCatalog(for: pairedMac)
        let codexCard = try #require(
            catalog.workspaceOverviews
                .first(where: { $0.workspace.id == workspace.id })?
                .providerCards
                .first(where: { $0.provider.id == .codex })
        )
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )

        #expect(codexCard.health.summary == "Codex 1.2.3 is available")
        #expect(codexCard.capabilities.launchDefaultSession.isSupported)
        #expect(codexCard.capabilities.launchDefaultSession.isEnabled)
        #expect(codexCard.capabilities.launchDefaultSession.disabledReason == nil)
        #expect(codexCard.capabilities.createNamedSession.isSupported)
        #expect(codexCard.capabilities.createNamedSession.isEnabled)
        #expect(codexCard.capabilities.createNamedSession.disabledReason == nil)
        #expect(detail.provider.id == .codex)
        #expect(detail.health.summary == "Codex 1.2.3 is available")
        #expect(detail.capabilities == codexCard.capabilities)
    }

    @Test func fetchesUnavailableCodexCapabilityReasonsOverDedicatedNetworkAPI() async throws {
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
            providerID: .codex
        )

        #expect(detail.provider.id == .codex)
        #expect(detail.health.summary == "Codex executable was not found")
        #expect(detail.capabilities.launchDefaultSession.isSupported)
        #expect(detail.capabilities.launchDefaultSession.isEnabled == false)
        #expect(detail.capabilities.launchDefaultSession.disabledReason == detail.health.summary)
        #expect(detail.capabilities.createNamedSession.isSupported)
        #expect(detail.capabilities.createNamedSession.isEnabled == false)
        #expect(detail.capabilities.createNamedSession.disabledReason == detail.health.summary)
    }

    @Test func launchesCodexDefaultSessionOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )

        #expect(session.workspaceID == workspace.id)
        #expect(session.providerID == ProviderID.codex)
        #expect(session.isDefault)
        #expect(session.state == Session.State.ready)
        #expect(detail.defaultSession?.id == session.id)
        #expect(detail.defaultSession?.state == Session.State.ready)
    }

    @Test func fetchesStructuredLocalCodexSessionScreenOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )
        let screen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(screen.session.id == session.id)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(sessionSurfaceSupport(for: screen, on: .remoteClient) == .supported)
    }

    @Test func localIBMBobStructuredSessionIsInspectableAndStreamsSharedUpdatesOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let launcher = ProcessSessionRuntimeLauncher(
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
            ibmBobTransportFactory: { _, _, _ in
                RemotePairingSynchronousIBMBobTransport(
                    stdoutLines: [
                        #"{"type":"status","text":"Bob turn started"}"#,
                        #"{"type":"message","text":"Hello from Bob"}"#,
                        #"{"type":"completion","text":"Bob turn complete"}"#
                    ],
                    terminationStatus: 0
                )
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(stdout: "[]\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .ibmBob
        )
        let idleScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(idleScreen.session.id == session.id)
        #expect(idleScreen.primarySurface == .structuredActivityFeed)
        #expect(idleScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(sessionSurfaceSupport(for: idleScreen, on: .remoteClient) == .supported)

        var observedScreens: [SessionScreen] = []
        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        do {
            _ = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, text: "Ship it")
            Issue.record("Expected IBM Bob structured prompt submission on iPhone to require Controller first")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before sending Session input.")
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let responseScreen = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, text: "Ship it")
        let observedScreen = try await waitForObservedScreen {
            observedScreens.last { $0.activityItems.contains(where: { $0.text == "Bob turn complete" }) }
        }
        let fetchedScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(responseScreen.session.id == session.id)
        #expect(responseScreen.primarySurface == .structuredActivityFeed)
        #expect(responseScreen.activityItems.map(\.text) == [
            "IBM Bob Session ready. Send a prompt to start IBM Bob.",
            "You: Ship it",
            "Bob turn started",
            "Hello from Bob",
            "Bob turn complete"
        ])
        #expect(observedScreen.session.id == session.id)
        #expect(observedScreen.activityItems.map(\.text) == responseScreen.activityItems.map(\.text))
        #expect(fetchedScreen == responseScreen)
    }

    @Test func failedStructuredCodexSessionScreenStaysInspectableOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )
        let screen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(session.state == .failed)
        #expect(screen.session.state == .failed)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.transcript == "Codex executable was not found in the service search paths.")
        #expect(screen.activityItems.map(\.kind) == [.error])
        #expect(screen.activityItems.map(\.text) == ["Codex executable was not found in the service search paths."])
        #expect(sessionSurfaceSupport(for: screen, on: .remoteClient) == .supported)
    }

    @Test func remoteControllerApprovesStructuredApprovalRequestOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let approvalRequest = SessionApprovalRequest(
            title: "deploy --prod",
            text: "Codex needs approval to deploy to production.",
            state: .pending
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            ),
            sessionRuntimeManager: StructuredPromptSessionRuntimeManager(
                providerName: "Codex",
                approvalRequests: [approvalRequest]
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let responseScreen = try await remoteClient.respondToApprovalRequest(
            for: pairedMac,
            sessionID: session.id,
            approvalRequestID: approvalRequest.id,
            decision: .approve
        )
        let fetchedScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(responseScreen.controller == .pairedDevice(try #require(pairedMac.pairedDeviceID)))
        #expect(responseScreen.primarySurface == .structuredActivityFeed)
        #expect(responseScreen.activityItems.map(\.text) == [
            "Codex shared Session stream connected",
            "Approval Request: deploy --prod",
            "Approved: deploy --prod"
        ])
        #expect(responseScreen.approvalRequests.first?.state == .approved)
        #expect(fetchedScreen == responseScreen)
    }

    @Test func remoteViewerCannotApproveStructuredApprovalRequestOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let approvalRequest = SessionApprovalRequest(
            title: "deploy --prod",
            text: "Codex needs approval to deploy to production.",
            state: .pending
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            ),
            sessionRuntimeManager: StructuredPromptSessionRuntimeManager(
                providerName: "Codex",
                approvalRequests: [approvalRequest]
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )

        do {
            _ = try await remoteClient.respondToApprovalRequest(
                for: pairedMac,
                sessionID: session.id,
                approvalRequestID: approvalRequest.id,
                decision: .deny
            )
            Issue.record("Expected viewer approval decision to require Controller first")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before responding to Approval Requests.")
        }
    }

    @Test func remoteControllerSendsStructuredPromptOverGenericSessionInputDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            ),
            sessionRuntimeManager: StructuredPromptSessionRuntimeManager(providerName: "Codex")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let responseScreen = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, text: "Ship it")
        let fetchedScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(responseScreen.controller == .pairedDevice(try #require(pairedMac.pairedDeviceID)))
        #expect(responseScreen.primarySurface == .structuredActivityFeed)
        #expect(responseScreen.activityItems.map(\.text) == [
            "Codex shared Session stream connected",
            "You: Ship it",
            "Codex: Acknowledged Ship it"
        ])
        #expect(fetchedScreen == responseScreen)
    }

    @Test func createsCodexNamedSessionOverDedicatedNetworkAPIWithoutDefaultSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.createNamedSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .codex
        )

        #expect(session.workspaceID == workspace.id)
        #expect(session.providerID == ProviderID.codex)
        #expect(session.isDefault == false)
        #expect(session.state == Session.State.ready)
        #expect(session.name == "Session 1")
        #expect(detail.defaultSession == nil)
        #expect(detail.alternateSessions.map { $0.id } == [session.id])
        #expect(detail.alternateSessions.first?.name == "Session 1")
    }

    @Test func launchesRemoteDefaultSessionOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(session.workspaceID == workspace.id)
        #expect(session.providerID == .claude)
        #expect(session.isDefault)
        #expect(detail.defaultSession?.id == session.id)
        #expect(detail.defaultSession?.state == .ready)
    }

    @Test func createsRemoteNamedSessionOverDedicatedNetworkAPIWithoutDefaultSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.createNamedSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )
        let screen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(session.workspaceID == workspace.id)
        #expect(session.providerID == .claude)
        #expect(session.isDefault == false)
        #expect(session.name == "Session 1")
        #expect(detail.defaultSession == nil)
        #expect(detail.alternateSessions.map(\.id) == [session.id])
        #expect(detail.alternateSessions.first?.name == "Session 1")
        #expect(screen.controller == .mac)
    }

    @Test func stopsRemoteSessionOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let stoppedSession = try await remoteClient.stopSession(for: pairedMac, sessionID: session.id)
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(stoppedSession.id == session.id)
        #expect(stoppedSession.state == .exited)
        #expect(detail.defaultSession?.id == session.id)
        #expect(detail.defaultSession?.state == .exited)
    }

    @Test func deletesDefaultRemoteSessionRecordOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        _ = try await remoteClient.stopSession(for: pairedMac, sessionID: session.id)
        let deleted = try await remoteClient.deleteSessionRecord(for: pairedMac, sessionID: session.id)
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )
        let catalog = try await remoteClient.fetchCatalog(for: pairedMac)
        let providerCard = try #require(
            catalog.workspaceOverviews
                .first(where: { $0.workspace.id == workspace.id })?
                .providerCards
                .first(where: { $0.provider.id == .claude })
        )

        #expect(deleted)
        #expect(detail.defaultSession == nil)
        #expect(providerCard.defaultSession.state == .notCreated)
        #expect(providerCard.defaultSession.actionTitle == "Launch")
    }

    @Test func deletesFailedRemoteSessionRecordOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let failedHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "", stderr: "NEXUS_REMOTE_CLAUDE_NOT_FOUND\n", exitStatus: 1)
        ])
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "python3 - <<'PY'\nimport os\nimport sys\npath = '/srv/api'\nif os.path.isdir(path):\n    print('available')\n    sys.exit(0)\nprint('missing')\nsys.exit(1)\nPY"
                ]
            ): .success(stdout: "available\n")
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: failedHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let failedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Review")

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let deleted = try await remoteClient.deleteSessionRecord(for: pairedMac, sessionID: failedSession.id)
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(deleted)
        #expect(detail.failedSessions.isEmpty)
    }

    @Test func relaunchesRemoteSessionRecordOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await client.stopSession(sessionID: session.id)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let relaunchedSession = try await remoteClient.launchOrResumeSession(for: pairedMac, sessionID: session.id)
        let detail = try await remoteClient.fetchProviderDetail(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .claude
        )

        #expect(relaunchedSession.id == session.id)
        #expect(relaunchedSession.state == .ready)
        #expect(detail.defaultSession?.id == session.id)
        #expect(detail.defaultSession?.state == .ready)
    }

    @Test func fetchesRemoteSessionScreenOverDedicatedNetworkAPI() async throws {
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
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let expectedScreen = try await client.getSessionScreen(sessionID: session.id)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let screen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(screen == expectedScreen)
    }

    @Test func fetchesRemotePiStructuredHistoryPagesOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let messageCount = StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + 100
        let messages = (0..<messageCount).map { index in
            [
                "role": "user",
                "content": "History \(index)"
            ]
        }
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: StubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(
                launcher: ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                    HistoryPagingPiRPCTransport(messages: messages)
                })
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        _ = try await client.sendSessionInput(sessionID: session.id, text: "/messages")
        let liveScreen = try await client.getSessionScreen(sessionID: session.id)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let page = try await remoteClient.fetchStructuredSessionHistoryPage(
            for: pairedMac,
            sessionID: session.id,
            pageSize: 20,
            before: nil
        )

        #expect(liveScreen.activityItems.first?.text == "Message 101 — user: History 100")
        #expect(page.activityItems.count == 20)
        #expect(page.activityItems.first?.text == "Message 81 — user: History 80")
        #expect(page.activityItems.last?.text == "Message 100 — user: History 99")
        #expect(page.activityItems.contains(where: { $0.text == liveScreen.activityItems.first?.text }) == false)
    }

    @Test func viewerCanTakeControllerStatusAndOwnTerminalSizeOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let controlledScreen = try await remoteClient.takeSessionControl(
            for: pairedMac,
            sessionID: session.id,
            columns: 44,
            rows: 12
        )
        let refreshedScreen = try await client.getSessionScreen(sessionID: session.id)

        #expect(controlledScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(controlledScreen.terminalColumns == 44)
        #expect(controlledScreen.terminalRows == 12)
        #expect(refreshedScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(refreshedScreen.terminalColumns == 44)
        #expect(refreshedScreen.terminalRows == 12)
    }

    @Test func remoteControllerReleaseRestoresMacControllerAndTerminalSizeOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await client.resizeSession(sessionID: session.id, columns: 132, rows: 40)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let releasedScreen = try await remoteClient.releaseSessionControl(for: pairedMac, sessionID: session.id)

        #expect(releasedScreen.controller == .mac)
        #expect(releasedScreen.terminalColumns == 132)
        #expect(releasedScreen.terminalRows == 40)
    }

    @Test func remoteControllerCanUpdateOwnedTerminalSizeOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await client.resizeSession(sessionID: session.id, columns: 132, rows: 40)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let resizedScreen = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 60, rows: 20)
        let refreshedScreen = try await client.getSessionScreen(sessionID: session.id)

        #expect(resizedScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(resizedScreen.terminalColumns == 60)
        #expect(resizedScreen.terminalRows == 20)
        #expect(refreshedScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(refreshedScreen.terminalColumns == 60)
        #expect(refreshedScreen.terminalRows == 20)
    }

    @Test func macInteractionReclaimsControllerStatusAndBlocksRemoteTerminalInputOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import sys

        print("READY", flush=True)
        first = sys.stdin.readline().rstrip("\r\n")
        print(f"LOCAL:{first}", flush=True)
        second = sys.stdin.readline().rstrip("\r\n")
        print(f"REMOTE:{second}", flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        _ = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.transcript.contains("READY")
        }
        _ = try await client.resizeSession(sessionID: session.id, columns: 132, rows: 40)

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        _ = try await client.sendSessionText(sessionID: session.id, text: "mac reclaim")
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .enter)
        let reclaimedScreen = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.transcript.contains("LOCAL:mac reclaim")
        }

        #expect(reclaimedScreen.controller == .mac)
        #expect(reclaimedScreen.terminalColumns == 132)
        #expect(reclaimedScreen.terminalRows == 40)

        do {
            _ = try await remoteClient.sendSessionText(for: pairedMac, sessionID: session.id, text: "still remote")
            Issue.record("Expected Mac interaction to reclaim Controller status before further remote terminal input")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before sending terminal input.")
        }
    }

    @Test func remoteSessionObservationDeliversPostInputScreenOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import sys

        print("AUTH?", flush=True)
        line = sys.stdin.readline().rstrip("\r\n")
        print(f"AUTH:{line}", flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        _ = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.transcript.contains("AUTH?")
        }

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )

        var observedScreens: [SessionScreen] = []
        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        _ = try await remoteClient.sendSessionText(for: pairedMac, sessionID: session.id, text: "654321")
        _ = try await remoteClient.sendSessionInputKey(for: pairedMac, sessionID: session.id, key: .enter)

        let observedScreen = try await waitForObservedScreen {
            observedScreens.last { $0.transcript.contains("AUTH:654321") }
        }
        let fetchedScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(observedScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(observedScreen.transcript.contains("AUTH:654321"))
        #expect(fetchedScreen.transcript.contains("AUTH:654321"))
    }

    @Test func remoteControllerCanSendTerminalTextAndReturnOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import sys

        print("AUTH?", flush=True)
        line = sys.stdin.readline().rstrip("\r\n")
        print(f"AUTH:{line}", flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        _ = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.transcript.contains("AUTH?")
        }

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        _ = try await remoteClient.sendSessionText(for: pairedMac, sessionID: session.id, text: "654321")
        _ = try await remoteClient.sendSessionInputKey(for: pairedMac, sessionID: session.id, key: .enter)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("AUTH:654321")
        }

        #expect(screen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(screen.transcript.contains("AUTH:654321"))
    }

    @Test func remoteSessionObservationDeliversPartialEchoedInputOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["claude": "/bin/cat"]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/cat", arguments: ["--version"]): .success(stdout: "cat (test)\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/cat", arguments: ["--help"]): .success(stdout: "Usage: cat\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        _ = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.session.state == .ready
        }

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )

        var observedScreens: [SessionScreen] = []
        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 40, rows: 17)
        let responseScreen = try await remoteClient.sendSessionText(for: pairedMac, sessionID: session.id, text: "yooo")

        let fetchedScreen = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.transcript.contains("yooo")
        }
        let observedScreen = try await waitForObservedScreen {
            observedScreens.last { $0.transcript.contains("yooo") }
        }

        #expect(responseScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(fetchedScreen.transcript.contains("yooo"))
        #expect(observedScreen.transcript.contains("yooo"))
    }

    @Test func remoteControllerSendTextResponseWaitsForDelayedEchoOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let delayedRuntimeManager = DelayedEchoSessionRuntimeManager(initialTranscript: "Ready\n> ayyy")
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["claude": "/bin/cat"]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/cat", arguments: ["--version"]): .success(stdout: "cat (test)\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/cat", arguments: ["--help"]): .success(stdout: "Usage: cat\n")
                ])
            ),
            sessionRuntimeManager: delayedRuntimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        _ = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.transcript.contains("> ayyy")
        }

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )

        var observedScreens: [SessionScreen] = []
        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 40, rows: 17)
        let responseScreen = try await remoteClient.sendSessionText(for: pairedMac, sessionID: session.id, text: "yooo")
        let observedScreen = try await waitForObservedScreen {
            observedScreens.last { $0.transcript.contains("ayyyyooo") }
        }

        #expect(responseScreen.controller == .pairedDevice(pairedMac.pairedDeviceID!))
        #expect(responseScreen.transcript.contains("ayyyyooo"))
        #expect(observedScreen.transcript.contains("ayyyyooo"))
    }

    @Test func remotePiStructuredSessionStreamsToolAndSubagentUpdatesBeforeTurnEndOverDedicatedNetworkAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
            RemotePairingStreamingPiRPCTransport()
        })
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .pi
        )

        var observedScreens: [SessionScreen] = []
        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        do {
            _ = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, text: "delegate")
            Issue.record("Expected Pi structured prompt submission on iPhone to require Controller first")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before sending Session input.")
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let responseScreen = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, text: "delegate")

        let streamedScreen = try await waitForObservedScreen {
            observedScreens.last {
                $0.session.id == session.id
                    && $0.isAgentTurnInProgress
                    && $0.activityItems.contains(where: { $0.text == "subagent: Looks good overall. Watch the new error path." })
            }
        }
        let completedScreen = try await waitForObservedScreen {
            observedScreens.last {
                $0.session.id == session.id
                    && $0.isAgentTurnInProgress == false
                    && $0.activityItems.contains(where: { $0.text == "Pi: Done" })
            }
        }

        #expect(responseScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: delegate"
        ])
        #expect(streamedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: delegate",
            "subagent reviewer: Review the latest diff and summarize issues",
            "subagent: Looks good overall. Watch the new error path."
        ])
        #expect(completedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: delegate",
            "subagent reviewer: Review the latest diff and summarize issues",
            "subagent: Looks good overall. Watch the new error path.",
            "Pi: Done"
        ])
    }

    @Test func remotePiNetworkControllerCanSendImageBearingPromptThroughDedicatedAPI() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let transport = RemotePairingRecordingPiRPCTransport(promptResponseText: "world")
        let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
            transport
        })
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .pi
        )

        var observedScreens: [SessionScreen] = []
        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let prompt = SessionPrompt(
            text: "What changed in this screenshot?",
            images: [SessionPromptImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")]
        )
        let responseScreen = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, prompt: prompt)
        let observedScreen = try await waitForObservedScreen {
            observedScreens.last { $0.activityItems.contains(where: { $0.text == "Pi: world" }) }
        }
        let fetchedScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)
        let promptLine = try #require(transport.sentLines.first(where: { $0.contains("\"type\":\"prompt\"") }))
        let promptData = try #require(promptLine.data(using: .utf8))
        let promptPayload = try #require(JSONSerialization.jsonObject(with: promptData) as? [String: Any])
        let images = try #require(promptPayload["images"] as? [[String: Any]])

        #expect(promptPayload["message"] as? String == "What changed in this screenshot?")
        #expect(images[0]["data"] as? String == "iVBORw==")
        #expect(images[0]["mimeType"] as? String == "image/png")
        #expect(responseScreen.activityItems[1].prompt == prompt)
        #expect(observedScreen.activityItems[1].prompt == prompt)
        #expect(fetchedScreen.activityItems[1].prompt == prompt)
        #expect(fetchedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: What changed in this screenshot? [1 image]",
            "Pi: world"
        ])
    }

    @Test func remotePiReconnectRecoversProviderEventsAndExtensionUIWhileControllerOwnsDialogResponses() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let transport = RemotePairingExtensionUIPiRPCTransport()
        let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
            transport
        })
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemotePairingTestExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: RemotePairingTestCommandRunner(results: [
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    RemotePairingTestCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let server = try RemotePairingServer(client: client, displayHost: "127.0.0.1", macName: "Studio Mac")

        _ = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()
        let group = try await client.createWorkspaceGroup(name: "Client Work")
        let workspace = try await client.createLocalWorkspace(
            name: "Nexus",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let remoteClient = RemotePairingHTTPClient()
        let pairedMac = try await remoteClient.completePairing(
            host: server.displayHost,
            port: server.port,
            pairingCode: pairing.code,
            deviceName: "Chris’s iPhone"
        )
        let session = try await remoteClient.launchOrResumeDefaultSession(
            for: pairedMac,
            workspaceID: workspace.id,
            providerID: .pi
        )

        var observedScreens: [SessionScreen] = []
        var observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    observedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )
        defer {
            Task {
                await observation.cancel()
            }
        }

        _ = try await waitForObservedScreen {
            observedScreens.last
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let pendingScreen = try await remoteClient.sendSessionInput(for: pairedMac, sessionID: session.id, text: "deploy")
        let dialog = try #require(pendingScreen.extensionUI?.pendingDialogs.first)

        #expect(pendingScreen.providerEvents.contains(where: { $0.type == "extension_ui_request" }))
        #expect(dialog.title == "Deploy to production?")

        transport.emitFireAndForgetUpdates()

        let observedPendingScreen = try await waitForObservedScreen {
            observedScreens.last {
                $0.extensionUI?.title == "Pi Demo"
                    && $0.extensionUI?.pendingDialogs.first?.id == dialog.id
                    && $0.providerEvents.contains(where: { $0.type == "extension_ui_request" })
            }
        }
        let fetchedPendingScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)

        #expect(observedPendingScreen.extensionUI?.statuses == [SessionExtensionUIStatus(key: "rpc-demo", text: "Turn ready")])
        #expect(fetchedPendingScreen.extensionUI?.widgets == [SessionExtensionUIWidget(key: "rpc-demo", lines: ["Ready.", "Waiting for input"], placement: .belowEditor)])
        #expect(fetchedPendingScreen.extensionUI?.editorText == "This text was set by the rpc-demo extension.")

        await observation.cancel()

        var reconnectedScreens: [SessionScreen] = []
        observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { screen in
                Task { @MainActor in
                    reconnectedScreens.append(screen)
                }
            },
            onDisconnect: { _ in }
        )

        let recoveredScreen = try await waitForObservedScreen {
            reconnectedScreens.last {
                $0.extensionUI?.title == "Pi Demo"
                    && $0.extensionUI?.pendingDialogs.first?.id == dialog.id
                    && $0.providerEvents.contains(where: { $0.type == "extension_ui_request" })
            }
        }

        #expect(recoveredScreen.extensionUI?.notifications.first?.message == "Editor prefilled")

        _ = try await remoteClient.releaseSessionControl(for: pairedMac, sessionID: session.id)

        do {
            _ = try await remoteClient.respondToExtensionDialog(
                for: pairedMac,
                sessionID: session.id,
                dialogID: dialog.id,
                response: .confirmed(true)
            )
            Issue.record("Expected Pi Extension UI dialog responses on iPhone to require Controller first")
        } catch {
            #expect(error.localizedDescription == "Take Controller on this iPhone before responding to Extension UI dialogs.")
        }

        _ = try await remoteClient.takeSessionControl(for: pairedMac, sessionID: session.id, columns: 44, rows: 12)
        let approvedScreen = try await remoteClient.respondToExtensionDialog(
            for: pairedMac,
            sessionID: session.id,
            dialogID: dialog.id,
            response: .confirmed(true)
        )
        let observedApprovedScreen = try await waitForObservedScreen {
            reconnectedScreens.last {
                $0.session.id == session.id
                    && ($0.extensionUI?.pendingDialogs.isEmpty ?? true)
                    && $0.activityItems.contains(where: { $0.text == "Pi: Deployment approved" })
            }
        }

        #expect(approvedScreen.extensionUI?.pendingDialogs.isEmpty == true)
        #expect(approvedScreen.activityItems.suffix(1).map { $0.text } == ["Pi: Deployment approved"])
        #expect(observedApprovedScreen.transcript == "> deploy\nDeployment approved")

        let fetchedApprovedScreen = try await remoteClient.fetchSessionScreen(for: pairedMac, sessionID: session.id)
        #expect(fetchedApprovedScreen.providerEvents.contains(where: { $0.type == "extension_ui_request" }))
        #expect(fetchedApprovedScreen.extensionUI?.statuses == [SessionExtensionUIStatus(key: "rpc-demo", text: "Turn ready")])
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

@MainActor
private func waitForObservedScreen(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    latestMatch: @escaping @MainActor () -> SessionScreen?
) async throws -> SessionScreen {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while true {
        if let screen = latestMatch() {
            return screen
        }

        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw NSError(domain: "RemotePairingNetworkTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for observed Session screen update"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

private func waitForSessionScreen(
    client: NexusIPCClient,
    sessionID: UUID,
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while true {
        let screen = try await client.getSessionScreen(sessionID: sessionID)
        if predicate(screen) {
            return screen
        }

        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw NSError(domain: "RemotePairingNetworkTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Session screen update"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

private final class RemotePairingSynchronousIBMBobTransport: IBMBobTransporting, @unchecked Sendable {
    private let stdoutLines: [String]
    private let terminationStatus: Int32
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var stderrLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(stdoutLines: [String], terminationStatus: Int32) {
        self.stdoutLines = stdoutLines
        self.terminationStatus = terminationStatus
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stderrLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {
        for line in stdoutLines {
            stdoutLineHandler?(line)
        }
        terminationHandler?(terminationStatus)
    }

    func terminate() throws {
        terminationHandler?(terminationStatus)
    }
}

private final class RemotePairingStreamingPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.emit([
                    "type": "tool_execution_start",
                    "toolCallId": "tool-1",
                    "toolName": "subagent",
                    "args": [
                        "agent": "reviewer",
                        "task": "Review the latest diff and summarize issues"
                    ]
                ])
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.10) { [weak self] in
                self?.emit([
                    "type": "tool_execution_end",
                    "toolCallId": "tool-1",
                    "toolName": "subagent",
                    "result": [
                        "content": [[
                            "type": "text",
                            "text": "Looks good overall. Watch the new error path."
                        ]]
                    ]
                ])
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.emit([
                    "type": "turn_end",
                    "message": [
                        "content": [[
                            "type": "text",
                            "text": "Done"
                        ]]
                    ]
                ])
            }
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}

private final class RemotePairingRecordingPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private let promptResponseText: String
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?
    private(set) var sentLines: [String] = []

    init(promptResponseText: String = "") {
        self.promptResponseText = promptResponseText
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        sentLines.append(line)
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            guard promptResponseText.isEmpty == false else {
                return
            }
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": promptResponseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [[
                        "type": "text",
                        "text": promptResponseText
                    ]]
                ]
            ])
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}

private final class RemotePairingExtensionUIPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private var pendingPrompt: String?
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
            ])
        case "prompt":
            pendingPrompt = object["message"] as? String
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            emit([
                "type": "extension_ui_request",
                "id": "11111111-1111-1111-1111-111111111111",
                "method": "confirm",
                "title": "Deploy to production?",
                "message": "Pi wants to run deploy --prod.",
                "timeout": 5000
            ])
        case "extension_ui_response":
            let confirmed = object["confirmed"] as? Bool ?? false
            pendingPrompt = nil
            emitTurnEnd(text: confirmed ? "Deployment approved" : "Deployment denied")
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    func emitFireAndForgetUpdates() {
        emit([
            "type": "extension_ui_request",
            "id": "notify-1",
            "method": "notify",
            "message": "Editor prefilled",
            "notifyType": "info"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "status-1",
            "method": "setStatus",
            "statusKey": "rpc-demo",
            "statusText": "Turn ready"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "widget-1",
            "method": "setWidget",
            "widgetKey": "rpc-demo",
            "widgetLines": ["Ready.", "Waiting for input"],
            "widgetPlacement": "belowEditor"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "title-1",
            "method": "setTitle",
            "title": "Pi Demo"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "editor-text-1",
            "method": "set_editor_text",
            "text": "This text was set by the rpc-demo extension."
        ])
    }

    private func emitTurnEnd(text: String) {
        emit([
            "type": "turn_end",
            "message": [
                "content": [[
                    "type": "text",
                    "text": text
                ]]
            ]
        ])
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}

private struct RemotePairingTestExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: ["/tmp/search-a"],
            homeDirectories: ["/tmp/home"],
            pathEnvironment: "/tmp/search-a"
        )
    }
}

private struct RemotePairingTestCommandRunner: ProviderCommandRunning {
    struct Invocation: Hashable {
        let executable: String
        let arguments: [String]
    }

    enum StubbedResult {
        case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
    }

    let results: [Invocation: StubbedResult]

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
            throw NSError(domain: "RemotePairingTestCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub"])
        }

        switch result {
        case .success(let stdout, let stderr, let exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private struct AvailableRemotePairingProviderHealthEvaluator: ProviderHealthEvaluating {
    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        ProviderHealthSummary(
            state: .available,
            summary: "\(providerID.displayName) is available",
            resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
            launchability: .launchable
        )
    }
}

private struct SlowCatalogReadProviderModule: ProviderModule {
    let provider: Provider
    let delayNanoseconds: UInt64

    init(providerID: ProviderID, delayNanoseconds: UInt64) {
        self.provider = Provider(id: providerID)
        self.delayNanoseconds = delayNanoseconds
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }

    func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: provider.id, workspace: workspace, remoteContext: remoteContext)
    }

    func readCatalog(
        _ request: ProviderModuleCatalogReadRequest,
        actions: ProviderModuleCatalogReadActions
    ) async throws -> ProviderModuleCatalogReadResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let health = try await actions.providerHealthSummary()
        return ProviderModuleCatalogReadResult(
            health: health,
            capabilities: providerCapabilities(in: request.workspace, health: health, defaultSession: request.defaultSession),
            prelaunchPrimarySurface: prelaunchPrimarySurface(in: request.workspace),
            defaultSession: defaultSessionSummary(for: request.defaultSession)
        )
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        makeProviderCapabilities(
            provider: provider,
            supportsDefaultSessionLaunch: true,
            supportsNamedSessions: true,
            health: health,
            defaultSession: defaultSession
        )
    }

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
        switch provider.id {
        case .claude:
            .terminal
        case .codex, .ibmBob, .pi:
            .structuredActivityFeed
        }
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        false
    }
}

private final class DelayedEchoSessionRuntimeManager: SessionRuntimeManaging, @unchecked Sendable {
    private struct RuntimeRecord {
        var transcript: String
        var columns: Int = 80
        var rows: Int = 24
        var state: Session.State = .ready
    }

    private let lock = NSLock()
    private let initialTranscript: String
    private var runtimes: [UUID: RuntimeRecord] = [:]
    private var updateObservers: [UUID: [UUID: @Sendable () -> Void]] = [:]
    private var observedSessionIDs: [UUID: UUID] = [:]

    init(initialTranscript: String) {
        self.initialTranscript = initialTranscript
    }

    func setRuntimeChangeHandler(_ handler: (@Sendable (UUID) -> Void)?) {}

    func launchOrResume(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) throws {
        lock.lock()
        runtimes[session.id] = RuntimeRecord(transcript: initialTranscript)
        lock.unlock()
        notifyUpdateObservers(for: session.id)
    }

    func stop(session: Session) throws {
        lock.lock()
        if var runtime = runtimes[session.id] {
            runtime.state = .exited
            runtimes[session.id] = runtime
        }
        lock.unlock()
        notifyUpdateObservers(for: session.id)
    }

    func remove(session: Session) {
        lock.lock()
        runtimes.removeValue(forKey: session.id)
        updateObservers.removeValue(forKey: session.id)
        observedSessionIDs = observedSessionIDs.filter { $0.value != session.id }
        lock.unlock()
    }

    func hasRuntime(for session: Session) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id]?.state
    }

    func sessionRecordAdapterMetadata(for session: Session) -> SessionRecordAdapterMetadata? {
        nil
    }

    func sessionScreen(for session: Session) throws -> SessionScreen {
        let runtime = try record(for: session)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.columns,
            terminalRows: runtime.rows
        )
    }

    func addUpdateObserver(id: UUID, for session: Session, observer: @escaping @Sendable () -> Void) {
        lock.lock()
        updateObservers[session.id, default: [:]][id] = observer
        observedSessionIDs[id] = session.id
        lock.unlock()
    }

    func removeUpdateObserver(id: UUID) {
        lock.lock()
        guard let sessionID = observedSessionIDs.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        updateObservers[sessionID]?.removeValue(forKey: id)
        if updateObservers[sessionID]?.isEmpty == true {
            updateObservers.removeValue(forKey: sessionID)
        }
        lock.unlock()
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let runtime = try record(for: session)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript + text,
            terminalColumns: runtime.columns,
            terminalRows: runtime.rows
        )
    }

    func sendText(_ text: String, to session: Session) throws -> SessionScreen {
        let runtime = try record(for: session)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            guard let self else {
                return
            }

            self.lock.lock()
            guard var updatedRuntime = self.runtimes[session.id] else {
                self.lock.unlock()
                return
            }
            updatedRuntime.transcript += text
            self.runtimes[session.id] = updatedRuntime
            self.lock.unlock()
            self.notifyUpdateObservers(for: session.id)
        }

        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.columns,
            terminalRows: runtime.rows
        )
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen {
        try sessionScreen(for: session)
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision, to session: Session) throws -> SessionScreen {
        throw NexusSessionApprovalError.approvalRequestsUnavailable
    }

    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen {
        lock.lock()
        guard var runtime = runtimes[session.id] else {
            lock.unlock()
            throw NexusMetadataStoreError.sessionNotFound
        }
        runtime.columns = columns
        runtime.rows = rows
        runtimes[session.id] = runtime
        lock.unlock()
        notifyUpdateObservers(for: session.id)
        return SessionScreen(
            session: session,
            transcript: runtime.transcript,
            terminalColumns: runtime.columns,
            terminalRows: runtime.rows
        )
    }

    private func record(for session: Session) throws -> RuntimeRecord {
        lock.lock()
        defer { lock.unlock() }
        guard let runtime = runtimes[session.id] else {
            throw NexusMetadataStoreError.sessionNotFound
        }
        return runtime
    }

    private func notifyUpdateObservers(for sessionID: UUID) {
        let observers: [@Sendable () -> Void]
        lock.lock()
        observers = Array(updateObservers[sessionID, default: [:]].values)
        lock.unlock()
        observers.forEach { $0() }
    }
}

private final class StructuredPromptSessionRuntimeManager: SessionRuntimeManaging, @unchecked Sendable {
    private struct RuntimeRecord {
        var session: Session
        var terminalColumns: Int = 80
        var terminalRows: Int = 24
        var activityItems: [SessionActivityItem]
        var approvalRequests: [SessionApprovalRequest]
    }

    private let lock = NSLock()
    private let providerName: String
    private let initialApprovalRequests: [SessionApprovalRequest]
    private var runtimes: [UUID: RuntimeRecord] = [:]
    private var updateObservers: [UUID: [UUID: @Sendable () -> Void]] = [:]
    private var observedSessionIDs: [UUID: UUID] = [:]

    init(providerName: String, approvalRequests: [SessionApprovalRequest] = []) {
        self.providerName = providerName
        self.initialApprovalRequests = approvalRequests
    }

    func setRuntimeChangeHandler(_ handler: (@Sendable (UUID) -> Void)?) {}

    func launchOrResume(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) throws {
        lock.lock()
        runtimes[session.id] = RuntimeRecord(
            session: session,
            activityItems: [SessionActivityItem(kind: .status, text: "\(providerName) shared Session stream connected")]
                + initialApprovalRequests.map { SessionActivityItem(kind: .approvalRequest, text: "Approval Request: \($0.title)") },
            approvalRequests: initialApprovalRequests
        )
        lock.unlock()
        notifyUpdateObservers(for: session.id)
    }

    func stop(session: Session) throws {
        lock.lock()
        runtimes.removeValue(forKey: session.id)
        lock.unlock()
        notifyUpdateObservers(for: session.id)
    }

    func remove(session: Session) {
        lock.lock()
        runtimes.removeValue(forKey: session.id)
        updateObservers.removeValue(forKey: session.id)
        observedSessionIDs = observedSessionIDs.filter { $0.value != session.id }
        lock.unlock()
    }

    func hasRuntime(for session: Session) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        hasRuntime(for: session) ? .ready : nil
    }

    func sessionRecordAdapterMetadata(for session: Session) -> SessionRecordAdapterMetadata? {
        nil
    }

    func sessionScreen(for session: Session) throws -> SessionScreen {
        let runtime = try record(for: session)
        return SessionScreen(
            session: runtime.session,
            primarySurface: .structuredActivityFeed,
            transcript: runtime.activityItems.map(\.text).joined(separator: "\n"),
            terminalColumns: runtime.terminalColumns,
            terminalRows: runtime.terminalRows,
            activityItems: runtime.activityItems,
            approvalRequests: runtime.approvalRequests
        )
    }

    func addUpdateObserver(id: UUID, for session: Session, observer: @escaping @Sendable () -> Void) {
        lock.lock()
        updateObservers[session.id, default: [:]][id] = observer
        observedSessionIDs[id] = session.id
        lock.unlock()
    }

    func removeUpdateObserver(id: UUID) {
        lock.lock()
        guard let sessionID = observedSessionIDs.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        updateObservers[sessionID]?.removeValue(forKey: id)
        if updateObservers[sessionID]?.isEmpty == true {
            updateObservers.removeValue(forKey: sessionID)
        }
        lock.unlock()
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return try sessionScreen(for: session)
        }

        lock.lock()
        guard var runtime = runtimes[session.id] else {
            lock.unlock()
            throw NexusMetadataStoreError.sessionNotFound
        }
        runtime.activityItems.append(SessionActivityItem(kind: .message, text: "You: \(trimmed)"))
        runtime.activityItems.append(SessionActivityItem(kind: .message, text: "\(providerName): Acknowledged \(trimmed)"))
        runtimes[session.id] = runtime
        lock.unlock()
        notifyUpdateObservers(for: session.id)
        return try sessionScreen(for: session)
    }

    func sendText(_ text: String, to session: Session) throws -> SessionScreen {
        try sessionScreen(for: session)
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen {
        try sessionScreen(for: session)
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision, to session: Session) throws -> SessionScreen {
        lock.lock()
        guard var runtime = runtimes[session.id] else {
            lock.unlock()
            throw NexusMetadataStoreError.sessionNotFound
        }
        guard let index = runtime.approvalRequests.firstIndex(where: { $0.id == approvalRequestID }) else {
            lock.unlock()
            throw NexusSessionApprovalError.approvalRequestsUnavailable
        }

        let approvalRequest = runtime.approvalRequests[index]
        runtime.approvalRequests[index] = SessionApprovalRequest(
            id: approvalRequest.id,
            title: approvalRequest.title,
            text: approvalRequest.text,
            state: decision == .approve ? .approved : .denied
        )
        runtime.activityItems.append(
            SessionActivityItem(
                kind: .approvalDecision,
                text: "\(decision == .approve ? "Approved" : "Denied"): \(approvalRequest.title)"
            )
        )
        runtimes[session.id] = runtime
        lock.unlock()
        notifyUpdateObservers(for: session.id)
        return try sessionScreen(for: session)
    }

    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen {
        lock.lock()
        guard var runtime = runtimes[session.id] else {
            lock.unlock()
            throw NexusMetadataStoreError.sessionNotFound
        }
        runtime.terminalColumns = columns
        runtime.terminalRows = rows
        runtimes[session.id] = runtime
        lock.unlock()
        notifyUpdateObservers(for: session.id)
        return try sessionScreen(for: session)
    }

    private func record(for session: Session) throws -> RuntimeRecord {
        lock.lock()
        defer { lock.unlock() }
        guard let runtime = runtimes[session.id] else {
            throw NexusMetadataStoreError.sessionNotFound
        }
        return runtime
    }

    private func notifyUpdateObservers(for sessionID: UUID) {
        let observers: [@Sendable () -> Void]
        lock.lock()
        observers = Array(updateObservers[sessionID, default: [:]].values)
        lock.unlock()
        observers.forEach { $0() }
    }
}
