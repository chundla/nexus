#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
import Testing

struct SessionScreenObservationAccumulatorTests {
    @Test func structuredAccumulatorPreservesStructuredViewportWhileApplyingStructuredDelta() throws {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let startScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "old transcript",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")],
            approvalRequests: [SessionApprovalRequest(title: "Review?", text: "Review?", state: .pending)],
            extensionUI: SessionExtensionUIState(title: "Extension"),
            slashCommands: [SessionSlashCommand(name: "/plan", source: .skill)],
            visibleLines: ["cached viewport"],
            styledVisibleLines: [TerminalLine(cells: [TerminalCell(text: "cached viewport")])],
            cursorRow: 7,
            cursorColumn: 4,
            cursorVisible: false
        )
        let start = SessionScreenObservationStart(
            observationID: UUID(),
            screen: startScreen,
            structuredSnapshot: StructuredSessionObservationSnapshot(revision: 0, screen: startScreen)
        )
        let accumulator = SessionScreenObservationAccumulator(start: start)

        let update = SessionScreenObservationUpdate.structuredDelta(
            StructuredSessionObservationDelta(
                baseRevision: 0,
                revision: 1,
                changes: [
                    .setTranscript("new transcript"),
                    .appendActivityItems([SessionActivityItem(kind: .message, text: "You: deploy")]),
                    .replaceApprovalRequests([]),
                    .replaceExtensionUI(SessionExtensionUIState(title: "Updated Extension")),
                    .replaceSlashCommands([SessionSlashCommand(name: "/ship", source: .prompt)]),
                    .setAgentTurnInProgress(true)
                ]
            )
        )

        let screen = try #require(try accumulator.apply(update))

        #expect(accumulator.currentStructuredRevision == 1)
        #expect(screen.transcript == "new transcript")
        #expect(screen.activityItems.map(\.text) == ["Pi ready", "You: deploy"])
        #expect(screen.approvalRequests.isEmpty)
        #expect(screen.extensionUI?.title == "Updated Extension")
        #expect(screen.slashCommands?.map(\.name) == ["/ship"])
        #expect(screen.isAgentTurnInProgress)
        #expect(screen.visibleLines == ["cached viewport"])
        #expect(screen.styledVisibleLines == [TerminalLine(cells: [TerminalCell(text: "cached viewport")])])
        #expect(screen.cursorRow == 7)
        #expect(screen.cursorColumn == 4)
        #expect(screen.cursorVisible == false)
    }

    @Test func structuredAccumulatorAppliesProviderFactsDelta() throws {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let startScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 1, lastProviderEventSequence: 0, lastProviderEventType: "response")
        )
        let start = SessionScreenObservationStart(
            observationID: UUID(),
            screen: startScreen,
            structuredSnapshot: StructuredSessionObservationSnapshot(revision: 0, screen: startScreen)
        )
        let accumulator = SessionScreenObservationAccumulator(start: start)

        let updatedFacts = StructuredSessionProviderFacts(
            providerEventCount: 2,
            lastProviderEventSequence: 1,
            lastProviderEventType: "message_update",
            liveAssistantDraftText: "world",
            tokenUsage: StructuredSessionProviderTokenUsage(usedTokens: 60000, totalTokens: 200000, percent: 30),
            modelIdentifier: "openai/gpt-5.1-codex-max"
        )
        let update = SessionScreenObservationUpdate.structuredDelta(
            StructuredSessionObservationDelta(
                baseRevision: 0,
                revision: 1,
                changes: [
                    .replaceProviderFacts(updatedFacts),
                    .setAgentTurnInProgress(true)
                ]
            )
        )

        let screen = try #require(try accumulator.apply(update))

        #expect(accumulator.currentStructuredRevision == 1)
        #expect(screen.providerFacts == updatedFacts)
        #expect(screen.isAgentTurnInProgress)
    }

    @Test func structuredAccumulatorAppliesRevisionedDelta() throws {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let startScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
        )
        let start = SessionScreenObservationStart(
            observationID: UUID(),
            screen: startScreen,
            structuredSnapshot: StructuredSessionObservationSnapshot(revision: 0, screen: startScreen)
        )
        let accumulator = SessionScreenObservationAccumulator(start: start)

        let updatedItem = SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy?")
        let update = SessionScreenObservationUpdate.structuredDelta(
            StructuredSessionObservationDelta(
                baseRevision: 0,
                revision: 1,
                changes: [
                    .setTranscript("> deploy"),
                    .appendActivityItems([
                        SessionActivityItem(kind: .message, text: "You: deploy"),
                        updatedItem
                    ]),
                    .replaceApprovalRequests([
                        SessionApprovalRequest(title: "Deploy?", text: "Deploy?", state: .pending)
                    ]),
                    .setAgentTurnInProgress(true)
                ]
            )
        )

        let screen = try #require(try accumulator.apply(update))

        #expect(accumulator.currentStructuredRevision == 1)
        #expect(screen.transcript == "> deploy")
        #expect(screen.activityItems.suffix(2).map(\.text) == ["You: deploy", "Approval Request: Deploy?"])
        #expect(screen.approvalRequests.first?.state == .pending)
        #expect(screen.isAgentTurnInProgress)
    }

    @Test func structuredAccumulatorAppliesTailActivityReplacementDelta() throws {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let statusItem = SessionActivityItem(id: UUID(), kind: .status, text: "Pi ready")
        let progressItem = SessionActivityItem(id: UUID(), kind: .progress, text: "Streaming 50%")
        let startScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [statusItem, progressItem]
        )
        let start = SessionScreenObservationStart(
            observationID: UUID(),
            screen: startScreen,
            structuredSnapshot: StructuredSessionObservationSnapshot(revision: 0, screen: startScreen)
        )
        let accumulator = SessionScreenObservationAccumulator(start: start)

        let update = SessionScreenObservationUpdate.structuredDelta(
            StructuredSessionObservationDelta(
                baseRevision: 0,
                revision: 1,
                changes: [
                    .replaceActivityItemRange(
                        startIndex: 1,
                        items: [
                            SessionActivityItem(id: progressItem.id, kind: .progress, text: "Streaming 100%"),
                            SessionActivityItem(kind: .completion, text: "Done")
                        ]
                    )
                ]
            )
        )

        let screen = try #require(try accumulator.apply(update))

        #expect(accumulator.currentStructuredRevision == 1)
        #expect(screen.activityItems.map { $0.text } == ["Pi ready", "Streaming 100%", "Done"])
    }

    @Test func structuredAccumulatorDetectsRevisionGap() {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let startScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
        )
        let start = SessionScreenObservationStart(
            observationID: UUID(),
            screen: startScreen,
            structuredSnapshot: StructuredSessionObservationSnapshot(revision: 1, screen: startScreen)
        )
        let accumulator = SessionScreenObservationAccumulator(start: start)

        #expect(throws: SessionScreenObservationGapError.structuredGap(expectedRevision: 1, currentRevision: 3)) {
            try accumulator.apply(
                .structuredDelta(
                    StructuredSessionObservationDelta(
                        baseRevision: 2,
                        revision: 3,
                        changes: [.setTranscript("> deploy")]
                    )
                )
            )
        }
    }
}
#endif
