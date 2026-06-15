import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

struct StructuredSessionFinalOutputLatencyTrackerTests {
    @Test mutating func trackerMeasuresClientPresentationLatencyAfterObservationReceivesFinalOutput() {
        let clock = TestUptimeClock()
        var tracker = StructuredSessionFinalOutputLatencyTracker(currentUptimeNanoseconds: clock.now)
        let previousScreen = screen(marker: "thinking", isAgentTurnInProgress: true)
        let finalMessage = SessionActivityItem(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            kind: .message,
            text: "Pi: done"
        )
        let finalScreen = screen(
            marker: "done",
            activityItems: [
                SessionActivityItem(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    kind: .status,
                    text: "Thinking turn active"
                ),
                finalMessage,
            ],
            isAgentTurnInProgress: false,
            finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic(
                trigger: .turnEnd,
                providerEventSequence: 9,
                providerRuntimeLatencyMilliseconds: 4,
                serviceObservationLatencyMilliseconds: 10,
                expectedActivityItemID: finalMessage.id,
                expectedActivityItemText: finalMessage.text,
                expectedThinkingIndicatorVisible: false
            )
        )

        clock.value = 100_000_000
        let pendingSample = tracker.update(
            screen: finalScreen,
            presentation: presentation(for: previousScreen)
        )

        #expect(pendingSample?.isVisibleInPresentation == false)
        #expect(pendingSample?.clientPresentationLatencyMilliseconds == nil)

        clock.value = 106_000_000
        let visibleSample = tracker.update(
            screen: finalScreen,
            presentation: presentation(for: finalScreen)
        )

        #expect(visibleSample?.trigger == .turnEnd)
        #expect(visibleSample?.providerRuntimeLatencyMilliseconds == 4)
        #expect(visibleSample?.serviceObservationLatencyMilliseconds == 10)
        #expect(visibleSample?.clientPresentationLatencyMilliseconds == 6)
        #expect(visibleSample?.totalVisibleLatencyMilliseconds == 20)
        #expect(visibleSample?.isVisibleInPresentation == true)
        #expect(visibleSample?.visibleActivityRowText == finalMessage.text)
    }

    private func presentation(for screen: SessionScreen) -> FocusedStructuredSessionPresentation? {
        FocusedStructuredSessionPresenter().presentation(for: screen)
    }

    private func screen(
        marker: String,
        activityItems: [SessionActivityItem]? = nil,
        isAgentTurnInProgress: Bool,
        finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic? = nil
    ) -> SessionScreen {
        let session = Session(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            workspaceID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let resolvedItems =
            activityItems ?? [
                SessionActivityItem(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    kind: .status,
                    text: "Thinking turn active"
                ),
                SessionActivityItem(kind: .message, text: "Pi: \(marker)"),
            ]

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: resolvedItems.map(\.text).joined(separator: "\n"),
            activityItems: resolvedItems,
            finalOutputDiagnostic: finalOutputDiagnostic,
            isAgentTurnInProgress: isAgentTurnInProgress
        )
    }
}

private final class TestUptimeClock: @unchecked Sendable {
    var value: UInt64 = 0

    func now() -> UInt64 {
        value
    }
}
