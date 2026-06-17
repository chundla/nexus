#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    @Suite(.serialized)
    struct NexusServiceIBMBobSessionDeletionTests {
        @Test func localIBMBobDeleteAttemptsBestEffortNativeCleanupWhenStoredContinuityExists() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let commandRunner = RecordingIBMBobDeletionCommandRunner(expectations: [
                .init(
                    invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]),
                    result: .success(stdout: "3.4.5\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                    result: .success(stdout: "[]\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                    result: .success(stdout: #"[{"session_id":"bob-session-1","index":2}]"# + "\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"]),
                    result: .success(stdout: "deleted\n")
                ),
            ])
            let service = try makeIBMBobDeletionService(
                rootURL: rootURL,
                commandRunner: commandRunner,
                turns: [
                    .init(stdoutLines: [
                        #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                        #"{"type":"message","text":"First reply"}"#,
                        #"{"type":"completion","text":"First turn complete"}"#,
                    ])
                ]
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Bob",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
            _ = try await service.sendSessionInput(sessionID: session.id, text: "ship it")
            let deleted = try service.deleteSessionRecord(sessionID: session.id)
            let cleanupInvocation = try #require(commandRunner.invocations.last)

            #expect(deleted)
            #expect(cleanupInvocation.arguments == ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"])
        }

        @Test func localIBMBobDeleteStillRemovesSessionRecordWhenNativeCleanupFails() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let commandRunner = RecordingIBMBobDeletionCommandRunner(expectations: [
                .init(
                    invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]),
                    result: .success(stdout: "3.4.5\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                    result: .success(stdout: "[]\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                    result: .success(stdout: #"[{"session_id":"bob-session-1","index":2}]"# + "\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"]),
                    result: .success(stdout: "", stderr: "delete failed\n", exitStatus: 1)
                ),
            ])
            let service = try makeIBMBobDeletionService(
                rootURL: rootURL,
                commandRunner: commandRunner,
                turns: [
                    .init(stdoutLines: [
                        #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                        #"{"type":"message","text":"First reply"}"#,
                        #"{"type":"completion","text":"First turn complete"}"#,
                    ])
                ]
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Bob",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
            _ = try await service.sendSessionInput(sessionID: session.id, text: "ship it")
            let deleted = try service.deleteSessionRecord(sessionID: session.id)
            let providerDetail = try await service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

            #expect(deleted)
            #expect(providerDetail.defaultSession == nil)
            #expect(
                commandRunner.invocations.contains(where: {
                    $0.arguments == ["-lic", "'/tmp/fake-bob' '--delete-session' '2'"]
                }))
        }

        @Test func remoteIBMBobDeleteAttemptsBestEffortHostCleanupWhenStoredContinuityExists() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let commandRunner = SequentialRemoteIBMBobDeletionCommandRunner(results: [
                .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                .success(stdout: "[]\n"),
                .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                .success(stdout: #"[{"session_id":"bob-session-1","index":2}]"# + "\n"),
                .success(stdout: "deleted\n"),
            ])
            let service = try makeRemoteIBMBobDeletionService(
                rootURL: rootURL,
                commandRunner: commandRunner,
                turns: [
                    .init(stdoutLines: [
                        #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                        #"{"type":"message","text":"First reply"}"#,
                        #"{"type":"completion","text":"First turn complete"}"#,
                    ])
                ]
            )

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Bob",
                hostID: host.id,
                remotePath: "/srv/bob",
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
            _ = try await service.sendSessionInput(sessionID: session.id, text: "ship it")
            let deleted = try service.deleteSessionRecord(sessionID: session.id)
            let providerDetail = try await service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)
            let cleanupInvocation = commandRunner.invocations.first(where: { invocation in
                invocation.executable == "/usr/bin/ssh"
                    && invocation.arguments.last?.contains("--delete-session") == true
            })

            #expect(deleted)
            #expect(providerDetail.defaultSession == nil)
            #expect(cleanupInvocation?.arguments.contains("build-box") == true)
            #expect(cleanupInvocation?.arguments.last?.contains("--delete-session") == true)
            #expect(cleanupInvocation?.arguments.last?.contains("'2'") == true)
        }

        @Test func remoteIBMBobDeleteStillRemovesSessionRecordWhenHostCleanupFails() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let commandRunner = SequentialRemoteIBMBobDeletionCommandRunner(results: [
                .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                .success(stdout: "[]\n"),
                .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                .success(stdout: #"[{"session_id":"bob-session-1","index":2}]"# + "\n"),
                .success(stdout: "", stderr: "delete failed\n", exitStatus: 1),
                .success(stdout: "/tmp/fake-bob\n3.4.5\n"),
                .success(stdout: "[]\n"),
            ])
            let service = try makeRemoteIBMBobDeletionService(
                rootURL: rootURL,
                commandRunner: commandRunner,
                turns: [
                    .init(stdoutLines: [
                        #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                        #"{"type":"message","text":"First reply"}"#,
                        #"{"type":"completion","text":"First turn complete"}"#,
                    ])
                ]
            )

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Bob",
                hostID: host.id,
                remotePath: "/srv/bob",
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
            _ = try await service.sendSessionInput(sessionID: session.id, text: "ship it")
            let deleted = try service.deleteSessionRecord(sessionID: session.id)
            let providerDetail = try await service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)
            let cleanupInvocation = commandRunner.invocations.first(where: { invocation in
                invocation.executable == "/usr/bin/ssh"
                    && invocation.arguments.last?.contains("--delete-session") == true
            })

            #expect(deleted)
            #expect(providerDetail.defaultSession == nil)
            #expect(cleanupInvocation?.arguments.contains("build-box") == true)
            #expect(cleanupInvocation?.arguments.last?.contains("--delete-session") == true)
        }

        @Test func deleteSessionRecordRoutesIBMBobStoredContinuityCleanupThroughProviderModule() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let commandRunner = RecordingIBMBobDeletionCommandRunner(expectations: [
                .init(
                    invocation: .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]),
                    result: .success(stdout: "3.4.5\n")
                ),
                .init(
                    invocation: .init(
                        executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]),
                    result: .success(stdout: "[]\n")
                ),
            ])
            let cleanupTracker = TrackingIBMBobNativeSessionCleaner()
            let providerModuleTracker = IBMBobDeleteSessionRecordTracker()
            let service = try makeIBMBobDeletionService(
                rootURL: rootURL,
                commandRunner: commandRunner,
                turns: [
                    .init(stdoutLines: [
                        #"{"type":"status","text":"Bob turn started","session_id":"bob-session-1"}"#,
                        #"{"type":"message","text":"First reply"}"#,
                        #"{"type":"completion","text":"First turn complete"}"#,
                    ])
                ],
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .ibmBob: DeleteTrackingIBMBobProviderModule(tracker: providerModuleTracker)
                    ]
                ),
                ibmBobNativeSessionCleaner: cleanupTracker
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Bob",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
            _ = try await service.sendSessionInput(sessionID: session.id, text: "ship it")

            let deleted = try service.deleteSessionRecord(sessionID: session.id)

            #expect(deleted)
            #expect(providerModuleTracker.requests == [session.id])
            #expect(cleanupTracker.requests == [session.id])
        }
    }

    private func makeIBMBobDeletionService(
        rootURL: URL,
        commandRunner: RecordingIBMBobDeletionCommandRunner,
        turns: [IBMBobDeletionTransportHarness.Turn],
        providerModuleRegistry: ProviderModuleRegistry? = nil,
        ibmBobNativeSessionCleaner: (any IBMBobNativeSessionCleaning)? = nil
    ) throws -> NexusService {
        let transportHarness = IBMBobDeletionTransportHarness(turns: turns)
        let launcher = ProcessSessionRuntimeLauncher(
            localShellEnvironmentResolver: IBMBobDeletionStubShellEnvironmentResolver(),
            ibmBobTransportFactory: { executable, arguments, workingDirectory in
                try transportHarness.makeTransport(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory
                )
            }
        )
        let resolvedNativeSessionCleaner =
            ibmBobNativeSessionCleaner
            ?? IBMBobNativeSessionCleaner(
                executableResolver: IBMBobDeletionStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )

        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: IBMBobDeletionStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher),
            providerModuleRegistry: providerModuleRegistry,
            ibmBobNativeSessionCleaner: resolvedNativeSessionCleaner
        )
    }

    private func makeRemoteIBMBobDeletionService(
        rootURL: URL,
        commandRunner: SequentialRemoteIBMBobDeletionCommandRunner,
        turns: [IBMBobDeletionTransportHarness.Turn]
    ) throws -> NexusService {
        let transportHarness = IBMBobDeletionTransportHarness(turns: turns)
        let launcher = ProcessSessionRuntimeLauncher(
            localShellEnvironmentResolver: IBMBobDeletionStubShellEnvironmentResolver(),
            ibmBobTransportFactory: { executable, arguments, workingDirectory in
                try transportHarness.makeTransport(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory
                )
            }
        )
        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: IBMBobDeletionStubExecutableResolver(executables: [:]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            hostValidationEvaluator: RemoteIBMBobDeletionAvailableHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: RemoteIBMBobDeletionAvailableWorkspaceAvailabilityEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher),
            ibmBobNativeSessionCleaner: IBMBobNativeSessionCleaner(
                executableResolver: IBMBobDeletionStubExecutableResolver(executables: [:]),
                commandRunner: commandRunner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
        )
    }

    private struct IBMBobDeletionStubShellEnvironmentResolver: LocalShellEnvironmentResolving {
        func resolvedEnvironment() -> [String: String]? {
            ["SHELL": "/bin/zsh", "PATH": "/tmp/bin"]
        }
    }

    private struct IBMBobDeletionStubExecutableResolver: ProviderExecutableResolving {
        let executables: [String: String]

        func resolveExecutable(named command: String) -> ProviderExecutableResolution {
            ProviderExecutableResolution(
                resolvedExecutable: executables[command],
                searchedDirectories: ["/tmp/bin"],
                homeDirectories: ["/tmp/home"],
                pathEnvironment: "/tmp/bin"
            )
        }
    }

    private struct RemoteIBMBobDeletionAvailableHostValidationEvaluator: HostValidationEvaluating {
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

    private struct RemoteIBMBobDeletionAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
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

    private final class RecordingIBMBobDeletionCommandRunner: ProviderCommandRunning, @unchecked Sendable {
        struct Invocation: Equatable {
            let executable: String
            let arguments: [String]
        }

        struct Expectation {
            let invocation: Invocation
            let result: StubbedResult
        }

        struct RecordedInvocation: Equatable {
            let executable: String
            let arguments: [String]
            let currentDirectoryURL: URL?
        }

        enum StubbedResult {
            case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
        }

        private let expectations: [Expectation]
        private(set) var invocations: [RecordedInvocation] = []

        init(expectations: [Expectation]) {
            self.expectations = expectations
        }

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            let recordedInvocation = RecordedInvocation(
                executable: executable, arguments: arguments, currentDirectoryURL: currentDirectoryURL)
            invocations.append(recordedInvocation)

            let invocation = Invocation(executable: executable, arguments: arguments)
            guard expectations.indices.contains(invocations.count - 1),
                expectations[invocations.count - 1].invocation == invocation
            else {
                throw NSError(
                    domain: "RecordingIBMBobDeletionCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected stub lookup for \(executable) \(arguments)"])
            }

            switch expectations[invocations.count - 1].result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class IBMBobDeleteSessionRecordTracker: @unchecked Sendable {
        var requests: [UUID] = []
    }

    private final class TrackingIBMBobNativeSessionCleaner: IBMBobNativeSessionCleaning, @unchecked Sendable {
        var requests: [UUID] = []

        func bestEffortDeleteStoredContinuity(
            for session: Session,
            workspace: Workspace,
            host: NexusDomain.Host?,
            sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
        ) {
            requests.append(session.id)
        }
    }

    private struct DeleteTrackingIBMBobProviderModule: ProviderModule {
        private let module = IBMBobProviderModule()
        let tracker: IBMBobDeleteSessionRecordTracker

        var provider: Provider { module.provider }

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
            module.supportsDefaultSessionLaunch(in: workspace)
        }

        func supportsNamedSessions(in workspace: Workspace) -> Bool {
            module.supportsNamedSessions(in: workspace)
        }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            await module.providerHealthSummary(
                for: workspace,
                remoteContext: remoteContext,
                providerHealthEvaluator: providerHealthEvaluator
            )
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            module.providerCapabilities(in: workspace, health: health, defaultSession: defaultSession)
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            module.prelaunchPrimarySurface(in: workspace)
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            module.reusesRemoteHealthSnapshot(snapshot, remoteContext: remoteContext)
        }

        func planSessionTransition(
            _ request: ProviderModuleSessionTransitionRequest
        ) async throws -> ProviderModuleSessionTransitionPlan {
            try await module.planSessionTransition(request)
        }

        func sessionMayRemainReadyWithoutRuntime(
            _ session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> Bool {
            module.sessionMayRemainReadyWithoutRuntime(
                session,
                workspace: workspace,
                persistedPrimarySurface: persistedPrimarySurface,
                storedMetadata: storedMetadata
            )
        }

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)? {
            try await module.constructRuntime(
                for: session,
                workspace: workspace,
                launchConfiguration: launchConfiguration,
                actions: actions
            )
        }

        func prepareDeleteSessionRecord(
            _ request: ProviderModuleDeleteSessionRecordRequest,
            actions: ProviderModuleDeleteSessionRecordActions
        ) {
            tracker.requests.append(request.session.id)
            module.prepareDeleteSessionRecord(request, actions: actions)
        }
    }

    private final class SequentialRemoteIBMBobDeletionCommandRunner: ProviderCommandRunning, @unchecked Sendable {
        struct RecordedInvocation: Equatable {
            let executable: String
            let arguments: [String]
            let currentDirectoryURL: URL?
        }

        enum StubbedResult {
            case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
        }

        let results: [StubbedResult]
        private(set) var invocations: [RecordedInvocation] = []

        init(results: [StubbedResult]) {
            self.results = results
        }

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            let recordedInvocation = RecordedInvocation(
                executable: executable, arguments: arguments, currentDirectoryURL: currentDirectoryURL)
            invocations.append(recordedInvocation)
            let index = invocations.count - 1
            guard results.indices.contains(index) else {
                throw NSError(
                    domain: "SequentialRemoteIBMBobDeletionCommandRunner", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Missing sequential stub #\(index) for \(executable) \(arguments)"
                    ])
            }

            switch results[index] {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class IBMBobDeletionTransportHarness: @unchecked Sendable {
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

        private let turns: [Turn]
        private var launchCount = 0

        init(turns: [Turn]) {
            self.turns = turns
        }

        func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws
            -> any IBMBobTransporting
        {
            defer { launchCount += 1 }
            return IBMBobDeletionSynchronousTransport(turn: turns[min(launchCount, turns.count - 1)])
        }
    }

    private final class IBMBobDeletionSynchronousTransport: IBMBobTransporting, @unchecked Sendable {
        private let turn: IBMBobDeletionTransportHarness.Turn
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(turn: IBMBobDeletionTransportHarness.Turn) {
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
