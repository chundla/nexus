#if os(macOS)
    import Foundation
    import NexusDomain

    protocol RemoteClaudeApprovalHookHosting: AnyObject {
        func prepare(host: NexusDomain.Host, runtimeIdentifier: String) throws -> RemoteClaudeApprovalHookPaths
        func startEventMonitor(
            host: NexusDomain.Host,
            paths: RemoteClaudeApprovalHookPaths,
            lineHandler: @escaping @Sendable (String) -> Void
        ) throws
        func pendingRequestIDs(host: NexusDomain.Host, paths: RemoteClaudeApprovalHookPaths) throws -> [String]
        func fetchRequestData(host: NexusDomain.Host, paths: RemoteClaudeApprovalHookPaths, requestID: String) throws
            -> Data
        func writeResponseData(
            _ data: Data,
            host: NexusDomain.Host,
            paths: RemoteClaudeApprovalHookPaths,
            requestID: String
        ) throws
        func stopEventMonitor()
    }

    struct RemoteClaudeApprovalHookPaths: Sendable, Equatable {
        let approvalsRoot: String
        let requestsDirectory: String
        let responsesDirectory: String
        let eventsLogPath: String
        let hookScriptPath: String
    }

    final class RemoteClaudeApprovalHookBridge: ClaudeApprovalHookBridging, @unchecked Sendable {
        private static let requestEventPrefix = "NEXUS_CLAUDE_APPROVAL_REQUEST:"

        private let host: NexusDomain.Host
        private let runtimeIdentifier: String
        private let hookHost: any RemoteClaudeApprovalHookHosting
        private let lock = NSLock()
        private var requestHandler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?
        private var deliveredRequestIDs: Set<String> = []
        private var preparedPaths: RemoteClaudeApprovalHookPaths?
        private var isStopped = false

        var settingsJSON: String {
            lock.lock()
            let hookScriptPath = preparedPaths?.hookScriptPath
            lock.unlock()

            guard let hookScriptPath else {
                return "{}"
            }

            let payload: [String: Any] = [
                "hooks": [
                    "PreToolUse": [
                        ["hooks": [["type": "command", "command": hookScriptPath]]]
                    ]
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8)
            else {
                return "{}"
            }
            return json
        }

        init(
            host: NexusDomain.Host,
            runtimeIdentifier: String,
            hookHost: (any RemoteClaudeApprovalHookHosting)? = nil
        ) {
            self.host = host
            self.runtimeIdentifier = runtimeIdentifier
            self.hookHost = hookHost ?? ProcessRemoteClaudeApprovalHookHost()
        }

        func setRequestHandler(_ handler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?) {
            lock.lock()
            requestHandler = handler
            lock.unlock()
        }

        func start() throws {
            let paths = try hookHost.prepare(host: host, runtimeIdentifier: runtimeIdentifier)
            lock.lock()
            preparedPaths = paths
            isStopped = false
            lock.unlock()

            try hookHost.startEventMonitor(host: host, paths: paths) { [weak self] line in
                self?.handleEventLine(line)
            }

            for requestID in try hookHost.pendingRequestIDs(host: host, paths: paths) {
                handleRequestID(requestID)
            }
        }

        func resolve(requestID: String, decision: ClaudeApprovalHookDecision, reason: String) throws {
            let payload: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision.rawValue,
                    "permissionDecisionReason": reason,
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)

            lock.lock()
            let paths = preparedPaths
            lock.unlock()
            guard let paths else {
                throw ClaudeApprovalHookBridgeError.requestNotOpen
            }

            try hookHost.writeResponseData(data, host: host, paths: paths, requestID: requestID)
        }

        func stop() {
            lock.lock()
            isStopped = true
            preparedPaths = nil
            deliveredRequestIDs.removeAll()
            requestHandler = nil
            lock.unlock()
            hookHost.stopEventMonitor()
        }

        deinit {
            stop()
        }

        private func handleEventLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(Self.requestEventPrefix) else {
                return
            }
            let requestID = String(trimmed.dropFirst(Self.requestEventPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard requestID.isEmpty == false else {
                return
            }
            handleRequestID(requestID)
        }

        private func handleRequestID(_ requestID: String) {
            let handler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?
            let paths: RemoteClaudeApprovalHookPaths?
            lock.lock()
            guard isStopped == false, deliveredRequestIDs.insert(requestID).inserted else {
                lock.unlock()
                return
            }
            handler = requestHandler
            paths = preparedPaths
            lock.unlock()

            guard let handler, let paths,
                let data = try? hookHost.fetchRequestData(host: host, paths: paths, requestID: requestID),
                let request = ClaudeApprovalHookRequest.parse(requestID: requestID, data: data)
            else {
                return
            }
            handler(request)
        }
    }

    final class ProcessRemoteClaudeApprovalHookHost: RemoteClaudeApprovalHookHosting, @unchecked Sendable {
        private let lock = NSLock()
        private var monitorProcess: Process?
        private var monitorHandle: FileHandle?
        private var monitorBuffer = Data()
        private var monitorLineHandler: (@Sendable (String) -> Void)?

        func prepare(host: NexusDomain.Host, runtimeIdentifier: String) throws -> RemoteClaudeApprovalHookPaths {
            let homeDirectory = try runSSH(host: host, remoteCommand: "printf %s \"$HOME\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let paths = resolvedPaths(homeDirectory: homeDirectory, runtimeIdentifier: runtimeIdentifier)

            _ = try runSSH(
                host: host,
                remoteCommand: [
                    "mkdir -p \(shellQuoted(paths.approvalsRoot)) \(shellQuoted(paths.requestsDirectory)) \(shellQuoted(paths.responsesDirectory))",
                    "touch \(shellQuoted(paths.eventsLogPath))",
                ].joined(separator: "; ")
            )

            let script = hookScript(paths: paths)
            _ = try runSSH(
                host: host,
                remoteCommand: [
                    "mkdir -p \(shellQuoted(paths.approvalsRoot))",
                    "cat > \(shellQuoted(paths.hookScriptPath))",
                    "chmod 700 \(shellQuoted(paths.hookScriptPath))",
                    "touch \(shellQuoted(paths.eventsLogPath))",
                ].joined(separator: "; "),
                stdin: script.data(using: .utf8)
            )

            return paths
        }

        func startEventMonitor(
            host: NexusDomain.Host,
            paths: RemoteClaudeApprovalHookPaths,
            lineHandler: @escaping @Sendable (String) -> Void
        ) throws {
            stopEventMonitor()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshArguments(
                host: host,
                remoteCommand: [
                    "mkdir -p \(shellQuoted(paths.approvalsRoot)) \(shellQuoted(paths.requestsDirectory)) \(shellQuoted(paths.responsesDirectory))",
                    "touch \(shellQuoted(paths.eventsLogPath))",
                    "exec tail -n 0 -F \(shellQuoted(paths.eventsLogPath))",
                ].joined(separator: "; ")
            )
            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()

            try process.run()

            let handle = stdoutPipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard data.isEmpty == false else {
                    fileHandle.readabilityHandler = nil
                    return
                }
                self?.consumeMonitorData(data)
            }

            lock.lock()
            monitorProcess = process
            monitorHandle = handle
            monitorLineHandler = lineHandler
            monitorBuffer = Data()
            lock.unlock()
        }

        func pendingRequestIDs(host: NexusDomain.Host, paths: RemoteClaudeApprovalHookPaths) throws -> [String] {
            let output = try runSSH(
                host: host,
                remoteCommand: [
                    "for request_path in \(shellQuoted(paths.requestsDirectory))/*.json; do",
                    "  [ -e \"$request_path\" ] || exit 0",
                    "  request_file=$(basename \"$request_path\")",
                    "  request_id=${request_file%.json}",
                    "  response_path=\(shellQuoted(paths.responsesDirectory))/\"$request_file\"",
                    "  [ -e \"$response_path\" ] && continue",
                    "  printf '%s\\n' \"$request_id\"",
                    "done",
                ].joined(separator: " ")
            )
            return
                output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { $0.isEmpty == false }
        }

        func fetchRequestData(host: NexusDomain.Host, paths: RemoteClaudeApprovalHookPaths, requestID: String) throws
            -> Data
        {
            try runSSHData(
                host: host,
                remoteCommand: "cat \(shellQuoted(paths.requestsDirectory))/\(shellQuoted(requestID)).json"
            )
        }

        func writeResponseData(
            _ data: Data,
            host: NexusDomain.Host,
            paths: RemoteClaudeApprovalHookPaths,
            requestID: String
        ) throws {
            _ = try runSSHData(
                host: host,
                remoteCommand: [
                    "mkdir -p \(shellQuoted(paths.responsesDirectory))",
                    "cat > \(shellQuoted(paths.responsesDirectory))/\(shellQuoted(requestID)).json",
                ].joined(separator: "; "),
                stdin: data
            )
        }

        func stopEventMonitor() {
            lock.lock()
            let process = monitorProcess
            let handle = monitorHandle
            monitorProcess = nil
            monitorHandle = nil
            monitorBuffer = Data()
            monitorLineHandler = nil
            lock.unlock()

            handle?.readabilityHandler = nil
            if process?.isRunning == true {
                process?.terminate()
            }
        }

        private func resolvedPaths(homeDirectory: String, runtimeIdentifier: String) -> RemoteClaudeApprovalHookPaths {
            let approvalsRoot =
                "\(homeDirectory)/.nexus/remote-protocol/\(runtimeIdentifier)/claude-approvals"
            return RemoteClaudeApprovalHookPaths(
                approvalsRoot: approvalsRoot,
                requestsDirectory: "\(approvalsRoot)/requests",
                responsesDirectory: "\(approvalsRoot)/responses",
                eventsLogPath: "\(approvalsRoot)/events.log",
                hookScriptPath: "\(approvalsRoot)/pre-tool-use-hook.sh"
            )
        }

        private func hookScript(paths: RemoteClaudeApprovalHookPaths) -> String {
            [
                "#!/bin/sh",
                "set -eu",
                "requests_dir=\(shellQuoted(paths.requestsDirectory))",
                "responses_dir=\(shellQuoted(paths.responsesDirectory))",
                "events_log=\(shellQuoted(paths.eventsLogPath))",
                "mkdir -p \"$requests_dir\" \"$responses_dir\"",
                "touch \"$events_log\"",
                "request_path=$(mktemp \"$requests_dir/request.XXXXXX.json\")",
                "request_id=$(basename \"$request_path\" .json)",
                "response_path=\"$responses_dir/$request_id.json\"",
                "cat > \"$request_path\"",
                "printf 'NEXUS_CLAUDE_APPROVAL_REQUEST:%s\\n' \"$request_id\" >> \"$events_log\"",
                "while [ ! -f \"$response_path\" ]; do sleep 0.1; done",
                "cat \"$response_path\"",
                "rm -f \"$request_path\" \"$response_path\"",
            ].joined(separator: "\n") + "\n"
        }

        private func consumeMonitorData(_ data: Data) {
            var lines: [String] = []
            let handler: (@Sendable (String) -> Void)?

            lock.lock()
            monitorBuffer.append(data)
            while let newlineIndex = monitorBuffer.firstIndex(of: 0x0A) {
                let lineData = monitorBuffer.prefix(upTo: newlineIndex)
                monitorBuffer.removeSubrange(...newlineIndex)
                if let line = String(bytes: lineData, encoding: .utf8)?.replacingOccurrences(of: "\r", with: "") {
                    lines.append(line)
                }
            }
            handler = monitorLineHandler
            lock.unlock()

            for line in lines where line.isEmpty == false {
                handler?(line)
            }
        }

        private func runSSH(host: NexusDomain.Host, remoteCommand: String, stdin: Data? = nil) throws -> String {
            let data = try runSSHData(host: host, remoteCommand: remoteCommand, stdin: stdin)
            return String(bytes: data, encoding: .utf8) ?? ""
        }

        private func runSSHData(host: NexusDomain.Host, remoteCommand: String, stdin: Data? = nil) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshArguments(host: host, remoteCommand: remoteCommand)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if stdin != nil {
                process.standardInput = Pipe()
            }

            try process.run()

            if let stdin, let input = process.standardInput as? Pipe {
                input.fileHandleForWriting.write(stdin)
                try? input.fileHandleForWriting.close()
            }

            process.waitUntilExit()
            let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr =
                (String(bytes: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "RemoteClaudeApprovalHookHost",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: stderr.isEmpty
                            ? "Remote Claude approval bridge command failed."
                            : stderr
                    ]
                )
            }
            return stdout
        }

        private func sshArguments(host: NexusDomain.Host, remoteCommand: String) -> [String] {
            var arguments = [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
            ]
            if let port = host.port {
                arguments += ["-p", String(port)]
            }
            arguments += [host.sshTarget, "/bin/sh", "-lc", remoteCommand]
            return arguments
        }

        private func shellQuoted(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
    }

    extension ClaudeApprovalHookRequest {
        static func parse(requestID: String, data: Data) -> ClaudeApprovalHookRequest? {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let toolName = (object["tool_name"] as? String) ?? "Tool"
            return ClaudeApprovalHookRequest(
                id: requestID,
                toolName: toolName,
                toolInputPreview: toolInputPreview(object["tool_input"])
            )
        }

        fileprivate static func toolInputPreview(_ input: Any?) -> String? {
            guard let input = input as? [String: Any], input.isEmpty == false else {
                return nil
            }
            if let path = input["file_path"] as? String {
                return path
            }
            if let command = input["command"] as? String {
                return command
            }
            guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
                let json = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return json.count > 120 ? String(json.prefix(120)) + "…" : json
        }
    }
#endif
