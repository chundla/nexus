#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    @Suite(.serialized)
    struct NexusServiceRemoteClaudeStructuredSessionTests {
        @Test func remoteClaudeDefaultSessionLaunchesStructuredSurfaceThroughSSHBridgeAndStreamsReplies()
            async throws
        {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteClaudeTransportHarness()
            let service = try makeRemoteClaudeService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Claude",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
            let streamingScreen = try await service.sendSessionInput(sessionID: session.id, text: "ping")
            transportHarness.completeLatestTurn(result: "pong")
            let completedScreen = try service.getSessionScreen(sessionID: session.id)
            let launch = try #require(transportHarness.launches().first)

            #expect(session.state == .ready)
            #expect(streamingScreen.primarySurface == .structuredActivityFeed)
            #expect(streamingScreen.isAgentTurnInProgress)
            #expect(
                streamingScreen.activityItems.map(\.text) == [
                    "Claude Session ready. Send a prompt to start Claude.",
                    "You: ping",
                    "Claude Session started.",
                    "Claude: pong",
                ])
            #expect(completedScreen.primarySurface == .structuredActivityFeed)
            #expect(completedScreen.isAgentTurnInProgress == false)
            #expect(
                completedScreen.activityItems.map(\.text) == [
                    "Claude Session ready. Send a prompt to start Claude.",
                    "You: ping",
                    "Claude Session started.",
                    "Claude: pong",
                    "pong",
                ])
            #expect(launch.executable == "/usr/bin/ssh")
            #expect(launch.arguments.prefix(5) == ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
            #expect(launch.arguments.contains("2222"))
            #expect(launch.arguments.last?.contains("tmux new-session") == true)
            #expect(launch.arguments.last?.contains("--session-id") == true)
            #expect(launch.arguments.last?.contains("/home/tester/.local/bin/claude") == true)
        }

        @Test func restartedRemoteClaudeDefaultSessionRecoversThroughAttachExistingBridgeAndResume() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteClaudeTransportHarness()
            func makeService() throws -> NexusService {
                try makeRemoteClaudeService(rootURL: rootURL, transportHarness: transportHarness)
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Claude",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let firstSession = try await service.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .claude)
            let restartedService = try makeService()
            let resumedSession = try await restartedService.launchOrResumeDefaultSession(
                workspaceID: workspace.id,
                providerID: .claude
            )
            let resumedScreen = try restartedService.getSessionScreen(sessionID: resumedSession.id)
            let launches = transportHarness.launches()
            let firstLaunch = try #require(launches.first)
            let resumedLaunch = try #require(launches.last)

            #expect(firstSession.id == resumedSession.id)
            #expect(resumedScreen.session.state == .ready)
            #expect(resumedScreen.primarySurface == .structuredActivityFeed)
            #expect(resumedScreen.activityItems.map(\.text) == ["Claude Session ready. Send a prompt to start Claude."])
            #expect(launches.count == 2)
            #expect(firstLaunch.isResuming == false)
            #expect(resumedLaunch.isResuming)
            #expect(resumedLaunch.sessionID == firstLaunch.sessionID)
            #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
            #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
        }

        @Test func remoteClaudeBridgeLossLeavesInterruptedInspectableSessionUntilExplicitResume() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let transportHarness = RemoteClaudeTransportHarness()
            let service = try makeRemoteClaudeService(rootURL: rootURL, transportHarness: transportHarness)

            let group = try service.createWorkspaceGroup(name: "Remote")
            let host = try service.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try service.validateHost(hostID: host.id)
            let workspace = try service.createRemoteWorkspace(
                name: "Remote Claude",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
            transportHarness.disconnectLatestTransport(status: 255)

            let interruptedScreen = try service.getSessionScreen(sessionID: session.id)
            let detail = try await service.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
            let launchesAfterDisconnect = transportHarness.launches()
            let resumedSession = try await service.launchOrResumeSession(sessionID: session.id)
            let resumedScreen = try service.getSessionScreen(sessionID: resumedSession.id)
            let resumedLaunch = try #require(transportHarness.launches().last)

            #expect(interruptedScreen.session.state == .interrupted)
            #expect(interruptedScreen.primarySurface == .structuredActivityFeed)
            #expect(
                interruptedScreen.activityItems.last?.text
                    == "Claude Session stream disconnected. Relaunch to reconnect to the tmux-backed remote runtime.")
            #expect(detail.defaultSession?.state == .interrupted)
            #expect(launchesAfterDisconnect.count == 1)
            #expect(resumedSession.id == session.id)
            #expect(resumedScreen.session.state == .ready)
            #expect(resumedScreen.primarySurface == .structuredActivityFeed)
            #expect(resumedLaunch.isResuming)
            #expect(resumedLaunch.arguments.last?.contains("tmux has-session") == true)
            #expect(resumedLaunch.arguments.last?.contains("tmux new-session") == false)
        }
    }

    private func makeRemoteClaudeService(rootURL: URL, transportHarness: RemoteClaudeTransportHarness) throws
        -> NexusService
    {
        let launcher = ProcessSessionRuntimeLauncher(claudeTransportFactory: transportHarness.makeTransport)

        return try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: RemoteClaudeStubExecutableResolver(),
                commandRunner: RemoteClaudeStubCommandRunner(),
                remoteClaudeStreamJSONReadinessProbe: RemoteClaudeReadyReadinessProbe()
            ),
            hostValidationEvaluator: RemoteClaudeAvailableHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: RemoteClaudeAvailableWorkspaceAvailabilityEvaluator(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
    }

    private struct RemoteClaudeStubExecutableResolver: ProviderExecutableResolving {
        func resolveExecutable(named command: String) -> ProviderExecutableResolution {
            ProviderExecutableResolution(
                resolvedExecutable: nil,
                searchedDirectories: [],
                homeDirectories: [],
                pathEnvironment: nil
            )
        }
    }

    private struct RemoteClaudeStubCommandRunner: ProviderCommandRunning {
        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            ProviderCommandResult(
                exitStatus: 0,
                stdout: "/home/tester/.local/bin/claude\n1.2.3\n",
                stderr: ""
            )
        }
    }

    private struct RemoteClaudeReadyReadinessProbe: RemoteClaudeStreamJSONReadinessProbing {
        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws {}
    }

    private struct RemoteClaudeAvailableHostValidationEvaluator: HostValidationEvaluating {
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

    private struct RemoteClaudeAvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
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

    private final class RemoteClaudeTransportHarness: @unchecked Sendable {
        struct ConnectionAttempt: Sendable {
            let executable: String
            let arguments: [String]
        }

        struct Launch: Sendable {
            let executable: String
            let arguments: [String]
            let sessionID: String
            let isResuming: Bool
        }

        private let lock = NSLock()
        private var recordedConnectionAttempts: [ConnectionAttempt] = []
        private var recordedLaunches: [Launch] = []
        private var sessionIDsByRuntimeIdentifier: [String: String] = [:]
        private var activeTransports: [RemoteClaudeTransport] = []

        func makeTransport(executable: String, arguments: [String], workingDirectory: String?) throws
            -> any ClaudeStreamJSONTransporting
        {
            lock.lock()
            recordedConnectionAttempts.append(ConnectionAttempt(executable: executable, arguments: arguments))
            lock.unlock()

            let transport = RemoteClaudeTransport(executable: executable, arguments: arguments, harness: self)
            register(transport)
            return transport
        }

        func recordLaunch(_ launch: Launch, runtimeIdentifier: String?) {
            lock.lock()
            recordedLaunches.append(launch)
            if let runtimeIdentifier {
                sessionIDsByRuntimeIdentifier[runtimeIdentifier] = launch.sessionID
            }
            lock.unlock()
        }

        func sessionID(for runtimeIdentifier: String?, explicitSessionID: String?) -> String {
            lock.lock()
            defer { lock.unlock() }
            if let explicitSessionID {
                if let runtimeIdentifier {
                    sessionIDsByRuntimeIdentifier[runtimeIdentifier] = explicitSessionID
                }
                return explicitSessionID
            }
            if let runtimeIdentifier,
                let stored = sessionIDsByRuntimeIdentifier[runtimeIdentifier]
            {
                return stored
            }
            return UUID().uuidString
        }

        func launches() -> [Launch] {
            lock.lock()
            defer { lock.unlock() }
            return recordedLaunches
        }

        func disconnectLatestTransport(status: Int32) {
            lock.lock()
            let transport = activeTransports.last
            lock.unlock()
            transport?.disconnect(status: status)
        }

        func completeLatestTurn(result: String) {
            lock.lock()
            let transport = activeTransports.last
            lock.unlock()
            transport?.completeTurn(result: result)
        }

        private func register(_ transport: RemoteClaudeTransport) {
            lock.lock()
            activeTransports.append(transport)
            lock.unlock()
        }
    }

    private final class RemoteClaudeTransport: ClaudeStreamJSONTransporting, @unchecked Sendable {
        private let executable: String
        private let arguments: [String]
        private let harness: RemoteClaudeTransportHarness
        private let runtimeIdentifier: String?
        private let sessionID: String
        private let isResuming: Bool
        private let workingDirectory: String
        private var didEmitInit = false
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(executable: String, arguments: [String], harness: RemoteClaudeTransportHarness) {
            self.executable = executable
            self.arguments = arguments
            self.harness = harness
            let remoteCommand = arguments.last ?? ""
            self.runtimeIdentifier = Self.runtimeIdentifier(in: remoteCommand)
            self.isResuming =
                remoteCommand.contains("--resume")
                || (remoteCommand.contains("tmux has-session") && remoteCommand.contains("tmux new-session") == false)
            self.sessionID = harness.sessionID(
                for: runtimeIdentifier,
                explicitSessionID: Self.explicitSessionID(in: remoteCommand)
            )
            self.workingDirectory = Self.workingDirectory(in: remoteCommand)
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
            harness.recordLaunch(
                .init(
                    executable: executable,
                    arguments: arguments,
                    sessionID: sessionID,
                    isResuming: isResuming
                ),
                runtimeIdentifier: runtimeIdentifier
            )
        }

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "user"
            else {
                return
            }

            if didEmitInit == false {
                didEmitInit = true
                emit([
                    "type": "system",
                    "subtype": "init",
                    "session_id": sessionID,
                    "cwd": workingDirectory,
                ])
            }

            emit([
                "type": "assistant",
                "message": [
                    "role": "assistant",
                    "content": [["type": "text", "text": "pong"]],
                ],
                "session_id": sessionID,
            ])
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        func disconnect(status: Int32) {
            terminationHandler?(status)
        }

        func completeTurn(result: String) {
            emit([
                "type": "result",
                "subtype": "success",
                "result": result,
                "session_id": sessionID,
            ])
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }

        private static func explicitSessionID(in remoteCommand: String) -> String? {
            for marker in ["--resume", "--session-id"] {
                guard let range = remoteCommand.range(of: marker) else {
                    continue
                }
                let suffix = remoteCommand[range.upperBound...]
                if let match = suffix.range(of: "[0-9A-Za-z-]{8,}", options: .regularExpression) {
                    return String(suffix[match])
                }
            }
            return nil
        }

        private static func runtimeIdentifier(in remoteCommand: String) -> String? {
            remoteCommand.range(of: "nexus-[0-9a-f-]+-runtime-[0-9]+", options: .regularExpression).map {
                String(remoteCommand[$0])
            }
        }

        private static func workingDirectory(in remoteCommand: String) -> String {
            if let addDirRange = remoteCommand.range(of: "--add-dir") {
                let suffix = remoteCommand[addDirRange.upperBound...]
                if let quotedMatch = suffix.range(of: "\"[^\"]+\"", options: .regularExpression) {
                    return String(suffix[quotedMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            return "/srv/api"
        }
    }
#endif
