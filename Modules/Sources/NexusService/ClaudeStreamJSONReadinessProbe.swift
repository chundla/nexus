#if os(macOS)
    import Foundation
    import NexusDomain

    struct ClaudeStreamJSONReadinessProbe: ClaudeStreamJSONReadinessProbing, @unchecked Sendable {
        typealias TransportFactory = ClaudeStreamJSONRuntime.TransportFactory

        private let transportFactory: TransportFactory
        private let timeoutNanoseconds: UInt64

        init(
            transportFactory: @escaping TransportFactory = { executable, arguments, workingDirectory in
                ProcessClaudeStreamJSONTransport(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory
                )
            },
            timeoutNanoseconds: UInt64 = 5_000_000_000
        ) {
            self.transportFactory = transportFactory
            self.timeoutNanoseconds = timeoutNanoseconds
        }

        func probe(executable: String, workingDirectory: String) async throws {
            let transport = try transportFactory(
                executable,
                Self.arguments(workingDirectory: workingDirectory),
                workingDirectory
            )

            let waiter = AsyncResultWaiter<Void>()
            let state = ClaudeStreamJSONReadinessProbeState(expectedWorkingDirectory: workingDirectory)

            transport.setStdoutLineHandler { line in
                state.handleStdout(line, waiter: waiter)
            }
            transport.setStderrLineHandler { line in
                state.record(stderrLine: line)
            }
            transport.setTerminationHandler { status in
                state.handleTermination(status: status, waiter: waiter)
            }

            try transport.start()
            try transport.sendLine(Self.userMessageLine())

            defer {
                try? transport.terminate()
            }

            do {
                try await waiter.wait(
                    timeoutNanoseconds: timeoutNanoseconds,
                    timeoutError: {
                        state.timeoutError()
                    }
                )
            } catch {
                throw state.error ?? error
            }

            if let error = state.error {
                throw error
            }
        }

        fileprivate static func arguments(workingDirectory: String) -> [String] {
            [
                "-p",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--verbose",
                "--permission-mode", "default",
                "--add-dir", workingDirectory,
                "--no-session-persistence",
            ]
        }

        fileprivate static func userMessageLine() throws -> String {
            let payload: [String: Any] = [
                "type": "user",
                "message": [
                    "role": "user",
                    "content": [["type": "text", "text": "ping"]],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let line = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: "ClaudeStreamJSONReadinessProbe",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode Claude stream-json readiness probe input."]
                )
            }
            return line
        }
    }

    struct SSHRemoteClaudeStreamJSONReadinessProbe: RemoteClaudeStreamJSONReadinessProbing, @unchecked Sendable {
        typealias TransportFactory = ClaudeStreamJSONRuntime.TransportFactory

        private let transportFactory: TransportFactory
        private let timeoutNanoseconds: UInt64

        init(
            transportFactory: @escaping TransportFactory = { executable, arguments, workingDirectory in
                ProcessClaudeStreamJSONTransport(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory
                )
            },
            timeoutNanoseconds: UInt64 = 5_000_000_000
        ) {
            self.transportFactory = transportFactory
            self.timeoutNanoseconds = timeoutNanoseconds
        }

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws {
            let transport = try transportFactory(
                "/usr/bin/ssh",
                sshArguments(host: host, executable: executable, workingDirectory: workingDirectory),
                nil
            )

            let waiter = AsyncResultWaiter<Void>()
            let state = ClaudeStreamJSONReadinessProbeState(expectedWorkingDirectory: workingDirectory)

            transport.setStdoutLineHandler { line in
                state.handleStdout(line, waiter: waiter)
            }
            transport.setStderrLineHandler { line in
                state.record(stderrLine: line)
            }
            transport.setTerminationHandler { status in
                state.handleTermination(status: status, waiter: waiter)
            }

            try transport.start()
            try transport.sendLine(ClaudeStreamJSONReadinessProbe.userMessageLine())

            defer {
                try? transport.terminate()
            }

            do {
                try await waiter.wait(
                    timeoutNanoseconds: timeoutNanoseconds,
                    timeoutError: {
                        state.timeoutError()
                    }
                )
            } catch {
                throw state.error ?? error
            }

            if let error = state.error {
                throw error
            }
        }

        private func sshArguments(host: NexusDomain.Host, executable: String, workingDirectory: String) -> [String] {
            var arguments = [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
            ]
            if let port = host.port {
                arguments += ["-p", String(port)]
            }
            arguments += [host.sshTarget, remoteCommand(executable: executable, workingDirectory: workingDirectory)]
            return arguments
        }

        private func remoteCommand(executable: String, workingDirectory: String) -> String {
            let arguments = ClaudeStreamJSONReadinessProbe.arguments(workingDirectory: workingDirectory)
            return
                "cd \(shellQuoted(workingDirectory)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec \(shellQuoted(executable)) \(renderedRemoteArguments(arguments))"
        }

        private func renderedRemoteArguments(_ arguments: [String]) -> String {
            arguments.enumerated().map { index, argument in
                index == 9 ? shellQuoted(argument) : argument
            }.joined(separator: " ")
        }

        private func shellQuoted(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
    }

    private final class ClaudeStreamJSONReadinessProbeState: @unchecked Sendable {
        private let lock = NSLock()
        private let expectedWorkingDirectory: String
        private var resolvedError: Error?
        private var initObserved = false
        private var stderrLines: [String] = []

        init(expectedWorkingDirectory: String) {
            self.expectedWorkingDirectory = expectedWorkingDirectory
        }

        var error: Error? {
            lock.lock()
            defer { lock.unlock() }
            return resolvedError
        }

        func record(stderrLine: String) {
            let trimmed = stderrLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return
            }

            lock.lock()
            stderrLines.append(trimmed)
            lock.unlock()
        }

        func handleStdout(_ line: String, waiter: AsyncResultWaiter<Void>) {
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "system",
                object["subtype"] as? String == "init"
            else {
                return
            }

            let sessionID = (object["session_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard sessionID.isEmpty == false else {
                let error = NSError(
                    domain: "ClaudeStreamJSONReadinessProbe",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Claude stream-json readiness probe returned system/init without a session_id."
                    ]
                )
                record(error: error)
                waiter.fail(error)
                return
            }

            let cwd = (object["cwd"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard cwd.isEmpty == false else {
                let error = NSError(
                    domain: "ClaudeStreamJSONReadinessProbe",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Claude stream-json readiness probe returned system/init without a cwd."
                    ]
                )
                record(error: error)
                waiter.fail(error)
                return
            }

            guard cwd == expectedWorkingDirectory else {
                let error = NSError(
                    domain: "ClaudeStreamJSONReadinessProbe",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Claude stream-json readiness probe returned system/init for cwd \(cwd) instead of \(expectedWorkingDirectory)."
                    ]
                )
                record(error: error)
                waiter.fail(error)
                return
            }

            lock.lock()
            initObserved = true
            lock.unlock()
            waiter.succeed()
        }

        func handleTermination(status: Int32, waiter: AsyncResultWaiter<Void>) {
            guard shouldFailForTermination() else {
                return
            }

            let detail = terminationDetail(status: status)
            let error = NSError(
                domain: "ClaudeStreamJSONReadinessProbe",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
            record(error: error)
            waiter.fail(error)
        }

        func timeoutError() -> Error {
            let error = NSError(
                domain: "ClaudeStreamJSONReadinessProbe",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Claude stream-json readiness probe timed out before system/init arrived."
                ]
            )
            record(error: error)
            return error
        }

        private func record(error: Error) {
            lock.lock()
            if resolvedError == nil {
                resolvedError = error
            }
            lock.unlock()
        }

        private func shouldFailForTermination() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return initObserved == false && resolvedError == nil
        }

        private func terminationDetail(status: Int32) -> String {
            lock.lock()
            defer { lock.unlock() }

            let stderr = stderrLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.isEmpty == false {
                return stderr
            }

            return status == 0
                ? "Claude stream-json readiness probe exited before system/init arrived."
                : "Claude stream-json readiness probe exited with status \(status) before system/init arrived."
        }
    }
#endif
