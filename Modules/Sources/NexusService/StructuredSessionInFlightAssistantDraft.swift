#if os(macOS)
    import Foundation
    import NexusDomain

    /// Materializes visible assistant text for structured sessions whose provider streams into
    /// provider facts/events before appending a finalized `Pi:` activity row.
    func structuredSessionInFlightAssistantMessageText(for screen: SessionScreen) -> String? {
        guard screen.primarySurface == .structuredActivityFeed,
            screen.isAgentTurnInProgress
        else {
            return nil
        }

        switch screen.session.providerID {
        case .pi:
            if let draft = screen.providerFacts.liveAssistantDraftText?.trimmingCharacters(in: .whitespacesAndNewlines),
                draft.isEmpty == false
            {
                return "Pi: \(draft)"
            }
            if let draft = piStructuredSessionLiveAssistantDraftText(from: screen.providerEvents) {
                return "Pi: \(draft)"
            }
            return nil
        case .codex, .ibmBob, .claude:
            return nil
        }
    }

    func structuredSessionScreenAugmentedForPersistence(_ screen: SessionScreen) -> SessionScreen {
        guard let messageText = structuredSessionInFlightAssistantMessageText(for: screen) else {
            return screen
        }

        if screen.activityItems.contains(where: { $0.kind == .message && $0.text == messageText }) {
            return screen
        }

        return SessionScreen(
            session: screen.session,
            primarySurface: screen.primarySurface,
            controller: screen.controller,
            transcript: screen.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows,
            activityItems: screen.activityItems + [SessionActivityItem(kind: .message, text: messageText)],
            approvalRequests: screen.approvalRequests,
            extensionUI: screen.extensionUI,
            slashCommands: screen.slashCommands,
            providerEvents: screen.providerEvents,
            providerFacts: screen.providerFacts,
            finalOutputDiagnostic: screen.finalOutputDiagnostic,
            isAgentTurnInProgress: screen.isAgentTurnInProgress,
            visibleLines: screen.visibleLines,
            styledVisibleLines: screen.styledVisibleLines,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
            cursorVisible: screen.cursorVisible
        )
    }

    private func piStructuredSessionLiveAssistantDraftText(from providerEvents: [SessionProviderEvent]) -> String? {
        var draft = ""

        for event in providerEvents {
            guard let data = event.rawPayload.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = payload["type"] as? String
            else {
                continue
            }

            switch type {
            case "message_update":
                guard let assistantMessageEvent = payload["assistantMessageEvent"] as? [String: Any],
                    assistantMessageEvent["type"] as? String == "text_delta",
                    let delta = assistantMessageEvent["delta"] as? String
                else {
                    continue
                }
                draft += delta
            case "turn_end", "message_end":
                draft = ""
            default:
                continue
            }
        }

        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDraft.isEmpty ? nil : trimmedDraft
    }
#endif
