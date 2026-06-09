import Foundation
import NexusDomain
import NexusIPC
import NexusSessionPresentation
import Testing
@testable import nexus

@MainActor
struct StructuredSessionHistoryPagingControllerTests {
    @Test func loadsOlderHistoryForCodexAndIBMBobStructuredSessions() async throws {
        for providerID in [ProviderID.codex, .ibmBob] {
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: providerID,
                isDefault: true,
                state: .ready
            )
            let liveActivity = SessionActivityItem(kind: .message, text: "Live message")
            let olderActivity = SessionActivityItem(kind: .message, text: "Older message")
            let controller = StructuredSessionHistoryPagingController(
                pageSize: 20,
                fetchPage: { sessionID, _, _ in
                    StructuredSessionHistoryPage(
                        sessionID: sessionID,
                        activityItems: [olderActivity],
                        providerEvents: [],
                        nextCursor: nil
                    )
                }
            )
            let screen = SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                terminalColumns: 80,
                terminalRows: 24,
                activityItems: [liveActivity]
            )

            controller.applyLiveScreen(screen)
            #expect(controller.canLoadOlder)

            await controller.loadOlderHistory(for: screen)

            #expect(controller.canLoadOlder == false)
            let presentation = try #require(controller.presentation(for: screen))
            #expect(presentation.feed.activityRows.map { $0.text } == [
                "Older message",
                "Live message"
            ])
        }
    }

    @Test func providerEventGapRecoveryDoesNotFetchOlderProviderEvents() async {
        let session = testSession(providerID: .pi)
        let activity = SessionActivityItem(kind: .message, text: "Live message")
        let previousScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            terminalColumns: 80,
            terminalRows: 24,
            activityItems: [activity],
            providerEvents: [
                providerEvent(sequence: 1, payload: "{\"type\":\"turn_start\"}"),
                providerEvent(sequence: 2, payload: "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"Hi\"}}")
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 2, lastProviderEventSequence: 2)
        )
        let currentScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            terminalColumns: 80,
            terminalRows: 24,
            activityItems: [activity],
            providerEvents: [
                providerEvent(sequence: 2, payload: "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"Hi\"}}"),
                providerEvent(sequence: 3, payload: "{\"type\":\"turn_end\"}")
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 2, lastProviderEventSequence: 3)
        )

        let fetchCounter = FetchCounter()
        let controller = StructuredSessionHistoryPagingController(
            pageSize: 20,
            fetchPage: { sessionID, _, _ in
                await fetchCounter.increment()
                return StructuredSessionHistoryPage(
                    sessionID: sessionID,
                    activityItems: [],
                    providerEvents: [providerEvent(sequence: 0, payload: "{\"type\":\"message_update\"}")],
                    nextCursor: nil
                )
            }
        )

        controller.applyLiveScreen(previousScreen)
        await controller.recoverPersistedGapIfNeeded(from: previousScreen, to: currentScreen)

        #expect(await fetchCounter.value == 0)
    }

    @Test func providerEventChurnDuringAgentTurnDoesNotRebuildPresentationWhenRowsStable() throws {
        let session = testSession(providerID: .pi)
        let activity = SessionActivityItem(kind: .message, text: "You: hi")
        let controller = StructuredSessionHistoryPagingController(pageSize: 20) { sessionID, _, _ in
            StructuredSessionHistoryPage(sessionID: sessionID, activityItems: [], providerEvents: [], nextCursor: nil)
        }
        let baseScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            terminalColumns: 80,
            terminalRows: 24,
            activityItems: [activity],
            providerEvents: [],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 1, liveAssistantDraftText: nil),
            isAgentTurnInProgress: true
        )

        controller.applyLiveScreen(baseScreen)
        let first = try #require(controller.presentation(for: baseScreen))

        let churnedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            terminalColumns: 80,
            terminalRows: 24,
            activityItems: [activity],
            providerEvents: [
                providerEvent(sequence: 1, payload: "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"x\"}}")
            ],
            providerFacts: StructuredSessionProviderFacts(providerEventCount: 99, liveAssistantDraftText: nil),
            isAgentTurnInProgress: true
        )

        _ = try #require(controller.presentation(for: churnedScreen))
        #expect(controller.presentationRebuildCount == 1)
        #expect(first == controller.presentation(for: churnedScreen))
    }

    @Test func loadingOlderActivityDoesNotMergeHistoricalProviderEventsIntoLivePresentation() async throws {
        let session = testSession(providerID: .pi)
        let liveActivity = SessionActivityItem(kind: .message, text: "You: Keep going")
        let olderActivity = SessionActivityItem(kind: .message, text: "Older message")
        let controller = StructuredSessionHistoryPagingController(
            pageSize: 20,
            fetchPage: { sessionID, _, _ in
                StructuredSessionHistoryPage(
                    sessionID: sessionID,
                    activityItems: [olderActivity],
                    providerEvents: [providerEvent(sequence: 1, payload: "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"historical draft\"}}")],
                    nextCursor: nil
                )
            }
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            terminalColumns: 80,
            terminalRows: 24,
            activityItems: [liveActivity],
            providerEvents: [],
            providerFacts: .empty,
            isAgentTurnInProgress: true
        )

        controller.applyLiveScreen(screen)
        await controller.loadOlderHistory(for: screen)

        let presentation = try #require(controller.presentation(for: screen))
        #expect(presentation.feed.activityRows.map(\.text) == [
            "Older message",
            "You: Keep going"
        ])
    }
}

private func testSession(providerID: ProviderID) -> Session {
    Session(
        id: UUID(),
        workspaceID: UUID(),
        providerID: providerID,
        isDefault: true,
        state: .ready
    )
}

private actor FetchCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private func providerEvent(sequence: Int, payload: String) -> SessionProviderEvent {
    SessionProviderEvent(
        sequence: sequence,
        providerID: .pi,
        type: "message_update",
        family: .message,
        rawPayload: payload
    )
}
