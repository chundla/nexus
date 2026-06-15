import Foundation
import NexusSessionPresentation
import Testing
@testable import nexus

struct StructuredSessionFeedProgressiveRevealPolicyTests {
    @Test func visibleActivityRowsRevealsTailFirstInBatches() {
        let rows = (0 ..< 20).map { index in
            StructuredSessionActivityRow(
                id: UUID(),
                title: "Row \(index)",
                systemImage: "message",
                text: "text \(index)",
                emphasis: .accent
            )
        }
        let feed = StructuredSessionFeedPresentation(
            copy: StructuredSessionPresentationCopy(
                emptyStateTitle: "Empty",
                emptyStateDescription: "None",
                composerPlaceholder: "Type"
            ),
            activityRows: rows,
            pendingApprovalRequests: [],
            thinkingIndicator: StructuredSessionThinkingIndicator(text: "Thinking…")
        )

        #expect(StructuredSessionFeedProgressiveRevealPolicy.initialVisibleTailRowCount == 3)
        #expect(StructuredSessionFeedProgressiveRevealPolicy.visibleTailRowsPerRevealBatch == 3)
        #expect(StructuredSessionFeedProgressiveRevealPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 0).isEmpty)
        let four = StructuredSessionFeedProgressiveRevealPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 4)
        #expect(four.count == 4)
        #expect(four.map(\.title) == (16 ..< 20).map { "Row \($0)" })
        #expect(StructuredSessionFeedProgressiveRevealPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 20).count == 20)
    }

    @Test func thinkingIndicatorVisibleDuringProgressiveReveal() {
        let row = StructuredSessionActivityRow(
            id: UUID(),
            title: "Row",
            systemImage: "message",
            text: "text",
            emphasis: .accent
        )
        let feed = StructuredSessionFeedPresentation(
            copy: StructuredSessionPresentationCopy(
                emptyStateTitle: "Empty",
                emptyStateDescription: "None",
                composerPlaceholder: "Type"
            ),
            activityRows: [row],
            pendingApprovalRequests: [],
            thinkingIndicator: StructuredSessionThinkingIndicator(text: "Thinking…")
        )

        #expect(StructuredSessionFeedProgressiveRevealPolicy.shouldShowThinkingIndicator(in: feed, visibleTailRowCount: 0) == true)
        #expect(StructuredSessionFeedProgressiveRevealPolicy.shouldShowThinkingIndicator(in: feed, visibleTailRowCount: 1) == true)
    }
}