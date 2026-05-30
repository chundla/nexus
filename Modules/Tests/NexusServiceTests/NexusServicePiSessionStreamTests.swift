#if os(macOS)
import Foundation
import NexusDomain
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
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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
        #expect(firstScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])
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

        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "Current Pi model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: medium)"
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
                    )
                ]
            )
        })

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: PiStreamStubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: PiStreamStubCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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

        #expect(screen.slashCommands == [
            SessionSlashCommand(
                name: "review-changes",
                description: "Summarize the current diff.",
                source: .prompt,
                location: .project,
                path: "/tmp/project/.pi/prompts/review-changes.md"
            ),
            SessionSlashCommand(
                name: "skill:create-cli",
                description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                source: .skill,
                location: .user,
                path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md"
            )
        ])
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
                        )
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

        #expect(screen.slashCommands == [
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
            )
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

        #expect(commandNames == [
            "thinking off",
            "thinking minimal",
            "thinking low",
            "thinking medium",
            "thinking high"
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
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "/model anthropic/claude-sonnet-4-20250514",
            "Pi model switched to anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4",
            "Current Pi model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4"
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
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "Current Pi model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: medium)",
            "/thinking high",
            "Pi thinking level set to high",
            "Current Pi model: anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4 (thinking: high)"
        ])
        #expect(screen.activityItems.map(\.kind) == [.status, .status, .command, .status, .status])
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
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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
        let relaunchedSession = try restartedService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        _ = try restartedService.sendSessionText(sessionID: relaunchedSession.id, text: "what was my last message?")
        let resumedTurn = try restartedService.sendSessionInputKey(sessionID: relaunchedSession.id, key: .enter)

        #expect(firstTurn.activityItems.suffix(2).map(\.text) == ["You: alpha", "Pi: alpha"])
        #expect(relaunchedSession.id == firstSession.id)
        #expect(resumedTurn.activityItems.suffix(2).map(\.text) == ["You: what was my last message?", "Pi: alpha"])
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
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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
        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")

        let restartedService = try makeService()
        let overview = try restartedService.getWorkspaceOverview(workspaceID: workspace.id)
        let providerDetail = try restartedService.getProviderDetail(workspaceID: workspace.id, providerID: .pi)
        let interruptedDefaultScreen = try restartedService.getSessionScreen(sessionID: defaultSession.id)
        let interruptedNamedScreen = try restartedService.getSessionScreen(sessionID: namedSession.id)

        let expectedMessage = "Pi Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."

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
        #expect(interruptedDefaultScreen.activityItems.map(\.kind) == [.error])
        #expect(interruptedDefaultScreen.activityItems.map(\.text) == [expectedMessage])
        #expect(interruptedNamedScreen.session.state == .interrupted)
        #expect(interruptedNamedScreen.activityItems.map(\.kind) == [.error])
        #expect(interruptedNamedScreen.activityItems.map(\.text) == [expectedMessage])
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
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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

        let namedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")
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
        try "#!/bin/sh\nIFS= read -r _line\nprintf '%s\\n' '{\"id\":\"nexus-pi-startup-state\",\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"data\":{\"sessionId\":\"pi-session-1\"}}'\n".write(to: interpreterURL, atomically: true, encoding: .utf8)
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

        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: world"
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
                    "delta": "world"
                ]
            ],
            [
                "type": "tool_execution_start",
                "toolCallId": "tool-1",
                "toolName": "subagent",
                "args": ["agent": "reviewer", "task": "Review the latest diff"]
            ],
            [
                "type": "tool_execution_update",
                "toolCallId": "tool-1",
                "partialResult": [
                    "content": [[
                        "type": "text_delta",
                        "delta": "Looks good overall."
                    ]]
                ]
            ],
            [
                "type": "tool_execution_end",
                "toolCallId": "tool-1",
                "toolName": "subagent",
                "result": [
                    "content": [[
                        "type": "text",
                        "text": "Looks good overall."
                    ]]
                ]
            ],
            [
                "type": "turn_end",
                "message": [
                    "content": [[
                        "type": "text",
                        "text": "world"
                    ]]
                ]
            ]
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

        #expect(screen.providerEvents.map(\.type) == [
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
            "response"
        ])
        #expect(screen.providerEvents.map(\.command) == [
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
            "get_commands"
        ])
        #expect(screen.providerEvents.map(\.family) == [
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
            .response
        ])
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "subagent reviewer: Review the latest diff",
            "subagent: Looks good overall.",
            "Pi: world"
        ])
        #expect(screen.transcript == "> hello\nworld")
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
                    "content": [[
                        "type": "text",
                        "text": "done"
                    ]]
                ]
            ]
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

        #expect(providerEvents.map(\.type) == [
            "queue_update",
            "compaction_checkpoint",
            "retry_scheduled",
            "extension_error",
            "future_event",
            "turn_end"
        ])
        #expect(providerEvents.map(\.family) == [
            .queue,
            .compaction,
            .retry,
            .extensionError,
            .unknown,
            .turn
        ])
        #expect(try #require(providerEvents.first(where: { $0.type == "extension_error" })).rawPayload.contains("Widget render failed"))
        #expect(try #require(providerEvents.first(where: { $0.type == "future_event" })).rawPayload.contains("\"ticket\":7"))
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: done"
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
        #expect(runningScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: delegate"
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
                "content": [[
                    "type": "text",
                    "text": "Looks good overall. Watch the new error path."
                ]]
            ]
        )
        transport.emitTurnEnd(text: "Done")

        let completedScreen = runtime.sessionScreen(for: session)

        #expect(completedScreen.isAgentTurnInProgress == false)
        #expect(completedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: delegate",
            "subagent reviewer: Review the latest diff and summarize issues",
            "subagent: Looks good overall. Watch the new error path.",
            "Pi: Done"
        ])
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
                "content": [[
                    "type": "text_delta",
                    "delta": "Looks good overall. Watch the new error path."
                ]]
            ]
        )

        let streamedScreen = runtime.sessionScreen(for: session)

        #expect(streamedScreen.isAgentTurnInProgress)
        #expect(streamedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: delegate",
            "subagent reviewer: Review the latest diff and summarize issues",
            "subagent: Looks good overall. Watch the new error path."
        ])
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
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: deploy"
        ])
        #expect(screen.approvalRequests.isEmpty)
        #expect(screen.extensionUI == SessionExtensionUIState(
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
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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
        #expect(runtime.sessionScreen(for: session).transcript == "> pick-color\nSelected: Green\n> input-name\nInput: Nexus")

        try runtime.sendInput("edit-notes")
        let editorDialog = try #require(runtime.sessionScreen(for: session).extensionUI?.pendingDialogs.first)
        try runtime.respondToExtensionDialog(editorDialog.id, response: .value("Line 1\nLine 2"))
        #expect(runtime.sessionScreen(for: session).transcript == "> pick-color\nSelected: Green\n> input-name\nInput: Nexus\n> edit-notes\nEditor: Line 1\nLine 2")
        #expect(transport.sentLines.contains(where: { $0.contains("\"type\":\"extension_ui_response\"") && $0.contains("\"value\":\"Green\"") }))
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
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
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
        _ = try service.observeSessionScreen(observationID: UUID(), sessionID: session.id) { screen in
            Task {
                await sink.record(screen)
            }
        }
        _ = await sink.nextScreen()

        transport.emitFireAndForgetUpdates()

        let observedScreen = try #require(await sink.nextScreen())
        let finalScreen = try service.getSessionScreen(sessionID: session.id)

        #expect(observedScreen.extensionUI != nil)
        #expect(finalScreen.extensionUI?.title == "Pi Demo")
        #expect(finalScreen.extensionUI?.notifications.count == 1)
        #expect(finalScreen.extensionUI?.notifications.first?.kind == .info)
        #expect(finalScreen.extensionUI?.notifications.first?.message == "Editor prefilled")
        #expect(finalScreen.extensionUI?.statuses == [SessionExtensionUIStatus(key: "rpc-demo", text: "Turn ready")])
        #expect(finalScreen.extensionUI?.widgets == [SessionExtensionUIWidget(key: "rpc-demo", lines: ["Ready.", "Waiting for input"], placement: .belowEditor)])
        #expect(finalScreen.extensionUI?.editorText == "This text was set by the rpc-demo extension.")
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
            throw NSError(domain: "PiStreamStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
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
           let state = sessionsByFile[sessionFile] {
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
        var state = sessionsByFile[sessionFile] ?? SessionState(
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
              let type = object["type"] as? String else {
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
                    "sessionFile": sessionFile
                ]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            let prompt = object["message"] as? String ?? ""
            let responseText = harness.responseText(for: prompt, sessionFile: sessionFile)
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": responseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": responseText
                        ]
                    ]
                ]
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
              let line = String(data: data, encoding: .utf8) else {
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
              let type = object["type"] as? String else {
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
                ]
            ])
        case "get_commands":
            emit([
                "id": object["id"] as? String ?? "commands",
                "type": "response",
                "command": "get_commands",
                "success": true,
                "data": ["commands": []]
            ])
        case "get_available_models":
            emit([
                "id": object["id"] as? String ?? "available-models",
                "type": "response",
                "command": "get_available_models",
                "success": true,
                "data": ["models": []]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            for event in promptEvents {
                emit(event)
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
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
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
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
            ])
        case "prompt":
            let prompt = object["message"] as? String ?? ""
            pendingPrompt = prompt
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            switch prompt {
            case "deploy":
                emit([
                    "type": "extension_ui_request",
                    "id": "11111111-1111-1111-1111-111111111111",
                    "method": "confirm",
                    "title": "Deploy to production?",
                    "message": "Pi wants to run deploy --prod.",
                    "timeout": 5000
                ])
            case "pick-color":
                emit([
                    "type": "extension_ui_request",
                    "id": "select-dialog",
                    "method": "select",
                    "title": "Pick a color",
                    "options": ["Red", "Green", "Blue"]
                ])
            case "input-name":
                emit([
                    "type": "extension_ui_request",
                    "id": "input-dialog",
                    "method": "input",
                    "title": "Enter a name",
                    "placeholder": "Type a name"
                ])
            case "edit-notes":
                emit([
                    "type": "extension_ui_request",
                    "id": "editor-dialog",
                    "method": "editor",
                    "title": "Edit notes",
                    "prefill": "Line 1"
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
                        "text": text
                    ]
                ]
            ]
        ])
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
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
              let type = object["type"] as? String else {
            return
        }

        if type == "get_state" {
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
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
            "notifyType": "info"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "status-1",
            "method": "setStatus",
            "statusKey": "rpc-demo",
            "statusText": "Turn ready"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "widget-1",
            "method": "setWidget",
            "widgetKey": "rpc-demo",
            "widgetLines": ["Ready.", "Waiting for input"],
            "widgetPlacement": "belowEditor"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "title-1",
            "method": "setTitle",
            "title": "Pi Demo"
        ])
        emit([
            "type": "extension_ui_request",
            "id": "editor-text-1",
            "method": "set_editor_text",
            "text": "This text was set by the rpc-demo extension."
        ])
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
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
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
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
            "args": args
        ])
    }

    func emitToolExecutionUpdate(toolCallID: String, partialResult: [String: Any]) {
        emit([
            "type": "tool_execution_update",
            "toolCallId": toolCallID,
            "partialResult": partialResult
        ])
    }

    func emitToolExecutionEnd(toolCallID: String, toolName: String, result: [String: Any], isError: Bool = false) {
        emit([
            "type": "tool_execution_end",
            "toolCallId": toolCallID,
            "toolName": toolName,
            "result": result,
            "isError": isError
        ])
    }

    func emitTurnEnd(text: String) {
        emit([
            "type": "turn_end",
            "message": [
                "content": [[
                    "type": "text",
                    "text": text
                ]]
            ]
        ])
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
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

    func responseObject() -> [String: Any] {
        var object: [String: Any] = [
            "name": name,
            "source": source.rawValue
        ]
        if let description {
            object["description"] = description
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
            "id": id
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

private final class TestPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private let promptResponseText: String
    private let slashCommands: [TestPiRPCCommand]
    private let availableModels: [TestPiRPCModel]
    private let stateModel: TestPiRPCModel?
    private let stateThinkingLevel: String?
    private(set) var sentLines: [String] = []
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(
        promptResponseText: String = "",
        slashCommands: [TestPiRPCCommand] = [],
        availableModels: [TestPiRPCModel] = [],
        stateModel: TestPiRPCModel? = nil,
        stateThinkingLevel: String? = nil
    ) {
        self.promptResponseText = promptResponseText
        self.slashCommands = slashCommands
        self.availableModels = availableModels
        self.stateModel = stateModel
        self.stateThinkingLevel = stateThinkingLevel
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
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            var data: [String: Any] = [
                "sessionId": "pi-session-1"
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
                "data": data
            ])
        case "get_commands":
            emit([
                "id": object["id"] as? String ?? "commands",
                "type": "response",
                "command": "get_commands",
                "success": true,
                "data": [
                    "commands": slashCommands.map { $0.responseObject() }
                ]
            ])
        case "get_available_models":
            emit([
                "id": object["id"] as? String ?? "available-models",
                "type": "response",
                "command": "get_available_models",
                "success": true,
                "data": [
                    "models": availableModels.map { $0.responseObject() }
                ]
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
                    "data": model.responseObject()
                ])
            } else {
                emit([
                    "id": object["id"] as? String ?? "set-model",
                    "type": "response",
                    "command": "set_model",
                    "success": false,
                    "error": "Model not found: \(provider)/\(modelID)"
                ])
            }
        case "set_thinking_level":
            emit([
                "id": object["id"] as? String ?? "set-thinking-level",
                "type": "response",
                "command": "set_thinking_level",
                "success": true
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            guard promptResponseText.isEmpty == false else {
                return
            }
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": promptResponseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": promptResponseText
                        ]
                    ]
                ]
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
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}
#endif
