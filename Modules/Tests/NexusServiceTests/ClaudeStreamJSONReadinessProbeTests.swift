#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct ClaudeStreamJSONReadinessProbeTests {
        @Test func localProbeLaunchesWithProbeArgumentsAndSendsMinimalUserMessage() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            let task = Task {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace")
            }

            try await transport.waitForSentLine()
            transport.emitStdout(
                #"{"type":"system","subtype":"init","session_id":"probe-session-1","cwd":"/tmp/workspace"}"#)

            try await task.value

            #expect(transport.launchedExecutable == "/tmp/fake-claude")
            #expect(transport.launchedWorkingDirectory == "/tmp/workspace")
            #expect(
                transport.launchedArguments == [
                    "-p",
                    "--input-format", "stream-json",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--permission-mode", "default",
                    "--add-dir", "/tmp/workspace",
                    "--no-session-persistence",
                ])
            #expect(transport.sentLines.count == 1)
            #expect(transport.sentLines.first?.contains("\"type\":\"user\"") == true)
            #expect(transport.didTerminate)
        }

        @Test func localProbeSucceedsWhenWorkingDirectoryHasTrailingSlashButReportedCWDDoesNot() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport }
            )

            let task = Task {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace/")
            }

            try await transport.waitForSentLine()
            transport.emitStdout(
                #"{"type":"system","subtype":"init","session_id":"probe-session-1","cwd":"/tmp/workspace"}"#)

            try await task.value
        }

        @Test func localProbeFailsWhenCWDDoesNotMatchBeyondTrailingSlash() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport }
            )

            let task = Task {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace/")
            }

            try await transport.waitForSentLine()
            transport.emitStdout(
                #"{"type":"system","subtype":"init","session_id":"probe-session-1","cwd":"/tmp/other"}"#)

            await #expect(throws: Error.self) {
                try await task.value
            }
        }

        @Test func localProbeFailsWhenProcessExitsBeforeInit() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport }
            )

            let task = Task {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace")
            }

            try await transport.waitForSentLine()
            transport.terminate(status: 1)

            await #expect(throws: Error.self) {
                try await task.value
            }
        }

        @Test func localProbeFailsWhenInitLineIsMissingSessionID() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport }
            )

            let task = Task {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace")
            }

            try await transport.waitForSentLine()
            transport.emitStdout(#"{"type":"system","subtype":"init","session_id":"","cwd":"/tmp/workspace"}"#)

            await #expect(throws: Error.self) {
                try await task.value
            }
        }

        @Test func localProbeFailsWhenInitLineIsMissingCWD() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport }
            )

            let task = Task {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace")
            }

            try await transport.waitForSentLine()
            transport.emitStdout(#"{"type":"system","subtype":"init","session_id":"probe-session-1"}"#)

            await #expect(throws: Error.self) {
                try await task.value
            }
        }

        @Test func localProbeFailsAfterTimeout() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = ClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport },
                timeoutNanoseconds: 50_000_000
            )

            await #expect(throws: Error.self) {
                try await probe.probe(executable: "/tmp/fake-claude", workingDirectory: "/tmp/workspace")
            }
        }

        @Test func remoteProbeWrapsCommandOverSSHWithoutTmuxOrPTY() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = SSHRemoteClaudeStreamJSONReadinessProbe(
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)

            let task = Task {
                try await probe.probe(
                    host: host, executable: "/home/tester/.local/bin/claude", workingDirectory: "/srv/api")
            }

            try await transport.waitForSentLine()
            transport.emitStdout(#"{"type":"system","subtype":"init","session_id":"probe-session-1","cwd":"/srv/api"}"#)

            try await task.value

            #expect(transport.launchedExecutable == "/usr/bin/ssh")
            #expect(
                transport.launchedArguments?.prefix(6) == [
                    "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p",
                ])
            #expect(transport.launchedArguments?.dropFirst(6).first == "2222")
            #expect(
                transport.launchedArguments?.last
                    == "cd '/srv/api' || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec '/home/tester/.local/bin/claude' -p --input-format stream-json --output-format stream-json --verbose --permission-mode default --add-dir '/srv/api' --no-session-persistence"
            )
            #expect(transport.launchedArguments?.contains("tmux") == false)
            #expect(transport.didTerminate)
        }

        @Test func remoteProbeFailsWhenProcessExitsBeforeInit() async throws {
            let transport = ScriptedClaudeProbeTransport()
            let probe = SSHRemoteClaudeStreamJSONReadinessProbe(
                transportFactory: { _, _, _ in transport }
            )
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")

            let task = Task {
                try await probe.probe(
                    host: host, executable: "/home/tester/.local/bin/claude", workingDirectory: "/srv/api")
            }

            try await transport.waitForSentLine()
            transport.terminate(status: 1)

            await #expect(throws: Error.self) {
                try await task.value
            }
        }
    }

    private final class ScriptedClaudeProbeTransport: ClaudeStreamJSONTransporting, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var launchedExecutable: String?
        private(set) var launchedArguments: [String]?
        private(set) var launchedWorkingDirectory: String?
        private(set) var sentLines: [String] = []
        private(set) var didTerminate = false
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private var sentLineContinuations: [CheckedContinuation<Void, Never>] = []

        func configure(executable: String, arguments: [String], workingDirectory: String?) {
            launchedExecutable = executable
            launchedArguments = arguments
            launchedWorkingDirectory = workingDirectory
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            lock.lock()
            stdoutLineHandler = handler
            lock.unlock()
        }

        func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {}

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            lock.lock()
            terminationHandler = handler
            lock.unlock()
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            lock.lock()
            sentLines.append(line)
            let continuations = sentLineContinuations
            sentLineContinuations = []
            lock.unlock()
            for continuation in continuations {
                continuation.resume()
            }
        }

        func terminate() throws {
            lock.lock()
            didTerminate = true
            lock.unlock()
        }

        func waitForSentLine() async throws {
            if hasSentLine() {
                return
            }

            await withCheckedContinuation { continuation in
                lock.lock()
                if sentLines.isEmpty == false {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sentLineContinuations.append(continuation)
                lock.unlock()
            }
        }

        private func hasSentLine() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return sentLines.isEmpty == false
        }

        func emitStdout(_ line: String) {
            lock.lock()
            let handler = stdoutLineHandler
            lock.unlock()
            handler?(line)
        }

        func terminate(status: Int32) {
            lock.lock()
            let handler = terminationHandler
            lock.unlock()
            handler?(status)
        }
    }
#endif
