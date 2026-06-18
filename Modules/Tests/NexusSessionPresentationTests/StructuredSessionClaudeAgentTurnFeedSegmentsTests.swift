import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

/// Claude **Agent Turn** composite feed segments (#252, ADR 0037).
struct StructuredSessionClaudeAgentTurnFeedSegmentsTests {
    private func claudeSession() -> Session {
        Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
    }

    @Test func claudeFeedSegmentsKeepLifecycleStatusStandaloneWhileGroupingReasoningToolsAndFinalAnswer() throws {
        let startedID = UUID()
        let commandID = UUID()
        let completionID = UUID()
        let screen = SessionScreen(
            session: claudeSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: review the README"),
                SessionActivityItem(id: startedID, kind: .status, text: "Claude Session started."),
                SessionActivityItem(kind: .message, text: "Claude (thinking): Need to inspect the file first."),
                SessionActivityItem(id: commandID, kind: .command, text: "Read: /tmp/workspace/README.md"),
                SessionActivityItem(kind: .message, text: "Read: # README"),
                SessionActivityItem(kind: .message, text: "Claude: Here is the summary."),
                SessionActivityItem(id: completionID, kind: .completion, text: "Here is the summary."),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionClaudeFeedSegments(for: screen))

        #expect(segments.count == 4)
        guard case .userMessage(let user) = segments[0] else {
            Issue.record("Expected user message segment")
            return
        }
        #expect(user.text == "review the README")

        guard case .standalone(let started) = segments[1] else {
            Issue.record("Expected standalone lifecycle status")
            return
        }
        #expect(started.id == startedID)

        guard case .agentTurn(let turn) = segments[2] else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.isOpen == false)
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Need to inspect the file first."])
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].activityItemID == commandID)
        #expect(turn.toolStackItems[0].detailText == "# README")
        #expect(turn.finalAnswer?.text == "Here is the summary.")

        guard case .standalone(let completion) = segments[3] else {
            Issue.record("Expected standalone completion row")
            return
        }
        #expect(completion.id == completionID)
    }

    @Test func claudeFeedSegmentsKeepOpenTurnCompositeWhileToolAndAssistantRowsStream() throws {
        let startedID = UUID()
        let commandID = UUID()
        let screen = SessionScreen(
            session: claudeSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: inspect src"),
                SessionActivityItem(id: startedID, kind: .status, text: "Claude Session started."),
                SessionActivityItem(kind: .message, text: "Claude (thinking): I should check the project layout."),
                SessionActivityItem(id: commandID, kind: .command, text: "LS: /tmp/workspace/src"),
                SessionActivityItem(kind: .message, text: "LS: App.swift"),
                SessionActivityItem(kind: .message, text: "Claude: I found the entry point."),
            ],
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionClaudeFeedSegments(for: screen))

        #expect(segments.count == 3)
        guard case .standalone(let started) = segments[1] else {
            Issue.record("Expected standalone lifecycle status")
            return
        }
        #expect(started.id == startedID)

        guard case .agentTurn(let turn) = segments[2] else {
            Issue.record("Expected open agent turn")
            return
        }
        #expect(turn.isOpen)
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["I should check the project layout."])
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].activityItemID == commandID)
        #expect(turn.toolStackItems[0].detailText == "App.swift")
        #expect(turn.finalAnswer == nil)
        #expect(
            segments.contains {
                if case .standalone(let item) = $0 {
                    return item.id != startedID
                }
                return false
            } == false)
    }

    @Test func claudeFeedPresentationIncludesCompositeFeedSegments() throws {
        let screen = SessionScreen(
            session: claudeSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi"),
                SessionActivityItem(kind: .message, text: "Claude: hello"),
            ]
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        let segments = try #require(feed.feedSegments)
        #expect(segments.count == 2)
        guard case .userMessage = segments[0],
            case .agentTurn = segments[1]
        else {
            Issue.record("Expected user then agent turn segments")
            return
        }
    }
}
