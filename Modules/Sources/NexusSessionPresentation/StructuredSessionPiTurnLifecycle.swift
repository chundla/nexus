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
    if structuredSessionPiProviderTurnAwaitingTurnEnd(
        activityItems: screen.activityItems,
        providerEvents: screen.providerEvents
    ) {
        return true
    }
    if let draft = screen.providerFacts.liveAssistantDraftText?.trimmingCharacters(in: .whitespacesAndNewlines),
       draft.isEmpty == false
    {
        return true
    }
    return structuredSessionPiActivityTailSuggestsOpenTurn(screen.activityItems)
}

/// Live observation often omits `providerEvents`; infer an open turn when post-prompt work continues after a provisional `Pi:` line.
func structuredSessionPiActivityTailSuggestsOpenTurn(_ activityItems: [SessionActivityItem]) -> Bool {
    guard
        let lastUserIndex = activityItems.lastIndex(where: {
            structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage($0)
        })
    else {
        return false
    }
    let tail = Array(activityItems[activityItems.index(after: lastUserIndex)...])
    guard tail.isEmpty == false else {
        return false
    }

    var firstPrimaryPiIndex: Int?
    for (index, item) in tail.enumerated() {
        if structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(item) {
            firstPrimaryPiIndex = index
            break
        }
    }

    if let firstPrimaryPiIndex {
        let interimPiBody =
            structuredSessionPiPrimaryAssistantBody(from: tail[firstPrimaryPiIndex].text) ?? ""
        if firstPrimaryPiIndex < tail.count - 1 {
            if let last = tail.last,
                structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(last)
            {
                return false
            }
            // Long interim `Pi:` with more activity after is a closed multi-phase turn (composite card absorbs tail).
            guard interimPiBody.count < 40 else {
                return false
            }
            let afterPi = Array(tail[(firstPrimaryPiIndex + 1)...])
            if afterPi.contains(where: { $0.kind == .error }) {
                return false
            }
            if structuredSessionPiTailIsOpenTurnContinuationAfterInterimAssistant(afterPi) {
                return true
            }
            return false
        }
        let beforePi = Array(tail.prefix(firstPrimaryPiIndex))
        guard beforePi.count <= 2 else {
            return false
        }
        if beforePi.contains(where: { $0.kind == .command }) {
            // Short trailing `Pi:` after tools is the final answer; long lines are still in-flight status.
            return interimPiBody.count >= 40
        }
        if beforePi.contains(where: { structuredSessionPiFeedSegmentIsThoughtsStatus($0) }) {
            return interimPiBody.count >= 40
        }
        return false
    }

    return tail.contains { item in
        item.kind == .command || structuredSessionPiFeedSegmentIsThoughtsStatus(item) || item.kind == .progress
    }
}

/// Post–interim-`Pi:` thoughts, tools, and progress still belong to the same user prompt until `turn_end`.
private func structuredSessionPiTailIsOpenTurnContinuationAfterInterimAssistant(_ items: [SessionActivityItem]) -> Bool {
    guard items.isEmpty == false else {
        return false
    }
    guard
        items.allSatisfy({
            $0.kind == .command
                || structuredSessionPiFeedSegmentIsThoughtsStatus($0)
                || $0.kind == .progress
                || $0.kind == .error
                || structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage($0)
        })
    else {
        return false
    }
    return items.contains {
        $0.kind == .command || structuredSessionPiFeedSegmentIsThoughtsStatus($0) || $0.kind == .progress
    }
}

private func structuredSessionPiThoughtsAppearBeforeAnyCommand(in items: [SessionActivityItem]) -> Bool {
    var sawCommand = false
    for item in items {
        if item.kind == .command {
            sawCommand = true
        }
        if structuredSessionPiFeedSegmentIsThoughtsStatus(item), sawCommand == false {
            return true
        }
    }
    return false
}

/// After the last prompt-anchored user message, the turn is still open until a `turn_end` provider event arrives.
func structuredSessionPiProviderTurnAwaitingTurnEnd(
    activityItems: [SessionActivityItem],
    providerEvents: [SessionProviderEvent]
) -> Bool {
    guard
        let lastUserIndex = activityItems.lastIndex(where: {
            structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage($0)
        })
    else {
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
