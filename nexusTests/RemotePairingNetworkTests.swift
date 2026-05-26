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

        #expect(catalog.workspaceGroups == [group])
        #expect(catalog.recentNavigation.map(\.target) == [.workspace(workspace.id)])
        #expect(catalog.workspaceOverviews.map(\.workspace.id) == [workspace.id])
        #expect(catalog.workspaceOverviews.first?.providerCards.isEmpty == false)
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

        var disconnectContinuation: AsyncStream<any Error>.Continuation?
        let disconnectStream = AsyncStream<any Error> { continuation in
            disconnectContinuation = continuation
        }
        var disconnectIterator = disconnectStream.makeAsyncIterator()

        let observation = try await remoteClient.observeSessionScreen(
            for: pairedMac,
            sessionID: session.id,
            onUpdate: { _ in },
            onDisconnect: { error in
                disconnectContinuation?.yield(error)
                disconnectContinuation?.finish()
            }
        )
        let disconnectError = try #require(await disconnectIterator.next())
        await observation.cancel()

        #expect((disconnectError as? RemotePairingHTTPError) == .pairingRevoked("Pair this iPhone again to browse this Paired Mac"))

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
