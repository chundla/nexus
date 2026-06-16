#if os(macOS)
    import Foundation
    import NexusDomain
    import NexusIPC
    @testable import NexusService
    import Testing

    struct NexusServicePiSessionStreamTests {
        @Test func localPiDefaultSessionLaunchAndResumePreserveSharedActivity() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let launchCounter = LaunchCounter()
            let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                launchCounter.increment()
                return TestPiRPCTransport()
            })

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStreamStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                            stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                            stdout: "Usage: pi\n"),
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let firstScreen = try service.getSessionScreen(sessionID: firstSession.id)
            let resumedSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

            #expect(firstSession.providerID == .pi)
            #expect(firstSession.isDefault)
            #expect(resumedSession.id == firstSession.id)
            #expect(firstScreen.activityItems.map(\.text) == ["Session stream connected"])
            #expect(firstScreen.activityItems.map(\.kind) == [.status])
            #expect(firstScreen.transcript.isEmpty)
            #expect(launchCounter.value == 1)
        }

        @Test func localPiSessionScreenShowsCurrentModelFromStartupState() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(
                        stateModel: TestPiRPCModel(
                            provider: "anthropic",
                            id: "claude-sonnet-4-20250514",
                            name: "Claude Sonnet 4"
                        ),
                        stateThinkingLevel: "medium"
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: medium)",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .status])
        }

        @Test func localPiSessionScreenIncludesLiveSlashCommandsFromRpc() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                TestPiRPCTransport(
                    slashCommands: [
                        TestPiRPCCommand(
                            name: "review-changes",
                            description: "Summarize the current diff.",
                            source: .prompt,
                            location: .project,
                            path: "/tmp/project/.pi/prompts/review-changes.md"
                        ),
                        TestPiRPCCommand(
                            name: "skill:create-cli",
                            description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                            source: .skill,
                            location: .user,
                            path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md"
                        ),
                    ]
                )
            })

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStreamStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                            stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                            stdout: "Usage: pi\n"),
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let screen = try service.getSessionScreen(sessionID: session.id)
            let slashCommands = try #require(screen.slashCommands)

            #expect(
                slashCommands.contains(
                    SessionSlashCommand(
                        name: "review-changes",
                        description: "Summarize the current diff.",
                        source: .prompt,
                        location: .project,
                        path: "/tmp/project/.pi/prompts/review-changes.md"
                    )))
            #expect(
                slashCommands.contains(
                    SessionSlashCommand(
                        name: "skill:create-cli",
                        description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                        source: .skill,
                        location: .user,
                        path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md"
                    )))
        }

        @Test func localPiRuntimeParsesRpcSlashCommandSourceInfoShape() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(
                        slashCommands: [
                            TestPiRPCCommand(
                                name: "review-changes",
                                description: "Summarize the current diff.",
                                source: .prompt,
                                location: .project,
                                path: "/tmp/project/.pi/prompts/review-changes.md",
                                sourceInfoOnly: true
                            ),
                            TestPiRPCCommand(
                                name: "skill:create-cli",
                                description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                                source: .skill,
                                location: .user,
                                path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md",
                                sourceInfoOnly: true
                            ),
                        ]
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)
            let slashCommands = try #require(screen.slashCommands)

            #expect(
                slashCommands.contains(
                    SessionSlashCommand(
                        name: "review-changes",
                        description: "Summarize the current diff.",
                        source: .prompt,
                        location: .project,
                        path: "/tmp/project/.pi/prompts/review-changes.md"
                    )))
            #expect(
                slashCommands.contains(
                    SessionSlashCommand(
                        name: "skill:create-cli",
                        description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                        source: .skill,
                        location: .user,
                        path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md"
                    )))
        }

        @Test func localPiRuntimeRetainsOnlyBoundedTranscriptTailAcrossManyTurns() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(promptResponseText: String(repeating: "assistant-tail-", count: 4_000))
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            for turn in 0..<5 {
                try runtime.sendInput("prompt-\(turn)")
            }
            let metadata = runtime.sessionRecordAdapterMetadata
            let screen = runtime.sessionScreen(for: session)

            let resumedRuntime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                restoredMetadata: metadata,
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport()
                }
            )
            let resumedScreen = resumedRuntime.sessionScreen(for: session)

            #expect(screen.transcript.count <= StructuredSessionLiveHistoryRetention.maxTranscriptCharacters)
            #expect(screen.transcript.contains("> prompt-4"))
            #expect(screen.transcript.contains("> prompt-0") == false)
            #expect(resumedScreen.transcript.contains("> prompt-4"))
            #expect(resumedScreen.transcript.contains("> prompt-0") == false)
            #expect(resumedScreen.transcript.count <= screen.transcript.count)
        }

        @Test func localPiRuntimePublishesAvailableModelCommandsFromRpc() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(
                        availableModels: [
                            TestPiRPCModel(
                                provider: "anthropic",
                                id: "claude-sonnet-4-20250514",
                                name: "Claude Sonnet 4"
                            ),
                            TestPiRPCModel(
                                provider: "openai",
                                id: "gpt-4o",
                                name: "GPT-4o"
                            ),
                        ]
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.slashCommands == [
                    SessionSlashCommand(
                        name: "model anthropic/claude-sonnet-4-20250514",
                        displayName: "model anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4",
                        insertionText: "model anthropic/claude-sonnet-4-20250514",
                        suggestionQueryPrefix: "model ",
                        description: "Switch to anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4.",
                        source: .builtIn
                    ),
                    SessionSlashCommand(
                        name: "model openai/gpt-4o",
                        displayName: "model openai/gpt-4o — GPT-4o",
                        insertionText: "model openai/gpt-4o",
                        suggestionQueryPrefix: "model ",
                        description: "Switch to openai/gpt-4o — GPT-4o.",
                        source: .builtIn
                    ),
                ])
        }

        @Test func localPiRuntimePublishesThinkingCommandsForCurrentModelState() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(
                        stateModel: TestPiRPCModel(
                            provider: "anthropic",
                            id: "claude-sonnet-4-20250514",
                            name: "Claude Sonnet 4",
                            reasoning: true
                        ),
                        stateThinkingLevel: "medium"
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)
            let commandNames = screen.slashCommands?.map(\.name)

            #expect(
                commandNames == [
                    "thinking off",
                    "thinking minimal",
                    "thinking low",
                    "thinking medium",
                    "thinking high",
                ])
            #expect(commandNames?.contains("thinking xhigh") == false)
        }

        @Test func localPiRuntimeShowsXhighThinkingCommandForCodexMaxModels() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(
                        stateModel: TestPiRPCModel(
                            provider: "openai",
                            id: "gpt-5.1-codex-max",
                            name: "GPT-5.1 Codex Max",
                            reasoning: true
                        ),
                        stateThinkingLevel: "high"
                    )
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)

            #expect(screen.slashCommands?.contains(where: { $0.name == "thinking xhigh" }) == true)
        }

        @Test func localPiRuntimePublishesCompactionAndRetryConvenienceCommands() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in TestPiRPCTransport() }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let commandNames = runtime.sessionScreen(for: session).slashCommands?.map(\.name) ?? []

            #expect(commandNames.contains("cycle-model"))
            #expect(commandNames.contains("cycle-thinking-level"))
            #expect(commandNames.contains("compact"))
            #expect(commandNames.contains("auto-compaction on"))
            #expect(commandNames.contains("auto-compaction off"))
            #expect(commandNames.contains("auto-retry on"))
            #expect(commandNames.contains("auto-retry off"))
            #expect(commandNames.contains("abort-retry"))
        }

        @Test func localPiRuntimeSwitchesModelsViaBuiltInModelCommand() throws {
            let transport = TestPiRPCTransport(
                availableModels: [
                    TestPiRPCModel(
                        provider: "anthropic",
                        id: "claude-sonnet-4-20250514",
                        name: "Claude Sonnet 4"
                    )
                ]
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/model anthropic/claude-sonnet-4-20250514")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"set_model\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/model anthropic/claude-sonnet-4-20250514",
                    "Model switched to anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .status, .status])
            #expect(screen.transcript.isEmpty)
        }

        @Test func localPiRuntimeSwitchesThinkingLevelsViaBuiltInThinkingCommand() throws {
            let transport = TestPiRPCTransport(
                stateModel: TestPiRPCModel(
                    provider: "anthropic",
                    id: "claude-sonnet-4-20250514",
                    name: "Claude Sonnet 4",
                    reasoning: true
                ),
                stateThinkingLevel: "medium"
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/thinking high")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"set_thinking_level\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: medium)",
                    "/thinking high",
                    "Thinking level set to high",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: high)",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .status, .command, .status, .status])
        }

        @Test func localPiRuntimeCyclesModelsViaConvenienceCommand() throws {
            let transport = TestPiRPCTransport(
                stateModel: TestPiRPCModel(
                    provider: "anthropic",
                    id: "claude-sonnet-4-20250514",
                    name: "Claude Sonnet 4"
                ),
                stateThinkingLevel: "medium",
                cycledModel: TestPiRPCModel(
                    provider: "openai",
                    id: "gpt-4o",
                    name: "GPT-4o"
                ),
                cycledThinkingLevel: "high"
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/cycle-model")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"cycle_model\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: medium)",
                    "/cycle-model",
                    "Model cycled to openai/gpt-4o — GPT-4o",
                    "Current Model: openai/gpt-4o — GPT-4o (thinking: high)",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .status, .command, .status, .status])
        }

        @Test func localPiRuntimeCyclesThinkingLevelsViaConvenienceCommand() throws {
            let transport = TestPiRPCTransport(
                stateModel: TestPiRPCModel(
                    provider: "anthropic",
                    id: "claude-sonnet-4-20250514",
                    name: "Claude Sonnet 4",
                    reasoning: true
                ),
                stateThinkingLevel: "medium",
                cycledThinkingLevelResult: "high"
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/cycle-thinking-level")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"cycle_thinking_level\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: medium)",
                    "/cycle-thinking-level",
                    "Thinking level cycled to high",
                    "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: high)",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .status, .command, .status, .status])
        }

        @Test func localPiRuntimeCompactsViaConvenienceCommand() throws {
            let transport = TestPiRPCTransport(
                compactionSummary: "Focus on the latest code changes", compactionTokensBefore: 150000)
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/compact Focus on the latest code changes")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"compact\"")
                        && $0.contains("\"customInstructions\":\"Focus on the latest code changes\"")
                }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/compact Focus on the latest code changes",
                    "Compacted the session context",
                    "Compaction summary: Focus on the latest code changes",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .status, .status])
        }

        @Test func localPiRuntimeUpdatesAutoCompactionAndRetryViaConvenienceCommands() throws {
            let transport = TestPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/auto-compaction off")
            try runtime.sendInput("/auto-retry on")
            try runtime.sendInput("/abort-retry")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"set_auto_compaction\"") && $0.contains("\"enabled\":false")
                }))
            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"set_auto_retry\"") && $0.contains("\"enabled\":true")
                }))
            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"abort_retry\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/auto-compaction off",
                    "Auto-compaction disabled",
                    "/auto-retry on",
                    "Auto-retry enabled",
                    "/abort-retry",
                    "Requested retry cancellation",
                ])
            #expect(
                screen.activityItems.map(\.kind) == [.status, .command, .status, .command, .status, .command, .status])
        }

        @Test func localPiRuntimeSendsMultimodalPromptAndProjectsImageSummary() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let prompt = SessionPrompt(
                text: "What changed in this screenshot?",
                images: [SessionPromptImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")]
            )

            try runtime.sendInput(prompt)
            let screen = runtime.sessionScreen(for: session)
            let payloadLine = try #require(transport.sentLines.first(where: { $0.contains("\"type\":\"prompt\"") }))
            let payloadData = try #require(payloadLine.data(using: .utf8))
            let payload = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
            let images = try #require(payload["images"] as? [[String: Any]])

            #expect(payload["message"] as? String == "What changed in this screenshot?")
            #expect(images.count == 1)
            #expect(images[0]["type"] as? String == "image")
            #expect(images[0]["data"] as? String == "iVBORw==")
            #expect(images[0]["mimeType"] as? String == "image/png")
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: What changed in this screenshot? [1 image]",
                ])
            #expect(screen.activityItems.last?.prompt == prompt)
            #expect(screen.transcript == "> What changed in this screenshot? [1 image]")
        }

        @Test func localPiRuntimeQueuesMultimodalSteeringCommandAndProjectsImageSummary() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let prompt = SessionPrompt(
                text: "/steer Focus on this image instead",
                images: [SessionPromptImage(data: Data([0x47, 0x49, 0x46]), mimeType: "image/gif")]
            )

            try runtime.sendInput(prompt)
            let screen = runtime.sessionScreen(for: session)
            let payloadLine = try #require(transport.sentLines.first(where: { $0.contains("\"type\":\"steer\"") }))
            let payloadData = try #require(payloadLine.data(using: .utf8))
            let payload = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
            let images = try #require(payload["images"] as? [[String: Any]])

            #expect(payload["message"] as? String == "Focus on this image instead")
            #expect(images[0]["data"] as? String == "R0lG")
            #expect(images[0]["mimeType"] as? String == "image/gif")
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Queued steering: Focus on this image instead [1 image]",
                    "Queue updated — steering: Focus on this image instead",
                ])
            #expect(
                screen.activityItems[1].prompt
                    == SessionPrompt(text: "Focus on this image instead", images: prompt.images))
            #expect(screen.transcript == "> Focus on this image instead [1 image]")
        }

        @Test func localPiRuntimeQueuesSteeringCommandAndProjectsQueueUpdates() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/steer Focus on error handling")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"steer\"") && $0.contains("\"message\":\"Focus on error handling\"")
                }))
            #expect(screen.providerEvents.contains(where: { $0.type == "queue_update" && $0.family == .queue }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Queued steering: Focus on error handling",
                    "Queue updated — steering: Focus on error handling",
                ])
            #expect(screen.transcript == "> Focus on error handling")
        }

        @Test func localPiRuntimeQueuesMultimodalFollowUpCommandAndProjectsImageSummary() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let prompt = SessionPrompt(
                text: "/follow-up Also check this screenshot",
                images: [SessionPromptImage(data: Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg")]
            )

            try runtime.sendInput(prompt)
            let screen = runtime.sessionScreen(for: session)
            let payloadLine = try #require(transport.sentLines.first(where: { $0.contains("\"type\":\"follow_up\"") }))
            let payloadData = try #require(payloadLine.data(using: .utf8))
            let payload = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
            let images = try #require(payload["images"] as? [[String: Any]])

            #expect(payload["message"] as? String == "Also check this screenshot")
            #expect(images[0]["data"] as? String == "/9j/")
            #expect(images[0]["mimeType"] as? String == "image/jpeg")
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Queued follow-up: Also check this screenshot [1 image]",
                    "Queue updated — follow-up: Also check this screenshot",
                ])
            #expect(
                screen.activityItems[1].prompt
                    == SessionPrompt(text: "Also check this screenshot", images: prompt.images))
            #expect(screen.transcript == "> Also check this screenshot [1 image]")
        }

        @Test func localPiRuntimeQueuesFollowUpCommandAndProjectsQueueUpdates() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/follow-up After that, summarize the result")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"follow_up\"")
                        && $0.contains("\"message\":\"After that, summarize the result\"")
                }))
            #expect(screen.providerEvents.contains(where: { $0.type == "queue_update" && $0.family == .queue }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "Queued follow-up: After that, summarize the result",
                    "Queue updated — follow-up: After that, summarize the result",
                ])
            #expect(screen.transcript == "> After that, summarize the result")
        }

        @Test func localPiRuntimeQueuesStreamingPromptViaPromptStreamingBehavior() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            try runtime.sendInput("Focus on error handling")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"prompt\"")
                        && $0.contains("\"message\":\"hello\"")
                        && $0.contains("streamingBehavior") == false
                }))
            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"prompt\"")
                        && $0.contains("\"message\":\"Focus on error handling\"")
                        && $0.contains("\"streamingBehavior\":\"steer\"")
                }))
            #expect(screen.providerEvents.contains(where: { $0.type == "queue_update" && $0.family == .queue }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: hello",
                    "Queued steering: Focus on error handling",
                    "Queue updated — steering: Focus on error handling",
                ])
            #expect(screen.transcript == "> hello\n> Focus on error handling")
            #expect(screen.isAgentTurnInProgress)
        }

        @Test func localPiRuntimeUpdatesQueueModesViaCommands() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/steering-mode all")
            try runtime.sendInput("/follow-up-mode all")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"set_steering_mode\"") && $0.contains("\"mode\":\"all\"")
                }))
            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"set_follow_up_mode\"") && $0.contains("\"mode\":\"all\"")
                }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/steering-mode all",
                    "Steering mode set to all",
                    "/follow-up-mode all",
                    "Follow-up mode set to all",
                ])
            #expect(screen.transcript.isEmpty)
        }

        @Test func localPiRuntimePublishesQueueControlCommandsFromCurrentPiState() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in QueueControlPiRPCTransport() }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let commandNames = runtime.sessionScreen(for: session).slashCommands?.map(\.name) ?? []

            #expect(commandNames.contains("steer"))
            #expect(commandNames.contains("follow-up"))
            #expect(commandNames.contains("abort"))
            #expect(commandNames.contains("steering-mode all"))
            #expect(commandNames.contains("steering-mode one-at-a-time"))
            #expect(commandNames.contains("follow-up-mode all"))
            #expect(commandNames.contains("follow-up-mode one-at-a-time"))
        }

        @Test func localPiRuntimeGetsForkMessagesViaBuiltInCommand() throws {
            let transport = TestPiRPCTransport(
                forkMessages: [
                    TestPiRPCForkMessage(entryID: "abc123", text: "First prompt..."),
                    TestPiRPCForkMessage(entryID: "def456", text: "Second prompt..."),
                ]
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/fork-messages")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"get_fork_messages\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/fork-messages",
                    "Fork message abc123: First prompt...",
                    "Fork message def456: Second prompt...",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .status, .status])
        }

        @Test func localPiRuntimePublishesSessionGraphCommands() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in TestPiRPCTransport() }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let commandNames = runtime.sessionScreen(for: session).slashCommands?.map(\.name) ?? []

            #expect(commandNames.contains("fork"))
            #expect(commandNames.contains("clone"))
            #expect(commandNames.contains("fork-messages"))
            #expect(commandNames.contains("session-name"))
        }

        @Test func localPiRuntimePublishesBashExportAndIntrospectionCommands() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in TestPiRPCTransport() }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let commandNames = runtime.sessionScreen(for: session).slashCommands?.map(\.name) ?? []

            #expect(commandNames.contains("bash"))
            #expect(commandNames.contains("abort-bash"))
            #expect(commandNames.contains("export-html"))
            #expect(commandNames.contains("messages"))
            #expect(commandNames.contains("session-stats"))
            #expect(commandNames.contains("last-assistant-text"))
        }

        @Test func localPiRuntimeAbortsActiveRunViaCommand() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            try runtime.sendInput("/abort")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"abort\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: hello",
                    "/abort",
                    "Operation aborted",
                ])
            #expect(screen.transcript == "> hello")
            #expect(screen.isAgentTurnInProgress == false)
        }

        @Test func localPiRuntimeRunsHostBashViaBuiltInCommand() throws {
            let transport = TestPiRPCTransport(
                bashResult: TestPiRPCBashResult(output: "total 48", exitCode: 0)
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/bash ls -la")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"bash\"") && $0.contains("\"command\":\"ls -la\"")
                }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/bash ls -la",
                    "Running bash: ls -la",
                    "bash: total 48",
                    "Pi bash completed with exit code 0 and will be included on the next prompt",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .progress, .message, .status])
            #expect(screen.transcript.isEmpty)
        }

        @Test func localPiRuntimeCancelsHostBashViaBuiltInCommand() throws {
            let transport = AbortableBashPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/bash sleep 10")
            try runtime.sendInput("/abort-bash")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"abort_bash\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/bash sleep 10",
                    "Running bash: sleep 10",
                    "/abort-bash",
                    "Requested Pi bash cancellation",
                    "Bash cancelled",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .progress, .command, .status, .status])
        }

        @Test func localPiRuntimeExportsSessionHtmlViaBuiltInCommand() throws {
            let transport = TestPiRPCTransport(exportedHTMLPath: "/tmp/pi-session.html")
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/export-html /tmp/pi-session.html")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"export_html\"") && $0.contains("pi-session.html")
                }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/export-html /tmp/pi-session.html",
                    "Exported session HTML to /tmp/pi-session.html",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .status])
        }

        @Test func localPiRuntimeListsSessionMessagesViaBuiltInCommand() throws {
            let transport = TestPiRPCTransport(messages: [
                [
                    "role": "user",
                    "content": "Hello Pi",
                ],
                [
                    "role": "assistant",
                    "content": [
                        [
                            "type": "text",
                            "text": "Hi there",
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/messages")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"get_messages\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/messages",
                    "Pi returned 2 messages",
                    "Message 1 — user: Hello Pi",
                    "Message 2 — assistant: Hi there",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .status, .status, .status])
        }

        @Test func localPiRuntimeShowsSessionStatsViaBuiltInCommand() throws {
            let transport = TestPiRPCTransport(sessionStats: [
                "userMessages": 5,
                "assistantMessages": 4,
                "toolCalls": 12,
                "toolResults": 12,
                "totalMessages": 21,
                "cost": 0.45,
                "contextUsage": [
                    "tokens": 60000,
                    "contextWindow": 200000,
                    "percent": 30,
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/session-stats")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"get_session_stats\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/session-stats",
                    "Session stats — user: 5 · assistant: 4 · tool calls: 12 · tool results: 12 · total: 21 · cost: $0.45",
                    "Context usage — 60000 / 200000 tokens (30%)",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .status, .status])
        }

        @Test func localPiRuntimeRequestsSessionStatsOnStartupForStatusBarUsage() throws {
            let transport = TestPiRPCTransport(
                sessionStats: [
                    "contextUsage": [
                        "tokens": 60000,
                        "contextWindow": 200000,
                        "percent": 30,
                    ]
                ],
                stateModel: TestPiRPCModel(
                    provider: "openai",
                    id: "gpt-5.1-codex-max",
                    name: "GPT-5.1 Codex Max"
                )
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"id\":\"nexus-pi-session-stats-auto-")
                        && $0.contains("\"type\":\"get_session_stats\"")
                }))
            #expect(
                screen.providerEvents.contains(where: {
                    $0.command == "get_session_stats" && $0.rawPayload.contains("\"contextWindow\":200000")
                }))
            #expect(
                screen.providerFacts.tokenUsage
                    == StructuredSessionProviderTokenUsage(usedTokens: 60000, totalTokens: 200000, percent: 30))
            #expect(screen.providerFacts.modelIdentifier == "openai/gpt-5.1-codex-max")
            #expect(
                screen.activityItems.allSatisfy {
                    $0.text.contains("Session stats —") == false && $0.text.contains("Context usage —") == false
                })
        }

        @Test func localPiRuntimeTurnEndPrefersLongerStreamedAssistantTextOverShorterTurnEndMessage() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "ABCDEFGHIJ",
                    ],
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "ABC",
                            ]
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let piMessage = try #require(screen.activityItems.last(where: { $0.text.hasPrefix("Pi:") }))

            #expect(piMessage.text == "Pi: ABCDEFGHIJ")
        }

        @Test func localPiRuntimePublishesLiveAssistantDraftProviderFactsDuringStreamingTurns() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "world",
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress)
            #expect(screen.providerFacts.liveAssistantDraftText == "world")
            #expect(screen.providerFacts.lastProviderEventType == "message_update")
        }

        @Test func localPiRuntimeCompactsLargeRetainedProviderEventPayloads() throws {
            let oversizedMarker = String(repeating: "oversized-provider-payload-", count: 512)
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi", "oversized": oversizedMarker],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "world",
                        "oversized": oversizedMarker,
                    ],
                    "oversized": oversizedMarker,
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "role": "assistant",
                        "content": [["type": "text", "text": oversizedMarker]],
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let compactedMessageUpdate = try #require(
                screen.providerEvents.first(where: { $0.type == "message_update" }))
            let compactedTurnEnd = try #require(screen.providerEvents.first(where: { $0.type == "turn_end" }))

            #expect(screen.providerFacts.liveAssistantDraftText == nil)
            #expect(compactedMessageUpdate.rawPayload.contains("\"delta\":\"world\""))
            #expect(compactedMessageUpdate.rawPayload.contains(oversizedMarker) == false)
            #expect(compactedTurnEnd.rawPayload == "{\"type\":\"turn_end\"}")
        }

        @Test func localPiRuntimeCompactsToolExecutionProviderEventPayloads() throws {
            let oversizedMarker = String(repeating: "oversized-tool-update-", count: 2_048)
            let transport = PromptEventPiRPCTransport(promptEvents: [
                [
                    "type": "tool_execution_start",
                    "toolCallId": "tool-1",
                    "toolName": "subagent",
                    "args": [
                        "agent": "reviewer",
                        "task": oversizedMarker,
                    ],
                ],
                [
                    "type": "tool_execution_update",
                    "toolCallId": "tool-1",
                    "partialResult": [
                        "content": [
                            [
                                "type": "text",
                                "text": "Looks good overall.",
                            ]
                        ],
                        "details": [
                            "messages": [
                                [
                                    "role": "assistant",
                                    "content": [
                                        [
                                            "type": "text",
                                            "text": oversizedMarker,
                                        ]
                                    ],
                                ]
                            ]
                        ],
                    ],
                ],
                [
                    "type": "tool_execution_end",
                    "toolCallId": "tool-1",
                    "toolName": "subagent",
                    "result": [
                        "content": [
                            [
                                "type": "text",
                                "text": oversizedMarker,
                            ]
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let startEvent = try #require(screen.providerEvents.first(where: { $0.type == "tool_execution_start" }))
            let updateEvent = try #require(screen.providerEvents.first(where: { $0.type == "tool_execution_update" }))
            let endEvent = try #require(screen.providerEvents.first(where: { $0.type == "tool_execution_end" }))

            #expect(startEvent.rawPayload.contains("\"toolName\":\"subagent\""))
            #expect(startEvent.rawPayload.contains(oversizedMarker) == false)
            #expect(updateEvent.rawPayload.contains("Looks good overall."))
            #expect(updateEvent.rawPayload.contains(oversizedMarker) == false)
            #expect(endEvent.rawPayload.contains("\"toolCallId\":\"tool-1\""))
            #expect(endEvent.rawPayload.contains(oversizedMarker) == false)
        }

        @Test func localPiRuntimeCompactsLegacyPersistedProviderEventsOnRestore() throws {
            let oversizedMarker = String(repeating: "legacy-provider-payload-", count: 512)
            let legacyStatePayload =
                "{\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"data\":{\"sessionId\":\"pi-session-1\",\"model\":{\"provider\":\"openai\",\"id\":\"gpt-5.1-codex-max\",\"name\":\"GPT-5.1 Codex Max\"},\"oversized\":\"\(oversizedMarker)\"}}"
            let legacyStatsPayload =
                "{\"type\":\"response\",\"command\":\"get_session_stats\",\"success\":true,\"data\":{\"contextUsage\":{\"tokens\":60000,\"contextWindow\":200000,\"percent\":30},\"oversized\":\"\(oversizedMarker)\"}}"
            let legacyMessageUpdatePayload =
                "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"world\",\"oversized\":\"\(oversizedMarker)\"},\"oversized\":\"\(oversizedMarker)\"}"
            let restoredMetadata = try #require(
                SessionRecordAdapterMetadata.pi(
                    linkage: PiSessionLinkage(piSessionID: "pi-session-1", sessionFile: "/tmp/pi-session.jsonl"),
                    providerEvents: [
                        SessionProviderEvent(
                            sequence: 0,
                            providerID: .pi,
                            type: "response",
                            family: .response,
                            command: "get_state",
                            rawPayload: legacyStatePayload
                        ),
                        SessionProviderEvent(
                            sequence: 1,
                            providerID: .pi,
                            type: "response",
                            family: .response,
                            command: "get_session_stats",
                            rawPayload: legacyStatsPayload
                        ),
                        SessionProviderEvent(
                            sequence: 2,
                            providerID: .pi,
                            type: "message_update",
                            family: .message,
                            rawPayload: legacyMessageUpdatePayload
                        ),
                    ]
                )
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                restoredMetadata: restoredMetadata,
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in TestPiRPCTransport() }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let screen = runtime.sessionScreen(for: session)

            #expect(screen.providerFacts.modelIdentifier == "openai/gpt-5.1-codex-max")
            #expect(
                screen.providerFacts.tokenUsage
                    == StructuredSessionProviderTokenUsage(usedTokens: 60000, totalTokens: 200000, percent: 30))
            #expect(screen.providerFacts.liveAssistantDraftText == "world")
            #expect(screen.providerEvents.allSatisfy { $0.rawPayload.contains(oversizedMarker) == false })
        }

        @Test func localPiRuntimeShowsLastAssistantTextViaBuiltInCommand() throws {
            let transport = TestPiRPCTransport(lastAssistantText: "Summarized answer")
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("/last-assistant-text")
            let screen = runtime.sessionScreen(for: session)

            #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"get_last_assistant_text\"") }))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "/last-assistant-text",
                    "Last assistant message: Summarized answer",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .command, .message])
        }

        @Test func localPiDefaultSessionRelaunchKeepsPiConversationLinkageAcrossServiceRestart() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = PersistentPiTransportHarness()
            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, arguments, _ in
                    transportHarness.makeTransport(arguments: arguments)
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let firstSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            _ = try service.sendSessionText(sessionID: firstSession.id, text: "alpha")
            let firstTurn = try service.sendSessionInputKey(sessionID: firstSession.id, key: .enter)

            let restartedService = try makeService()
            let relaunchedSession = try restartedService.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .pi)
            _ = try restartedService.sendSessionText(sessionID: relaunchedSession.id, text: "what was my last message?")
            let resumedTurn = try restartedService.sendSessionInputKey(sessionID: relaunchedSession.id, key: .enter)

            #expect(firstTurn.activityItems.suffix(2).map(\.text) == ["You: alpha", "Pi: alpha"])
            #expect(relaunchedSession.id == firstSession.id)
            #expect(resumedTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: alpha"])
        }

        @Test func localPiNewCommandResetsCurrentSessionHistoryAndStartsFreshPiSession() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = PersistentPiTransportHarness()
            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, arguments, _ in
                    transportHarness.makeTransport(arguments: arguments)
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let firstTurn = try service.sendSessionInput(sessionID: session.id, text: "alpha")
            let resetScreen = try service.sendSessionInput(sessionID: session.id, text: "/new")
            let nextTurn = try service.sendSessionInput(sessionID: session.id, text: "what was my last message?")

            #expect(firstTurn.activityItems.suffix(2).map(\.text) == ["You: alpha", "Pi: alpha"])
            #expect(resetScreen.session.id == session.id)
            #expect(resetScreen.activityItems.map(\.text) == ["Session stream connected"])
            #expect(nextTurn.session.id == session.id)
            #expect(nextTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: (none)"])
        }

        @Test func localPiClearCommandResetsCurrentSessionHistoryAndStartsFreshPiSession() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = PersistentPiTransportHarness()
            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, arguments, _ in
                    transportHarness.makeTransport(arguments: arguments)
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            _ = try service.sendSessionInput(sessionID: session.id, text: "alpha")
            let resetScreen = try service.sendSessionInput(sessionID: session.id, text: "/clear")
            let nextTurn = try service.sendSessionInput(sessionID: session.id, text: "what was my last message?")

            #expect(resetScreen.session.id == session.id)
            #expect(resetScreen.activityItems.map(\.text) == ["Session stream connected"])
            #expect(nextTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: (none)"])
        }

        @Test func localPiRestartedSessionShowsInterruptedLostRuntimeCopyAcrossInspectableSurfaces() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                    TestPiRPCTransport()
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let defaultSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let namedSession = try service.createNamedSession(
                workspaceID: workspace.id, providerID: .pi, name: "Review")

            let restartedService = try makeService()
            let overview = try restartedService.getWorkspaceOverview(workspaceID: workspace.id)
            let providerDetail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
            let interruptedDefaultScreen = try restartedService.getSessionScreen(sessionID: defaultSession.id)
            let interruptedNamedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)

            let expectedMessage =
                "Pi Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."

            let piCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))
            let restartedNamedSession = try #require(providerDetail.alternateSessions.first)

            #expect(piCard.defaultSession.state == .interrupted)
            #expect(piCard.defaultSession.summary == expectedMessage)
            #expect(piCard.defaultSession.actionTitle == "Relaunch")
            #expect(providerDetail.defaultSession?.failureMessage == expectedMessage)
            #expect(restartedNamedSession.id == namedSession.id)
            #expect(restartedNamedSession.state == .interrupted)
            #expect(restartedNamedSession.failureMessage == expectedMessage)
            #expect(interruptedDefaultScreen.session.state == .interrupted)
            #expect(interruptedDefaultScreen.transcript == expectedMessage)
            #expect(interruptedDefaultScreen.activityItems.map(\.kind) == [.status, .error])
            #expect(
                interruptedDefaultScreen.activityItems.map(\.text) == ["Session stream connected", expectedMessage])
            #expect(interruptedNamedScreen.session.state == .interrupted)
            #expect(interruptedNamedScreen.activityItems.map(\.kind) == [.status, .error])
            #expect(interruptedNamedScreen.activityItems.map(\.text) == ["Session stream connected", expectedMessage])
        }

        @Test
        func localPiInFlightTurnBecomesInterruptedAfterServiceRestartWhileKeepingPartialAssistantOutputInspectable()
            throws
        {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "Partial reply",
                    ],
                ],
            ])

            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in transport })
                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let partialScreen = try service.sendSessionInput(sessionID: session.id, text: "first")

            let restartedService = try makeService()
            let interruptedSession = try restartedService.getSessionRecord(sessionID: session.id)
            let interruptedScreen = try restartedService.getSessionScreen(sessionID: session.id)

            let expectedFailureMessage = structuredInterruptedSessionFailureMessage(for: .pi)
            let expectedPartialItems: [SessionActivityItem] =
                partialScreen.activityItems + [
                    SessionActivityItem(kind: .message, text: "Pi: Partial reply")
                ]

            #expect(partialScreen.isAgentTurnInProgress)
            #expect(partialScreen.providerFacts.liveAssistantDraftText == "Partial reply")
            #expect(interruptedSession.state == .interrupted)
            #expect(interruptedSession.failureMessage == expectedFailureMessage)
            #expect(interruptedScreen.session.state == .interrupted)
            #expect(interruptedScreen.activityItems.dropLast().map(\.text) == expectedPartialItems.map(\.text))
            #expect(interruptedScreen.activityItems.last?.kind == .error)
            #expect(interruptedScreen.activityItems.last?.text == expectedFailureMessage)
        }

        @Test func localPiNamedSessionCanBeStoppedRelaunchedAndDeletedWhilePreservingConversationLinkage() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = PersistentPiTransportHarness()
            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, arguments, _ in
                    transportHarness.makeTransport(arguments: arguments)
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let namedSession = try service.createNamedSession(
                workspaceID: workspace.id, providerID: .pi, name: "Review")
            _ = try service.sendSessionText(sessionID: namedSession.id, text: "alpha")
            let firstTurn = try service.sendSessionInputKey(sessionID: namedSession.id, key: .enter)
            let stoppedSession = try service.stopSession(sessionID: namedSession.id)
            let stoppedRecord = try service.getSessionRecord(sessionID: namedSession.id)

            let restartedService = try makeService()
            let relaunchedSession = try restartedService.launchOrResumeSession(sessionID: namedSession.id)
            _ = try restartedService.sendSessionText(sessionID: relaunchedSession.id, text: "what was my last message?")
            let resumedTurn = try restartedService.sendSessionInputKey(sessionID: relaunchedSession.id, key: .enter)
            _ = try restartedService.stopSession(sessionID: namedSession.id)
            let deleted = try restartedService.deleteSessionRecord(sessionID: namedSession.id)
            let providerDetail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

            #expect(namedSession.providerID == .pi)
            #expect(namedSession.name == "Review")
            #expect(namedSession.isDefault == false)
            #expect(firstTurn.activityItems.suffix(2).map(\.text) == ["You: alpha", "Pi: alpha"])
            #expect(stoppedSession.id == namedSession.id)
            #expect(stoppedSession.state == .exited)
            #expect(stoppedRecord.id == namedSession.id)
            #expect(stoppedRecord.state == .exited)
            #expect(relaunchedSession.id == namedSession.id)
            #expect(relaunchedSession.state == .ready)
            #expect(resumedTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: alpha"])
            #expect(deleted)
            #expect(providerDetail.alternateSessions.isEmpty)

            do {
                _ = try restartedService.getSessionScreen(sessionID: namedSession.id)
                Issue.record("Expected deleted Pi Session Record to be unavailable")
            } catch {
            }
        }

        @Test func processPiRPCTransportLaunchesSiblingInterpreterForEnvShebangScripts() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

            let interpreterURL = binURL.appendingPathComponent("fake-node-interpreter", isDirectory: false)
            try
                "#!/bin/sh\nIFS= read -r _line\nprintf '%s\\n' '{\"id\":\"nexus-pi-startup-state\",\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"data\":{\"sessionId\":\"pi-session-1\"}}'\n"
                .write(to: interpreterURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: interpreterURL.path)

            let scriptURL = binURL.appendingPathComponent("fake-pi", isDirectory: false)
            try "#!/usr/bin/env fake-node-interpreter\n".write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let transport = try ProcessPiRPCTransport(
                executable: scriptURL.path,
                arguments: ["--mode", "rpc"],
                workingDirectory: rootURL.path(percentEncoded: false)
            )
            let startupSemaphore = DispatchSemaphore(value: 0)
            let response = LockedValue<String?>(nil)
            transport.setStdoutLineHandler { line in
                response.set(line)
                startupSemaphore.signal()
            }

            try transport.start()
            defer { try? transport.terminate() }
            try transport.sendLine("{\"id\":\"nexus-pi-startup-state\",\"type\":\"get_state\"}")

            #expect(startupSemaphore.wait(timeout: .now() + 2) == .success)
            #expect(response.get()?.contains("\"success\":true") == true)
        }

        @Test func localPiRuntimeStreamsPromptAndAssistantMessageIntoSharedSessionActivity() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(promptResponseText: "world")
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendText("hello")
            try runtime.sendInputKey(.enter, applicationCursorMode: false)
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: hello",
                    "Pi: world",
                ])
            #expect(screen.activityItems.map(\.kind) == [.status, .message, .message])
            #expect(screen.transcript == "> hello\nworld")
        }

        @Test func localPiRuntimePreservesRawProviderEventsAlongsideProjectedSharedSessionActivity() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "world",
                    ],
                ],
                [
                    "type": "tool_execution_start",
                    "toolCallId": "tool-1",
                    "toolName": "subagent",
                    "args": ["agent": "reviewer", "task": "Review the latest diff"],
                ],
                [
                    "type": "tool_execution_update",
                    "toolCallId": "tool-1",
                    "partialResult": [
                        "content": [
                            [
                                "type": "text_delta",
                                "delta": "Looks good overall.",
                            ]
                        ]
                    ],
                ],
                [
                    "type": "tool_execution_end",
                    "toolCallId": "tool-1",
                    "toolName": "subagent",
                    "result": [
                        "content": [
                            [
                                "type": "text",
                                "text": "Looks good overall.",
                            ]
                        ]
                    ],
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "world",
                            ]
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.providerEvents.map(\.type) == [
                    "response",
                    "response",
                    "response",
                    "response",
                    "response",
                    "agent_start",
                    "message_update",
                    "tool_execution_start",
                    "tool_execution_update",
                    "tool_execution_end",
                    "turn_end",
                    "response",
                ])
            #expect(
                screen.providerEvents.map(\.command) == [
                    "get_state",
                    "get_commands",
                    "get_available_models",
                    "prompt",
                    "get_commands",
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    "get_commands",
                ])
            #expect(
                screen.providerEvents.map(\.family) == [
                    .response,
                    .response,
                    .response,
                    .response,
                    .response,
                    .agent,
                    .message,
                    .toolExecution,
                    .toolExecution,
                    .toolExecution,
                    .turn,
                    .response,
                ])
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: hello",
                    "subagent reviewer: Review the latest diff",
                    "reviewer: Looks good overall.",
                    "Pi: world",
                ])
            #expect(screen.transcript == "> hello\nworld")
        }

        @Test func localPiRuntimeAttachesFinalOutputLatencyDiagnosticToTurnCompletion() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "world",
                    ],
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "world",
                            ]
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let diagnostic = try #require(screen.finalOutputDiagnostic)

            #expect(diagnostic.trigger == .turnEnd)
            #expect(
                diagnostic.providerEventSequence
                    == screen.providerEvents.last(where: { $0.type == "turn_end" })?.sequence)
            #expect(diagnostic.providerRuntimeLatencyMilliseconds >= 0)
            #expect(diagnostic.serviceObservationLatencyMilliseconds == nil)
            #expect(diagnostic.expectedActivityItemID == screen.activityItems.last?.id)
            #expect(diagnostic.expectedActivityItemText == "Pi: world")
            #expect(diagnostic.expectedThinkingIndicatorVisible == false)
            #expect(diagnostic.serviceObservationAnchorUptimeNanoseconds != nil)
        }

        @Test func localPiRuntimeProjectsAssistantThinkingToolCallsAndCompletionIntoSharedSessionActivity() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "thinking_start",
                        "partial": [
                            "content": [
                                [
                                    "type": "thinking",
                                    "thinking": "",
                                ]
                            ]
                        ],
                    ],
                ],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "thinking_end",
                        "content": "Inspect the auth flow before running tools.",
                        "partial": [
                            "content": [
                                [
                                    "type": "thinking",
                                    "thinking": "Inspect the auth flow before running tools.",
                                ]
                            ]
                        ],
                    ],
                ],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "toolcall_end",
                        "toolCall": [
                            "type": "toolCall",
                            "id": "tool-1",
                            "name": "subagent",
                            "arguments": [
                                "agent": "reviewer",
                                "task": "Inspect the auth flow",
                            ],
                        ],
                    ],
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "Done",
                            ]
                        ]
                    ],
                ],
                [
                    "type": "agent_end",
                    "messages": [],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("inspect auth")
            let screen = runtime.sessionScreen(for: session)
            let providerEvents = screen.providerEvents.filter { $0.family != .response }

            #expect(
                providerEvents.map(\.type) == [
                    "agent_start",
                    "message_update",
                    "message_update",
                    "message_update",
                    "turn_end",
                    "agent_end",
                ])
            #expect(
                providerEvents.map(\.family) == [
                    .agent,
                    .message,
                    .message,
                    .message,
                    .turn,
                    .agent,
                ])
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: inspect auth",
                    "thoughts:",
                    "subagent reviewer: Inspect the auth flow",
                    "Pi: Done",
                ])
            #expect(
                screen.activityItems.map(\.kind) == [
                    .status,
                    .message,
                    .status,
                    .command,
                    .message,
                ])
            #expect(screen.activityItems[2].detailText == "Inspect the auth flow before running tools.")
            #expect(screen.activityItems.contains(where: { $0.kind == .completion }) == false)
            #expect(screen.transcript == "> inspect auth\nDone")
        }

        @Test func localPiRuntimeProjectsAssistantMessageErrorsWithoutReportingFalseCompletion() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "Partial answer",
                    ],
                ],
                [
                    "type": "message_end",
                    "message": [
                        "role": "assistant",
                        "stopReason": "error",
                        "errorMessage": "Provider overloaded",
                        "content": [
                            [
                                "type": "text",
                                "text": "Partial answer",
                            ]
                        ],
                    ],
                ],
                [
                    "type": "agent_end",
                    "messages": [],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("inspect auth")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: inspect auth",
                    "Pi: Partial answer",
                    "Provider overloaded",
                ])
            #expect(screen.isAgentTurnInProgress == false)
            #expect(screen.activityItems.contains(where: { $0.kind == .completion }) == false)
            #expect(screen.transcript == "> inspect auth\nPartial answer")
        }

        @Test func localPiRuntimeKeepsPromptTurnOpenAfterIntermediateTurnEndUntilAgentEnd() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "thinking_end",
                        "content": "Plan step one.",
                    ],
                ],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "toolcall_end",
                        "toolCall": [
                            "type": "toolCall",
                            "id": "tool-1",
                            "name": "read",
                            "arguments": ["path": "A.md"],
                        ],
                    ],
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [["type": "text", "text": "Cycle one done."]]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("review")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress == true)
            #expect(screen.activityItems.contains { $0.text == "Pi: Cycle one done." })
        }

        @Test func localPiRuntimeClearsThinkingWhenTransportTerminatesMidPrompt() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "thinking_end",
                        "content": "Planning.",
                    ],
                ],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "toolcall_end",
                        "toolCall": [
                            "type": "toolCall",
                            "id": "tool-1",
                            "name": "read",
                            "arguments": ["path": "README.md"],
                        ],
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("review")
            #expect(runtime.sessionScreen(for: session).isAgentTurnInProgress == true)
            try transport.terminate()
            let screen = runtime.sessionScreen(for: session)
            #expect(screen.isAgentTurnInProgress == false)
        }

        @Test func localPiRuntimeFinalizesTurnOnAgentEndWhenTurnEndMissing() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "thinking_end",
                        "content": "Plan the review.",
                    ],
                ],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "toolcall_end",
                        "toolCall": [
                            "type": "toolCall",
                            "id": "tool-1",
                            "name": "read",
                            "arguments": ["path": "README.md"],
                        ],
                    ],
                ],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "toolcall_end",
                        "toolCall": [
                            "type": "toolCall",
                            "id": "tool-2",
                            "name": "read",
                            "arguments": ["path": "ARCHITECTURE.md"],
                        ],
                    ],
                ],
                [
                    "type": "agent_end",
                    "messages": [
                        [
                            "role": "assistant",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "## Code review\n\nFindings look good.",
                                ]
                            ],
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("review nexus")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress == false)
            #expect(screen.providerFacts.liveAssistantDraftText == nil)
            #expect(screen.activityItems.map(\.kind).filter { $0 == .command }.count == 2)
            #expect(screen.activityItems.contains { $0.text == "Pi: ## Code review\n\nFindings look good." })
        }

        @Test func localPiRuntimeRecordsToolUseMessageEndBeforeTurnEndWithoutClosingAgentTurn() throws {
            let interimText = "Gathering context before running tools."
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": interimText,
                    ],
                ],
                [
                    "type": "message_end",
                    "message": [
                        "role": "assistant",
                        "stopReason": "toolUse",
                        "content": [
                            [
                                "type": "text",
                                "text": interimText,
                            ]
                        ],
                    ],
                ],
                [
                    "type": "tool_execution_start",
                    "toolCallId": "tool-1",
                    "toolName": "read",
                    "args": ["path": "README.md"],
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "Final answer after tools.",
                            ]
                        ]
                    ],
                ],
                [
                    "type": "agent_end",
                    "messages": [],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("review")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress == false)
            #expect(screen.providerFacts.liveAssistantDraftText == nil)
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: review",
                    "Pi: \(interimText)",
                    "read: README.md",
                    "Pi: Final answer after tools.",
                ])
        }

        @Test func localPiRuntimeRollsBackPromptTurnWhenPromptResponseRejected() throws {
            let transport = ConfigurablePromptPiRPCTransport(
                promptEvents: [],
                promptSuccess: false,
                promptRejectionError: "Pi rejected the prompt."
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress == false)
            #expect(screen.activityItems.contains { $0.text == "Pi rejected the prompt." })
        }

        @Test func localPiRuntimeHandlesMessageUpdateDoneWithoutMessageEnd() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": "Answer from done delta",
                    ],
                ],
                [
                    "type": "message_update",
                    "message": [
                        "role": "assistant",
                        "stopReason": "stop",
                        "content": [["type": "text", "text": "Answer from done delta"]],
                    ],
                    "assistantMessageEvent": [
                        "type": "done",
                        "reason": "stop",
                    ],
                ],
                ["type": "agent_end", "messages": []],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress == false)
            #expect(screen.activityItems.contains { $0.text == "Pi: Answer from done delta" })
        }

        @Test func localPiRuntimeSurfacesUnhandledRpcResponseErrors() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                [
                    "type": "response",
                    "command": "steer",
                    "success": false,
                    "error": "Steering is unavailable right now.",
                ],
                ["type": "agent_end", "messages": []],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.activityItems.contains { $0.kind == .error && $0.text == "Steering is unavailable right now." })
        }

        @Test func localPiRuntimeSurfacesExtensionErrorEvent() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                [
                    "type": "extension_error",
                    "extensionPath": "/tmp/ext.ts",
                    "event": "tool_call",
                    "error": "boom",
                ],
                ["type": "agent_end", "messages": []],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.contains {
                    $0.text == "Extension error (/tmp/ext.ts, tool_call): boom"
                })
        }

        @Test func localPiRuntimeTracksThinkingLevelChangedEvent() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(
                        stateModel: TestPiRPCModel(
                            provider: "anthropic",
                            id: "claude-sonnet-4-20250514",
                            name: "Claude Sonnet 4",
                            reasoning: true
                        ),
                        stateThinkingLevel: "high",
                        promptEvents: [
                            ["type": "thinking_level_changed", "level": "off"],
                            ["type": "agent_end", "messages": []],
                        ]
                    )
                }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(
                screen.activityItems.contains {
                    $0.text == "Current Model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: off)"
                })
        }

        @Test func localPiRuntimeQueuesStreamingPromptWithFollowUpBehaviorForFollowUpSlashPrefix() throws {
            let transport = QueueControlPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            try runtime.sendInput("/follow-up After that, summarize")
            let _ = runtime.sessionScreen(for: session)

            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"prompt\"")
                        && $0.contains("\"message\":\"/follow-up After that, summarize\"")
                        && $0.contains("\"streamingBehavior\":\"followUp\"")
                }))
        }

        @Test func localPiRuntimeReconcilesOpenPromptWhenGetStateReportsNotStreaming() throws {
            let transport = ConfigurablePromptPiRPCTransport(
                promptEvents: [
                    ["type": "agent_start", "agent": "pi"],
                    [
                        "type": "message_update",
                        "assistantMessageEvent": [
                            "type": "text_delta",
                            "delta": "Partial",
                        ],
                    ],
                    [
                        "type": "turn_end",
                        "message": [
                            "role": "assistant",
                            "content": [["type": "text", "text": "Partial"]],
                        ],
                    ],
                ],
                getStateIsStreaming: false
            )
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.isAgentTurnInProgress == false)
        }

        @Test func localPiRuntimeRetainsStopReasonInCompactedMessageEndProviderEvents() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                [
                    "type": "message_end",
                    "message": [
                        "role": "assistant",
                        "stopReason": "toolUse",
                        "content": [["type": "text", "text": "x"]],
                    ],
                ],
                ["type": "agent_end", "messages": []],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let compacted = try #require(screen.providerEvents.first(where: { $0.type == "message_end" }))
            #expect(compacted.rawPayload.contains("\"stopReason\":\"toolUse\""))
        }

        @Test func localPiRuntimeProjectsCompactionAndRetryLifecycleIntoSharedSessionActivity() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "compaction_start", "reason": "manual"],
                [
                    "type": "compaction_end",
                    "reason": "manual",
                    "aborted": false,
                    "willRetry": false,
                    "result": [
                        "summary": "Focus on the latest code changes",
                        "tokensBefore": 128000,
                    ],
                ],
                [
                    "type": "auto_retry_start",
                    "attempt": 2,
                    "maxAttempts": 3,
                    "delayMs": 3000,
                    "errorMessage": "Provider overloaded",
                ],
                [
                    "type": "auto_retry_end",
                    "success": false,
                    "attempt": 3,
                    "finalError": "Provider overloaded",
                ],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "done",
                            ]
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let providerEvents = screen.providerEvents.filter { $0.family != .response }

            #expect(
                providerEvents.map(\.type) == [
                    "compaction_start",
                    "compaction_end",
                    "auto_retry_start",
                    "auto_retry_end",
                    "turn_end",
                ])
            #expect(
                providerEvents.map(\.family) == [
                    .compaction,
                    .compaction,
                    .retry,
                    .retry,
                    .turn,
                ])
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: hello",
                    "Compacting the session context",
                    "Compacted the session context",
                    "Compaction summary: Focus on the latest code changes",
                    "Retrying automatically (attempt 2 of 3) in 3s",
                    "Retry failed after 3 attempts: Provider overloaded",
                    "Pi: done",
                ])
        }

        @Test func localPiRuntimePreservesUnknownAndUnprojectedProviderEventsOpaquely() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "queue_update", "depth": 2],
                ["type": "compaction_checkpoint", "tokens": 128],
                ["type": "retry_scheduled", "delaySeconds": 3],
                ["type": "extension_error", "message": "Widget render failed"],
                ["type": "future_event", "ticket": 7, "nested": ["flag": true]],
                [
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "done",
                            ]
                        ]
                    ],
                ],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("hello")
            let screen = runtime.sessionScreen(for: session)
            let providerEvents = screen.providerEvents.filter { $0.family != .response }

            #expect(
                providerEvents.map(\.type) == [
                    "queue_update",
                    "compaction_checkpoint",
                    "retry_scheduled",
                    "extension_error",
                    "future_event",
                    "turn_end",
                ])
            #expect(
                providerEvents.map(\.family) == [
                    .queue,
                    .compaction,
                    .retry,
                    .extensionError,
                    .unknown,
                    .turn,
                ])
            #expect(
                try #require(providerEvents.first(where: { $0.type == "extension_error" })).rawPayload.contains(
                    "Widget render failed"))
            #expect(
                try #require(providerEvents.first(where: { $0.type == "future_event" })).rawPayload.contains(
                    "\"ticket\":7"))
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: hello",
                    "Pi: done",
                ])
        }

        @Test func localPiRuntimeSurfacesToolExecutionAndKeepsThinkingIndicatorVisibleUntilTurnEnds() throws {
            let transport = StreamingToolPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("delegate")
            let runningScreen = runtime.sessionScreen(for: session)

            #expect(runningScreen.isAgentTurnInProgress)
            #expect(
                runningScreen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: delegate",
                ])

            transport.emitToolExecutionStart(
                toolCallID: "tool-1",
                toolName: "subagent",
                args: ["agent": "reviewer", "task": "Review the latest diff and summarize issues"]
            )
            transport.emitToolExecutionEnd(
                toolCallID: "tool-1",
                toolName: "subagent",
                result: [
                    "content": [
                        [
                            "type": "text",
                            "text": "Looks good overall. Watch the new error path.",
                        ]
                    ]
                ]
            )
            transport.emitTurnEnd(text: "Done")

            let completedScreen = runtime.sessionScreen(for: session)

            #expect(completedScreen.isAgentTurnInProgress == false)
            #expect(
                completedScreen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: delegate",
                    "subagent reviewer: Review the latest diff and summarize issues",
                    "reviewer: Looks good overall. Watch the new error path.",
                    "Pi: Done",
                ])
        }

        @Test func localPiRuntimeSurfacesReadToolOutputFromResultDetailsWhenContentEmpty() throws {
            let transport = PromptEventPiRPCTransport(promptEvents: [
                ["type": "agent_start", "agent": "pi"],
                [
                    "type": "tool_execution_start",
                    "toolCallId": "tool-read",
                    "toolName": "read",
                    "args": ["path": "AGENTS.md"],
                ],
                [
                    "type": "tool_execution_end",
                    "toolCallId": "tool-read",
                    "toolName": "read",
                    "result": [
                        "content": [] as [Any],
                        "details": ["diff": "# AGENTS\n\nBe concise."],
                    ],
                    "isError": false,
                ],
                ["type": "agent_end", "messages": []],
            ])
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            try runtime.sendInput("read agents")
            let screen = runtime.sessionScreen(for: session)
            let command = try #require(screen.activityItems.first(where: { $0.kind == .command }))
            #expect(command.text == "read AGENTS.md")
            #expect(command.detailText == "# AGENTS\n\nBe concise.")
        }

        @Test func localPiRuntimeStreamsToolExecutionUpdatesFromDeltaContentBlocksBeforeTurnEnds() throws {
            let transport = StreamingToolPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("delegate")
            transport.emitToolExecutionStart(
                toolCallID: "tool-1",
                toolName: "subagent",
                args: ["agent": "reviewer", "task": "Review the latest diff and summarize issues"]
            )
            transport.emitToolExecutionUpdate(
                toolCallID: "tool-1",
                partialResult: [
                    "content": [
                        [
                            "type": "text_delta",
                            "delta": "Looks good overall. Watch the new error path.",
                        ]
                    ]
                ]
            )

            let streamedScreen = runtime.sessionScreen(for: session)

            #expect(streamedScreen.isAgentTurnInProgress)
            #expect(
                streamedScreen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: delegate",
                    "subagent reviewer: Review the latest diff and summarize issues",
                ])
            #expect(streamedScreen.activityItems.last?.detailText == "Looks good overall. Watch the new error path.")
        }

        @Test func localPiSessionScreenShowsPendingExtensionDialogInSharedSessionState() throws {
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    ExtensionDialogTestPiRPCTransport()
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendText("deploy")
            try runtime.sendInputKey(.enter, applicationCursorMode: false)
            let screen = runtime.sessionScreen(for: session)

            #expect(screen.activityItems.map(\.kind) == [.status, .message])
            #expect(
                screen.activityItems.map(\.text) == [
                    "Session stream connected",
                    "You: deploy",
                ])
            #expect(screen.approvalRequests.isEmpty)
            #expect(
                screen.extensionUI
                    == SessionExtensionUIState(
                        pendingDialogs: [
                            SessionExtensionUIDialog(
                                id: "11111111-1111-1111-1111-111111111111",
                                kind: .confirm,
                                title: "Deploy to production?",
                                message: "Pi wants to run deploy --prod.",
                                timeoutMilliseconds: 5000
                            )
                        ]
                    ))
        }

        @Test func localPiExtensionDialogResponseContinuesSessionWithoutChangingProviderHealth() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                ExtensionDialogTestPiRPCTransport()
            })

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStreamStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                            stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                            stdout: "Usage: pi\n"),
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let pendingScreen = try service.sendSessionInput(sessionID: session.id, text: "deploy")
            let dialog = try #require(pendingScreen.extensionUI?.pendingDialogs.first)

            let approvedScreen = try service.respondToExtensionDialog(
                sessionID: session.id,
                dialogID: dialog.id,
                response: .confirmed(true)
            )
            let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .pi)

            #expect(pendingScreen.extensionUI?.pendingDialogs == [dialog])
            #expect(approvedScreen.extensionUI == nil || approvedScreen.extensionUI?.pendingDialogs.isEmpty == true)
            #expect(approvedScreen.activityItems.suffix(1).map(\.text) == ["Pi: Deployment approved"])
            #expect(approvedScreen.transcript == "> deploy\nDeployment approved")
            #expect(providerDetail.health.state == .available)
            #expect(providerDetail.health.summary == "Pi 0.9.0 is available")
        }

        @Test func localPiRuntimeRespondsToSelectInputAndEditorExtensionDialogs() throws {
            let transport = ExtensionDialogTestPiRPCTransport()
            let runtime = try PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in transport }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("pick-color")
            let selectDialog = try #require(runtime.sessionScreen(for: session).extensionUI?.pendingDialogs.first)
            try runtime.respondToExtensionDialog(selectDialog.id, response: .value("Green"))
            #expect(runtime.sessionScreen(for: session).transcript == "> pick-color\nSelected: Green")

            try runtime.sendInput("input-name")
            let inputDialog = try #require(runtime.sessionScreen(for: session).extensionUI?.pendingDialogs.first)
            try runtime.respondToExtensionDialog(inputDialog.id, response: .value("Nexus"))
            #expect(
                runtime.sessionScreen(for: session).transcript
                    == "> pick-color\nSelected: Green\n> input-name\nInput: Nexus")

            try runtime.sendInput("edit-notes")
            let editorDialog = try #require(runtime.sessionScreen(for: session).extensionUI?.pendingDialogs.first)
            try runtime.respondToExtensionDialog(editorDialog.id, response: .value("Line 1\nLine 2"))
            #expect(
                runtime.sessionScreen(for: session).transcript
                    == "> pick-color\nSelected: Green\n> input-name\nInput: Nexus\n> edit-notes\nEditor: Line 1\nLine 2"
            )
            #expect(
                transport.sentLines.contains(where: {
                    $0.contains("\"type\":\"extension_ui_response\"") && $0.contains("\"value\":\"Green\"")
                }))
            #expect(transport.sentLines.contains(where: { $0.contains("\"value\":\"Nexus\"") }))
            #expect(transport.sentLines.contains(where: { $0.contains("\"value\":\"Line 1\\nLine 2\"") }))
        }

        @Test func localPiFireAndForgetExtensionUIUpdatesAppearOnObservedSessionScreen() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transport = FireAndForgetExtensionUITestPiRPCTransport()
            let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in transport })
            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: PiStreamStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                            stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                            stdout: "Usage: pi\n"),
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            let sink = SessionScreenSink()
            let accumulatorBox = ObservationAccumulatorBox()
            let start = try service.observeSessionScreen(observationID: UUID(), sessionID: session.id) { update in
                guard let accumulator = accumulatorBox.value,
                    let screen = try? accumulator.apply(update)
                else {
                    return
                }
                Task {
                    await sink.record(screen)
                }
            }
            accumulatorBox.value = SessionScreenObservationAccumulator(start: start)
            await sink.record(start.screen)
            _ = await sink.nextScreen()

            transport.emitFireAndForgetUpdates()

            let observedScreen = try #require(await sink.nextScreen())
            let finalScreen = try service.getSessionScreen(sessionID: session.id)

            #expect(observedScreen.extensionUI != nil)
            #expect(finalScreen.extensionUI?.title == "Pi Demo")
            #expect(finalScreen.extensionUI?.notifications.count == 1)
            #expect(finalScreen.extensionUI?.notifications.first?.kind == .info)
            #expect(finalScreen.extensionUI?.notifications.first?.message == "Editor prefilled")
            #expect(
                finalScreen.extensionUI?.statuses == [SessionExtensionUIStatus(key: "rpc-demo", text: "Turn ready")])
            #expect(
                finalScreen.extensionUI?.widgets == [
                    SessionExtensionUIWidget(
                        key: "rpc-demo", lines: ["Ready.", "Waiting for input"], placement: .belowEditor)
                ])
            #expect(finalScreen.extensionUI?.editorText == "This text was set by the rpc-demo extension.")
        }

        @Test func inMemorySessionRuntimeManagerDoesNotBlockRuntimeChangeDrainOnObservers() async throws {
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let workspace = Workspace(
                id: session.workspaceID,
                name: "Local Pi",
                kind: .local,
                folderPath: "/tmp",
                primaryGroupID: UUID(),
                remoteHostID: nil
            )
            let runtime = BlockingObserverProbeSessionRuntime(sessionID: session.id)
            let manager = InMemorySessionRuntimeManager(
                launcher: StaticSessionRuntimeLauncher(runtime: runtime)
            )

            let observerEntered = DispatchSemaphore(value: 0)
            let unblockObserver = DispatchSemaphore(value: 0)
            let secondChangeTriggered = DispatchSemaphore(value: 0)
            let blockOnce = OnceBox()
            let observationID = UUID()

            manager.addUpdateObserver(id: observationID, for: session) {
                let screen = runtime.sessionScreen(for: session)
                guard screen.activityItems.contains(where: { $0.kind == .command && $0.text == "read CONTEXT.md" }),
                    blockOnce.take()
                else {
                    return
                }
                observerEntered.signal()
                _ = unblockObserver.wait(timeout: .now() + .seconds(1))
            }
            defer { manager.removeUpdateObserver(id: observationID) }

            try await manager.launchOrResume(
                session: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/tmp/fake-pi",
                    workingDirectory: "/tmp",
                    remoteHost: nil
                )
            )

            DispatchQueue.global().async {
                runtime.replaceScreen(
                    SessionScreen(
                        session: session,
                        primarySurface: .structuredActivityFeed,
                        controller: .mac,
                        transcript: "",
                        terminalColumns: 80,
                        terminalRows: 24,
                        activityItems: [SessionActivityItem(kind: .command, text: "read CONTEXT.md")],
                        isAgentTurnInProgress: true
                    )
                )
                runtime.triggerChange()
                runtime.replaceScreen(
                    SessionScreen(
                        session: session,
                        primarySurface: .structuredActivityFeed,
                        controller: .mac,
                        transcript: "",
                        terminalColumns: 80,
                        terminalRows: 24,
                        activityItems: [
                            SessionActivityItem(kind: .command, text: "read CONTEXT.md"),
                            SessionActivityItem(kind: .command, text: "LS"),
                        ],
                        isAgentTurnInProgress: false
                    )
                )
                runtime.triggerChange()
                secondChangeTriggered.signal()
            }

            #expect(await waitForSemaphore(observerEntered))
            #expect(await waitForSemaphore(secondChangeTriggered))

            let blockedScreen = try manager.sessionScreen(for: session)
            #expect(blockedScreen.activityItems.contains { $0.kind == .command && $0.text == "read CONTEXT.md" })
            #expect(blockedScreen.activityItems.contains { $0.kind == .command && $0.text == "LS" })
            #expect(blockedScreen.isAgentTurnInProgress == false)

            unblockObserver.signal()
        }

        @Test func localPiPersistsStructuredHistoryOverflowOnDiskAndRestoresRecentTailAcrossInspectPaths() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let messageCount = StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + 100
            let messages = (0..<messageCount).map { index in
                [
                    "role": "user",
                    "content": "History \(index)",
                ]
            }

            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                    TestPiRPCTransport(messages: messages)
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            _ = try service.sendSessionInput(sessionID: session.id, text: "/messages")

            let liveScreen = try service.getSessionScreen(sessionID: session.id)
            let restartedService = try makeService()
            let interruptedScreen = try restartedService.getSessionScreen(sessionID: session.id)
            let observationSnapshot = try restartedService.getSessionScreenObservationSnapshot(sessionID: session.id)

            let historyDirectory =
                rootURL
                .appendingPathComponent("PiStructuredSessionHistory", isDirectory: true)
                .appendingPathComponent(session.id.uuidString, isDirectory: true)
            let snapshotData = try Data(
                contentsOf: historyDirectory.appendingPathComponent("current.json", isDirectory: false))
            let persistedState = try JSONDecoder().decode(PiStructuredSessionPersistedState.self, from: snapshotData)
            let overflowLines = try String(
                decoding: Data(
                    contentsOf: historyDirectory.appendingPathComponent("activity-items.jsonl", isDirectory: false)),
                as: UTF8.self
            )
            .split(separator: "\n")
            let overflowItems = try overflowLines.map { line in
                try JSONDecoder().decode(SessionActivityItem.self, from: Data(line.utf8))
            }

            #expect(liveScreen.activityItems.count == StructuredSessionLiveHistoryRetention.maxRetainedActivityItems)
            #expect(liveScreen.activityItems.contains(where: { $0.text == "Message 1 — user: History 0" }) == false)
            #expect(
                liveScreen.activityItems.contains(where: {
                    $0.text == "Message \(messageCount) — user: History \(messageCount - 1)"
                }))
            #expect(persistedState.activityItems == liveScreen.activityItems)
            #expect(overflowItems.isEmpty == false)
            #expect(overflowItems.contains(where: { $0.text == "Message 1 — user: History 0" }))
            #expect(interruptedScreen.activityItems.dropLast() == liveScreen.activityItems)
            #expect(interruptedScreen.activityItems.last?.kind == .error)
            #expect(observationSnapshot.screen.activityItems.last?.kind == interruptedScreen.activityItems.last?.kind)
            #expect(observationSnapshot.screen.activityItems.last?.text == interruptedScreen.activityItems.last?.text)
            #expect(
                observationSnapshot.screen.activityItems.suffix(200).map(\.text)
                    == interruptedScreen.activityItems.suffix(200).map(\.text)
            )
        }

        @Test func localPiLoadsOlderStructuredHistoryPagesFromPersistedOverflowWithoutGrowingLiveTail() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let overflowCount = 100
            let messageCount = StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + overflowCount
            let messages = (0..<messageCount).map { index in
                [
                    "role": "user",
                    "content": "History \(index)",
                ]
            }

            func makeService() throws -> NexusService {
                let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                    TestPiRPCTransport(messages: messages)
                })

                return try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            _ = try service.sendSessionInput(sessionID: session.id, text: "/messages")

            let restartedService = try makeService()
            let liveScreen = try restartedService.getSessionScreen(sessionID: session.id)
            let firstPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id,
                pageSize: 40,
                before: nil
            )
            let secondPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id,
                pageSize: 40,
                before: firstPage.nextCursor
            )
            let finalPage = try restartedService.getStructuredSessionHistoryPage(
                sessionID: session.id,
                pageSize: 40,
                before: secondPage.nextCursor
            )

            #expect(
                liveScreen.activityItems.count == StructuredSessionLiveHistoryRetention.maxRetainedActivityItems + 1)
            #expect(liveScreen.activityItems.first?.text == "Message 101 — user: History 100")
            #expect(firstPage.activityItems.count == 40)
            #expect(firstPage.activityItems.first?.text == "Message 61 — user: History 60")
            #expect(firstPage.activityItems.last?.text == "Message 100 — user: History 99")
            #expect(firstPage.nextCursor != nil)
            #expect(secondPage.activityItems.count == 40)
            #expect(secondPage.activityItems.first?.text == "Message 21 — user: History 20")
            #expect(secondPage.activityItems.last?.text == "Message 60 — user: History 59")
            #expect(secondPage.nextCursor != nil)
            #expect(finalPage.activityItems.count >= 20)
            #expect(finalPage.activityItems.contains(where: { $0.text == "Message 1 — user: History 0" }))
            #expect(finalPage.activityItems.contains(where: { $0.text == "Message 20 — user: History 19" }))
            #expect(finalPage.nextCursor == nil)
        }
    }

    private struct PiStreamStubExecutableResolver: ProviderExecutableResolving {
        let executables: [String: String]

        func resolveExecutable(named command: String) -> ProviderExecutableResolution {
            ProviderExecutableResolution(
                resolvedExecutable: executables[command],
                searchedDirectories: ["/tmp/search-a", "/tmp/search-b"],
                homeDirectories: ["/tmp/home"],
                pathEnvironment: "/tmp/search-a:/tmp/search-b"
            )
        }
    }

    private struct PiStreamStubCommandRunner: ProviderCommandRunning {
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
                    domain: "PiStreamStubCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private final class LaunchCounter: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    private final class PersistentPiTransportHarness: @unchecked Sendable {
        private struct SessionState {
            let sessionID: String
            let sessionFile: String
            var lastPrompt: String?
        }

        private let lock = NSLock()
        private var nextSessionNumber = 0
        private var sessionsByFile: [String: SessionState] = [:]

        func makeTransport(arguments: [String]) -> any PiRPCTransporting {
            PersistentTestPiRPCTransport(harness: self, arguments: arguments)
        }

        fileprivate func currentSession(for arguments: [String]) -> (sessionID: String, sessionFile: String) {
            lock.lock()
            defer { lock.unlock() }

            if let sessionFile = sessionArgument(in: arguments),
                let state = sessionsByFile[sessionFile]
            {
                return (state.sessionID, state.sessionFile)
            }

            nextSessionNumber += 1
            let sessionID = "pi-session-\(nextSessionNumber)"
            let sessionFile = "/tmp/\(sessionID).jsonl"
            sessionsByFile[sessionFile] = SessionState(sessionID: sessionID, sessionFile: sessionFile, lastPrompt: nil)
            return (sessionID, sessionFile)
        }

        fileprivate func responseText(for prompt: String, sessionFile: String) -> String {
            lock.lock()
            defer { lock.unlock() }

            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            var state =
                sessionsByFile[sessionFile]
                ?? SessionState(
                    sessionID: UUID().uuidString,
                    sessionFile: sessionFile,
                    lastPrompt: nil
                )

            let response: String
            if trimmedPrompt == "what was my last message?" {
                response = state.lastPrompt ?? "(none)"
            } else {
                state.lastPrompt = trimmedPrompt
                response = trimmedPrompt
            }

            sessionsByFile[sessionFile] = state
            return response
        }

        private func sessionArgument(in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: "--session"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }

    private final class PersistentTestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private let harness: PersistentPiTransportHarness
        private let sessionID: String
        private let sessionFile: String
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(harness: PersistentPiTransportHarness, arguments: [String]) {
            self.harness = harness
            let session = harness.currentSession(for: arguments)
            sessionID = session.sessionID
            sessionFile = session.sessionFile
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": [
                        "sessionId": sessionID,
                        "sessionFile": sessionFile,
                    ],
                ])
            case "prompt":
                emit([
                    "type": "response",
                    "command": "prompt",
                    "success": true,
                ])
                let prompt = object["message"] as? String ?? ""
                let responseText = harness.responseText(for: prompt, sessionFile: sessionFile)
                emit([
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": responseText,
                    ],
                ])
                emit([
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": responseText,
                            ]
                        ]
                    ],
                ])
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    private final class PromptEventPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private let promptEvents: [[String: Any]]
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(promptEvents: [[String: Any]]) {
            self.promptEvents = promptEvents
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": [
                        "sessionId": "pi-session-1"
                    ],
                ])
            case "get_commands":
                emit([
                    "id": object["id"] as? String ?? "commands",
                    "type": "response",
                    "command": "get_commands",
                    "success": true,
                    "data": ["commands": []],
                ])
            case "get_available_models":
                emit([
                    "id": object["id"] as? String ?? "available-models",
                    "type": "response",
                    "command": "get_available_models",
                    "success": true,
                    "data": ["models": []],
                ])
            case "prompt":
                emit([
                    "type": "response",
                    "command": "prompt",
                    "success": true,
                ])
                for event in promptEvents {
                    emit(event)
                }
            case "get_session_stats":
                emit([
                    "id": object["id"] as? String ?? "stats",
                    "type": "response",
                    "command": "get_session_stats",
                    "success": true,
                    "data": ["sessionId": "pi-session-1"],
                ])
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    private final class ConfigurablePromptPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private let promptEvents: [[String: Any]]
        private let promptSuccess: Bool
        private let promptRejectionError: String?
        private let getStateIsStreaming: Bool?
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(
            promptEvents: [[String: Any]],
            promptSuccess: Bool = true,
            promptRejectionError: String? = nil,
            getStateIsStreaming: Bool? = nil
        ) {
            self.promptEvents = promptEvents
            self.promptSuccess = promptSuccess
            self.promptRejectionError = promptRejectionError
            self.getStateIsStreaming = getStateIsStreaming
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                var dataPayload: [String: Any] = ["sessionId": "pi-session-1"]
                if let getStateIsStreaming {
                    dataPayload["isStreaming"] = getStateIsStreaming
                }
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": dataPayload,
                ])
            case "get_commands":
                emit([
                    "id": object["id"] as? String ?? "commands",
                    "type": "response",
                    "command": "get_commands",
                    "success": true,
                    "data": ["commands": []],
                ])
            case "get_available_models":
                emit([
                    "id": object["id"] as? String ?? "available-models",
                    "type": "response",
                    "command": "get_available_models",
                    "success": true,
                    "data": ["models": []],
                ])
            case "get_session_stats":
                emit([
                    "id": object["id"] as? String ?? "stats",
                    "type": "response",
                    "command": "get_session_stats",
                    "success": true,
                    "data": ["sessionId": "pi-session-1"],
                ])
            case "prompt":
                var response: [String: Any] = [
                    "type": "response",
                    "command": "prompt",
                    "success": promptSuccess,
                ]
                if promptSuccess == false, let promptRejectionError {
                    response["error"] = promptRejectionError
                }
                emit(response)
                if promptSuccess {
                    for event in promptEvents {
                        emit(event)
                    }
                }
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    private final class QueueControlPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private(set) var sentLines: [String] = []

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": [
                        "sessionId": "pi-session-1",
                        "steeringMode": "one-at-a-time",
                        "followUpMode": "one-at-a-time",
                    ],
                ])
            case "get_commands":
                emit([
                    "id": object["id"] as? String ?? "commands",
                    "type": "response",
                    "command": "get_commands",
                    "success": true,
                    "data": ["commands": []],
                ])
            case "get_available_models":
                emit([
                    "id": object["id"] as? String ?? "available-models",
                    "type": "response",
                    "command": "get_available_models",
                    "success": true,
                    "data": ["models": []],
                ])
            case "steer":
                let message = object["message"] as? String ?? ""
                emit([
                    "type": "response",
                    "command": "steer",
                    "success": true,
                ])
                emit([
                    "type": "queue_update",
                    "steering": [message],
                    "followUp": [],
                ])
            case "follow_up":
                let message = object["message"] as? String ?? ""
                emit([
                    "type": "response",
                    "command": "follow_up",
                    "success": true,
                ])
                emit([
                    "type": "queue_update",
                    "steering": [],
                    "followUp": [message],
                ])
            case "prompt":
                emit([
                    "type": "response",
                    "command": "prompt",
                    "success": true,
                ])
                if let streamingBehavior = object["streamingBehavior"] as? String,
                    let message = object["message"] as? String
                {
                    if streamingBehavior == "steer" {
                        emit([
                            "type": "queue_update",
                            "steering": [message],
                            "followUp": [],
                        ])
                    } else if streamingBehavior == "followUp" {
                        emit([
                            "type": "queue_update",
                            "steering": [],
                            "followUp": [message],
                        ])
                    }
                }
            case "set_steering_mode":
                emit([
                    "id": object["id"] as? String ?? "set-steering-mode",
                    "type": "response",
                    "command": "set_steering_mode",
                    "success": true,
                ])
            case "set_follow_up_mode":
                emit([
                    "id": object["id"] as? String ?? "set-follow-up-mode",
                    "type": "response",
                    "command": "set_follow_up_mode",
                    "success": true,
                ])
            case "abort":
                emit([
                    "type": "response",
                    "command": "abort",
                    "success": true,
                ])
                emit([
                    "type": "message_end",
                    "message": [
                        "role": "assistant",
                        "content": [],
                        "stopReason": "aborted",
                    ],
                ])
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    private final class ObservationAccumulatorBox: @unchecked Sendable {
        var value: SessionScreenObservationAccumulator?
    }

    private final class OnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func take() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard fired == false else {
                return false
            }
            fired = true
            return true
        }
    }

    private actor SessionScreenSink {
        private var screens: [SessionScreen] = []

        func record(_ screen: SessionScreen) {
            screens.append(screen)
        }

        func nextScreen(timeoutNanoseconds: UInt64 = 1_000_000_000) async -> SessionScreen? {
            let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
            while DispatchTime.now().uptimeNanoseconds < deadline {
                if let screen = screens.first {
                    screens.removeFirst()
                    return screen
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return nil
        }
    }

    private func waitForSemaphore(
        _ semaphore: DispatchSemaphore,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let timeout = DispatchTime.now() + .nanoseconds(Int(timeoutNanoseconds))
                continuation.resume(returning: semaphore.wait(timeout: timeout) == .success)
            }
        }
    }

    private final class ExtensionDialogTestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private(set) var sentLines: [String] = []
        private var pendingPrompt: String?

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": ["sessionId": "pi-session-1"],
                ])
            case "prompt":
                let prompt = object["message"] as? String ?? ""
                pendingPrompt = prompt
                emit([
                    "type": "response",
                    "command": "prompt",
                    "success": true,
                ])
                switch prompt {
                case "deploy":
                    emit([
                        "type": "extension_ui_request",
                        "id": "11111111-1111-1111-1111-111111111111",
                        "method": "confirm",
                        "title": "Deploy to production?",
                        "message": "Pi wants to run deploy --prod.",
                        "timeout": 5000,
                    ])
                case "pick-color":
                    emit([
                        "type": "extension_ui_request",
                        "id": "select-dialog",
                        "method": "select",
                        "title": "Pick a color",
                        "options": ["Red", "Green", "Blue"],
                    ])
                case "input-name":
                    emit([
                        "type": "extension_ui_request",
                        "id": "input-dialog",
                        "method": "input",
                        "title": "Enter a name",
                        "placeholder": "Type a name",
                    ])
                case "edit-notes":
                    emit([
                        "type": "extension_ui_request",
                        "id": "editor-dialog",
                        "method": "editor",
                        "title": "Edit notes",
                        "prefill": "Line 1",
                    ])
                default:
                    emitTurnEnd(text: prompt)
                }
            case "extension_ui_response":
                let responseText: String
                switch pendingPrompt {
                case "deploy":
                    let confirmed = object["confirmed"] as? Bool ?? false
                    responseText = confirmed ? "Deployment approved" : "Deployment denied"
                case "pick-color":
                    responseText = "Selected: \(object["value"] as? String ?? "")"
                case "input-name":
                    responseText = "Input: \(object["value"] as? String ?? "")"
                case "edit-notes":
                    responseText = "Editor: \(object["value"] as? String ?? "")"
                default:
                    responseText = "Cancelled"
                }
                pendingPrompt = nil
                emitTurnEnd(text: responseText)
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emitTurnEnd(text: String) {
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": text,
                        ]
                    ]
                ],
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
    }

    private final class AbortableBashPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?
        private(set) var sentLines: [String] = []
        private var pendingBashRequestID: String?

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": ["sessionId": "pi-session-1"],
                ])
            case "get_commands":
                emit([
                    "id": object["id"] as? String ?? "commands",
                    "type": "response",
                    "command": "get_commands",
                    "success": true,
                    "data": ["commands": []],
                ])
            case "get_available_models":
                emit([
                    "id": object["id"] as? String ?? "available-models",
                    "type": "response",
                    "command": "get_available_models",
                    "success": true,
                    "data": ["models": []],
                ])
            case "bash":
                pendingBashRequestID = object["id"] as? String
            case "abort_bash":
                emit([
                    "type": "response",
                    "command": "abort_bash",
                    "success": true,
                ])
                emit([
                    "id": pendingBashRequestID ?? "bash",
                    "type": "response",
                    "command": "bash",
                    "success": true,
                    "data": [
                        "output": "",
                        "exitCode": 130,
                        "cancelled": true,
                        "truncated": false,
                    ],
                ])
                pendingBashRequestID = nil
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    private final class FireAndForgetExtensionUITestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            if type == "get_state" {
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": ["sessionId": "pi-session-1"],
                ])
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        func emitFireAndForgetUpdates() {
            emit([
                "type": "extension_ui_request",
                "id": "notify-1",
                "method": "notify",
                "message": "Editor prefilled",
                "notifyType": "info",
            ])
            emit([
                "type": "extension_ui_request",
                "id": "status-1",
                "method": "setStatus",
                "statusKey": "rpc-demo",
                "statusText": "Turn ready",
            ])
            emit([
                "type": "extension_ui_request",
                "id": "widget-1",
                "method": "setWidget",
                "widgetKey": "rpc-demo",
                "widgetLines": ["Ready.", "Waiting for input"],
                "widgetPlacement": "belowEditor",
            ])
            emit([
                "type": "extension_ui_request",
                "id": "title-1",
                "method": "setTitle",
                "title": "Pi Demo",
            ])
            emit([
                "type": "extension_ui_request",
                "id": "editor-text-1",
                "method": "set_editor_text",
                "text": "This text was set by the rpc-demo extension.",
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
    }

    private struct StaticSessionRuntimeLauncher: SessionRuntimeLaunching {
        let runtime: any SessionRuntime

        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            _ = session
            _ = workspace
            _ = launchConfiguration
            return runtime
        }
    }

    private final class BlockingObserverProbeSessionRuntime: SessionRuntime, @unchecked Sendable {
        private let lock = NSLock()
        private var changeHandler: (@Sendable () -> Void)?
        private var transcript = ""
        private var activityItems: [SessionActivityItem] = []
        private var isAgentTurnInProgress = false

        init(sessionID: UUID) {
            _ = sessionID
        }

        var state: Session.State { .ready }
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            lock.lock()
            defer { lock.unlock() }
            return SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .mac,
                transcript: transcript,
                terminalColumns: 80,
                terminalRows: 24,
                activityItems: activityItems,
                isAgentTurnInProgress: isAgentTurnInProgress
            )
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
            lock.lock()
            changeHandler = handler
            lock.unlock()
        }

        func replaceScreen(_ screen: SessionScreen) {
            lock.lock()
            transcript = screen.transcript
            activityItems = screen.activityItems
            isAgentTurnInProgress = screen.isAgentTurnInProgress
            lock.unlock()
        }

        func triggerChange() {
            let handler: (@Sendable () -> Void)?
            lock.lock()
            handler = changeHandler
            lock.unlock()
            handler?()
        }

        func stop() throws {}
        func sendInput(_ text: String) throws {}
        func sendInput(_ prompt: SessionPrompt) throws {}
        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
        func resize(columns: Int, rows: Int) throws {}
    }

    private final class StreamingToolPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": ["sessionId": "pi-session-1"],
                ])
            case "prompt":
                emit([
                    "type": "response",
                    "command": "prompt",
                    "success": true,
                ])
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        func emitToolExecutionStart(toolCallID: String, toolName: String, args: [String: Any]) {
            emit([
                "type": "tool_execution_start",
                "toolCallId": toolCallID,
                "toolName": toolName,
                "args": args,
            ])
        }

        func emitToolExecutionUpdate(toolCallID: String, partialResult: [String: Any]) {
            emit([
                "type": "tool_execution_update",
                "toolCallId": toolCallID,
                "partialResult": partialResult,
            ])
        }

        func emitToolExecutionEnd(toolCallID: String, toolName: String, result: [String: Any], isError: Bool = false) {
            emit([
                "type": "tool_execution_end",
                "toolCallId": toolCallID,
                "toolName": toolName,
                "result": result,
                "isError": isError,
            ])
        }

        func emitTurnEnd(text: String) {
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": text,
                        ]
                    ]
                ],
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
    }

    private final class LockedValue<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func set(_ newValue: Value) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        func get() -> Value {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct TestPiRPCCommand {
        let name: String
        let description: String?
        let source: SessionSlashCommandSource
        let location: SessionSlashCommandLocation?
        let path: String?
        let sourceInfoOnly: Bool

        init(
            name: String,
            description: String?,
            source: SessionSlashCommandSource,
            location: SessionSlashCommandLocation?,
            path: String?,
            sourceInfoOnly: Bool = false
        ) {
            self.name = name
            self.description = description
            self.source = source
            self.location = location
            self.path = path
            self.sourceInfoOnly = sourceInfoOnly
        }

        func responseObject() -> [String: Any] {
            var object: [String: Any] = [
                "name": name,
                "source": source.rawValue,
            ]
            if let description {
                object["description"] = description
            }
            if sourceInfoOnly {
                var sourceInfo: [String: Any] = [:]
                if let path {
                    sourceInfo["path"] = path
                }
                if let location {
                    sourceInfo["scope"] =
                        switch location {
                        case .user:
                            "user"
                        case .project:
                            "project"
                        case .path:
                            "temporary"
                        }
                }
                object["sourceInfo"] = sourceInfo
                return object
            }
            if let location {
                object["location"] = location.rawValue
            }
            if let path {
                object["path"] = path
            }
            return object
        }
    }

    private struct TestPiRPCModel {
        let provider: String
        let id: String
        let name: String?
        let reasoning: Bool?

        init(provider: String, id: String, name: String?, reasoning: Bool? = nil) {
            self.provider = provider
            self.id = id
            self.name = name
            self.reasoning = reasoning
        }

        func responseObject() -> [String: Any] {
            var object: [String: Any] = [
                "provider": provider,
                "id": id,
            ]
            if let name {
                object["name"] = name
            }
            if let reasoning {
                object["reasoning"] = reasoning
            }
            return object
        }
    }

    private struct TestPiRPCForkMessage {
        let entryID: String
        let text: String

        func responseObject() -> [String: Any] {
            [
                "entryId": entryID,
                "text": text,
            ]
        }
    }

    private struct TestPiRPCBashResult {
        let output: String
        let exitCode: Int
        let cancelled: Bool
        let truncated: Bool
        let fullOutputPath: String?

        init(
            output: String,
            exitCode: Int,
            cancelled: Bool = false,
            truncated: Bool = false,
            fullOutputPath: String? = nil
        ) {
            self.output = output
            self.exitCode = exitCode
            self.cancelled = cancelled
            self.truncated = truncated
            self.fullOutputPath = fullOutputPath
        }

        func responseObject() -> [String: Any] {
            var object: [String: Any] = [
                "output": output,
                "exitCode": exitCode,
                "cancelled": cancelled,
                "truncated": truncated,
            ]
            if let fullOutputPath {
                object["fullOutputPath"] = fullOutputPath
            }
            return object
        }
    }

    private final class TestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
        private let promptResponseText: String
        private let slashCommands: [TestPiRPCCommand]
        private let availableModels: [TestPiRPCModel]
        private let forkMessages: [TestPiRPCForkMessage]
        private let bashResult: TestPiRPCBashResult?
        private let exportedHTMLPath: String?
        private let messages: [[String: Any]]
        private let sessionStats: [String: Any]?
        private let lastAssistantText: String?
        private let stateModel: TestPiRPCModel?
        private let stateThinkingLevel: String?
        private let cycledModel: TestPiRPCModel?
        private let cycledThinkingLevel: String?
        private let cycledThinkingLevelResult: String?
        private let compactionSummary: String?
        private let compactionTokensBefore: Int?
        private let promptEvents: [[String: Any]]
        private let stallAfterPromptAcceptance: Bool
        private(set) var sentLines: [String] = []
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        init(
            promptResponseText: String = "",
            slashCommands: [TestPiRPCCommand] = [],
            availableModels: [TestPiRPCModel] = [],
            forkMessages: [TestPiRPCForkMessage] = [],
            bashResult: TestPiRPCBashResult? = nil,
            exportedHTMLPath: String? = nil,
            messages: [[String: Any]] = [],
            sessionStats: [String: Any]? = nil,
            lastAssistantText: String? = nil,
            stateModel: TestPiRPCModel? = nil,
            stateThinkingLevel: String? = nil,
            cycledModel: TestPiRPCModel? = nil,
            cycledThinkingLevel: String? = nil,
            cycledThinkingLevelResult: String? = nil,
            compactionSummary: String? = nil,
            compactionTokensBefore: Int? = nil,
            promptEvents: [[String: Any]] = [],
            stallAfterPromptAcceptance: Bool = false
        ) {
            self.promptResponseText = promptResponseText
            self.slashCommands = slashCommands
            self.availableModels = availableModels
            self.forkMessages = forkMessages
            self.bashResult = bashResult
            self.exportedHTMLPath = exportedHTMLPath
            self.messages = messages
            self.sessionStats = sessionStats
            self.lastAssistantText = lastAssistantText
            self.stateModel = stateModel
            self.stateThinkingLevel = stateThinkingLevel
            self.cycledModel = cycledModel
            self.cycledThinkingLevel = cycledThinkingLevel
            self.cycledThinkingLevelResult = cycledThinkingLevelResult
            self.compactionSummary = compactionSummary
            self.compactionTokensBefore = compactionTokensBefore
            self.promptEvents = promptEvents
            self.stallAfterPromptAcceptance = stallAfterPromptAcceptance
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            sentLines.append(line)

            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                return
            }

            switch type {
            case "get_state":
                var data: [String: Any] = [
                    "sessionId": "pi-session-1",
                    "isStreaming": stallAfterPromptAcceptance,
                ]
                if let stateModel {
                    data["model"] = stateModel.responseObject()
                }
                if let stateThinkingLevel {
                    data["thinkingLevel"] = stateThinkingLevel
                }
                emit([
                    "id": object["id"] as? String ?? "state",
                    "type": "response",
                    "command": "get_state",
                    "success": true,
                    "data": data,
                ])
            case "get_commands":
                emit([
                    "id": object["id"] as? String ?? "commands",
                    "type": "response",
                    "command": "get_commands",
                    "success": true,
                    "data": [
                        "commands": slashCommands.map { $0.responseObject() }
                    ],
                ])
            case "get_available_models":
                emit([
                    "id": object["id"] as? String ?? "available-models",
                    "type": "response",
                    "command": "get_available_models",
                    "success": true,
                    "data": [
                        "models": availableModels.map { $0.responseObject() }
                    ],
                ])
            case "get_fork_messages":
                emit([
                    "id": object["id"] as? String ?? "fork-messages",
                    "type": "response",
                    "command": "get_fork_messages",
                    "success": true,
                    "data": [
                        "messages": forkMessages.map { $0.responseObject() }
                    ],
                ])
            case "set_model":
                let provider = object["provider"] as? String ?? ""
                let modelID = object["modelId"] as? String ?? ""
                if let model = availableModels.first(where: { $0.provider == provider && $0.id == modelID }) {
                    emit([
                        "id": object["id"] as? String ?? "set-model",
                        "type": "response",
                        "command": "set_model",
                        "success": true,
                        "data": model.responseObject(),
                    ])
                } else {
                    emit([
                        "id": object["id"] as? String ?? "set-model",
                        "type": "response",
                        "command": "set_model",
                        "success": false,
                        "error": "Model not found: \(provider)/\(modelID)",
                    ])
                }
            case "cycle_model":
                if let cycledModel {
                    emit([
                        "id": object["id"] as? String ?? "cycle-model",
                        "type": "response",
                        "command": "cycle_model",
                        "success": true,
                        "data": [
                            "model": cycledModel.responseObject(),
                            "thinkingLevel": cycledThinkingLevel as Any,
                        ],
                    ])
                } else {
                    emit([
                        "id": object["id"] as? String ?? "cycle-model",
                        "type": "response",
                        "command": "cycle_model",
                        "success": true,
                        "data": NSNull(),
                    ])
                }
            case "cycle_thinking_level":
                emit([
                    "id": object["id"] as? String ?? "cycle-thinking-level",
                    "type": "response",
                    "command": "cycle_thinking_level",
                    "success": true,
                    "data": cycledThinkingLevelResult.map { ["level": $0] } ?? NSNull(),
                ])
            case "set_thinking_level":
                emit([
                    "id": object["id"] as? String ?? "set-thinking-level",
                    "type": "response",
                    "command": "set_thinking_level",
                    "success": true,
                ])
            case "compact":
                emit([
                    "id": object["id"] as? String ?? "compact",
                    "type": "response",
                    "command": "compact",
                    "success": true,
                    "data": [
                        "summary": compactionSummary ?? "Summary of conversation...",
                        "firstKeptEntryId": "entry-1",
                        "tokensBefore": compactionTokensBefore ?? 0,
                        "details": [:],
                    ],
                ])
            case "set_auto_compaction":
                emit([
                    "id": object["id"] as? String ?? "auto-compaction",
                    "type": "response",
                    "command": "set_auto_compaction",
                    "success": true,
                ])
            case "set_auto_retry":
                emit([
                    "id": object["id"] as? String ?? "auto-retry",
                    "type": "response",
                    "command": "set_auto_retry",
                    "success": true,
                ])
            case "abort_retry":
                emit([
                    "id": object["id"] as? String ?? "abort-retry",
                    "type": "response",
                    "command": "abort_retry",
                    "success": true,
                ])
            case "bash":
                emit([
                    "id": object["id"] as? String ?? "bash",
                    "type": "response",
                    "command": "bash",
                    "success": true,
                    "data": bashResult?.responseObject()
                        ?? TestPiRPCBashResult(output: "", exitCode: 0).responseObject(),
                ])
            case "export_html":
                emit([
                    "id": object["id"] as? String ?? "export-html",
                    "type": "response",
                    "command": "export_html",
                    "success": true,
                    "data": [
                        "path": exportedHTMLPath ?? (object["outputPath"] as? String ?? "/tmp/pi-session.html")
                    ],
                ])
            case "get_messages":
                emit([
                    "id": object["id"] as? String ?? "messages",
                    "type": "response",
                    "command": "get_messages",
                    "success": true,
                    "data": ["messages": messages],
                ])
            case "get_session_stats":
                emit([
                    "id": object["id"] as? String ?? "session-stats",
                    "type": "response",
                    "command": "get_session_stats",
                    "success": true,
                    "data": sessionStats ?? [:],
                ])
            case "get_last_assistant_text":
                emit([
                    "id": object["id"] as? String ?? "last-assistant-text",
                    "type": "response",
                    "command": "get_last_assistant_text",
                    "success": true,
                    "data": ["text": lastAssistantText as Any],
                ])
            case "prompt":
                emit([
                    "type": "response",
                    "command": "prompt",
                    "success": true,
                ])
                if stallAfterPromptAcceptance {
                    return
                }
                for event in promptEvents {
                    emit(event)
                }
                guard promptResponseText.isEmpty == false else {
                    return
                }
                emit([
                    "type": "message_update",
                    "assistantMessageEvent": [
                        "type": "text_delta",
                        "delta": promptResponseText,
                    ],
                ])
                emit([
                    "type": "turn_end",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": promptResponseText,
                            ]
                        ]
                    ],
                ])
            default:
                return
            }
        }

        func terminate() throws {
            terminationHandler?(0)
        }

        private func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                let line = String(data: data, encoding: .utf8)
            else {
                return
            }
            stdoutLineHandler?(line)
        }
    }

    extension NexusServicePiSessionStreamTests {
        @Test func piTurnWatchdogDeclaresProviderStallWhenRpcStdoutStaysIdle() async throws {
            setenv("NEXUS_PI_RPC_TURN_STALL_SEC", "1", 1)
            setenv("NEXUS_PI_RPC_TURN_POLL_SEC", "0.2", 1)
            setenv("NEXUS_PI_RPC_TURN_WATCHDOG_TICK_SEC", "0.1", 1)
            defer {
                unsetenv("NEXUS_PI_RPC_TURN_STALL_SEC")
                unsetenv("NEXUS_PI_RPC_TURN_POLL_SEC")
                unsetenv("NEXUS_PI_RPC_TURN_WATCHDOG_TICK_SEC")
            }

            let runtime = try await PiRPCSessionRuntime(
                executable: "/tmp/fake-pi",
                workingDirectory: "/tmp",
                terminationStatusMessageBuilder: { _ in "" },
                nexusSessionID: UUID(),
                transportFactory: { _, _, _ in
                    TestPiRPCTransport(stallAfterPromptAcceptance: true)
                }
            )

            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            try runtime.sendInput("stall me")
            try await Task.sleep(nanoseconds: 2_500_000_000)

            let screen = runtime.sessionScreen(for: session)
            #expect(screen.isAgentTurnInProgress == false)
            #expect(screen.activityItems.contains { $0.kind == .error && $0.text.contains("Pi stopped responding") })
        }

        @Test func relaunchedPiSessionScreenDropsInterruptedErrorWhenLiveRuntimeExists() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let launcher = ProcessSessionRuntimeLauncher(piTransportFactory: { _, _, _ in
                TestPiRPCTransport()
            })
            func makeService() throws -> NexusService {
                try NexusService.bootstrapForTests(
                    rootURL: rootURL,
                    providerHealthEvaluator: ProviderHealthFacts(
                        executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                        commandRunner: PiStreamStubCommandRunner(results: [
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(
                                stdout: "0.9.0\n"),
                            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(
                                stdout: "Usage: pi\n"),
                        ]),
                        localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                    ),
                    sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
                )
            }

            let service = try makeService()
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

            let restarted = try makeService()
            let interruptedScreen = try restarted.getSessionScreen(sessionID: session.id)
            #expect(interruptedScreen.session.state == .interrupted)

            _ = try await restarted.launchOrResumeSession(sessionID: session.id)
            let liveScreen = try restarted.getSessionScreen(sessionID: session.id)

            #expect(liveScreen.session.state == .ready)
            #expect(liveScreen.activityItems.contains(where: { $0.kind == .error }) == false)
            #expect(liveScreen.activityItems.contains(where: { $0.text == "Session stream connected" }))
        }
    }
#endif
