#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceRemoteIBMBobStructuredSessionTests {
    @Test func remoteIBMBobDefaultSessionLaunchCreatesStructuredIdleSessionFromSharedProviderCapabilities() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness()
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)
        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let screen = try service.getSessionScreen(sessionID: session.id)

        #expect(providerCard.health.summary == "IBM Bob 3.4.5 is available")
        #expect(providerCard.capabilities.launchDefaultSession.isEnabled)
        #expect(providerCard.capabilities.createNamedSession.isEnabled)
        #expect(providerCard.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(detail.capabilities == providerCard.capabilities)
        #expect(detail.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(session.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(transportHarness.launches().isEmpty)
    }

    @Test func restartedRemoteIBMBobDefaultSessionStaysReadyAndResumableWithoutRemoteRuntimeRecovery() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness()
        func makeService() throws -> NexusService {
            try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let restartedService = try makeService()
        let restartedScreen = try restartedService.getSessionScreen(sessionID: firstSession.id)
        let resumedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)

        #expect(restartedScreen.session.state == .ready)
        #expect(restartedScreen.primarySurface == .structuredActivityFeed)
        #expect(restartedScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(resumedSession.id == firstSession.id)
        #expect(resumedScreen.session.state == .ready)
        #expect(resumedScreen.primarySurface == .structuredActivityFeed)
        #expect(resumedScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(transportHarness.launches().isEmpty)
    }

    @Test func remoteIBMBobNamedSessionUsesSharedNamingAndStructuredIdleScreen() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness()
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let firstSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: nil)
        let secondSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: nil)
        let firstScreen = try service.getSessionScreen(sessionID: firstSession.id)
        let detail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

        #expect(firstSession.name == "Session 1")
        #expect(secondSession.name == "Session 2")
        #expect(firstScreen.primarySurface == .structuredActivityFeed)
        #expect(firstScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(detail.alternateSessions.map(\.name) == ["Session 1", "Session 2"])
        #expect(transportHarness.launches().isEmpty)
    }

    @Test func remoteIBMBobDefaultPromptRunsOnHostThroughTmuxAndReturnsToReadyWithPersistedHistory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness(turns: [
            .init(stdoutLines: [
                #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                #"{"type":"message","text":"Hello from remote Bob"}"#,
                #"{"type":"completion","text":"Remote Bob turn complete"}"#
            ])
        ])
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let responseScreen = try service.sendSessionInput(sessionID: session.id, text: "ship it")
        let persistedScreen = try service.getSessionScreen(sessionID: session.id)
        let metadataStore = try NexusMetadataStore(storeURL: service.storeURL)
        let metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)
        let launch = try #require(transportHarness.launches().first)
        let remoteCommand = try #require(launch.arguments.last)

        #expect(responseScreen.session.state == .ready)
        #expect(responseScreen.primarySurface == .structuredActivityFeed)
        #expect(responseScreen.activityItems.map(\.text) == [
            "IBM Bob Session ready. Send a prompt to start IBM Bob.",
            "You: ship it",
            "Bob turn started",
            "Hello from remote Bob",
            "Remote Bob turn complete"
        ])
        #expect(persistedScreen.activityItems == responseScreen.activityItems)
        #expect(metadata?.ibmBobSessionLinkage?.sessionID == "bob-session-1")
        #expect(launch.executable == "/usr/bin/ssh")
        #expect(launch.arguments.contains("build-box"))
        #expect(remoteCommand.contains("tmux new-session"))
        #expect(remoteCommand.contains("/tmp/fake-bob"))
        #expect(remoteCommand.contains("--approval-mode"))
    }

    @Test func remoteIBMBobLaterPromptResumesFromExactStoredSessionIdentifier() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness(turns: [
            .init(stdoutLines: [
                #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                #"{"type":"message","text":"First reply"}"#,
                #"{"type":"completion","text":"First turn complete"}"#
            ]),
            .init(stdoutLines: [
                #"{"type":"status","text":"Bob resumed turn started"}"#,
                #"{"type":"message","text":"Second reply"}"#,
                #"{"type":"completion","text":"Second turn complete"}"#
            ])
        ])
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        _ = try service.sendSessionInput(sessionID: session.id, text: "first")
        let secondResponse = try service.sendSessionInput(sessionID: session.id, text: "second")
        let metadataStore = try NexusMetadataStore(storeURL: service.storeURL)
        let metadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)
        let secondLaunch = try #require(transportHarness.launches().last)
        let secondRemoteCommand = try #require(secondLaunch.arguments.last)

        #expect(metadata?.ibmBobSessionLinkage?.sessionID == "bob-session-1")
        #expect(secondRemoteCommand.contains("--resume"))
        #expect(secondRemoteCommand.contains("bob-session-1"))
        #expect(secondRemoteCommand.contains("latest") == false)
        #expect(secondResponse.activityItems.suffix(4).map(\.text) == [
            "You: second",
            "Bob resumed turn started",
            "Second reply",
            "Second turn complete"
        ])
    }

    @Test func remoteIBMBobDefaultAndNamedSessionsResumeOnlyTheirOwnStoredContinuity() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness(turns: [
            .init(stdoutLines: [
                #"{"type":"status","text":"Default turn started","session_id":"bob-default"}"#,
                #"{"type":"message","text":"Default first reply"}"#,
                #"{"type":"completion","text":"Default first complete"}"#
            ]),
            .init(stdoutLines: [
                #"{"type":"status","text":"Review turn started","session_id":"bob-review"}"#,
                #"{"type":"message","text":"Review first reply"}"#,
                #"{"type":"completion","text":"Review first complete"}"#
            ]),
            .init(stdoutLines: [
                #"{"type":"status","text":"Follow Up turn started","session_id":"bob-follow-up"}"#,
                #"{"type":"message","text":"Follow Up first reply"}"#,
                #"{"type":"completion","text":"Follow Up first complete"}"#
            ]),
            .init(stdoutLines: [
                #"{"type":"status","text":"Follow Up resumed turn started"}"#,
                #"{"type":"message","text":"Follow Up second reply"}"#,
                #"{"type":"completion","text":"Follow Up second complete"}"#
            ]),
            .init(stdoutLines: [
                #"{"type":"status","text":"Default resumed turn started"}"#,
                #"{"type":"message","text":"Default second reply"}"#,
                #"{"type":"completion","text":"Default second complete"}"#
            ]),
            .init(stdoutLines: [
                #"{"type":"status","text":"Review resumed turn started"}"#,
                #"{"type":"message","text":"Review second reply"}"#,
                #"{"type":"completion","text":"Review second complete"}"#
            ])
        ])
        func makeService() throws -> NexusService {
            try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)
        }

        let service = try makeService()
        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let defaultSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let reviewSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: "Review")
        let followUpSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: "Follow Up")
        _ = try service.sendSessionInput(sessionID: defaultSession.id, text: "default first")
        _ = try service.sendSessionInput(sessionID: reviewSession.id, text: "review first")
        _ = try service.sendSessionInput(sessionID: followUpSession.id, text: "follow up first")

        let restartedService = try makeService()
        let followUpSecondResponse = try restartedService.sendSessionInput(sessionID: followUpSession.id, text: "follow up second")
        let defaultSecondResponse = try restartedService.sendSessionInput(sessionID: defaultSession.id, text: "default second")
        let reviewSecondResponse = try restartedService.sendSessionInput(sessionID: reviewSession.id, text: "review second")
        let launches = transportHarness.launches()
        #expect(launches.count == 6)
        let followUpResumeLaunch = launches[3]
        let defaultResumeLaunch = launches[4]
        let reviewResumeLaunch = launches[5]
        let metadataStore = try NexusMetadataStore(storeURL: restartedService.storeURL)
        let defaultMetadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: defaultSession.id)
        let reviewMetadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: reviewSession.id)
        let followUpMetadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: followUpSession.id)

        #expect(defaultMetadata?.ibmBobSessionLinkage?.sessionID == "bob-default")
        #expect(reviewMetadata?.ibmBobSessionLinkage?.sessionID == "bob-review")
        #expect(followUpMetadata?.ibmBobSessionLinkage?.sessionID == "bob-follow-up")

        let followUpResumeCommand = try #require(followUpResumeLaunch.arguments.last)
        #expect(followUpResumeCommand.contains("--resume"))
        #expect(followUpResumeCommand.contains("bob-follow-up"))
        #expect(followUpResumeCommand.contains("bob-default") == false)
        #expect(followUpResumeCommand.contains("bob-review") == false)
        #expect(followUpResumeCommand.contains("latest") == false)

        let defaultResumeCommand = try #require(defaultResumeLaunch.arguments.last)
        #expect(defaultResumeCommand.contains("--resume"))
        #expect(defaultResumeCommand.contains("bob-default"))
        #expect(defaultResumeCommand.contains("bob-review") == false)
        #expect(defaultResumeCommand.contains("bob-follow-up") == false)
        #expect(defaultResumeCommand.contains("latest") == false)

        let reviewResumeCommand = try #require(reviewResumeLaunch.arguments.last)
        #expect(reviewResumeCommand.contains("--resume"))
        #expect(reviewResumeCommand.contains("bob-review"))
        #expect(reviewResumeCommand.contains("bob-default") == false)
        #expect(reviewResumeCommand.contains("bob-follow-up") == false)
        #expect(reviewResumeCommand.contains("latest") == false)

        #expect(followUpSecondResponse.activityItems.suffix(4).map(\.text) == [
            "You: follow up second",
            "Follow Up resumed turn started",
            "Follow Up second reply",
            "Follow Up second complete"
        ])
        #expect(defaultSecondResponse.activityItems.suffix(4).map(\.text) == [
            "You: default second",
            "Default resumed turn started",
            "Default second reply",
            "Default second complete"
        ])
        #expect(reviewSecondResponse.activityItems.suffix(4).map(\.text) == [
            "You: review second",
            "Review resumed turn started",
            "Review second reply",
            "Review second complete"
        ])
    }

    @Test func remoteControllerSeesSharedRemoteIBMBobActivityAndMacCanReopenSameReadyHistory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let transportHarness = RemoteIBMBobTransportHarness(turns: [
            .init(stdoutLines: [
                #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                #"{"type":"message","text":"Hello from remote Bob"}"#,
                #"{"type":"completion","text":"Remote Bob turn complete"}"#
            ])
        ])
        let service = try makeRemoteIBMBobService(rootURL: rootURL, transportHarness: transportHarness)

        let group = try service.createWorkspaceGroup(name: "Remote")
        let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try service.validateHost(hostID: host.id)
        let workspace = try service.createRemoteWorkspace(
            name: "Remote Bob",
            hostID: host.id,
            remotePath: "/srv/bob",
            primaryGroupID: group.id
        )

        let pairedDeviceID = UUID()
        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        _ = try service.takeRemoteSessionControl(sessionID: session.id, pairedDeviceID: pairedDeviceID, columns: 44, rows: 12)
        let remoteScreen = try service.sendRemoteSessionInput(sessionID: session.id, pairedDeviceID: pairedDeviceID, text: "ship it")
        let macScreen = try service.getSessionScreen(sessionID: session.id)

        #expect(remoteScreen.controller == .pairedDevice(pairedDeviceID))
        #expect(remoteScreen.session.state == .ready)
        #expect(remoteScreen.activityItems.map(\.text) == [
            "IBM Bob Session ready. Send a prompt to start IBM Bob.",
            "You: ship it",
            "Bob turn started",
            "Hello from remote Bob",
            "Remote Bob turn complete"
        ])
        #expect(macScreen.activityItems == remoteScreen.activityItems)
        #expect(macScreen.session.state == .ready)
    }
}

