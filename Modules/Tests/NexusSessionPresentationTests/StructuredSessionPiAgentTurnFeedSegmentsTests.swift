import Foundation
import NexusDomain
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionPiAgentTurnFeedSegmentsTests {
    private func piSession() -> Session {
        Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
    }

    @Test func piFeedSegmentsEmitUserAgentTurnAndStandaloneRows() throws {
        let userID = UUID()
        let thoughtsID = UUID()
        let commandID = UUID()
        let subagentMessageID = UUID()
        let answerID = UUID()
        let connectedID = UUID()

        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(id: connectedID, kind: .status, text: "Session stream connected"),
                SessionActivityItem(
                    id: userID,
                    kind: .message,
                    text: "You: hello",
                    prompt: SessionPrompt(text: "hello")
                ),
                SessionActivityItem(
                    id: thoughtsID,
                    kind: .status,
                    text: "thoughts:",
                    detailText: "Plan the change."
                ),
                SessionActivityItem(id: commandID, kind: .command, text: "subagent reviewer: Review diff"),
                SessionActivityItem(id: subagentMessageID, kind: .message, text: "reviewer: Looks good overall."),
                SessionActivityItem(id: answerID, kind: .message, text: "Pi: Done")
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))

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
        #expect(user.activityItemID == userID)
        #expect(user.text == "hello")

        guard case .agentTurn(let turn) = segments[2] else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.isOpen == false)
        #expect(turn.reasoning?.markdownBody == "Plan the change.")
        #expect(turn.tools.count == 1)
        #expect(turn.tools[0].callPreview == "subagent reviewer: Review diff")
        #expect(turn.tools[0].subagentOutputs == ["Looks good overall."])
        #expect(turn.finalAnswer?.text == "Done")
        #expect(turn.finalAnswer?.isStreaming == false)
    }

    @Test func piFeedSegmentsMergeMultipleThoughtsBlocksIntoOneReasoningAccordion() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(
                    kind: .message,
                    text: "You: go",
                    prompt: SessionPrompt(text: "go")
                ),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "First thought."),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Second thought."),
                SessionActivityItem(kind: .message, text: "Pi: ok")
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.reasoning?.markdownBody == "First thought.\n\nSecond thought.")
    }

    @Test func piFeedSegmentsNestSubagentAssistantTextUnderParentToolCall() throws {
        let commandID = UUID()
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: run", prompt: SessionPrompt(text: "run")),
                SessionActivityItem(id: commandID, kind: .command, text: "subagent reviewer: Task", detailText: "step 1"),
                SessionActivityItem(kind: .message, text: "reviewer: Summary output"),
                SessionActivityItem(kind: .message, text: "Pi: final")
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.tools.count == 1)
        #expect(turn.tools[0].activityItemID == commandID)
        #expect(turn.tools[0].detailText == "step 1")
        #expect(turn.tools[0].subagentOutputs == ["Summary output"])
        #expect(turn.finalAnswer?.text == "final")
    }

    @Test func piFeedSegmentsAttachLiveAssistantDraftToOpenTurn() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi", prompt: SessionPrompt(text: "hi")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Thinking through it.")
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "partial"),
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer?.text == "partial")
        #expect(turn.finalAnswer?.isStreaming == true)
    }

    @Test func piFeedPresentationIncludesCompositeFeedSegments() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi", prompt: SessionPrompt(text: "hi")),
                SessionActivityItem(kind: .message, text: "Pi: hey")
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

    @Test func nonPiSessionsDoNotEmitCompositeFeedSegments() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi")
            ]
        )

        #expect(structuredSessionPiFeedSegments(for: screen) == nil)
    }
}