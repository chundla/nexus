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
        guard let segments = feed.feedSegments, segments.isEmpty == false else {
            return true
        }
        guard usesProgressiveFeedSegmentReveal else {
            return true
        }
        guard visibleTailSegmentCount >= segments.count else {
            return false
        }
        return true
    }

    public static func isFeedMarkdownHydrationAllowed(visibleTailSegmentCount: Int, totalFeedSegmentCount: Int) -> Bool {
        guard usesProgressiveFeedSegmentReveal else {
            return true
        }
        return visibleTailSegmentCount >= totalFeedSegmentCount
    }
}

public struct StructuredSessionAgentTurnDisclosureExpansionDefaults: Equatable, Sendable {
    public let reasoning: Bool
    public let tools: Bool
    public let toolRows: [Bool]

    public init(reasoning: Bool, tools: Bool, toolRows: [Bool]) {
        self.reasoning = reasoning
        self.tools = tools
        self.toolRows = toolRows
    }
}

/// ADR 0037 / CONTEXT: Reasoning expanded while the open **Agent Turn** is in progress; Tools collapsed.
public func structuredSessionAgentTurnDisclosureExpansionDefaults(
    for turn: StructuredSessionFeedAgentTurnSegment
) -> StructuredSessionAgentTurnDisclosureExpansionDefaults {
    StructuredSessionAgentTurnDisclosureExpansionDefaults(
        reasoning: turn.isOpen && turn.reasoning != nil,
        tools: false,
        toolRows: turn.tools.map { _ in false }
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
            return turn.reasoning != nil
        }
        return false
    }
    return false
}

public func structuredSessionOpenAgentTurnHasReasoningContent(for screen: SessionScreen) -> Bool {
    structuredSessionOpenAgentTurnHasReasoningContent(in: structuredSessionPiFeedSegments(for: screen))
}