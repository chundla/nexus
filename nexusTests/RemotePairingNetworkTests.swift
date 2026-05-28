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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
        #expect(sessionSurfaceSupport(for: screen, on: .remoteClient, workspaceKind: .local) == .supported)
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
            providerHealthEvaluator: ProviderHealthEvaluator(
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
    }

    private let lock = NSLock()
    private let providerName: String
    private var runtimes: [UUID: RuntimeRecord] = [:]
    private var updateObservers: [UUID: [UUID: @Sendable () -> Void]] = [:]
    private var observedSessionIDs: [UUID: UUID] = [:]

    init(providerName: String) {
        self.providerName = providerName
    }

    func launchOrResume(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) throws {
        lock.lock()
        runtimes[session.id] = RuntimeRecord(
            session: session,
            activityItems: [SessionActivityItem(kind: .status, text: "\(providerName) shared Session stream connected")]
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
            activityItems: runtime.activityItems
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
        throw NexusSessionApprovalError.approvalRequestsUnavailable
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
