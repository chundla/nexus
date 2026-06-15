import Foundation
import NexusDomain
import Testing
@testable import NexusSessionPresentation

struct StructuredSessionInFlightAssistantPresentationTests {
    @Test func suppressesPiAssistantActivityItemWhileTurnOpen() {
        let piItemID = UUID()
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(id: piItemID, kind: .message, text: "Pi: streaming chunk")
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "streaming chunk"),
            isAgentTurnInProgress: true
        )

        let filtered = structuredSessionActivityItemsForFeedPresentation(for: screen)
        #expect(filtered.map(\.text) == ["You: go"])
        #expect(filtered.contains { $0.id == piItemID } == false)

        let segments = structuredSessionPiFeedSegments(for: screen)
        #expect(segments?.contains { segment in
            if case .standalone(let item) = segment, item.text.hasPrefix("Pi:") {
                return true
            }
            return false
        } == false)
    }

    @Test func keepsPiAssistantActivityItemAfterTurnCloses() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .message, text: "Pi: done")
            ],
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionActivityItemsForFeedPresentation(for: screen).count == 2)
    }
}