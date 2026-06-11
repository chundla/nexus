#if os(macOS)
import Foundation
import NexusSessionPresentation
import Testing
@testable import nexus

struct StructuredSessionFeedMacOSStartupPolicyTests {
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

        #expect(StructuredSessionFeedMacOSStartupPolicy.initialVisibleTailRowCount == 3)
        #expect(StructuredSessionFeedMacOSStartupPolicy.visibleTailRowsPerRevealBatch == 3)
        #expect(StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 0).isEmpty)
        let four = StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 4)
        #expect(four.count == 4)
        #expect(four.map(\.title) == (16 ..< 20).map { "Row \($0)" })
        #expect(StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 20).count == 20)
    }

    @Test func thinkingIndicatorHiddenUntilFullReveal() {
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

        #expect(StructuredSessionFeedMacOSStartupPolicy.shouldShowThinkingIndicator(in: feed, visibleTailRowCount: 0) == false)
        #expect(StructuredSessionFeedMacOSStartupPolicy.shouldShowThinkingIndicator(in: feed, visibleTailRowCount: 1) == true)
    }

    @Test func markdownHydrationAllowedDuringProgressiveReveal() {
        #expect(StructuredSessionFeedMacOSStartupPolicy.allowsMarkdownHydrationDuringProgressiveReveal)
        #expect(
            StructuredSessionFeedMacOSStartupPolicy.isFeedMarkdownHydrationAllowed(
                visibleTailRowCount: 4,
                totalActivityRowCount: 20
            )
        )
        #expect(
            StructuredSessionFeedMacOSStartupPolicy.isFeedMarkdownHydrationAllowed(
                visibleTailRowCount: 20,
                totalActivityRowCount: 20
            )
        )
    }

    @Test func progressiveRevealUsesThreePlusThreeBatches() {
        #expect(StructuredSessionFeedMacOSStartupPolicy.initialVisibleTailRowCount == 3)
        #expect(StructuredSessionFeedMacOSStartupPolicy.visibleTailRowsPerRevealBatch == 3)
    }
}
#endif