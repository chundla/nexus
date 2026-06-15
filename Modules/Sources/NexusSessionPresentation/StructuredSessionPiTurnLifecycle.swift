import Foundation
import NexusDomain

/// Pi can emit `message_end` (assistant sub-message done) before `turn_end`. Segment `isOpen` must follow `turn_end`, not only `isStreaming`.
func structuredSessionPiFeedSegmentTurnInProgress(for screen: SessionScreen) -> Bool {
    if screen.isAgentTurnInProgress {
        return true
    }
    guard screen.session.providerID == .pi else {
        return false
    }
    return structuredSessionPiProviderTurnAwaitingTurnEnd(
        activityItems: screen.activityItems,
        providerEvents: screen.providerEvents
    )
}

/// After the last prompt-anchored user message, the turn is still open until a `turn_end` provider event arrives.
func structuredSessionPiProviderTurnAwaitingTurnEnd(
    activityItems: [SessionActivityItem],
    providerEvents: [SessionProviderEvent]
) -> Bool {
    guard let lastUserIndex = activityItems.lastIndex(where: {
        structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage($0)
    }) else {
        return false
    }
    let tail = activityItems[activityItems.index(after: lastUserIndex)...]
    guard tail.isEmpty == false else {
        return false
    }
    let userPromptOrdinal = activityItems[0...lastUserIndex].filter {
        structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage($0)
    }.count
    guard providerEvents.isEmpty == false else {
        // Unit tests and history snapshots often omit provider events; do not infer an open turn.
        return false
    }
    let turnEndCount = providerEvents.filter { $0.type == "turn_end" }.count
    return turnEndCount < userPromptOrdinal
}