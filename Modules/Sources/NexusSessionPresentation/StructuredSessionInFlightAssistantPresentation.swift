import Foundation
import NexusDomain

/// Visible `Pi:` / assistant message text synthesized from provider facts or events (not a sealed activity row).
public func structuredSessionInFlightAssistantMessageActivityText(for screen: SessionScreen) -> String? {
    guard screen.primarySurface == .structuredActivityFeed,
          screen.isAgentTurnInProgress else {
        return nil
    }

    switch screen.session.providerID {
    case .pi:
        if let draft = screen.providerFacts.liveAssistantDraftText?.trimmingCharacters(in: .whitespacesAndNewlines),
           draft.isEmpty == false {
            return "Pi: \(draft)"
        }
        if let draft = piStructuredSessionLiveAssistantDraftTextFromProviderEvents(screen.providerEvents) {
            return "Pi: \(draft)"
        }
        return nil
    case .codex, .ibmBob, .claude:
        return nil
    }
}

/// Hides duplicate assistant placeholders while an agent turn is open (composite feed + flat rows).
public func structuredSessionShouldSuppressVisibleInFlightAssistantActivityItem(
    _ item: SessionActivityItem,
    screen: SessionScreen
) -> Bool {
    guard screen.isAgentTurnInProgress else {
        return false
    }

    switch screen.session.providerID {
    case .pi:
        guard structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(item) else {
            return false
        }
        if let inFlight = structuredSessionInFlightAssistantMessageActivityText(for: screen),
           item.text == inFlight {
            return true
        }
        // Any `Pi:` message during an open turn is absorbed by the turn stack, not shown as a standalone bubble.
        return true
    case .codex:
        return structuredSessionCodexFeedSegmentIsPrimaryCodexAssistantMessage(item)
    case .ibmBob:
        return structuredSessionIBMBobPlainAssistantMessageBody(from: item) != nil
    case .claude:
        return false
    }
}

public func structuredSessionActivityItemsForFeedPresentation(for screen: SessionScreen) -> [SessionActivityItem] {
    screen.activityItems.filter {
        structuredSessionShouldSuppressVisibleInFlightAssistantActivityItem($0, screen: screen) == false
    }
}

private func piStructuredSessionLiveAssistantDraftTextFromProviderEvents(_ providerEvents: [SessionProviderEvent]) -> String? {
    var draft = ""

    for event in providerEvents {
        guard let data = event.rawPayload.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String else {
            continue
        }

        switch type {
        case "message_update":
            guard let assistantMessageEvent = payload["assistantMessageEvent"] as? [String: Any],
                  assistantMessageEvent["type"] as? String == "text_delta",
                  let delta = assistantMessageEvent["delta"] as? String else {
                continue
            }
            draft += delta
        case "turn_end":
            draft = ""
        case "message_end":
            if let message = payload["message"] as? [String: Any],
               message["role"] as? String == "assistant" {
                draft = ""
            }
        default:
            continue
        }
    }

    let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedDraft.isEmpty ? nil : trimmedDraft
}