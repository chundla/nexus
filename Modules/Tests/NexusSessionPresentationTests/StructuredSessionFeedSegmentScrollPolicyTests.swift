import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

struct StructuredSessionFeedSegmentScrollPolicyTests {
    private func piSession() -> Session {
        Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
    }

    @Test func feedScrollItemCountUsesSegmentListNotActivityRowCount() throws {
        let connectedID = UUID()
        let userID = UUID()
        let thoughtsID = UUID()
        let commandID = UUID()
        let answerID = UUID()

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
                    detailText: "Plan."
                ),
                SessionActivityItem(id: commandID, kind: .command, text: "git status"),
                SessionActivityItem(id: answerID, kind: .message, text: "Pi: Done"),
            ],
            isAgentTurnInProgress: false
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        let segments = try #require(feed.feedSegments)

        #expect(segments.count == 3)
        #expect(feed.activityRows.count > segments.count)
        #expect(feed.feedScrollItemCount == 3)
        #expect(feed.feedScrollItemIDs == segments.map(\.id))
    }

    @Test func progressiveRevealTailUsesSegmentCount() throws {
        let segmentIDs = (0..<4).map { _ in UUID() }
        let rows = segmentIDs.enumerated().map { index, id in
            StructuredSessionActivityRow(
                id: id,
                title: "Row \(index)",
                systemImage: "message",
                text: "text \(index)",
                emphasis: .accent
            )
        }
        let segments: [StructuredSessionFeedSegment] = segmentIDs.map { id in
            .userMessage(StructuredSessionFeedUserMessageSegment(activityItemID: id, text: "u"))
        }
        let feed = StructuredSessionFeedPresentation(
            copy: StructuredSessionPresentationCopy(
                emptyStateTitle: "Empty",
                emptyStateDescription: "None",
                composerPlaceholder: "Type"
            ),
            activityRows: rows,
            feedSegments: segments,
            pendingApprovalRequests: [],
            thinkingIndicator: StructuredSessionThinkingIndicator(text: "Thinking…")
        )

        #expect(structuredSessionFeedScrollItemCount(for: feed) == 4)
        #expect(
            structuredSessionFeedRevealShowsFullTail(
                visibleTailItemCount: 3, totalFeedItemCount: feed.feedScrollItemCount)
                == false
        )
        #expect(
            structuredSessionFeedRevealShowsFullTail(
                visibleTailItemCount: 4, totalFeedItemCount: feed.feedScrollItemCount)
        )

        let tailTwo = structuredSessionActivityRows(in: feed, visibleTailItemCount: 2)
        #expect(tailTwo.count == 2)
        #expect(Set(tailTwo.map(\.id)) == Set(segmentIDs.suffix(2)))
    }

    @Test func scrollTargetUsesOpenAgentTurnSegmentWithoutFinalAnswerPlaceholder() throws {
        let turnAnchorID = UUID()
        let userID = UUID()
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(
                    id: userID,
                    kind: .message,
                    text: "You: hi",
                    prompt: SessionPrompt(text: "hi")
                ),
                SessionActivityItem(id: turnAnchorID, kind: .status, text: "thoughts:", detailText: "think"),
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "draft body"),
            isAgentTurnInProgress: true
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        let segments = try #require(feed.feedSegments)
        guard
            case .agentTurn(let turn) = segments.first(where: {
                if case .agentTurn = $0 { return true }
                return false
            })
        else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.id == turnAnchorID)
        #expect(turn.finalAnswer == nil)

        let presentation = FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: feed,
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )

        #expect(structuredSessionFeedScrollTarget(for: presentation) == .activityRow(turnAnchorID))
        #expect(presentation.autoScrollTrigger.lastActivityRowID == turnAnchorID)

        let snapshot = structuredSessionFeedScrollSnapshot(for: presentation)
        #expect(snapshot.feedScrollTarget == .activityRow(turnAnchorID))
        #expect(snapshot.liveDraftGrowthToken == nil)
    }

    @Test func autoScrollTriggerUsesLastSegmentIDWhenManyActivityItemsCollapseIntoTurn() throws {
        let userID = UUID()
        let thoughtsID = UUID()
        let commandID = UUID()
        let answerID = UUID()

        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(
                    id: userID,
                    kind: .message,
                    text: "You: go",
                    prompt: SessionPrompt(text: "go")
                ),
                SessionActivityItem(id: thoughtsID, kind: .status, text: "thoughts:", detailText: "a"),
                SessionActivityItem(id: commandID, kind: .command, text: "run"),
                SessionActivityItem(id: answerID, kind: .message, text: "Pi: ok"),
            ],
            isAgentTurnInProgress: false
        )

        let trigger = structuredSessionAutoScrollTrigger(for: screen)
        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(trigger.lastActivityRowID == segments.last?.id)
        #expect(trigger.lastActivityRowID != answerID)
    }
}
