import Foundation
import NexusDomain

/// File-scoped merge closure so `@MainActor` models can pass it to `CoalescingMainActorValuePump`
/// without inheriting MainActor on the function value (Swift 6).
let preferredSessionScreenMergePendingValue: CoalescingMainActorValuePump<SessionScreen>.MergePendingValue = {
    pending, candidate in
    preferredSessionScreenUpdate(pending: pending, new: candidate)
}

nonisolated func sessionScreenAppearsToAdvance(_ candidate: SessionScreen, beyond current: SessionScreen) -> Bool {
    guard candidate.session.id == current.session.id else {
        return false
    }

    if candidate == current {
        return true
    }

    if current.isAgentTurnInProgress, candidate.isAgentTurnInProgress == false {
        return true
    }

    if current.isAgentTurnInProgress == false, candidate.isAgentTurnInProgress {
        return false
    }

    if candidate.activityItems.count != current.activityItems.count {
        return candidate.activityItems.count > current.activityItems.count
    }

    if candidate.transcript.count != current.transcript.count {
        return candidate.transcript.count > current.transcript.count
    }

    let currentProviderEventCount = sessionScreenProviderEventCount(current)
    let candidateProviderEventCount = sessionScreenProviderEventCount(candidate)
    if candidateProviderEventCount != currentProviderEventCount {
        return candidateProviderEventCount > currentProviderEventCount
    }

    return true
}

nonisolated func preferredSessionScreenUpdate(pending: SessionScreen, new candidate: SessionScreen) -> SessionScreen {
    guard pending.session.id == candidate.session.id else {
        return candidate
    }

    let candidateAdvances = sessionScreenAppearsToAdvance(candidate, beyond: pending)
    let pendingAdvances = sessionScreenAppearsToAdvance(pending, beyond: candidate)

    if candidateAdvances && pendingAdvances == false {
        return candidate
    }

    if pendingAdvances && candidateAdvances == false {
        return pending
    }

    return candidate
}

nonisolated private func sessionScreenProviderEventCount(_ screen: SessionScreen) -> Int {
    screen.providerFacts.providerEventCount == 0 ? screen.providerEvents.count : screen.providerFacts.providerEventCount
}
