import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

struct StructuredSessionThinkingStallAttributionTests {
    @Test func attributesStuckThinkingToObservationWhenCanonicalStateAdvancesWithoutObservedProgress() {
        let previousService = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentService = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "1"),
            structuredRevision: 2
        )
        let previousClientObservation = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentClientObservation = previousClientObservation
        let previousClientPresentation = StructuredSessionPresentationProgressSample(
            presentation: thinkingPresentation(marker: "0")
        )
        let currentClientPresentation = previousClientPresentation

        let attribution = structuredSessionThinkingStallAttribution(
            previousService: previousService,
            currentService: currentService,
            previousClientObservation: previousClientObservation,
            currentClientObservation: currentClientObservation,
            previousClientPresentation: previousClientPresentation,
            currentClientPresentation: currentClientPresentation
        )

        #expect(attribution.layer == .observation)
        #expect(attribution.stillThinking)
        #expect(attribution.serviceAdvanced)
        #expect(attribution.clientObservationAdvanced == false)
        #expect(attribution.clientPresentationAdvanced == false)
    }

    @Test func attributesStuckThinkingToSessionPresentationWhenObservedScreenAdvancesWithoutPresentationProgress() {
        let previousService = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentService = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "1"),
            structuredRevision: 2
        )
        let previousClientObservation = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentClientObservation = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "1"),
            structuredRevision: 2
        )
        let previousClientPresentation = StructuredSessionPresentationProgressSample(
            presentation: thinkingPresentation(marker: "0")
        )
        let currentClientPresentation = previousClientPresentation

        let attribution = structuredSessionThinkingStallAttribution(
            previousService: previousService,
            currentService: currentService,
            previousClientObservation: previousClientObservation,
            currentClientObservation: currentClientObservation,
            previousClientPresentation: previousClientPresentation,
            currentClientPresentation: currentClientPresentation
        )

        #expect(attribution.layer == .sessionPresentation)
        #expect(attribution.stillThinking)
        #expect(attribution.serviceAdvanced)
        #expect(attribution.clientObservationAdvanced)
        #expect(attribution.clientPresentationAdvanced == false)
    }

    @Test func attributesStuckThinkingToRuntimeWhenCanonicalStateStopsAdvancing() {
        let previousService = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentService = previousService
        let previousClientObservation = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentClientObservation = previousClientObservation
        let previousClientPresentation = StructuredSessionPresentationProgressSample(
            presentation: thinkingPresentation(marker: "0")
        )
        let currentClientPresentation = previousClientPresentation

        let attribution = structuredSessionThinkingStallAttribution(
            previousService: previousService,
            currentService: currentService,
            previousClientObservation: previousClientObservation,
            currentClientObservation: currentClientObservation,
            previousClientPresentation: previousClientPresentation,
            currentClientPresentation: currentClientPresentation
        )

        #expect(attribution.layer == .runtime)
        #expect(attribution.stillThinking)
        #expect(attribution.serviceAdvanced == false)
        #expect(attribution.clientObservationAdvanced == false)
        #expect(attribution.clientPresentationAdvanced == false)
    }

    @Test func clearsStallAttributionWhenThinkingHasEnded() {
        let previousService = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentScreen = thinkingScreen(marker: "done", isAgentTurnInProgress: false)
        let currentService = StructuredSessionObservationProgressSample(
            screen: currentScreen,
            structuredRevision: 2
        )
        let previousClientObservation = StructuredSessionObservationProgressSample(
            screen: thinkingScreen(marker: "0"),
            structuredRevision: 1
        )
        let currentClientObservation = StructuredSessionObservationProgressSample(
            screen: currentScreen,
            structuredRevision: 2
        )
        let previousClientPresentation = StructuredSessionPresentationProgressSample(
            presentation: thinkingPresentation(marker: "0")
        )
        let currentClientPresentation = StructuredSessionPresentationProgressSample(
            presentation: presentation(for: currentScreen)
        )

        let attribution = structuredSessionThinkingStallAttribution(
            previousService: previousService,
            currentService: currentService,
            previousClientObservation: previousClientObservation,
            currentClientObservation: currentClientObservation,
            previousClientPresentation: previousClientPresentation,
            currentClientPresentation: currentClientPresentation
        )

        #expect(attribution.layer == .none)
        #expect(attribution.stillThinking == false)
    }

    private func thinkingPresentation(marker: String) -> FocusedStructuredSessionPresentation {
        presentation(for: thinkingScreen(marker: marker))
    }

    private func presentation(for screen: SessionScreen) -> FocusedStructuredSessionPresentation {
        FocusedStructuredSessionPresenter().presentation(for: screen)!
    }

    private func thinkingScreen(marker: String, isAgentTurnInProgress: Bool = true) -> SessionScreen {
        let session = Session(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            workspaceID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let statusItem = SessionActivityItem(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            kind: .status,
            text: "Thinking turn active"
        )
        let messageItem = SessionActivityItem(
            kind: .message,
            text: "Pi: step \(marker)"
        )

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi: step \(marker)",
            activityItems: [statusItem, messageItem],
            isAgentTurnInProgress: isAgentTurnInProgress
        )
    }
}
