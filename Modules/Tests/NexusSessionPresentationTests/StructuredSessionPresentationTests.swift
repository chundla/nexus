import Foundation
import NexusDomain
import NexusSessionPresentation
import Testing

struct StructuredSessionPresentationTests {
    @Test func structuredSessionActivityRowsDescribeSharedSessionActivityKinds() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Connected"),
                SessionActivityItem(kind: .message, text: "Pi: hello"),
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy to production?"),
                SessionActivityItem(kind: .approvalDecision, text: "Approved: Deploy to production?"),
                SessionActivityItem(kind: .progress, text: "Gathering context"),
                SessionActivityItem(kind: .command, text: "git status"),
                SessionActivityItem(kind: .diff, text: "Edited ContentView.swift"),
                SessionActivityItem(kind: .error, text: "Provider request failed"),
                SessionActivityItem(kind: .completion, text: "Turn complete")
            ]
        )

        #expect(structuredSessionActivityRows(for: screen) == [
            StructuredSessionActivityRow(id: screen.activityItems[0].id, title: "Status", systemImage: "dot.radiowaves.left.and.right", text: "Connected", emphasis: .neutral),
            StructuredSessionActivityRow(id: screen.activityItems[1].id, title: "Message", systemImage: "message", text: "Pi: hello", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[2].id, title: "Approval Request", systemImage: "hand.raised", text: "Approval Request: Deploy to production?", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[3].id, title: "Approval Decision", systemImage: "checkmark.shield", text: "Approved: Deploy to production?", emphasis: .success),
            StructuredSessionActivityRow(id: screen.activityItems[4].id, title: "Progress", systemImage: "hourglass", text: "Gathering context", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[5].id, title: "Command", systemImage: "terminal", text: "git status", emphasis: .neutral),
            StructuredSessionActivityRow(id: screen.activityItems[6].id, title: "Diff", systemImage: "square.and.pencil", text: "Edited ContentView.swift", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[7].id, title: "Error", systemImage: "exclamationmark.triangle", text: "Provider request failed", emphasis: .critical),
            StructuredSessionActivityRow(id: screen.activityItems[8].id, title: "Completion", systemImage: "checkmark.circle", text: "Turn complete", emphasis: .success)
        ])
    }

    @Test func structuredSessionPresentationCopyUsesProviderDisplayName() {
        let codexScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(structuredSessionPresentationCopy(for: codexScreen) == StructuredSessionPresentationCopy(
            emptyStateTitle: "No Session activity yet",
            emptyStateDescription: "Send a prompt to start the Codex Session.",
            composerPlaceholder: "Send a prompt to Codex"
        ))
    }

    @Test func structuredSessionStatusBarPresentationFormatsTokenUsageFromProviderEvents() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "response",
                    family: .response,
                    command: "get_session_stats",
                    rawPayload: #"{"type":"response","command":"get_session_stats","success":true,"data":{"contextUsage":{"tokens":60000,"contextWindow":200000,"percent":30}}}"#
                )
            ]
        )

        #expect(structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus") == StructuredSessionStatusBarPresentation(
            workspaceLocation: "/tmp/nexus",
            tokenUsage: StructuredSessionTokenUsagePresentation(usedTokens: 60000, totalTokens: 200000, percent: 30)
        ))
    }

    @Test func structuredSessionStatusBarPresentationFallsBackToKnownContextWindowForPiModels() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "response",
                    family: .response,
                    command: "get_state",
                    rawPayload: #"{"type":"response","command":"get_state","success":true,"data":{"model":{"provider":"openai","id":"gpt-5.1-codex-max","name":"GPT-5.1 Codex Max"}}}"#
                )
            ]
        )

        let presentation = structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus")

        #expect(presentation.workspaceLocation == "/tmp/nexus")
        #expect(presentation.tokenUsage == StructuredSessionTokenUsagePresentation(usedTokens: 0, totalTokens: 272000, percent: 0))
        #expect(presentation.tokenUsageText == "0/272k 0%")
    }

    @Test func structuredSessionStatusBarPresentationFallsBackToKnownContextWindowForCodexModels() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .codex,
                    type: "response",
                    family: .response,
                    rawPayload: #"{"id":"nexus-codex-thread-start","result":{"thread":{"id":"codex-thread-1"},"model":"gpt-5.5"}}"#
                )
            ]
        )

        #expect(structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus").tokenUsageText == "0/272k 0%")
    }

    @Test func structuredSessionPresentationBuildsSharedFeedAndComposerStateFromSessionScreenAndDraft() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let pendingRequest = SessionApprovalRequest(title: "Deploy", text: "Deploy to production?", state: .pending)
        let approvedRequest = SessionApprovalRequest(title: "Cleanup", text: "Delete temp files?", state: .approved)
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .progress, text: "Gathering context")],
            approvalRequests: [pendingRequest, approvedRequest]
        )

        let presentation = StructuredSessionPresentation(
            screen: screen,
            hasWriterAuthority: false,
            draft: "Ship it",
            isPerformingAction: false
        )

        #expect(presentation.feed == StructuredSessionFeedPresentation(
            copy: StructuredSessionPresentationCopy(
                emptyStateTitle: "No Session activity yet",
                emptyStateDescription: "Send a prompt to start the Codex Session.",
                composerPlaceholder: "Send a prompt to Codex"
            ),
            activityRows: [
                StructuredSessionActivityRow(
                    id: screen.activityItems[0].id,
                    title: "Progress",
                    systemImage: "hourglass",
                    text: "Gathering context",
                    emphasis: .accent
                )
            ],
            pendingApprovalRequests: [pendingRequest],
            thinkingIndicator: nil
        ))
        #expect(presentation.composer == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
        #expect(presentation.sendAffordance == StructuredSessionComposerSendAffordance(
            isVisible: false,
            isEnabled: false
        ))
        #expect(presentation.approvalRequest == StructuredSessionApprovalRequestPresentation(
            actionsAreEnabled: false,
            disabledReason: "Take Controller to respond to Approval Requests from this iPhone."
        ))
        #expect(presentation.slashCommandMenu == StructuredSessionSlashCommandMenuPresentation(
            isVisible: false,
            commands: []
        ))
    }

    @Test func structuredSessionConversationPresentationClassifiesSharedMessageRowsAndFallsBackToProviderLabel() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )
        let userRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "You: Ship it",
            emphasis: .accent
        )
        let assistantRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "Planner: Check git status",
            emphasis: .accent
        )
        let fallbackRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "Still working",
            emphasis: .accent
        )

        #expect(structuredSessionConversationPresentation(for: userRow, screen: screen) == StructuredSessionConversationPresentation(
            role: .user,
            text: "Ship it"
        ))
        #expect(structuredSessionConversationPresentation(for: assistantRow, screen: screen) == StructuredSessionConversationPresentation(
            role: .assistant(label: "Planner"),
            text: "Check git status"
        ))
        #expect(structuredSessionConversationPresentation(for: fallbackRow, screen: screen) == StructuredSessionConversationPresentation(
            role: .assistant(label: "Codex"),
            text: "Still working"
        ))
    }

    @Test func structuredSessionFeedPresentationShowsThinkingIndicatorWhileAgentTurnIsInProgress() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .message, text: "You: Ship it")],
            isAgentTurnInProgress: true
        )

        #expect(structuredSessionFeedPresentation(for: screen).thinkingIndicator == StructuredSessionThinkingIndicator(text: "Thinking…"))
    }

    @Test func structuredSessionComposerPresentationKeepsViewerPromptVisibleButDisabledUntilControllerTaken() {
        let codexScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(structuredSessionComposerPresentation(for: codexScreen, hasWriterAuthority: false) == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
    }

    @Test func structuredSessionComposerPresentationUsesPiCopyWhileKeepingViewerPromptVisibleButDisabledUntilControllerTaken() {
        let piScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(structuredSessionComposerPresentation(for: piScreen, hasWriterAuthority: false) == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Pi",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
    }

    @Test func structuredSessionComposerSendAffordanceAppearsAfterTheFirstSendableCharacter() {
        let composer = StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: true,
            disabledReason: nil
        )

        #expect(structuredSessionComposerSendAffordance(
            for: "H",
            composer: composer,
            isPerformingAction: false
        ) == StructuredSessionComposerSendAffordance(
            isVisible: true,
            isEnabled: true
        ))
    }

    @Test func structuredSessionComposerSendAffordanceStaysHiddenForWhitespaceOnlyDrafts() {
        let composer = StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Pi",
            isEnabled: true,
            disabledReason: nil
        )

        #expect(structuredSessionComposerSendAffordance(
            for: " \n ",
            composer: composer,
            isPerformingAction: false
        ) == StructuredSessionComposerSendAffordance(
            isVisible: false,
            isEnabled: false
        ))
    }

    @Test func structuredSessionApprovalRequestPresentationKeepsViewerActionsVisibleButDisabledUntilControllerTaken() {
        #expect(structuredSessionApprovalRequestPresentation(hasWriterAuthority: false) == StructuredSessionApprovalRequestPresentation(
            actionsAreEnabled: false,
            disabledReason: "Take Controller to respond to Approval Requests from this iPhone."
        ))
    }

    @Test func structuredSessionSlashCommandMenuAppearsAsSoonAsSlashIsTyped() {
        let menu = structuredSessionSlashCommandMenuPresentation(
            for: "/",
            screen: SessionScreen(
                session: Session(
                    id: UUID(),
                    workspaceID: UUID(),
                    providerID: .codex,
                    isDefault: true,
                    state: .ready
                ),
                transcript: ""
            )
        )

        #expect(menu.isVisible)
        #expect(menu.commands.first?.displayText == "/model")
    }

    @Test func structuredSessionSlashCommandMenuNarrowsUsingTypedPrefixAndSupportsArgumentCommands() {
        let codexMenu = structuredSessionSlashCommandMenuPresentation(
            for: "/go",
            screen: SessionScreen(
                session: Session(
                    id: UUID(),
                    workspaceID: UUID(),
                    providerID: .codex,
                    isDefault: true,
                    state: .ready
                ),
                transcript: ""
            )
        )
        let bobMenu = structuredSessionSlashCommandMenuPresentation(
            for: "/mode a",
            screen: SessionScreen(
                session: Session(
                    id: UUID(),
                    workspaceID: UUID(),
                    providerID: .ibmBob,
                    isDefault: true,
                    state: .ready
                ),
                transcript: ""
            )
        )

        #expect(codexMenu.commands.map(\.displayText) == ["/goal <objective>"])
        #expect(bobMenu.commands.map(\.displayText) == ["/mode advanced", "/mode ask"])
    }

    @Test func structuredSessionSlashCommandMenuUsesLivePiSkillCommandsFromSessionScreen() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "skill:create-cli",
                    description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                    source: .skill,
                    location: .user,
                    path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md"
                ),
                SessionSlashCommand(
                    name: "skill:tdd",
                    description: "Test-driven development with red-green-refactor loop.",
                    source: .skill,
                    location: .project,
                    path: "/tmp/project/.pi/skills/tdd/SKILL.md"
                )
            ]
        )
        let menu = structuredSessionSlashCommandMenuPresentation(for: "/skill:", screen: screen)

        #expect(menu.isVisible)
        #expect(menu.commands.map(\.displayText) == ["/skill:create-cli [u]", "/skill:tdd [p]"])
        #expect(menu.commands.first?.summary == "CLI UX/spec: args, flags, help, output, errors, config, dry-run.")
    }

    @Test func structuredSessionSlashCommandMenuUsesStaticPiModelCommandAndLiveModelSuggestions() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "model anthropic/claude-sonnet-4-20250514",
                    displayName: "model anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4",
                    insertionText: "model anthropic/claude-sonnet-4-20250514",
                    suggestionQueryPrefix: "model ",
                    description: "Switch to anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "skill:tdd",
                    description: "Test-driven development with red-green-refactor loop.",
                    source: .skill,
                    location: .project,
                    path: "/tmp/project/.pi/skills/tdd/SKILL.md"
                )
            ]
        )

        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText).contains("/model <provider>/<model>"))
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.contains(where: { $0.displayText.contains("Claude Sonnet 4") }) == false)
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/model anth", screen: screen).commands.map(\.displayText) == ["/model anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4"])
    }

    @Test func structuredSessionSlashCommandMenuUsesLivePiThinkingCommandsOnlyAfterThinkingPrefix() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "thinking high",
                    displayName: "thinking high",
                    insertionText: "thinking high",
                    suggestionQueryPrefix: "thinking ",
                    description: "Set Pi thinking level to high.",
                    source: .builtIn
                )
            ]
        )

        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText).contains("/thinking <level>"))
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.contains(where: { $0.displayText == "/thinking high" }) == false)
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/thinking h", screen: screen).commands.map(\.displayText) == ["/thinking high"])
    }

    @Test func structuredSessionSlashCommandMenuUsesStaticPiQueueControlsAndLiveModeSuggestions() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "steering-mode one-at-a-time",
                    displayName: "steering-mode one-at-a-time",
                    insertionText: "steering-mode one-at-a-time",
                    suggestionQueryPrefix: "steering-mode ",
                    description: "Current Pi steering mode.",
                    source: .builtIn
                )
            ]
        )

        let rootCommands = structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText)

        #expect(rootCommands.contains("/steer <message>"))
        #expect(rootCommands.contains("/follow-up <message>"))
        #expect(rootCommands.contains("/abort"))
        #expect(rootCommands.contains("/steering-mode <mode>"))
        #expect(rootCommands.contains("/follow-up-mode <mode>"))
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/steering-mode o", screen: screen).commands.map(\.displayText) == ["/steering-mode one-at-a-time"])
    }

    @Test func structuredSessionSlashCommandMenuUsesStaticPiCompactionAndRetryControls() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: ""
        )

        let rootCommands = structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText)

        #expect(rootCommands.contains("/cycle-model"))
        #expect(rootCommands.contains("/cycle-thinking-level"))
        #expect(rootCommands.contains("/compact [instructions]"))
        #expect(rootCommands.contains("/auto-compaction <on|off>"))
        #expect(rootCommands.contains("/auto-retry <on|off>"))
        #expect(rootCommands.contains("/abort-retry"))
    }

    @Test func structuredSessionSlashCommandMenuUsesLiveCodexModelCommandsOnlyAfterModelPrefix() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "model gpt-5.5",
                    displayName: "model gpt-5.5 — GPT-5.5",
                    insertionText: "model gpt-5.5",
                    suggestionQueryPrefix: "model ",
                    description: "Default model. Frontier coding model.",
                    source: .builtIn
                )
            ]
        )

        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.contains(where: { $0.displayText.contains("GPT-5.5") }) == false)
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/model g", screen: screen).commands.map(\.displayText) == ["/model gpt-5.5 — GPT-5.5"])
    }

    @Test func structuredSessionSlashCommandMenuUsesLiveBobCommandArgumentHintsFromSessionScreen() throws {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "api-endpoint",
                    displayName: "api-endpoint <endpoint-name> <http-method>",
                    insertionText: "api-endpoint ",
                    description: "Create a new API endpoint.",
                    source: .prompt,
                    location: .project,
                    path: "/tmp/project/.bob/commands/api-endpoint.md"
                )
            ]
        )
        let menu = structuredSessionSlashCommandMenuPresentation(for: "/api", screen: screen)

        #expect(menu.commands.map(\.displayText) == ["/api-endpoint <endpoint-name> <http-method> [p]"])
        let command = try #require(menu.commands.first)
        #expect(applyStructuredSessionSlashCommand(command, to: "/api") == "/api-endpoint ")
    }

    @Test func structuredSessionSlashCommandMenuAppliesSelectedCommandThroughSharedMenuPolicy() throws {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            transcript: ""
        )
        let menu = structuredSessionSlashCommandMenuPresentation(for: "  /go", screen: screen)
        let command = try #require(menu.commands.first)

        #expect(menu.applying(command, to: "  /go") == "  /goal ")
    }

    @Test func applyStructuredSessionSlashCommandReplacesSlashDraftWhilePreservingLeadingWhitespace() {
        let command = StructuredSessionSlashCommand(
            matchText: "goal",
            displayText: "/goal <objective>",
            insertionText: "/goal ",
            summary: "Set or view the goal for a long-running task.",
            acceptsArguments: true
        )

        #expect(applyStructuredSessionSlashCommand(command, to: "  /go") == "  /goal ")
    }
}
