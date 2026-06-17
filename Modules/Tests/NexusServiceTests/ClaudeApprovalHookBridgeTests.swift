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
#endif
