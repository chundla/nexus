import Foundation
import NexusDomain
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionFeedSegmentIterationPolicyTests {
    private func piFeedWithSegments() -> StructuredSessionFeedPresentation {
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
            activityItems: [
                SessionActivityItem(kind: .status, text: "Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: one", prompt: SessionPrompt(text: "one")),
                SessionActivityItem(kind: .message, text: "Pi: a"),
                SessionActivityItem(kind: .message, text: "You: two", prompt: SessionPrompt(text: "two")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Planning."),
                SessionActivityItem(kind: .message, text: "Pi: b")
            ]
        )
        return structuredSessionFeedPresentation(for: screen)
    }

    @Test func progressiveRevealUsesFeedSegmentTailWhenSegmentsExist() throws {
        let feed = piFeedWithSegments()
        let segments = try #require(feed.feedSegments)
        #expect(segments.count == 5)

        let visible = try #require(
            structuredSessionVisibleFeedSegments(in: feed, visibleTailItemCount: 2)
        )
        #expect(visible.count == 2)
        #expect(visible.map(\.id) == Array(segments.suffix(2).map(\.id)))
    }

    @Test func thinkingIndicatorDefersWhenOpenTurnHasReasoningContent() {
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
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Working.")
            ],
            isAgentTurnInProgress: true
        )
        #expect(structuredSessionThinkingIndicator(for: screen, hasPendingApprovalRequests: false) == nil)
    }

    @Test func agentTurnDisclosureDefaultsExpandReasoningWhileOpenTurnInProgress() {
        let turn = StructuredSessionFeedAgentTurnSegment(
            id: UUID(),
            isOpen: true,
            reasoning: StructuredSessionFeedAgentTurnReasoningSegment(markdownBody: "Plan."),
            tools: [StructuredSessionFeedAgentTurnToolSegment(activityItemID: UUID(), callPreview: "tool: run")],
            finalAnswer: nil
        )
        let defaults = structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn)
        #expect(defaults.reasoning == true)
        #expect(defaults.tools == false)
        #expect(defaults.toolRows == [false])
    }

    @Test func agentTurnDisclosureDefaultsCollapseReasoningAndToolsWhenTurnComplete() {
        let toolID = UUID()
        let turn = StructuredSessionFeedAgentTurnSegment(
            id: UUID(),
            isOpen: false,
            reasoning: StructuredSessionFeedAgentTurnReasoningSegment(markdownBody: "Done thinking."),
            tools: [StructuredSessionFeedAgentTurnToolSegment(activityItemID: toolID, callPreview: "bash: ls")],
            finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment(text: "ok", isStreaming: false)
        )
        let defaults = structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn)
        #expect(defaults.reasoning == false)
        #expect(defaults.tools == false)
        #expect(defaults.toolRows == [false])
    }
}