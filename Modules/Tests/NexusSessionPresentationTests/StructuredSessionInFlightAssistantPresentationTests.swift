import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

struct StructuredSessionOpenTurnAssistantBubbleTests {
    @Test func interimPiMessageHiddenWhileTurnOpenShowsThinkingOnly() throws {
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
        #expect(segments.count == 2)
        guard case .userMessage = segments[0],
            case .agentTurn(let turn) = segments[1]
        else {
            Issue.record("Expected user and open turn without interim Pi bubble")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
        #expect(structuredSessionThinkingIndicator(for: screen, hasPendingApprovalRequests: false) != nil)
    }

    @Test func primaryStandalonePiAssistantUsesDedicatedBubblePresentationNotActivityPreview() throws {
        let item = SessionActivityItem(kind: .message, text: "Pi: # Done\n\nFinal body")
        let assistant = try #require(structuredSessionPiStandaloneAssistantPresentation(for: item))
        #expect(assistant.label == "Pi")
        #expect(assistant.text == "# Done\n\nFinal body")
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
        // Under autoscroll policy we only suppress the narrow documented interim-standalone-Pi case;
        // Thinking + appended interim text no longer blanket-suppresses. Pin-state decides follow.
        #expect(current.suppressesProgrammaticBottomScroll == false)
        #expect(structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation) == false)
    }

    @Test func bottomEdgeScrollBindingDisabledForClosedTurnFeed() throws {
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
                SessionActivityItem(kind: .message, text: "Pi: **done**"),
            ],
            isAgentTurnInProgress: false
        )
        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: structuredSessionFeedPresentation(for: screen),
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: presentation) == false)
        #expect(structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation) == false)
    }

    @Test func autoScrollTriggerAnchorsOpenAgentTurnWhileAssistantTextHidden() throws {
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
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Scan."),
                SessionActivityItem(
                    kind: .message,
                    text: "Pi: Reviewing Nexus: checking recent changes and key architecture."
                ),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected open agent turn")
            return
        }
        #expect(segments.count == 2)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)
        #expect(structuredSessionAutoScrollTrigger(for: screen).lastActivityRowID == turn.id)

        let feed = structuredSessionFeedPresentation(for: screen)
        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: feed,
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
        #expect(structuredSessionFeedScrollTarget(for: presentation) == .activityRow(turn.id))
        // Normal open turn; bottom scroll allowed when user is pinned to bottom.
        #expect(structuredSessionFeedScrollSnapshot(for: presentation).suppressesProgrammaticBottomScroll == false)
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
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected open turn without interim Pi bubble")
            return
        }
        #expect(segments.count == 2)
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

    @Test func piThoughtsThenLongPiWithoutToolKeepsTurnOpen() throws {
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
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Scanning repo layout."),
                SessionActivityItem(
                    kind: .message,
                    text: "Pi: Reviewing Nexus: mapping structure and sampling critical paths."
                ),
            ],
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)
        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected open turn without visible assistant text")
            return
        }
        #expect(segments.count == 2)
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
    }

    @Test func piLiveDraftDoesNotRenderAssistantBubbleWhileTurnOpen() throws {
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
            ],
            providerFacts: StructuredSessionProviderFacts(
                liveAssistantDraftText: "Reviewing Nexus: mapping structure and sampling critical paths."
            ),
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
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
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected open turn with tools, no provisional Pi bubble")
            return
        }
        #expect(segments.count == 2)
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
        #expect(turn.toolStackItems.count == 1)
        #expect(structuredSessionThinkingIndicator(for: screen, hasPendingApprovalRequests: false) != nil)

        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: structuredSessionFeedPresentation(for: screen),
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
        #expect(structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation) == false)
        // Normal open turn with tools + Thinking; autoscroll when pinned.
        #expect(structuredSessionFeedScrollSnapshot(for: presentation).suppressesProgrammaticBottomScroll == false)
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
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Working."),
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "streaming chunk"),
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionPiFeedSegmentTurnInProgress(for: screen) == true)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)
    }

    @Test func feedPinStateDetachesWhileEffectiveOpenTurn() {
        // Policy: distance-driven pin/follow at all times, including during open agent turns.
        // Near bottom (distance <= threshold) => follow, even while Thinking/tool rows/final streaming.
        // Only detaches when the viewport is far from bottom (user scrolled up to read history).
        let pinned = StructuredSessionFeedPinState(isFollowingBottom: true, userHasDetachedFromBottom: false)
        let nearBottomSample = StructuredSessionScrollGeometrySample(distanceFromBottom: 20, contentOffsetY: 100)
        let stillFollowing = structuredSessionFeedPinStateDuringOpenAgentTurn(
            previous: pinned,
            sample: nearBottomSample,
            effectiveTurnInProgress: true
        )
        #expect(stillFollowing.isFollowingBottom == true)
        #expect(stillFollowing.userHasDetachedFromBottom == false)

        // Far from bottom => detach (user reading history).
        let farSample = StructuredSessionScrollGeometrySample(distanceFromBottom: 120, contentOffsetY: 100)
        let detached = structuredSessionFeedPinStateDuringOpenAgentTurn(
            previous: pinned,
            sample: farSample,
            effectiveTurnInProgress: true
        )
        #expect(detached.isFollowingBottom == false)
        #expect(detached.userHasDetachedFromBottom == true)
    }

    @Test func postInterimPiCommandsStayInContinuationTurnWithoutStandaloneBubble() throws {
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
                SessionActivityItem(kind: .message, text: "Pi: Reviewing Nexus while tools continue."),
                SessionActivityItem(kind: .command, text: "read: file.swift"),
            ],
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected single open turn with hidden interim Pi and follow-on tool")
            return
        }
        #expect(turn.isOpen)
        #expect(turn.toolStackItems.count == 1)
        #expect(structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(in: segments) == false)
        #expect(structuredSessionFeedScrollAnchorTurnID(in: segments) == turn.id)
    }

    @Test func effectiveTurnInProgressWhenOpenTurnWithoutVisibleAssistantText() throws {
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
            ) == false)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)
    }

    @Test func shortInterimPiWithPostPromptToolsKeepsTurnOpenWhenServiceFlagFalse() throws {
        let interim = "Let me gather context first"
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
                    kind: .message,
                    text: "You: Lets perform a code review on nexus",
                    prompt: SessionPrompt(text: "Lets perform a code review on nexus")
                ),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: interim),
                SessionActivityItem(kind: .message, text: "Pi: \(interim)"),
                SessionActivityItem(kind: .command, text: "read: README.md"),
            ],
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionPiFeedSegmentTurnInProgress(for: screen) == true)
        #expect(structuredSessionEffectiveAgentTurnInProgress(for: screen) == true)

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected single open turn with reasoning and tool")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.reasoningStackItems.map(\.markdownBody) == [interim])
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.finalAnswer == nil)
    }
}
