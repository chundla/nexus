#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct RemoteClaudeApprovalHookBridgeTests {
        @Test func startUsesPreparedRemoteHookScriptAndSurfacesPendingAndStreamedRequests() throws {
            let hoster = FakeRemoteClaudeApprovalHookHost()
            hoster.pendingRequestIDs = ["request.0001"]
            hoster.requestDataByID = [
                "request.0001": Data(
                    #"{"tool_name":"Write","tool_input":{"file_path":"/srv/api/README.md"}}"#.utf8),
                "request.0002": Data(
                    #"{"tool_name":"Bash","tool_input":{"command":"rm -rf /srv/api/tmp"}}"#.utf8),
            ]
            let bridge = RemoteClaudeApprovalHookBridge(
                host: NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222),
                runtimeIdentifier: "nexus-runtime-1",
                hookHost: hoster
            )

            let requests = LockedValue<[ClaudeApprovalHookRequest]>([])
            bridge.setRequestHandler { request in
                requests.withLock { $0.append(request) }
            }

            try bridge.start()
            hoster.emitEvent("NEXUS_CLAUDE_APPROVAL_REQUEST:request.0002")

            let received = requests.withLock { $0 }
            #expect(hoster.startEventMonitorCalls == 1)
            #expect(received.map(\.id) == ["request.0001", "request.0002"])
            #expect(received.map(\.toolName) == ["Write", "Bash"])
            #expect(received.map(\.toolInputPreview) == ["/srv/api/README.md", "rm -rf /srv/api/tmp"])

            let data = try #require(bridge.settingsJSON.data(using: .utf8))
            let settings = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let hooks = try #require(settings["hooks"] as? [String: Any])
            let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
            let command = try #require(
                (preToolUse.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
            #expect(command == hoster.paths.hookScriptPath)
        }

        @Test func resolveWritesDecisionPayloadBackToTheRemoteHost() throws {
            let hoster = FakeRemoteClaudeApprovalHookHost()
            let bridge = RemoteClaudeApprovalHookBridge(
                host: NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: nil),
                runtimeIdentifier: "nexus-runtime-1",
                hookHost: hoster
            )

            try bridge.start()
            try bridge.resolve(requestID: "request.0001", decision: .deny, reason: "Controller denied this tool call.")

            let responseData = try #require(hoster.responseDataByID["request.0001"])
            let object = try #require(JSONSerialization.jsonObject(with: responseData) as? [String: Any])
            let output = try #require(object["hookSpecificOutput"] as? [String: Any])
            #expect(output["hookEventName"] as? String == "PreToolUse")
            #expect(output["permissionDecision"] as? String == "deny")
            #expect(output["permissionDecisionReason"] as? String == "Controller denied this tool call.")
        }
    }

    private final class FakeRemoteClaudeApprovalHookHost: RemoteClaudeApprovalHookHosting, @unchecked Sendable {
        let paths = RemoteClaudeApprovalHookPaths(
            approvalsRoot: "/home/tester/.nexus/remote-protocol/nexus-runtime-1/claude-approvals",
            requestsDirectory: "/home/tester/.nexus/remote-protocol/nexus-runtime-1/claude-approvals/requests",
            responsesDirectory: "/home/tester/.nexus/remote-protocol/nexus-runtime-1/claude-approvals/responses",
            eventsLogPath: "/home/tester/.nexus/remote-protocol/nexus-runtime-1/claude-approvals/events.log",
            hookScriptPath: "/home/tester/.nexus/remote-protocol/nexus-runtime-1/claude-approvals/pre-tool-use-hook.sh"
        )
        var pendingRequestIDs: [String] = []
        var requestDataByID: [String: Data] = [:]
        var responseDataByID: [String: Data] = [:]
        var startEventMonitorCalls = 0
        private var lineHandler: (@Sendable (String) -> Void)?

        func prepare(host: NexusDomain.Host, runtimeIdentifier: String) throws -> RemoteClaudeApprovalHookPaths {
            paths
        }

        func startEventMonitor(
            host: NexusDomain.Host,
            paths: RemoteClaudeApprovalHookPaths,
            lineHandler: @escaping @Sendable (String) -> Void
        ) throws {
            startEventMonitorCalls += 1
            self.lineHandler = lineHandler
        }

        func pendingRequestIDs(host: NexusDomain.Host, paths: RemoteClaudeApprovalHookPaths) throws -> [String] {
            pendingRequestIDs
        }

        func fetchRequestData(host: NexusDomain.Host, paths: RemoteClaudeApprovalHookPaths, requestID: String) throws
            -> Data
        {
            try #require(requestDataByID[requestID])
        }

        func writeResponseData(
            _ data: Data,
            host: NexusDomain.Host,
            paths: RemoteClaudeApprovalHookPaths,
            requestID: String
        ) throws {
            responseDataByID[requestID] = data
        }

        func stopEventMonitor() {
            lineHandler = nil
        }

        func emitEvent(_ line: String) {
            lineHandler?(line)
        }
    }

    private final class LockedValue<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func withLock<T>(_ body: (inout Value) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }
#endif
