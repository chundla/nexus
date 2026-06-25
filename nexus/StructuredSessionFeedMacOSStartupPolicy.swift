#if os(macOS)
    import Foundation
    import NexusSessionPresentation

    /// macOS structured feed startup (#225); implementation shared with iOS via `StructuredSessionFeedProgressiveRevealPolicy`.
    enum StructuredSessionFeedMacOSStartupPolicy {
        static var usesProgressiveActivityRowReveal: Bool {
            // Progressive tail batches remount LazyVStack segments and can spin ScrollView layout (#hang).
            false
        }

        static var initialVisibleTailRowCount: Int {
            StructuredSessionFeedProgressiveRevealPolicy.initialVisibleTailRowCount
        }

        static var visibleTailRowsPerRevealBatch: Int {
            StructuredSessionFeedProgressiveRevealPolicy.visibleTailRowsPerRevealBatch
        }

        static func nextVisibleTailRowCount(currentVisibleCount: Int, totalRowCount: Int) -> Int {
            StructuredSessionFeedProgressiveRevealPolicy.nextVisibleTailRowCount(
                currentVisibleCount: currentVisibleCount,
                totalRowCount: totalRowCount
            )
        }

        static var allowsMarkdownHydrationDuringProgressiveReveal: Bool {
            StructuredSessionFeedProgressiveRevealPolicy.allowsMarkdownHydrationDuringProgressiveReveal
        }

        static func visibleActivityRows(
            in feed: StructuredSessionFeedPresentation,
            visibleTailRowCount: Int
        ) -> [StructuredSessionActivityRow] {
            guard usesProgressiveActivityRowReveal else {
                if feed.feedSegments != nil {
                    return structuredSessionActivityRows(in: feed, visibleTailItemCount: feed.activityRows.count)
                }
                return feed.activityRows
            }
            return StructuredSessionFeedProgressiveRevealPolicy.visibleActivityRows(
                in: feed,
                visibleTailRowCount: visibleTailRowCount
            )
        }

        static func shouldShowThinkingIndicator(
            in feed: StructuredSessionFeedPresentation,
            visibleTailRowCount: Int
        ) -> Bool {
            guard usesProgressiveActivityRowReveal else {
                return feed.thinkingIndicator != nil
            }
            return StructuredSessionFeedProgressiveRevealPolicy.shouldShowThinkingIndicator(
                in: feed,
                visibleTailRowCount: visibleTailRowCount
            )
        }

        static func isFeedMarkdownHydrationAllowed(visibleTailRowCount: Int, totalActivityRowCount: Int) -> Bool {
            // Row reveal is disabled on macOS, but markdown hydration still follows the shared progressive gate (#225).
            StructuredSessionFeedProgressiveRevealPolicy.isFeedMarkdownHydrationAllowed(
                visibleTailRowCount: visibleTailRowCount,
                totalActivityRowCount: totalActivityRowCount
            )
        }
    }
#endif
