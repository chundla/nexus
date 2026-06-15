import Foundation
import NexusDomain
import Testing
@testable import NexusSessionPresentation

struct StructuredSessionOpenTurnAssistantBubbleTests {
    @Test func interimPiMessageRendersAsStandaloneAfterOpenTurn() throws {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Working."),
                SessionActivityItem(kind: .message, text: "Pi: interim chunk")
            ],
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 3)
        guard case .userMessage = segments[0],
              case .agentTurn(let turn) = segments[1],
              case .standalone(let item) = segments[2] else {
            Issue.record("Expected user, open turn, then standalone Pi message")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
        #expect(item.text == "Pi: interim chunk")
    }

    @Test func scrollTargetUsesBottomSentinelWhileThinkingIndicatorVisible() throws {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi", prompt: SessionPrompt(text: "hi")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "think"),
                SessionActivityItem(kind: .message, text: "Pi: partial")
            ],
            isAgentTurnInProgress: true
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        #expect(feed.thinkingIndicator != nil)

        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: feed,
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )

        #expect(structuredSessionFeedScrollTarget(for: presentation) == .bottomSentinel)
        #expect(structuredSessionFeedScrollSnapshot(for: presentation).liveDraftGrowthToken == nil)
    }
}