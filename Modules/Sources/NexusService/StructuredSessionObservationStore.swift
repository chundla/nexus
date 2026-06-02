import Foundation
import NexusDomain
import NexusIPC

final class StructuredSessionObservationStore: @unchecked Sendable {
    private struct Entry {
        var snapshot: StructuredSessionObservationSnapshot
        var deltas: [StructuredSessionObservationDelta]
    }

    private let lock = NSLock()
    private let maxRetainedDeltas: Int
    private var entries: [UUID: Entry] = [:]

    init(maxRetainedDeltas: Int = 64) {
        self.maxRetainedDeltas = max(1, maxRetainedDeltas)
    }

    func snapshotResponse(for screen: SessionScreen) -> SessionScreenObservationSnapshotResponse {
        withLock {
            guard screen.primarySurface == .structuredActivityFeed else {
                entries.removeValue(forKey: screen.session.id)
                return SessionScreenObservationSnapshotResponse(screen: screen)
            }

            let entry = ensureCurrentEntryLocked(for: screen)
            return SessionScreenObservationSnapshotResponse(screen: entry.snapshot.screen, structuredSnapshot: entry.snapshot)
        }
    }

    func observationStart(observationID: UUID, screen: SessionScreen) -> SessionScreenObservationStart {
        let snapshot = snapshotResponse(for: screen)
        return SessionScreenObservationStart(
            observationID: observationID,
            screen: snapshot.screen,
            structuredSnapshot: snapshot.structuredSnapshot
        )
    }

    func recordChange(for screen: SessionScreen) {
        withLock {
            guard screen.primarySurface == .structuredActivityFeed else {
                entries.removeValue(forKey: screen.session.id)
                return
            }
            _ = ensureCurrentEntryLocked(for: screen)
        }
    }

    func updates(for sessionID: UUID, after revision: Int?) -> [SessionScreenObservationUpdate] {
        withLock {
            guard let revision,
                  let entry = entries[sessionID] else {
                return []
            }

            let currentRevision = entry.snapshot.revision
            guard revision < currentRevision else {
                return []
            }

            let expectedRevisions = Array((revision + 1)...currentRevision)
            let matchingDeltas = entry.deltas.filter { $0.revision > revision }
            guard matchingDeltas.count == expectedRevisions.count else {
                return [.structuredGap(currentRevision: currentRevision)]
            }

            let sortedDeltas = matchingDeltas.sorted { $0.revision < $1.revision }
            var previousRevision = revision
            for (expectedRevision, delta) in zip(expectedRevisions, sortedDeltas) {
                guard delta.baseRevision == previousRevision, delta.revision == expectedRevision else {
                    return [.structuredGap(currentRevision: currentRevision)]
                }
                previousRevision = delta.revision
            }

            return sortedDeltas.map(SessionScreenObservationUpdate.structuredDelta)
        }
    }

    private func ensureCurrentEntryLocked(for screen: SessionScreen) -> Entry {
        if let entry = entries[screen.session.id], entry.snapshot.screen == screen {
            return entry
        }

        guard var entry = entries[screen.session.id] else {
            let initialEntry = Entry(
                snapshot: StructuredSessionObservationSnapshot(revision: 0, screen: screen),
                deltas: []
            )
            entries[screen.session.id] = initialEntry
            return initialEntry
        }

        let changes = makeChanges(from: entry.snapshot, to: screen)
        guard changes.isEmpty == false else {
            let refreshedEntry = Entry(
                snapshot: StructuredSessionObservationSnapshot(revision: entry.snapshot.revision, screen: screen),
                deltas: entry.deltas
            )
            entries[screen.session.id] = refreshedEntry
            return refreshedEntry
        }

        let nextRevision = entry.snapshot.revision + 1
        let delta = StructuredSessionObservationDelta(
            baseRevision: entry.snapshot.revision,
            revision: nextRevision,
            changes: changes
        )
        entry.snapshot = StructuredSessionObservationSnapshot(revision: nextRevision, screen: screen)
        entry.deltas.append(delta)
        if entry.deltas.count > maxRetainedDeltas {
            entry.deltas.removeFirst(entry.deltas.count - maxRetainedDeltas)
        }
        entries[screen.session.id] = entry
        return entry
    }

    private func makeChanges(
        from snapshot: StructuredSessionObservationSnapshot,
        to screen: SessionScreen
    ) -> [StructuredSessionObservationChange] {
        var changes: [StructuredSessionObservationChange] = []

        if snapshot.session != screen.session {
            changes.append(.replaceSession(screen.session))
        }
        if snapshot.controller != screen.controller {
            changes.append(.setController(screen.controller))
        }
        if snapshot.transcript != screen.transcript {
            changes.append(.setTranscript(screen.transcript))
        }
        if snapshot.terminalColumns != screen.terminalColumns || snapshot.terminalRows != screen.terminalRows {
            changes.append(.setTerminalSize(columns: screen.terminalColumns, rows: screen.terminalRows))
        }
        changes.append(contentsOf: activityItemChanges(from: snapshot.activityItems, to: screen.activityItems))
        if snapshot.approvalRequests != screen.approvalRequests {
            changes.append(.replaceApprovalRequests(screen.approvalRequests))
        }
        if snapshot.extensionUI != screen.extensionUI {
            changes.append(.replaceExtensionUI(screen.extensionUI))
        }
        if snapshot.slashCommands != screen.slashCommands {
            changes.append(.replaceSlashCommands(screen.slashCommands))
        }
        changes.append(contentsOf: providerEventChanges(from: snapshot.providerEvents, to: screen.providerEvents))
        if snapshot.isAgentTurnInProgress != screen.isAgentTurnInProgress {
            changes.append(.setAgentTurnInProgress(screen.isAgentTurnInProgress))
        }

        return changes
    }

    private func activityItemChanges(
        from existingItems: [SessionActivityItem],
        to newItems: [SessionActivityItem]
    ) -> [StructuredSessionObservationChange] {
        guard existingItems != newItems else {
            return []
        }

        let sharedCount = min(existingItems.count, newItems.count)
        var changes: [StructuredSessionObservationChange] = []

        for index in 0..<sharedCount {
            guard existingItems[index].id == newItems[index].id else {
                return [.replaceActivityItems(newItems)]
            }
            if existingItems[index] != newItems[index] {
                changes.append(.replaceActivityItem(newItems[index]))
            }
        }

        guard newItems.count >= existingItems.count else {
            return [.replaceActivityItems(newItems)]
        }

        let appendedItems = Array(newItems.dropFirst(sharedCount))
        if appendedItems.isEmpty == false {
            changes.append(.appendActivityItems(appendedItems))
        }

        return changes.isEmpty ? [.replaceActivityItems(newItems)] : changes
    }

    private func providerEventChanges(
        from existingEvents: [SessionProviderEvent],
        to newEvents: [SessionProviderEvent]
    ) -> [StructuredSessionObservationChange] {
        guard existingEvents != newEvents else {
            return []
        }

        guard newEvents.count >= existingEvents.count else {
            return [.replaceProviderEvents(newEvents)]
        }

        for index in existingEvents.indices {
            guard existingEvents[index] == newEvents[index] else {
                return [.replaceProviderEvents(newEvents)]
            }
        }

        let appendedEvents = Array(newEvents.dropFirst(existingEvents.count))
        return appendedEvents.isEmpty ? [.replaceProviderEvents(newEvents)] : [.appendProviderEvents(appendedEvents)]
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
