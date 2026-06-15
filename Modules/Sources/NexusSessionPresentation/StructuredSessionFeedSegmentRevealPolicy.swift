import Foundation
import NexusDomain

/// Progressive structured-feed reveal keyed on composite **feed segment** identity (#225, ADR 0037).
public enum StructuredSessionFeedSegmentRevealPolicy {
    public static var usesProgressiveFeedSegmentReveal: Bool {
        true
    }

    public static var initialVisibleTailSegmentCount: Int {
        3
    }

    public static var visibleTailSegmentsPerRevealBatch: Int {
        3
    }

    public static func visibleFeedSegments(
        in feed: StructuredSessionFeedPresentation,
        visibleTailSegmentCount: Int
    ) -> [StructuredSessionFeedSegment] {
        guard let segments = feed.feedSegments, segments.isEmpty == false else {
            return []
        }
        guard usesProgressiveFeedSegmentReveal, visibleTailSegmentCount < segments.count else {
            return segments
        }
        guard visibleTailSegmentCount > 0 else {
            return []
        }
        return Array(segments.suffix(visibleTailSegmentCount))
    }

    public static func shouldShowThinkingIndicator(
        in feed: StructuredSessionFeedPresentation,
        visibleTailSegmentCount: Int
    ) -> Bool {
        guard feed.thinkingIndicator != nil else {
            return false
        }
        _ = visibleTailSegmentCount
        return true
    }

    public static func isFeedMarkdownHydrationAllowed(visibleTailSegmentCount: Int, totalFeedSegmentCount: Int) -> Bool {
        guard usesProgressiveFeedSegmentReveal else {
            return true
        }
        return visibleTailSegmentCount >= totalFeedSegmentCount
    }

    /// Keeps progressive tail reveal in sync when the feed grows after the initial reveal pass (#225 / ADR 0037).
    /// Without this, `visibleTailSegmentCount` can stay at the count from first paint while new user/tools segments append.
    public static func synchronizedVisibleTailSegmentCount(
        currentVisibleCount: Int,
        totalFeedSegmentCount: Int
    ) -> Int {
        guard usesProgressiveFeedSegmentReveal else {
            return totalFeedSegmentCount
        }
        guard totalFeedSegmentCount > 0 else {
            return 0
        }
        if currentVisibleCount <= 0 {
            return min(initialVisibleTailSegmentCount, totalFeedSegmentCount)
        }
        return min(max(currentVisibleCount, totalFeedSegmentCount), totalFeedSegmentCount)
    }
}

public struct StructuredSessionAgentTurnDisclosureExpansionDefaults: Equatable, Sendable {
    public let tools: Bool
    public let toolRows: [Bool]

    public init(tools: Bool, toolRows: [Bool]) {
        self.tools = tools
        self.toolRows = toolRows
    }
}

/// ADR 0037: per-row reasoning/tool bubbles start collapsed; user expands on tap.
public func structuredSessionAgentTurnDisclosureExpansionDefaults(
    for turn: StructuredSessionFeedAgentTurnSegment
) -> StructuredSessionAgentTurnDisclosureExpansionDefaults {
    let toolCount = turn.stackItems.filter {
        if case .tool = $0 { return true }
        return false
    }.count
    return StructuredSessionAgentTurnDisclosureExpansionDefaults(
        tools: false,
        toolRows: Array(repeating: false, count: toolCount)
    )
}

public func structuredSessionOpenAgentTurnHasReasoningContent(
    in feedSegments: [StructuredSessionFeedSegment]?
) -> Bool {
    guard let segments = feedSegments, segments.isEmpty == false else {
        return false
    }
    for segment in segments.reversed() {
        guard case .agentTurn(let turn) = segment else {
            continue
        }
        if turn.isOpen {
            return turn.stackItems.contains {
                if case .reasoning = $0 { return true }
                return false
            }
        }
        return false
    }
    return false
}

public func structuredSessionOpenAgentTurnHasReasoningContent(for screen: SessionScreen) -> Bool {
    structuredSessionOpenAgentTurnHasReasoningContent(in: structuredSessionAgentTurnFeedSegments(for: screen))
}

/// Open **Agent Turn** on the composite feed (presentation), independent of provider `isStreaming` gaps.
public func structuredSessionOpenAgentTurnSegment(
    in feedSegments: [StructuredSessionFeedSegment]?
) -> StructuredSessionFeedAgentTurnSegment? {
    guard let feedSegments, feedSegments.isEmpty == false else {
        return nil
    }
    for segment in feedSegments.reversed() {
        guard case .agentTurn(let turn) = segment else {
            continue
        }
        if turn.isOpen {
            return turn
        }
        return nil
    }
    return nil
}

/// UI turn-in-progress: service flag or an open turn segment (Pi can clear `isStreaming` mid-turn).
public func structuredSessionEffectiveAgentTurnInProgress(for screen: SessionScreen) -> Bool {
    if screen.isAgentTurnInProgress {
        return true
    }
    return structuredSessionOpenAgentTurnSegment(
        in: structuredSessionAgentTurnFeedSegments(for: screen)
    ) != nil
}

public func structuredSessionEffectiveAgentTurnInProgress(
    for presentation: FocusedStructuredSessionPresentation
) -> Bool {
    if presentation.feed.thinkingIndicator != nil {
        return true
    }
    return structuredSessionOpenAgentTurnSegment(in: presentation.feed.feedSegments) != nil
}