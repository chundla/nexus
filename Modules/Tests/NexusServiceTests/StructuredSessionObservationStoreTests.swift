#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import Testing

struct StructuredSessionObservationStoreTests {
    @Test func structuredObservationSnapshotKeepsOnlyBoundedTranscriptTail() {
        let store = StructuredSessionObservationStore()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let lines = (0..<40_000).map { "line-\($0)" }.joined(separator: "\n")
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: lines,
            activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
        )

        let response = store.snapshotResponse(for: screen)
        let snapshot = try! #require(response.structuredSnapshot)

        #expect(snapshot.transcript.count <= StructuredSessionLiveHistoryRetention.maxTranscriptCharacters)
        #expect(snapshot.transcript.hasSuffix("line-39999"))
        #expect(snapshot.transcript.contains("line-0") == false)
    }

    @Test func structuredObservationDeltaKeepsOnlyBoundedTranscriptTail() {
        let store = StructuredSessionObservationStore()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        _ = store.snapshotResponse(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "initial",
                activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
            )
        )

        let lines = (0..<40_000).map { "line-\($0)" }.joined(separator: "\n")
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: lines,
                activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
            )
        )

        let updates = store.updates(for: session.id, after: 0)
        let delta: StructuredSessionObservationDelta
        switch try! #require(updates.first) {
        case let .structuredDelta(value):
            delta = value
        default:
            Issue.record("Expected structured delta update")
            return
        }
        let transcript = try! #require(delta.changes.compactMap { change -> String? in
            if case let .setTranscript(value) = change {
                return value
            }
            return nil
        }.first)

        #expect(transcript.count <= StructuredSessionLiveHistoryRetention.maxTranscriptCharacters)
        #expect(transcript.hasSuffix("line-39999"))
        #expect(transcript.contains("line-0") == false)
    }

    @Test func structuredObservationDeltaCarriesProviderFacts() {
        let store = StructuredSessionObservationStore()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        _ = store.snapshotResponse(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "initial",
                activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
            )
        )

        let updatedFacts = StructuredSessionProviderFacts(
            providerEventCount: 2,
            lastProviderEventSequence: 1,
            lastProviderEventType: "message_update",
            liveAssistantDraftText: "world"
        )
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "initial",
                activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")],
                providerFacts: updatedFacts,
                isAgentTurnInProgress: true
            )
        )

        let updates = store.updates(for: session.id, after: 0)
        let delta: StructuredSessionObservationDelta
        switch try! #require(updates.first) {
        case let .structuredDelta(value):
            delta = value
        default:
            Issue.record("Expected structured delta update")
            return
        }

        #expect(delta.changes.contains(.replaceProviderFacts(updatedFacts)))
    }

    @Test func structuredObservationDeltaReplacesSingleUpdatedActivityItem() {
        let store = StructuredSessionObservationStore()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let statusID = UUID()
        let commandID = UUID()
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "initial",
            activityItems: [
                SessionActivityItem(id: statusID, kind: .status, text: "Pi ready"),
                SessionActivityItem(id: commandID, kind: .command, text: "subagent reviewer", detailText: "step 1")
            ]
        )
        _ = store.snapshotResponse(for: initialScreen)

        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "initial",
            activityItems: [
                SessionActivityItem(id: statusID, kind: .status, text: "Pi ready"),
                SessionActivityItem(id: commandID, kind: .command, text: "subagent reviewer", detailText: "step 1\nstep 2")
            ]
        )
        store.recordChange(for: updatedScreen)

        let updates = store.updates(for: session.id, after: 0)
        let delta: StructuredSessionObservationDelta
        switch try! #require(updates.first) {
        case let .structuredDelta(value):
            delta = value
        default:
            Issue.record("Expected structured delta update")
            return
        }

        #expect(delta.changes.contains {
            if case let .replaceActivityItem(item) = $0 {
                return item.id == commandID && item.detailText == "step 1\nstep 2"
            }
            return false
        })
        #expect(delta.changes.contains { if case .replaceActivityItemRange = $0 { return true }; return false } == false)
        #expect(delta.changes.contains { if case .replaceActivityItems = $0 { return true }; return false } == false)
    }

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
