#if os(macOS)
import Foundation
import NexusSessionPresentation

/// macOS structured feed startup: split first `ScrollView` layout from bulk `LazyVStack` row mount (#225).
enum StructuredSessionFeedMacOSStartupPolicy {
    /// When true, activity rows are not mounted on the first feed `onAppear` turn; tail rows appear in batches.
    static var usesProgressiveActivityRowReveal: Bool {
        true
    }

    /// First batch after the defer turn: only the last N rows (bottom-edge follow stays near the tail).
    static var initialVisibleTailRowCount: Int {
        4
    }

    /// Additional rows revealed per main-actor turn (`Task.yield` between batches).
    static var visibleTailRowsPerRevealBatch: Int {
        4
    }

    /// When false, row `StructuredSessionMarkdownText` stays plain until full reveal (#225).
    static var allowsMarkdownHydrationDuringProgressiveReveal: Bool {
        false
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
        guard allowsMarkdownHydrationDuringProgressiveReveal else {
            return visibleTailRowCount >= totalActivityRowCount
        }
        return true
    }
}
#endif