import Foundation
import NexusDomain

/// Standalone `Pi:` assistant segment after an open agent-turn card (interim text during the same user prompt).
public func structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(
    in feedSegments: [StructuredSessionFeedSegment]?
) -> Bool {
    guard let feedSegments, feedSegments.count >= 2 else {
        return false
    }
    guard case .agentTurn(let turn) = feedSegments[feedSegments.count - 2],
          turn.isOpen else {
        return false
    }
    guard case .standalone(let item) = feedSegments.last,
          structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(item) else {
        return false
    }
    return true
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

/// UI turn-in-progress: service flag, Pi `turn_end` lifecycle, open turn segment, or interim `Pi:` after open turn.
public func structuredSessionEffectiveAgentTurnInProgress(for screen: SessionScreen) -> Bool {
    if screen.isAgentTurnInProgress {
        return true
    }
    if screen.session.providerID == .pi,
       structuredSessionPiProviderTurnAwaitingTurnEnd(
           activityItems: screen.activityItems,
           providerEvents: screen.providerEvents
       ) {
        return true
    }
    let segments = structuredSessionAgentTurnFeedSegments(for: screen)
    if structuredSessionOpenAgentTurnSegment(in: segments) != nil {
        return true
    }
    return structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(in: segments)
}

public func structuredSessionEffectiveAgentTurnInProgress(
    for presentation: FocusedStructuredSessionPresentation
) -> Bool {
    if presentation.feed.thinkingIndicator != nil {
        return true
    }
    // Feed was built with segment open state; re-check segments before chrome-only flags.
    let segments = presentation.feed.feedSegments
    if structuredSessionOpenAgentTurnSegment(in: segments) != nil {
        return true
    }
    return structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(in: segments)
}