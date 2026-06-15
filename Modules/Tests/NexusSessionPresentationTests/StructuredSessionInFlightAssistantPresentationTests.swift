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
                SessionActivityItem(kind: .message, text: "Pi: interim chunk"),
            ],
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 3)
        guard case .userMessage = segments[0],
            case .agentTurn(let turn) = segments[1],
            case .standalone(let item) = segments[2]
        else {
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
                SessionActivityItem(kind: .message, text: "Pi: partial"),
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
            case .agentTurn(let turn) = segments[1]
        else {
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
        #expect(current.suppressesProgrammaticBottomScroll == true)
        #expect(structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation) == false)
    }

    @Test func piTurnStaysOpenWhenServiceFlagFalseBeforeTurnEndProviderEvent() throws {
        let userID = UUID()
        let thoughtsID = UUID()
        let interimID = UUID()
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
                SessionActivityItem(
                    id: userID,
                    kind: .message,
                    text: "You: go",
                    prompt: SessionPrompt(text: "go")
                ),
                SessionActivityItem(id: thoughtsID, kind: .status, text: "thoughts:", detailText: "Working."),
                SessionActivityItem(
                    id: interimID, kind: .message, text: "Pi: No PR or file named — reviewing architecture."),
            ],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update"}"#
                )
            ],
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments[1],
            case .standalone = segments[2]
        else {
            Issue.record("Expected open turn then interim Pi standalone")
            return
        }
        #expect(turn.isOpen == true)
        #expect(structuredSessionThinkingIndicator(for: screen, hasPendingApprovalRequests: false) != nil)

        let feed = structuredSessionFeedPresentation(for: screen)
        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: feed,
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
        #expect(structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation) == false)
    }

    @Test func piProvisionalPiLastLineKeepsTurnOpenWithoutServiceFlag() throws {
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
                SessionActivityItem(kind: .message, text: "You: review", prompt: SessionPrompt(text: "review")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Planning."),
                SessionActivityItem(kind: .command, text: "read: ARCHITECTURE.md"),
                SessionActivityItem(
                    kind: .message,
                    text: "Pi: No PR or file named — reviewing architecture and recent changes."
                ),
            ],
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionPiActivityTailSuggestsOpenTurn(screen.activityItems) == true)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments[1],
              case .standalone = segments[2]
        else {
            Issue.record("Expected open turn then standalone provisional Pi")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
        #expect(structuredSessionThinkingIndicator(for: screen, hasPendingApprovalRequests: false) != nil)

        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: structuredSessionFeedPresentation(for: screen),
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
        #expect(structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation) == false)
        #expect(structuredSessionFeedScrollSnapshot(for: presentation).suppressesProgrammaticBottomScroll == true)
    }

    @Test func piTurnStaysOpenWhenLiveAssistantDraftPresentDespiteServiceFlagFalse() throws {
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
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Working.")
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "streaming chunk"),
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionPiFeedSegmentTurnInProgress(for: screen) == true)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)
    }

    @Test func feedPinStateDetachesWhileEffectiveOpenTurn() {
        let pinned = StructuredSessionFeedPinState(isFollowingBottom: true, userHasDetachedFromBottom: false)
        let sample = StructuredSessionScrollGeometrySample(distanceFromBottom: 0, contentOffsetY: 100)
        let detached = structuredSessionFeedPinStateDuringOpenAgentTurn(
            previous: pinned,
            sample: sample,
            effectiveTurnInProgress: true
        )
        #expect(detached.isFollowingBottom == false)
        #expect(detached.userHasDetachedFromBottom == true)
    }

    @Test func effectiveTurnInProgressWhenOpenTurnAndInterimPiStandalone() throws {
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
                SessionActivityItem(kind: .message, text: "Pi: interim"),
            ],
            isAgentTurnInProgress: true
        )

        #expect(
            structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(
                in: structuredSessionPiFeedSegments(for: screen)
            ) == true)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)
    }
}
