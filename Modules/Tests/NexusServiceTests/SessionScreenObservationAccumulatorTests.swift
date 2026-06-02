#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
import Testing

struct SessionScreenObservationAccumulatorTests {
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
