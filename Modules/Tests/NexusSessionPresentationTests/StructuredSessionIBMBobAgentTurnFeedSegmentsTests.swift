import Foundation
import NexusDomain
@testable import NexusSessionPresentation
import Testing

/// IBM Bob **Agent Turn** composite feed segments (#238, ADR 0037).
struct StructuredSessionIBMBobAgentTurnFeedSegmentsTests {
    private func bobSession() -> Session {
        Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )
    }

    @Test func bobFeedSegmentsMapsSubagentToolsAndPlainTextFinalAnswer() throws {
        let commandID = UUID()
        let screen = SessionScreen(
            session: bobSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: delegate"),
                SessionActivityItem(
                    id: commandID,
                    kind: .command,
                    text: "subagent: reviewer: Summarize the latest diff"
                ),
                SessionActivityItem(kind: .message, text: "Watch the retry path."),
                SessionActivityItem(kind: .message, text: "Shipped the fix.")
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionIBMBobFeedSegments(for: screen))

        #expect(segments.count == 2)
        guard case .userMessage(let user) = segments[0] else {
            Issue.record("Expected user message segment")
            return
        }
        #expect(user.text == "delegate")

        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.isOpen == false)
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].activityItemID == commandID)
        #expect(turn.toolStackItems[0].subagentOutputs == ["Watch the retry path."])
        #expect(turn.finalAnswer?.text == "Shipped the fix.")
    }

    @Test func bobFeedSegmentsMergeThoughtsIntoReasoning() throws {
        let screen = SessionScreen(
            session: bobSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: plan"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Outline steps."),
                SessionActivityItem(kind: .message, text: "Here is the plan.")
            ]
        )

        let segments = try #require(structuredSessionIBMBobFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Outline steps."])
        #expect(turn.finalAnswer?.text == "Here is the plan.")
    }

    @Test func bobFeedPresentationIncludesCompositeFeedSegments() throws {
        let screen = SessionScreen(
            session: bobSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi"),
                SessionActivityItem(kind: .message, text: "Hello from Bob.")
            ]
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        let segments = try #require(feed.feedSegments)
        #expect(segments.count == 2)
        guard case .userMessage = segments[0],
              case .agentTurn = segments[1] else {
            Issue.record("Expected user then agent turn segments")
            return
        }
    }

    @Test func bobAgentTurnRegressionToolRowsNeverLeakAsStandaloneSegments() throws {
        let screen = SessionScreen(
            session: bobSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: run"),
                SessionActivityItem(kind: .command, text: "attempt_completion: I am Bob."),
                SessionActivityItem(kind: .message, text: "I am Bob.")
            ]
        )

        let segments = try #require(structuredSessionIBMBobFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(segments.contains { if case .standalone = $0 { return true }; return false } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected composite agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].subagentOutputs == ["I am Bob."])
    }

    @Test func nonBobSessionsDoNotEmitBobCompositeFeedSegments() {
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
                SessionActivityItem(kind: .message, text: "You: hi")
            ]
        )

        #expect(structuredSessionIBMBobFeedSegments(for: screen) == nil)
    }
}