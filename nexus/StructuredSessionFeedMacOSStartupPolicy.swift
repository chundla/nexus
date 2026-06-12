#if os(macOS)
import Foundation
import NexusSessionPresentation

/// macOS structured feed startup (#225); implementation shared with iOS via `StructuredSessionFeedProgressiveRevealPolicy`.
enum StructuredSessionFeedMacOSStartupPolicy {
    static var usesProgressiveActivityRowReveal: Bool {
        StructuredSessionFeedProgressiveRevealPolicy.usesProgressiveActivityRowReveal
    }

    static var initialVisibleTailRowCount: Int {
        StructuredSessionFeedProgressiveRevealPolicy.initialVisibleTailRowCount
    }

    static var visibleTailRowsPerRevealBatch: Int {
        StructuredSessionFeedProgressiveRevealPolicy.visibleTailRowsPerRevealBatch
    }

    static var allowsMarkdownHydrationDuringProgressiveReveal: Bool {
        StructuredSessionFeedProgressiveRevealPolicy.allowsMarkdownHydrationDuringProgressiveReveal
    }

    static func visibleActivityRows(
        in feed: StructuredSessionFeedPresentation,
        visibleTailRowCount: Int
    ) -> [StructuredSessionActivityRow] {
        StructuredSessionFeedProgressiveRevealPolicy.visibleActivityRows(
            in: feed,
            visibleTailRowCount: visibleTailRowCount
        )
    }

    static func shouldShowThinkingIndicator(
        in feed: StructuredSessionFeedPresentation,
        visibleTailRowCount: Int
    ) -> Bool {
        StructuredSessionFeedProgressiveRevealPolicy.shouldShowThinkingIndicator(
            in: feed,
            visibleTailRowCount: visibleTailRowCount
        )
    }

    static func isFeedMarkdownHydrationAllowed(visibleTailRowCount: Int, totalActivityRowCount: Int) -> Bool {
        StructuredSessionFeedProgressiveRevealPolicy.isFeedMarkdownHydrationAllowed(
            visibleTailRowCount: visibleTailRowCount,
            totalActivityRowCount: totalActivityRowCount
        )
    }
}
#endif