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

        guard let segments = feed.feedSegments,
              case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected open turn segment")
            return
        }
        #expect(structuredSessionFeedScrollTarget(for: presentation) == .activityRow(turn.id))
        #expect(structuredSessionAutoScrollTrigger(for: screen).lastActivityRowID == turn.id)
        #expect(structuredSessionFeedScrollSnapshot(for: presentation).liveDraftGrowthToken == nil)

        let previous = structuredSessionFeedScrollSnapshot(for: presentation)
        let appendedPiScreen = SessionScreen(
            session: screen.session,
            primarySurface: screen.primarySurface,
            transcript: screen.transcript,
            activityItems: screen.activityItems + [
                SessionActivityItem(kind: .message, text: "Pi: another interim")
            ],
            isAgentTurnInProgress: true
        )
        let appendedFeed = structuredSessionFeedPresentation(for: appendedPiScreen)
        let appendedPresentation = FocusedStructuredSessionPresentation(
            session: appendedPiScreen.session,
            feed: appendedFeed,
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: appendedPiScreen)
        )
        let current = structuredSessionFeedScrollSnapshot(for: appendedPresentation)
        #expect(current.feedScrollTarget == .activityRow(turn.id))
        #expect(
            structuredSessionBottomScrollIntent(previous: previous, current: current, isPinnedToBottom: true) == .none
        )
    }
}