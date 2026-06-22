#if os(macOS)
    import Darwin
    import Foundation
    @testable import NexusService
    import Testing

    struct LocalShellEnvironmentResolverTests {
        @Test func localShellEnvironmentResolverMergesShellEnvironmentOverBaseEnvironment() {
            let resolver = LocalShellEnvironmentResolver(
                baseEnvironment: ["PATH": "/service/bin", "HOME": "/Users/tester", "UNCHANGED": "value"],
                commandRunner: TestCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "/usr/bin/env -0"]): .success(
                        stdout: "PATH=/shell/bin\0PI_CONFIG_DIR=/tmp/pi-config\0EMPTY=\0"
                    )
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )

            let environment = resolver.resolvedEnvironment()

            #expect(environment?["PATH"] == "/shell/bin")
            #expect(environment?["PI_CONFIG_DIR"] == "/tmp/pi-config")
            #expect(environment?["HOME"] == "/Users/tester")
            #expect(environment?["UNCHANGED"] == "value")
            #expect(environment?["EMPTY"] == "")
        }

        @Test func localShellEnvironmentResolverReusesCachedResultWithinTTL() {
            let runner = CountingCommandRunner(
                result: .success(stdout: "PATH=/shell/bin\0")
            )
            let cache = ResolvedEnvironmentCache(ttl: 300, currentDate: { Date(timeIntervalSince1970: 0) })
            let resolver = LocalShellEnvironmentResolver(
                baseEnvironment: [:],
                commandRunner: runner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                cache: cache
            )

            _ = resolver.resolvedEnvironment()
            _ = resolver.resolvedEnvironment()
            _ = resolver.resolvedEnvironment()

            #expect(runner.invocationCount == 1)
        }

        @Test func localShellEnvironmentResolverRefreshesAfterTTLExpires() {
            let runner = CountingCommandRunner(
                result: .success(stdout: "PATH=/shell/bin\0")
            )
            var now = Date(timeIntervalSince1970: 0)
            let cache = ResolvedEnvironmentCache(ttl: 10, currentDate: { now })
            let resolver = LocalShellEnvironmentResolver(
                baseEnvironment: [:],
                commandRunner: runner,
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                cache: cache
            )

            _ = resolver.resolvedEnvironment()
            now = now.addingTimeInterval(11)
            _ = resolver.resolvedEnvironment()

            #expect(runner.invocationCount == 2)
        }

        @Test func processPiRPCTransportUsesProvidedEnvironmentForShebangInterpreterResolution() async throws {
            let fixture = try makeShebangFixture()
            let transport = try ProcessPiRPCTransport(
                executable: fixture.providerScript,
                arguments: [],
                workingDirectory: nil,
                environment: fixture.environment
            )
            let recorder = StdoutTransportRecorder<Int32>()
            transport.setStdoutLineHandler(recorder.record(line:))
            transport.setTerminationHandler(recorder.record(status:))

            try transport.start()
            try await waitForTransportOutput(recorder)

            #expect(recorder.stdoutLines == ["from-shell"])
            #expect(recorder.status == 0)
        }

        @Test func processCodexAppServerTransportUsesProvidedEnvironmentForShebangInterpreterResolution() async throws {
            let fixture = try makeShebangFixture()
            let transport = try ProcessCodexAppServerTransport(
                executable: fixture.providerScript,
                arguments: [],
                workingDirectory: nil,
                environment: fixture.environment
            )
            let recorder = StdoutTransportRecorder<CodexAppServerTermination>()
            transport.setStdoutLineHandler(recorder.record(line:))
            transport.setTerminationHandler(recorder.record(status:))

            try transport.start()
            try await waitForTransportOutput(recorder)

            #expect(recorder.stdoutLines == ["from-shell"])
            #expect(recorder.status?.status == 0)
        }

        @Test func processIBMBobTransportUsesProvidedEnvironmentForShebangInterpreterResolution() async throws {
            let fixture = try makeShebangFixture()
            let transport = try ProcessIBMBobTransport(
                executable: fixture.providerScript,
                arguments: [],
                workingDirectory: nil,
                environment: fixture.environment
            )
            let recorder = StdoutTransportRecorder<Int32>()
            transport.setStdoutLineHandler(recorder.record(line:))
            transport.setTerminationHandler(recorder.record(status:))

            try transport.start()
            try await waitForTransportOutput(recorder)

            #expect(recorder.stdoutLines == ["from-shell"])
            #expect(recorder.status == 0)
        }
    }

    private struct TestCommandRunner: ProviderCommandRunning {
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
                throw NSError(
                    domain: "TestCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class CountingCommandRunner: ProviderCommandRunning, @unchecked Sendable {
        enum StubbedResult {
            case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
        }

        private let lock = NSLock()
        private let result: StubbedResult
        private var count = 0

        init(result: StubbedResult) {
            self.result = result
        }

        var invocationCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            lock.lock()
            count += 1
            lock.unlock()

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private struct ShebangFixture {
        let providerScript: String
        let environment: [String: String]
    }

    private func makeShebangFixture() throws -> ShebangFixture {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShellEnvironmentResolverTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let binDirectory = tempRoot.appendingPathComponent("bin", isDirectory: true)
        let scriptDirectory = tempRoot.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)

        let interpreterPath = binDirectory.appendingPathComponent("env-printer", isDirectory: false)
        try "#!/bin/sh\nprintf '%s\\n' \"$NEXUS_TEST_ENV\"\n".write(
            to: interpreterPath, atomically: true, encoding: .utf8)
        #expect(chmod(interpreterPath.path(percentEncoded: false), 0o755) == 0)

        let providerScriptPath = scriptDirectory.appendingPathComponent("provider", isDirectory: false)
        try "#!/usr/bin/env env-printer\n".write(to: providerScriptPath, atomically: true, encoding: .utf8)
        #expect(chmod(providerScriptPath.path(percentEncoded: false), 0o755) == 0)

        return ShebangFixture(
            providerScript: providerScriptPath.path(percentEncoded: false),
            environment: [
                "PATH": binDirectory.path(percentEncoded: false),
                "NEXUS_TEST_ENV": "from-shell",
            ]
        )
    }

    private final class StdoutTransportRecorder<Status>: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var stdoutLines: [String] = []
        private(set) var status: Status?

        func record(line: String) {
            lock.lock()
            stdoutLines.append(line)
            lock.unlock()
        }

        func record(status: Status) {
            lock.lock()
            self.status = status
            lock.unlock()
        }

        func snapshot() -> (stdoutLines: [String], status: Status?) {
            lock.lock()
            defer { lock.unlock() }
            return (stdoutLines, status)
        }
    }

    private func waitForTransportOutput<Status>(
        _ recorder: StdoutTransportRecorder<Status>,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let snapshot = recorder.snapshot()
            if snapshot.status != nil, snapshot.stdoutLines.isEmpty == false {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        throw NSError(
            domain: "LocalShellEnvironmentResolverTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for transport output."])
    }
#endif
