import Foundation
import NexusDomain
import Testing

@testable import nexus

@MainActor
struct SessionScreenUpdateCoalescingTests {
    @Test func preferredSessionScreenUpdateKeepsMoreAdvancedPendingPiScreen() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let advancedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: Lets perform a code review on nexus"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Reviewing scope"),
                SessionActivityItem(kind: .command, text: "Grep"),
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 4),
            isAgentTurnInProgress: true
        )
        let regressedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: Lets perform a code review on nexus"),
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 1),
            isAgentTurnInProgress: true
        )

        let preferred = preferredSessionScreenUpdate(pending: advancedScreen, new: regressedScreen)

        #expect(preferred == advancedScreen)
    }

    @Test func sessionScreenAdvanceHeuristicRejectsRegressingPiObservation() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let advancedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: Lets perform a code review on nexus"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Reviewing scope"),
                SessionActivityItem(kind: .command, text: "Grep"),
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 4),
            isAgentTurnInProgress: true
        )
        let regressedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: Lets perform a code review on nexus"),
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 1),
            isAgentTurnInProgress: true
        )

        #expect(sessionScreenAppearsToAdvance(advancedScreen, beyond: regressedScreen))
        #expect(sessionScreenAppearsToAdvance(regressedScreen, beyond: advancedScreen) == false)
    }
}
