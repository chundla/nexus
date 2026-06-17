#if os(macOS)
    import Foundation
    @testable import NexusService
    import Testing

    struct ClaudeApprovalHookBridgeTests {
        @Test func resolvesAnAllowDecisionBackToTheHookCommandOverTheSocket() async throws {
            let bridge = ClaudeApprovalHookBridge()
            try bridge.start()
            defer { bridge.stop() }

            let receivedRequest = SingleValueBox<ClaudeApprovalHookRequest>()
            bridge.setRequestHandler { request in
                receivedRequest.value = request
                try? bridge.resolve(requestID: request.id, decision: .allow, reason: "looks safe")
            }

            let output = try runHookCommand(
                bridge: bridge,
                stdin: #"{"tool_name":"Write","tool_input":{"file_path":"/tmp/workspace/file.txt"}}"#)

            #expect(receivedRequest.value?.toolName == "Write")
            #expect(receivedRequest.value?.toolInputPreview == "/tmp/workspace/file.txt")
            let decoded = try decodeHookOutput(output)
            #expect(decoded["permissionDecision"] as? String == "allow")
            #expect(decoded["permissionDecisionReason"] as? String == "looks safe")
        }

        @Test func resolvesADenyDecisionWithReasonBackToTheHookCommand() async throws {
            let bridge = ClaudeApprovalHookBridge()
            try bridge.start()
            defer { bridge.stop() }

            bridge.setRequestHandler { request in
                try? bridge.resolve(requestID: request.id, decision: .deny, reason: "Controller denied this tool call.")
            }

            let output = try runHookCommand(
                bridge: bridge,
                stdin: #"{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}"#)

            let decoded = try decodeHookOutput(output)
            #expect(decoded["permissionDecision"] as? String == "deny")
            #expect(decoded["permissionDecisionReason"] as? String == "Controller denied this tool call.")
        }

        @Test func acceptsASecondPreToolUseRequestWhileTheFirstIsStillAwaitingADecision() throws {
            let bridge = ClaudeApprovalHookBridge()
            try bridge.start()
            defer { bridge.stop() }

            let pendingRequests = PendingRequestsBox()
            bridge.setRequestHandler { request in
                pendingRequests.append(request)
            }

            let firstOutputBox = SingleValueBox<Data>()
            let secondOutputBox = SingleValueBox<Data>()
            let firstThread = Thread {
                firstOutputBox.value = try? self.runHookCommand(
                    bridge: bridge,
                    stdin: #"{"tool_name":"Write","tool_input":{"file_path":"/tmp/workspace/a.txt"}}"#)
            }
            let secondThread = Thread {
                secondOutputBox.value = try? self.runHookCommand(
                    bridge: bridge,
                    stdin: #"{"tool_name":"Bash","tool_input":{"command":"ls"}}"#)
            }
            firstThread.start()
            secondThread.start()

            let deadline = Date().addingTimeInterval(5)
            while pendingRequests.count() < 2, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }

            let requests = pendingRequests.snapshot()
            #expect(requests.count == 2)
            let writeRequest = try #require(requests.first(where: { $0.toolName == "Write" }))
            let bashRequest = try #require(requests.first(where: { $0.toolName == "Bash" }))

            try bridge.resolve(requestID: writeRequest.id, decision: .allow, reason: "looks safe")
            try bridge.resolve(requestID: bashRequest.id, decision: .deny, reason: "not allowed")

            firstThread.cancel()
            secondThread.cancel()
            while firstOutputBox.value == nil || secondOutputBox.value == nil {
                Thread.sleep(forTimeInterval: 0.02)
            }

            let firstDecoded = try decodeHookOutput(try #require(firstOutputBox.value))
            let secondDecoded = try decodeHookOutput(try #require(secondOutputBox.value))
            #expect(firstDecoded["permissionDecision"] as? String == "allow")
            #expect(secondDecoded["permissionDecision"] as? String == "deny")
        }

        @Test func settingsJSONConfiguresAPreToolUseHookPointingAtTheSocket() throws {
            let bridge = ClaudeApprovalHookBridge()
            try bridge.start()
            defer { bridge.stop() }

            let data = try #require(bridge.settingsJSON.data(using: .utf8))
            let settings = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let hooks = try #require(settings["hooks"] as? [String: Any])
            let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
            let command = try #require(
                (preToolUse.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)

            #expect(command.contains("nc"))
            #expect(command.contains("-U"))
        }

        private func runHookCommand(bridge: ClaudeApprovalHookBridge, stdin: String) throws -> Data {
            let data = try #require(bridge.settingsJSON.data(using: .utf8))
            let settings = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let hooks = try #require(settings["hooks"] as? [String: Any])
            let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
            let command = try #require(
                (preToolUse.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
            let parts = command.split(separator: " ").map(String.init)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: parts[0])
            process.arguments = Array(parts.dropFirst())
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            try process.run()
            stdinPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
            try stdinPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            return stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }

        private func decodeHookOutput(_ data: Data) throws -> [String: Any] {
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try #require(object["hookSpecificOutput"] as? [String: Any])
        }
    }

    private final class SingleValueBox<Value>: @unchecked Sendable {
        var value: Value?
    }

    private final class PendingRequestsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [ClaudeApprovalHookRequest] = []

        func append(_ request: ClaudeApprovalHookRequest) {
            lock.lock()
            requests.append(request)
            lock.unlock()
        }

        func count() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return requests.count
        }

        func snapshot() -> [ClaudeApprovalHookRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }
    }
#endif
