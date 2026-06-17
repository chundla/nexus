#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct IBMBobSessionRuntimeTests {
        @Test func launchesBobOnDemandWithStructuredFlagsAndReturnsToReadyAfterCompletion() throws {
            let launchRecorder = IBMBobLaunchRecorder()
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { executable, arguments, workingDirectory in
                    launchRecorder.record(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    return SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"status","text":"Bob turn started"}"#,
                            #"{"type":"message","text":"Hello from Bob"}"#,
                            #"{"type":"command","command":"npm test"}"#,
                            #"{"type":"diff","text":"diff --git a/file b/file"}"#,
                            #"{"type":"completion","text":"Bob turn complete"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("ship it")
            let screen = runtime.sessionScreen(for: session)

            #expect(launchRecorder.launches.count == 1)
            #expect(launchRecorder.launches.first?.executable == "/tmp/fake-bob")
            #expect(launchRecorder.launches.first?.workingDirectory == "/tmp/workspace")
            #expect(
                launchRecorder.launches.first?.arguments == [
                    "-o", "stream-json",
                    "--chat-mode", "advanced",
                    "--hide-intermediary-output",
                    "--approval-mode", "yolo",
                    "ship it",
                ])
            #expect(launchRecorder.launches.first?.arguments.contains("--trust") == false)
            #expect(launchRecorder.launches.first?.arguments.contains("--accept-license") == false)
            #expect(launchRecorder.launches.first?.arguments.contains("--instance-id") == false)
            #expect(launchRecorder.launches.first?.arguments.contains("--team-id") == false)
            #expect(launchRecorder.launches.first?.arguments.contains("--include-directories") == false)
            #expect(runtime.state == .ready)
            #expect(screen.primarySurface == .structuredActivityFeed)
            #expect(
                screen.activityItems.map(\.kind) == [
                    .status, .message, .status, .message, .command, .diff, .completion,
                ])
            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: ship it",
                    "Bob turn started",
                    "Hello from Bob",
                    "npm test",
                    "diff --git a/file b/file",
                    "Bob turn complete",
                ])
        }

        @Test func sessionScreenIncludesLiveBobSlashCommandsFromWorkspaceFiles() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("IBMBobSessionRuntimeTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let commandsDirectory = rootURL.appendingPathComponent(".bob/commands", isDirectory: true)
            try FileManager.default.createDirectory(at: commandsDirectory, withIntermediateDirectories: true)
            try """
            ---
            description: Create a new API endpoint
            argument-hint: <endpoint-name> <http-method>
            ---
            Create a new API endpoint called $1 that handles $2 requests.
            """.write(
                to: commandsDirectory.appendingPathComponent("api-endpoint.md"), atomically: true, encoding: .utf8)
            try """
            customModes:
              - slug: shell-debug
                name: Shell Debugger
                whenToUse: Use for debugging shell scripts and environment issues.
            """.write(to: rootURL.appendingPathComponent(".bob/custom_modes.yaml"), atomically: true, encoding: .utf8)

            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: rootURL.path,
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(stdoutLines: [], terminationStatus: 0)
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            #expect(
                runtime.sessionScreen(for: session).slashCommands == [
                    SessionSlashCommand(
                        name: "api-endpoint",
                        displayName: "api-endpoint <endpoint-name> <http-method>",
                        insertionText: "api-endpoint ",
                        description: "Create a new API endpoint",
                        source: .prompt,
                        location: .project,
                        path: commandsDirectory.appendingPathComponent("api-endpoint.md").resolvingSymlinksInPath().path
                    ),
                    SessionSlashCommand(
                        name: "shell-debug",
                        description: "Use for debugging shell scripts and environment issues.",
                        source: .builtIn,
                        location: .project,
                        path: rootURL.appendingPathComponent(".bob/custom_modes.yaml").resolvingSymlinksInPath().path
                    ),
                ])
        }

        @Test func retainsOnlyBoundedLiveHistoryAcrossPersistedBobResume() throws {
            let reply = String(repeating: "bob-tail-", count: 40)
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"message","text":"\#(reply)","session_id":"bob-bounded-history"}"#,
                            #"{"type":"completion","text":"Done"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            for turn in 0..<700 {
                try runtime.sendInput("prompt-\(turn)")
            }

            let linkage = try #require(runtime.sessionRecordAdapterMetadata?.ibmBobSessionLinkage)
            let resumedRuntime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                sessionLinkage: linkage,
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(stdoutLines: [], terminationStatus: 0)
                }
            )
            let screen = resumedRuntime.sessionScreen(for: session)

            #expect(screen.activityItems.count <= StructuredSessionLiveHistoryRetention.maxRetainedActivityItems)
            #expect(screen.transcript.count <= StructuredSessionLiveHistoryRetention.maxTranscriptCharacters)
            #expect(screen.transcript.contains("> prompt-699"))
            #expect(screen.transcript.contains("> prompt-0") == false)
        }

        @Test func secondPromptStartsFreshBobTurnOnSameReadyRuntime() throws {
            let launchRecorder = IBMBobLaunchRecorder()
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { executable, arguments, workingDirectory in
                    launchRecorder.record(
                        executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                    let reply = launchRecorder.launches.count == 1 ? "First turn" : "Second turn"
                    return SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"message","text":"\#(reply)"}"#,
                            #"{"type":"completion","text":"Done"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("first prompt")
            try runtime.sendInput("second prompt")
            let screen = runtime.sessionScreen(for: session)

            #expect(launchRecorder.launches.map(\.arguments.last) == ["first prompt", "second prompt"])
            #expect(runtime.state == .ready)
            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: first prompt",
                    "First turn",
                    "Done",
                    "You: second prompt",
                    "Second turn",
                    "Done",
                ])
        }

        @Test func ignoresBobUserRoleMessagesSoOnlyAssistantRepliesAppearAsBobOutput() throws {
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"status","text":"Bob turn started"}"#,
                            #"{"type":"message","role":"user","text":"hey"}"#,
                            #"{"type":"message","role":"assistant","text":"I am IBM Bob"}"#,
                            #"{"type":"completion","text":"Done"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hey")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: hey",
                    "Bob turn started",
                    "I am IBM Bob",
                    "Done",
                ])
        }

        @Test func readsAssistantTextFromNestedBobMessagePayloadAfterUserEchoIsFiltered() throws {
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"status","text":"Bob turn started"}"#,
                            #"{"type":"message","role":"user","text":"Hey who are you"}"#,
                            #"{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"I am IBM Bob"}]}}"#,
                            #"{"type":"completion","text":"Done"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("Hey who are you")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: Hey who are you",
                    "Bob turn started",
                    "I am IBM Bob",
                    "Done",
                ])
        }

        @Test func readsAssistantReplyFromSuccessfulAttemptCompletionToolResult() throws {
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"init","session_id":"bob-session-1"}"#,
                            #"{"type":"message","role":"user","content":"Hey who are you"}"#,
                            #"{"type":"tool_use","tool_name":"attempt_completion","tool_id":"tool-1","parameters":{"result":"I am Bob."}}"#,
                            #"{"type":"tool_result","tool_id":"tool-1","status":"success","output":"I am Bob."}"#,
                            #"{"type":"result","status":"success"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("Hey who are you")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: Hey who are you",
                    "attempt_completion: I am Bob.",
                    "I am Bob.",
                ])
        }

        @Test func surfacesBobToolUseWhenOnlyToolMetadataIsAvailable() throws {
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"tool_use","tool_name":"subagent","tool_id":"tool-1","parameters":{"agent":"reviewer","task":"Summarize the latest diff"}}"#,
                            #"{"type":"tool_result","tool_id":"tool-1","status":"success","output":"Watch the retry path."}"#,
                            #"{"type":"result","status":"success"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("delegate")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: delegate",
                    "subagent: reviewer: Summarize the latest diff",
                    "Watch the retry path.",
                ])
        }

        @Test func surfacesBobToolResultsFromNestedDeltaContentBlocks() throws {
            let runtime = try IBMBobSessionRuntime(
                executable: "/tmp/fake-bob",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
                transportFactory: { _, _, _ in
                    SynchronousIBMBobTransport(
                        stdoutLines: [
                            #"{"type":"tool_use","tool_name":"subagent","tool_id":"tool-1","parameters":{"agent":"reviewer","task":"Summarize the latest diff"}}"#,
                            #"{"type":"tool_result","tool_id":"tool-1","status":"success","content":[{"type":"text_delta","delta":"Watch the retry path."}]}"#,
                            #"{"type":"result","status":"success"}"#,
                        ],
                        terminationStatus: 0
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("delegate")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "IBM Bob Session ready. Send a prompt to start IBM Bob.",
                    "You: delegate",
                    "subagent: reviewer: Summarize the latest diff",
                    "Watch the retry path.",
                ])
        }
    }

    private final class IBMBobLaunchRecorder: @unchecked Sendable {
        struct Launch {
            let executable: String
            let arguments: [String]
            let workingDirectory: String?
        }

        private let lock = NSLock()
        private(set) var launches: [Launch] = []

        func record(executable: String, arguments: [String], workingDirectory: String?) {
            lock.lock()
            launches.append(Launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
            lock.unlock()
        }
    }

    private final class SynchronousIBMBobTransport: IBMBobTransporting, @unchecked Sendable {
        private let stdoutLines: [String]
        private let stderrLines: [String]
        private let terminationStatus: Int32
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(stdoutLines: [String], stderrLines: [String] = [], terminationStatus: Int32) {
            self.stdoutLines = stdoutLines
            self.stderrLines = stderrLines
            self.terminationStatus = terminationStatus
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
            for line in stdoutLines {
                stdoutLineHandler?(line)
            }
            for line in stderrLines {
                stderrLineHandler?(line)
            }
            terminationHandler?(terminationStatus)
        }

        func terminate() throws {}
    }
#endif
