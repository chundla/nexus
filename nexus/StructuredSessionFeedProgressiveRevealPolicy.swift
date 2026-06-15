import Foundation
import NexusSessionPresentation

/// Structured feed startup: defer mounting the full `LazyVStack` on first paint (#225 macOS, iOS Remote Client).
enum StructuredSessionFeedProgressiveRevealPolicy {
    static var usesProgressiveActivityRowReveal: Bool {
        StructuredSessionFeedSegmentRevealPolicy.usesProgressiveFeedSegmentReveal
    }

    static var initialVisibleTailRowCount: Int {
        StructuredSessionFeedSegmentRevealPolicy.initialVisibleTailSegmentCount
    }

    static var visibleTailRowsPerRevealBatch: Int {
        StructuredSessionFeedSegmentRevealPolicy.visibleTailSegmentsPerRevealBatch
    }

    static var allowsMarkdownHydrationDuringProgressiveReveal: Bool {
        true
    }

    static func visibleActivityRows(
        in feed: StructuredSessionFeedPresentation,
        visibleTailRowCount: Int
    ) -> [StructuredSessionActivityRow] {
        if feed.feedSegments != nil {
            return structuredSessionActivityRows(in: feed, visibleTailItemCount: visibleTailRowCount)
        }
        let rows = feed.activityRows
        guard usesProgressiveActivityRowReveal, visibleTailRowCount < rows.count else {
            return rows
        }
        guard visibleTailRowCount > 0 else {
            return []
        }
        return Array(rows.suffix(visibleTailRowCount))
    }

    static func shouldShowThinkingIndicator(
        in feed: StructuredSessionFeedPresentation,
        visibleTailRowCount: Int
    ) -> Bool {
        if feed.feedSegments != nil {
            return StructuredSessionFeedSegmentRevealPolicy.shouldShowThinkingIndicator(
                in: feed,
                visibleTailSegmentCount: visibleTailRowCount
            )
        }
        _ = visibleTailRowCount
        return feed.thinkingIndicator != nil
    }

    static func isFeedMarkdownHydrationAllowed(visibleTailRowCount: Int, totalActivityRowCount: Int) -> Bool {
        guard usesProgressiveActivityRowReveal else {
            return true
        }
        if allowsMarkdownHydrationDuringProgressiveReveal {
            return true
        }
        return visibleTailRowCount >= totalActivityRowCount
    }
}