private func makeRemoteIBMBobService(rootURL: URL, transportHarness: RemoteIBMBobTransportHarness) throws -> NexusService {
    let launcher = ProcessSessionRuntimeLauncher(ibmBobTransportFactory: transportHarness.makeTransport)

    return try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthEvaluator(
            executableResolver: RemoteIBMBobStubExecutableResolver(executables: [:]),
            commandRunner: RemoteIBMBobCommandRunner(),
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
        ),
        hostValidationEvaluator: RemoteIBMBobAvailableHostValidationEvaluator(),
        workspaceAvailabilityEvaluator: RemoteIBMBobAvailableWorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
    )
}

private struct RemoteIBMBobStubExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: ["/tmp/search-a", "/tmp/search-b"],
            homeDirectories: ["/tmp/home"],
            pathEnvironment: "/tmp/search-a:/tmp/search-b"
        )
    }
}

private final class RemoteIBMBobCommandRunner: ProviderCommandRunning, @unchecked Sendable {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        guard let script = arguments.last else {
            throw NSError(domain: "RemoteIBMBobCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SSH script for \(executable) \(arguments)"])
        }

        if script.contains("--list-sessions") {
            return ProviderCommandResult(exitStatus: 0, stdout: "[]\n", stderr: "")
        }

        if script.contains("--version") {
            return ProviderCommandResult(exitStatus: 0, stdout: "/tmp/fake-bob\n3.4.5\n", stderr: "")
        }

        throw NSError(domain: "RemoteIBMBobCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected SSH script: \(script)"])
    }
}

