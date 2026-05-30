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
