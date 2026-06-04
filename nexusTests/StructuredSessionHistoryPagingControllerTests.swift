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
}