private struct RemoteIBMBobAvailableHostValidationEvaluator: HostValidationEvaluating {
    func validate(host: NexusDomain.Host) -> HostValidationResult {
        HostValidationResult(
            state: .available,
            summary: "Host is available",
            diagnostics: [
                HostValidationDiagnostic(severity: .info, code: "sshTarget", message: "Validated \(host.sshTarget)")
            ]
        )
    }
}

private struct RemoteIBMBobAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult {
        WorkspaceAvailabilityResult(
            state: .available,
            summary: "Workspace is available",
            diagnostics: [
                WorkspaceAvailabilityDiagnostic(
                    severity: .info,
                    code: "remotePath",
                    message: "Validated remote path \(workspace.folderPath) on \(host.name)."
                )
            ]
        )
    }
}

private final class RemoteIBMBobTransportHarness: @unchecked Sendable {
    struct Turn {
        let stdoutLines: [String]
        let stderrLines: [String]
        let terminationStatus: Int32

        init(stdoutLines: [String], stderrLines: [String] = [], terminationStatus: Int32 = 0) {
            self.stdoutLines = stdoutLines
            self.stderrLines = stderrLines
            self.terminationStatus = terminationStatus
        }
    }

    struct Launch: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    private let lock = NSLock()
    private let turns: [Turn]
    private var recordedLaunches: [Launch] = []

    init(turns: [Turn] = []) {
        self.turns = turns
    }

    func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws -> any IBMBobTransporting {
        lock.lock()
        recordedLaunches.append(Launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        let launchIndex = recordedLaunches.count - 1
        let turn = turns.isEmpty ? Turn(stdoutLines: []) : turns[min(launchIndex, turns.count - 1)]
        lock.unlock()
        return RemoteIBMBobSynchronousTransport(turn: turn)
    }

    func launches() -> [Launch] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunches
    }
}

private final class RemoteIBMBobSynchronousTransport: IBMBobTransporting, @unchecked Sendable {
    private let turn: RemoteIBMBobTransportHarness.Turn
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var stderrLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(turn: RemoteIBMBobTransportHarness.Turn = .init(stdoutLines: [])) {
        self.turn = turn
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
        for line in turn.stdoutLines {
            stdoutLineHandler?(line)
        }
        for line in turn.stderrLines {
            stderrLineHandler?(line)
        }
        terminationHandler?(turn.terminationStatus)
    }

    func terminate() throws {}
}
#endif
