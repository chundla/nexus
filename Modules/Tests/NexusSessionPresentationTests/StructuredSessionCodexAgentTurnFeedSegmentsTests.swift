import Foundation
import NexusDomain
@testable import NexusSessionPresentation
import Testing

/// Codex **Agent Turn** composite feed segments (#237, ADR 0037).
struct StructuredSessionCodexAgentTurnFeedSegmentsTests {
    private func codexSession() -> Session {
        Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
    }

    @Test func codexFeedSegmentsMapsSubagentToolsAndFinalAnswer() throws {
        let connectedID = UUID()
        let commandID = UUID()
        let screen = SessionScreen(
            session: codexSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(id: connectedID, kind: .status, text: "Codex shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: Ship it"),
                SessionActivityItem(
                    id: commandID,
                    kind: .command,
                    text: "subagent reviewer: Check the diff and summarize follow-up work"
                ),
                SessionActivityItem(
                    kind: .message,
                    text: "subagent: Looks good overall. Follow up on the retry path."
                ),
                SessionActivityItem(kind: .message, text: "Codex: Done")
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionCodexFeedSegments(for: screen))

        #expect(segments.count == 3)
        guard case .standalone(let connected) = segments[0] else {
            Issue.record("Expected standalone session status")
            return
        }
        #expect(connected.id == connectedID)

        guard case .userMessage(let user) = segments[1] else {
            Issue.record("Expected user message segment")
            return
        }
        #expect(user.text == "Ship it")

        guard case .agentTurn(let turn) = segments[2] else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.isOpen == false)
        #expect(turn.reasoningStackItems.isEmpty)
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].activityItemID == commandID)
        #expect(turn.toolStackItems[0].subagentOutputs == ["Looks good overall. Follow up on the retry path."])
        #expect(turn.finalAnswer?.text == "Done")
    }

    @Test func codexFeedSegmentsMergeThoughtsStatusAndThinkingStreamsIntoReasoning() throws {
        let screen = SessionScreen(
            session: codexSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: plan"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Outline steps."),
                SessionActivityItem(kind: .message, text: "thinking: Still weighing options."),
                SessionActivityItem(kind: .message, text: "Codex: Here is the plan")
            ]
        )

        let segments = try #require(structuredSessionCodexFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Outline steps.", "Still weighing options."])
        #expect(turn.finalAnswer?.text == "Here is the plan")
    }

    @Test func codexFeedPresentationIncludesCompositeFeedSegments() throws {
        let screen = SessionScreen(
            session: codexSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi"),
                SessionActivityItem(kind: .message, text: "Codex: hey")
            ]
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        let segments = try #require(feed.feedSegments)
        #expect(segments.count == 2)
        guard case .userMessage = segments[0],
              case .agentTurn = segments[1] else {
            Issue.record("Expected user then agent turn segments")
            return
        }
    }

    @Test func codexAgentTurnRegressionToolRowsNeverLeakAsStandaloneSegments() throws {
        let screen = SessionScreen(
            session: codexSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: run"),
                SessionActivityItem(kind: .command, text: "command: ls"),
                SessionActivityItem(kind: .message, text: "command: ok"),
                SessionActivityItem(kind: .message, text: "Codex: finished")
            ]
        )

        let segments = try #require(structuredSessionCodexFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(segments.contains { if case .standalone = $0 { return true }; return false } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected composite agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].subagentOutputs == ["ok"])
    }
}