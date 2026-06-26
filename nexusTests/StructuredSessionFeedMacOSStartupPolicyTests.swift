#if os(macOS)
    import Foundation
    import NexusSessionPresentation
    import Testing
    @testable import nexus

    struct StructuredSessionFeedMacOSStartupPolicyTests {
        @Test func progressiveRevealDisabledOnMacOS() {
            #expect(StructuredSessionFeedMacOSStartupPolicy.usesProgressiveActivityRowReveal == false)
        }

        @Test func visibleActivityRowsRevealsTailFirstInBatches() {
            let rows = (0..<20).map { index in
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
            #expect(
                StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 0).count
                    == 20)
            let four = StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 4)
            #expect(four.count == 20)
            #expect(
                StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(in: feed, visibleTailRowCount: 20).count
                    == 20)
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

            #expect(
                StructuredSessionFeedMacOSStartupPolicy.shouldShowThinkingIndicator(in: feed, visibleTailRowCount: 0)
                    == true)
            #expect(
                StructuredSessionFeedMacOSStartupPolicy.shouldShowThinkingIndicator(in: feed, visibleTailRowCount: 1)
                    == true)
        }

        @Test func markdownHydrationDeferredUntilFullTailRevealed() {
            #expect(StructuredSessionFeedMacOSStartupPolicy.allowsMarkdownHydrationDuringProgressiveReveal == false)
            #expect(
                StructuredSessionFeedMacOSStartupPolicy.isFeedMarkdownHydrationAllowed(
                    visibleTailRowCount: 4,
                    totalActivityRowCount: 20
                ) == false
            )
            #expect(
                StructuredSessionFeedMacOSStartupPolicy.isFeedMarkdownHydrationAllowed(
                    visibleTailRowCount: 20,
                    totalActivityRowCount: 20
                )
            )
        }

        @Test func nextVisibleTailRowCountForwardsToSharedDoublingPolicy() {
            #expect(
                StructuredSessionFeedMacOSStartupPolicy.nextVisibleTailRowCount(
                    currentVisibleCount: 3,
                    totalRowCount: 100
                ) == 6
            )
        }
    }
#endif
