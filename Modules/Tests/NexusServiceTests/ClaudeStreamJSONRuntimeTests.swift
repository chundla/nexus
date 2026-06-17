#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct ClaudeStreamJSONRuntimeTests {
        @Test func launchesWithStreamJSONFlagsAndPreAssignedSessionID() throws {
            let transport = ScriptedClaudeTransport()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                approvalHookBridge: FakeApprovalHookBridge(),
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            #expect(transport.launchedExecutable == "/tmp/fake-claude")
            #expect(transport.launchedWorkingDirectory == "/tmp/workspace")
            #expect(
                transport.launchedArguments == [
                    "-p",
                    "--input-format", "stream-json",
                    "--output-format", "stream-json",
                    "--include-partial-messages",
                    "--verbose",
                    "--permission-mode", "default",
                    "--add-dir", "/tmp/workspace",
                    "--session-id", "generated-session-id",
                    "--settings", "FAKE_SETTINGS_JSON",
                ])
            #expect(runtime.state == .ready)
        }

        @Test func resumesWithStoredClaudeSessionIDInsteadOfGeneratingANewOne() throws {
            let transport = ScriptedClaudeTransport()
            _ = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: ClaudeSessionLinkage(claudeSessionID: "stored-session-id"),
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: {
                    Issue.record("should not generate a fresh id when one is stored"); return "x"
                },
                approvalHookBridge: FakeApprovalHookBridge(),
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            #expect(transport.launchedArguments.contains("--resume"))
            #expect(transport.launchedArguments.contains("--session-id") == false)
            let resumeIndex = try #require(transport.launchedArguments.firstIndex(of: "--resume"))
            #expect(transport.launchedArguments[resumeIndex + 1] == "stored-session-id")
        }

        @Test func registersAPendingApprovalRequestWhenTheHookBridgeReceivesAPreToolUseCall() throws {
            let bridge = FakeApprovalHookBridge()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                approvalHookBridge: bridge,
                transportFactory: { executable, arguments, workingDirectory in
                    let transport = ScriptedClaudeTransport()
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            bridge.simulateRequest(
                ClaudeApprovalHookRequest(id: "hook-1", toolName: "Write", toolInputPreview: "/tmp/workspace/file.txt"))

            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.approvalRequests.count == 1)
            #expect(screen.approvalRequests.first?.state == .pending)
            #expect(screen.approvalRequests.first?.title == "Write")
            #expect(screen.activityItems.last?.kind == .approvalRequest)
            #expect(screen.activityItems.last?.text == "Approval Request: Write")
        }

        @Test func approvingAnApprovalRequestResolvesTheHookBridgeWithAnAllowDecision() throws {
            let bridge = FakeApprovalHookBridge()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                approvalHookBridge: bridge,
                transportFactory: { executable, arguments, workingDirectory in
                    let transport = ScriptedClaudeTransport()
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            bridge.simulateRequest(
                ClaudeApprovalHookRequest(id: "hook-1", toolName: "Write", toolInputPreview: "/tmp/workspace/file.txt"))
            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
            let pendingApprovalRequestID = try #require(runtime.sessionScreen(for: session).approvalRequests.first?.id)

            try runtime.respondToApprovalRequest(pendingApprovalRequestID, decision: .approve)

            #expect(bridge.resolvedDecisions.map(\.requestID) == ["hook-1"])
            #expect(bridge.resolvedDecisions.map(\.decision) == [.allow])
            let screen = runtime.sessionScreen(for: session)
            #expect(screen.approvalRequests.first?.state == .approved)
            #expect(screen.activityItems.last?.kind == .approvalDecision)
            #expect(screen.activityItems.last?.text == "Approved: Write")
        }

        @Test func denyingAnApprovalRequestResolvesTheHookBridgeWithADenyDecision() throws {
            let bridge = FakeApprovalHookBridge()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                approvalHookBridge: bridge,
                transportFactory: { executable, arguments, workingDirectory in
                    let transport = ScriptedClaudeTransport()
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            bridge.simulateRequest(
                ClaudeApprovalHookRequest(id: "hook-1", toolName: "Bash", toolInputPreview: "rm -rf /tmp/workspace"))
            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
            let pendingApprovalRequestID = try #require(runtime.sessionScreen(for: session).approvalRequests.first?.id)

            try runtime.respondToApprovalRequest(pendingApprovalRequestID, decision: .deny)

            #expect(bridge.resolvedDecisions.map(\.decision) == [.deny])
            let screen = runtime.sessionScreen(for: session)
            #expect(screen.approvalRequests.first?.state == .denied)
            #expect(screen.activityItems.last?.text == "Denied: Bash")
        }

        @Test func respondingToAnUnknownApprovalRequestIDThrows() throws {
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                approvalHookBridge: FakeApprovalHookBridge(),
                transportFactory: { executable, arguments, workingDirectory in
                    let transport = ScriptedClaudeTransport()
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            #expect(throws: Error.self) {
                try runtime.respondToApprovalRequest(UUID(), decision: .approve)
            }
        }

        @Test func projectsAssistantTextAndToolUseOntoStructuredActivityFeed() throws {
            let transport = ScriptedClaudeTransport()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            try runtime.sendInput("ping")
            transport.emitStdout(
                #"{"type":"system","subtype":"init","session_id":"generated-session-id","cwd":"/tmp/workspace"}"#)
            transport.emitStdout(
                #"""
                {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Read","input":{"file_path":"/tmp/workspace/README.md"}}]},"session_id":"generated-session-id"}
                """#)
            transport.emitStdout(
                #"""
                {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"1\thello","is_error":false}]},"session_id":"generated-session-id"}
                """#)
            transport.emitStdout(
                #"""
                {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"pong"}]},"session_id":"generated-session-id"}
                """#)
            transport.emitStdout(
                #"{"type":"result","subtype":"success","result":"pong","session_id":"generated-session-id"}"#)

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .claude,
                isDefault: true,
                state: .ready
            )
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.primarySurface == .structuredActivityFeed)
            #expect(
                screen.activityItems.map(\.kind) == [
                    .status, .message, .status, .command, .message, .message, .completion,
                ])
            #expect(
                screen.activityItems.map(\.text) == [
                    "Claude Session ready. Send a prompt to start Claude.",
                    "You: ping",
                    "Claude Session started.",
                    "Read: /tmp/workspace/README.md",
                    "Read: 1\thello",
                    "Claude: pong",
                    "pong",
                ])
            #expect(screen.isAgentTurnInProgress == false)
            #expect(
                runtime.sessionRecordAdapterMetadata?.claudeSessionLinkage
                    == ClaudeSessionLinkage(
                        claudeSessionID: "generated-session-id"))
        }

        @Test func straySynchronousAutoDenyToolResultSurfacesAsErrorNotSilentlyDropped() throws {
            let transport = ScriptedClaudeTransport()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            try runtime.sendInput("write a file")
            transport.emitStdout(
                #"""
                {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_2","content":"Claude requested permissions to write to /tmp/workspace/file, but you haven't granted it yet.","is_error":true}]},"session_id":"generated-session-id"}
                """#)

            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.activityItems.last?.kind == .error)
            #expect(
                screen.activityItems.last?.text
                    == "Claude requested permissions to write to /tmp/workspace/file, but you haven't granted it yet.")
        }

        @Test func nonZeroTerminationSurfacesStderrAsErrorActivityItem() throws {
            let transport = ScriptedClaudeTransport()
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .failed,
                sessionIDGenerator: { "generated-session-id" },
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            transport.emitStderr("claude: fatal: out of memory")
            transport.terminate(status: 1)

            #expect(runtime.state == .failed)
            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
            #expect(runtime.sessionScreen(for: session).activityItems.last?.text == "claude: fatal: out of memory")
        }

        @Test func stopInvokesStopHandlerWithoutSurfacingTransportTerminationAsAnError() throws {
            let transport = ScriptedClaudeTransport()
            transport.terminationStatusOnTerminate = 15
            var stopCalls = 0
            let runtime = try ClaudeStreamJSONRuntime(
                executable: "/tmp/fake-claude",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: nil,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." },
                unexpectedTerminationState: .interrupted,
                unexpectedTerminationMessageBuilder: { _ in "should stay hidden" },
                stopHandler: { stopCalls += 1 },
                sessionIDGenerator: { "generated-session-id" },
                transportFactory: { executable, arguments, workingDirectory in
                    transport.configure(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return transport
                }
            )

            try runtime.stop()

            #expect(stopCalls == 1)
            #expect(runtime.state == .exited)
            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
            #expect(
                runtime.sessionScreen(for: session).activityItems.map(\.text) == [
                    "Claude Session ready. Send a prompt to start Claude."
                ])
        }
    }

    private final class ScriptedClaudeTransport: ClaudeStreamJSONTransporting, @unchecked Sendable {
        private(set) var launchedExecutable: String?
        private(set) var launchedArguments: [String] = []
        private(set) var launchedWorkingDirectory: String?
        private(set) var sentLines: [String] = []
        var terminationStatusOnTerminate: Int32 = 0
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        func configure(executable: String, arguments: [String], workingDirectory: String?) {
            launchedExecutable = executable
            launchedArguments = arguments
            launchedWorkingDirectory = workingDirectory
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

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)
        }

        func terminate() throws {
            terminate(status: terminationStatusOnTerminate)
        }

        func terminate(status: Int32) {
            terminationHandler?(status)
        }

        func emitStdout(_ line: String) {
            stdoutLineHandler?(line)
        }

        func emitStderr(_ line: String) {
            stderrLineHandler?(line)
        }
    }

    private final class FakeApprovalHookBridge: ClaudeApprovalHookBridging, @unchecked Sendable {
        let settingsJSON = "FAKE_SETTINGS_JSON"
        private(set) var resolvedDecisions:
            [(requestID: String, decision: ClaudeApprovalHookDecision, reason: String)] =
                []
        private var handler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?

        func setRequestHandler(_ handler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?) {
            self.handler = handler
        }

        func start() throws {}

        func resolve(requestID: String, decision: ClaudeApprovalHookDecision, reason: String) throws {
            resolvedDecisions.append((requestID, decision, reason))
        }

        func stop() {}

        func simulateRequest(_ request: ClaudeApprovalHookRequest) {
            handler?(request)
        }
    }
#endif
