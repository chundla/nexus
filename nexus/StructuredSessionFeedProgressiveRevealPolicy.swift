import Foundation
import NexusSessionPresentation

/// Structured feed startup: defer mounting the full `LazyVStack` on first paint (#225 macOS, iOS Remote Client).
enum StructuredSessionFeedProgressiveRevealPolicy {
    static var usesProgressiveActivityRowReveal: Bool {
        true
    }

    static var initialVisibleTailRowCount: Int {
        3
    }

    static var visibleTailRowsPerRevealBatch: Int {
        3
    }

    static var allowsMarkdownHydrationDuringProgressiveReveal: Bool {
        true
    }

    static func visibleActivityRows(
        in feed: StructuredSessionFeedPresentation,
        visibleTailRowCount: Int
    ) -> [StructuredSessionActivityRow] {
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
        guard usesProgressiveActivityRowReveal else {
            return feed.thinkingIndicator != nil
        }
        guard visibleTailRowCount >= feed.activityRows.count else {
            return false
        }
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