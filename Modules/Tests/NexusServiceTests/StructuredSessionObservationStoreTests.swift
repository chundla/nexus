#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import Testing

struct StructuredSessionObservationStoreTests {
    @Test func structuredObservationStartPreservesStructuredViewportState() {
        let store = StructuredSessionObservationStore()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "structured transcript",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")],
            visibleLines: ["cached viewport"],
            styledVisibleLines: [TerminalLine(cells: [TerminalCell(text: "cached viewport")])],
            cursorRow: 6,
            cursorColumn: 2,
            cursorVisible: false
        )

        let start = store.observationStart(observationID: UUID(), screen: screen)

        #expect(start.screen == screen)
        #expect(start.structuredSnapshot?.screen == screen)
    }

    @Test func terminalObservationStartLeavesTerminalSessionsUnchanged() {
        let store = StructuredSessionObservationStore()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)
        let screen = SessionScreen(
            session: session,
            primarySurface: .terminal,
            transcript: "terminal transcript"
        )

        let start = store.observationStart(observationID: UUID(), screen: screen)

        #expect(start.screen == screen)
        #expect(start.structuredSnapshot == nil)
    }
}
#endif
