import Foundation
import NexusDomain

nonisolated enum StructuredFeedProfilingFixture {
    static let updateIntervalNanoseconds: UInt64 = 200_000_000
    private static let seededTurnCount = 28
    private static let modelIdentifier = "xai/grok-4.3"
    private static let totalTokenLimit = 128_000
    private static let draftPrefixFractions: [Double] = [0.18, 0.38, 0.62, 0.85]

    enum Phase: Equatable {
        case drafting(step: Int)
        case finalized
        case finalizedDwell(remaining: Int)  // post-turn_end dwell: isAgent=false, finalOutputDiagnostic present, activity rows stable (no appends), but providerEventSequence and extensionUI notifications continue to tick every 200 ms. Provides a reliable multi-tick window (~1 s) for observers to sample turn-end state before the next turn's startTurn appends You+progress rows.
    }

    private static let postTurnDwellTicks = 5

    struct State {
        var turnIndex: Int
        var phase: Phase
        var transcript: String
        var activityItems: [SessionActivityItem]
        var providerEventSequence: Int
    }

    static func makeInitialState() -> State {
        var transcriptLines = ["Pi shared Session stream connected"]
        var activityItems = [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        var providerEventSequence = 0

        for turnIndex in 0..<seededTurnCount {
            let prompt = userPrompt(for: turnIndex)
            let assistantMessage = finalizedAssistantMessage(for: turnIndex)

            activityItems.append(SessionActivityItem(kind: .message, text: "You: \(prompt)"))
            activityItems.append(
                SessionActivityItem(
                    kind: .progress,
                    text: "Planning streaming burst \(turnIndex)",
                    detailText: progressDetail(for: turnIndex)
                ))
            activityItems.append(
                SessionActivityItem(
                    kind: .command,
                    text: commandTitle(for: turnIndex),
                    detailText: commandOutput(for: turnIndex)
                ))
            activityItems.append(SessionActivityItem(kind: .message, text: "Pi: \(assistantMessage)"))

            if turnIndex.isMultiple(of: 4) {
                activityItems.append(SessionActivityItem(kind: .status, text: "Trace marker \(turnIndex) captured"))
            }

            transcriptLines.append("You: \(prompt)")
            transcriptLines.append("Pi: \(assistantMessage)")
            providerEventSequence += 2
        }

        let historyState = State(
            turnIndex: seededTurnCount - 1,
            phase: .finalized,
            transcript: transcriptLines.joined(separator: "\n"),
            activityItems: activityItems,
            providerEventSequence: providerEventSequence
        )
        return startTurn(after: historyState, turnIndex: seededTurnCount)
    }

    static func advance(_ state: State) -> State {
        switch state.phase {
        case .drafting(let step):
            if step < draftPrefixFractions.count - 1 {
                var updated = state
                updated.phase = .drafting(step: step + 1)
                updated.providerEventSequence += 1
                return updated
            }

            return finalizeTurn(state)
        case .finalized:
            // Enter dwell: keep activity rows stable, keep isAgent=false, keep finalOutputDiagnostic,
            // but continue mutating providerEventSequence + extensionUI (for AutoScrollTrigger.notificationIDs churn)
            // for a multi-tick window before the next turn appends rows.
            return State(
                turnIndex: state.turnIndex,
                phase: .finalizedDwell(remaining: postTurnDwellTicks),
                transcript: state.transcript,
                activityItems: state.activityItems,
                providerEventSequence: state.providerEventSequence + 1
            )
        case .finalizedDwell(let remaining):
            if remaining > 1 {
                var updated = state
                updated.phase = .finalizedDwell(remaining: remaining - 1)
                updated.providerEventSequence += 1
                return updated
            }
            return startTurn(after: state, turnIndex: state.turnIndex + 1)
        }
    }

    static func screen(
        for state: State,
        session: Session,
        controller: SessionController = .mac,
        terminalColumns: Int = 80,
        terminalRows: Int = 24
    ) -> SessionScreen {
        let providerFacts = StructuredSessionProviderFacts(
            providerEventCount: max(1, state.providerEventSequence),
            lastProviderEventSequence: max(1, state.providerEventSequence),
            lastProviderEventType: providerEventType(for: state.phase),
            liveAssistantDraftText: liveAssistantDraftText(for: state),
            tokenUsage: tokenUsage(for: state),
            modelIdentifier: modelIdentifier
        )

        let isPostTurn =
            switch state.phase {
            case .finalized, .finalizedDwell: true
            default: false
            }
        let finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic? =
            if isPostTurn,
                let assistantItem = state.activityItems.last(where: { $0.kind == .message && $0.text.hasPrefix("Pi: ") }
                )
            {
                StructuredSessionFinalOutputDiagnostic(
                    trigger: .turnEnd,
                    providerEventSequence: max(1, state.providerEventSequence),
                    providerRuntimeLatencyMilliseconds: 6 + (state.turnIndex % 5),
                    serviceObservationLatencyMilliseconds: 11 + (state.turnIndex % 7),
                    expectedActivityItemID: assistantItem.id,
                    expectedActivityItemText: assistantItem.text,
                    expectedThinkingIndicatorVisible: false
                )
            } else {
                nil
            }

        // Drive full Pi mutation mix on every advance for hang reproduction:
        // - providerFacts (liveAssistantDraftText + tokenUsage growth + event seq during drafting)
        // - isAgentTurnInProgress toggles (true while drafting)
        // - finalOutputDiagnostic appears only on .finalized / turn_end
        // - extensionUI notifications rotate every observation (metadata churn; must not republish feed presentation during dwell)
        // - thinking indicator visibility derived from isAgentTurnInProgress in presentation
        let extensionUI: SessionExtensionUIState?
        switch state.phase {
        case .drafting(let step):
            let notif = SessionExtensionUINotification(
                id: Self.deterministicNotificationID(sequence: state.providerEventSequence),
                kind: .info,
                message: "live provider event \(state.providerEventSequence) step \(step)"
            )
            extensionUI = SessionExtensionUIState(
                notifications: [notif],
                statuses: [SessionExtensionUIStatus(key: "draft", text: "drafting \(step)")]
            )
        case .finalizedDwell:
            // Continue notification/status churn during dwell on every 200 ms tick even though activity rows
            // and isAgentTurnInProgress are stable (presentation reuse must hold).
            let notif = SessionExtensionUINotification(
                id: Self.deterministicNotificationID(sequence: state.providerEventSequence),
                kind: .info,
                message: "turn_end dwell \(state.providerEventSequence)"
            )
            extensionUI = SessionExtensionUIState(
                notifications: [notif],
                statuses: [SessionExtensionUIStatus(key: "turn", text: "finalized dwell")]
            )
        case .finalized:
            extensionUI = nil
        }

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: controller,
            transcript: state.transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: state.activityItems,
            extensionUI: extensionUI,
            providerFacts: providerFacts,
            finalOutputDiagnostic: finalOutputDiagnostic,
            isAgentTurnInProgress: isDrafting(state.phase)
        )
    }

    private static func deterministicNotificationID(sequence: Int) -> UUID {
        // Stable, unique per sequence for extensionUI notification churn on (nearly) every tick
        let last = String(format: "%012x", UInt64(sequence) & 0x0000_ffff_ffff_ffff)
        let s = "feedc0de-0000-0000-0000-\(last)"
        return UUID(uuidString: s)!
    }

    private static func startTurn(after state: State, turnIndex: Int) -> State {
        let prompt = userPrompt(for: turnIndex)
        var transcript = state.transcript
        if transcript.isEmpty == false {
            transcript += "\n"
        }
        transcript += "You: \(prompt)"

        return State(
            turnIndex: turnIndex,
            phase: .drafting(step: 0),
            transcript: transcript,
            activityItems: state.activityItems + [
                SessionActivityItem(kind: .message, text: "You: \(prompt)"),
                SessionActivityItem(
                    kind: .progress,
                    text: "Planning streaming burst \(turnIndex)",
                    detailText: progressDetail(for: turnIndex)
                ),
            ],
            providerEventSequence: state.providerEventSequence + 1
        )
    }

    private static func finalizeTurn(_ state: State) -> State {
        let assistantMessage = finalizedAssistantMessage(for: state.turnIndex)
        var transcript = state.transcript
        if transcript.isEmpty == false {
            transcript += "\n"
        }
        transcript += "Pi: \(assistantMessage)"

        return State(
            turnIndex: state.turnIndex,
            phase: .finalized,
            transcript: transcript,
            activityItems: state.activityItems + [
                SessionActivityItem(
                    kind: .command,
                    text: commandTitle(for: state.turnIndex),
                    detailText: commandOutput(for: state.turnIndex)
                ),
                SessionActivityItem(kind: .message, text: "Pi: \(assistantMessage)"),
            ],
            providerEventSequence: state.providerEventSequence + 1
        )
    }

    private static func providerEventType(for phase: Phase) -> String {
        switch phase {
        case .drafting:
            "message_update"
        case .finalized, .finalizedDwell:
            "turn_end"
        }
    }

    private static func liveAssistantDraftText(for state: State) -> String? {
        guard case .drafting(let step) = state.phase else {
            return nil
        }

        let fragments = draftFragments(for: state.turnIndex)
        return fragments[min(step, fragments.count - 1)]
    }

    private static func tokenUsage(for state: State) -> StructuredSessionProviderTokenUsage {
        let draftStep = if case .drafting(let step) = state.phase { step } else { draftPrefixFractions.count }
        let usedTokens = min(
            totalTokenLimit - 1,
            34_000 + (state.turnIndex * 913) + (draftStep * 271)
        )
        let percent = Int((Double(usedTokens) / Double(totalTokenLimit)) * 100.0)
        return StructuredSessionProviderTokenUsage(
            usedTokens: usedTokens,
            totalTokens: totalTokenLimit,
            percent: percent
        )
    }

    private static func draftFragments(for turnIndex: Int) -> [String] {
        let message = finalizedAssistantMessage(for: turnIndex)
        return draftPrefixFractions.map { fraction in
            prefixedDraftText(message, fraction: fraction)
        }
    }

    private static func prefixedDraftText(_ text: String, fraction: Double) -> String {
        guard text.isEmpty == false else {
            return text
        }

        let characterCount = max(1, min(text.count, Int(Double(text.count) * fraction)))
        let endIndex = text.index(text.startIndex, offsetBy: characterCount)
        return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func userPrompt(for turnIndex: Int) -> String {
        "Profile the structured feed burst \(turnIndex)"
    }

    private static func finalizedAssistantMessage(for turnIndex: Int) -> String {
        """
        ### Streaming burst \(turnIndex)
        - keep the scroll anchor near the live tail
        - preserve finalized assistant output without clipping
        - collapse only the streaming draft preview when the text grows

        ```swift
        let burst = \(turnIndex)
        let visibleRows = \(92 + (turnIndex % 11))
        let profile = \"structured-feed\"
        ```

        This deterministic fixture alternates compact and multi-line command output so Instruments can sample stable layout pressure while the live draft keeps changing height.
        """
    }

    private static func progressDetail(for turnIndex: Int) -> String {
        """
        preloadedRows=\(92 + turnIndex)
        liveDraftPhase=\(turnIndex % draftPrefixFractions.count)
        feedMode=streaming-feed-profile
        """
    }

    private static func commandTitle(for turnIndex: Int) -> String {
        if turnIndex.isMultiple(of: 2) {
            return "swift test --filter StructuredFeedBurst\(turnIndex)"
        }

        return "git diff --stat -- StreamingBurst\(turnIndex).swift"
    }

    private static func commandOutput(for turnIndex: Int) -> String {
        if turnIndex.isMultiple(of: 2) {
            return """
                Test Suite 'StructuredFeedBurst\(turnIndex)' started
                Test Case '-[StructuredFeedBurst\(turnIndex) testTailAppend]' passed (0.04 seconds)
                Executed 1 test, with 0 failures in 0.04 seconds
                """
        }

        return (0..<14).map { index in
            "StreamingBurst\(turnIndex).swift | \(index + 1) insertions | chunk \(index)"
        }.joined(separator: "\n")
    }

    private static func isDrafting(_ phase: Phase) -> Bool {
        if case .drafting = phase {
            return true
        }
        return false
    }
}
