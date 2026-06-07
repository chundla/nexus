import Foundation
import NexusDomain
import NexusIPC

final class StructuredSessionObservationStore: @unchecked Sendable {
    private struct Entry {
        var snapshot: StructuredSessionObservationSnapshot
        var deltas: [StructuredSessionObservationDelta]
    }

    private struct DeltaBuildSummary {
        let baseRevision: Int
        let revision: Int
        let changes: [StructuredSessionObservationChange]
        let snapshot: StructuredSessionObservationSnapshot
        let elapsedMilliseconds: Int
    }

    private struct EntryResolution {
        let entry: Entry
        let deltaBuildSummary: DeltaBuildSummary?
    }

    private let lock = NSLock()
    private let maxRetainedDeltas: Int
    private let recordPerformanceDiagnostic: (PerformanceDiagnosticRecord) -> Void
    private let currentDate: () -> Date
    private let currentUptimeNanoseconds: () -> UInt64
    private var entries: [UUID: Entry] = [:]

    init(
        maxRetainedDeltas: Int = 64,
        recordPerformanceDiagnostic: @escaping (PerformanceDiagnosticRecord) -> Void = { _ in },
        currentDate: @escaping () -> Date = Date.init,
        currentUptimeNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.maxRetainedDeltas = max(1, maxRetainedDeltas)
        self.recordPerformanceDiagnostic = recordPerformanceDiagnostic
        self.currentDate = currentDate
        self.currentUptimeNanoseconds = currentUptimeNanoseconds
    }

    func snapshotResponse(for screen: SessionScreen) -> SessionScreenObservationSnapshotResponse {
        let retainedScreen = StructuredSessionLiveHistoryRetention.normalizedScreen(screen)
        guard retainedScreen.primarySurface == .structuredActivityFeed else {
            return withLock {
                entries.removeValue(forKey: retainedScreen.session.id)
                return SessionScreenObservationSnapshotResponse(screen: retainedScreen)
            }
        }

        let observedScreen = screenWithObservedFinalOutputDiagnostic(retainedScreen)
        var trace = makeTrace(for: observedScreen.session)
        var deltaBuildSummary: DeltaBuildSummary?
        let response = trace.measure("buildStructuredSnapshot") {
            withLock {
                let resolution = ensureCurrentEntryLocked(for: observedScreen)
                deltaBuildSummary = resolution.deltaBuildSummary
                return SessionScreenObservationSnapshotResponse(
                    screen: resolution.entry.snapshot.screen,
                    structuredSnapshot: resolution.entry.snapshot
                )
            }
        }

        if let deltaBuildSummary {
            recordPerformanceDiagnostic(deltaDiagnostic(for: retainedScreen.session, summary: deltaBuildSummary))
        }
        if let structuredSnapshot = response.structuredSnapshot {
            recordPerformanceDiagnostic(
                trace.finish(
                    outcome: .success,
                    metrics: snapshotMetrics(from: structuredSnapshot)
                )
            )
        }
        return response
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
        let retainedScreen = StructuredSessionLiveHistoryRetention.normalizedScreen(screen)
        guard retainedScreen.primarySurface == .structuredActivityFeed else {
            _ = withLock {
                entries.removeValue(forKey: retainedScreen.session.id)
            }
            return
        }

        let observedScreen = screenWithObservedFinalOutputDiagnostic(retainedScreen)
        let deltaBuildSummary = withLock {
            ensureCurrentEntryLocked(for: observedScreen).deltaBuildSummary
        }
        if let deltaBuildSummary {
            recordPerformanceDiagnostic(deltaDiagnostic(for: retainedScreen.session, summary: deltaBuildSummary))
        }
    }

    func updates(for sessionID: UUID, after revision: Int?) -> [SessionScreenObservationUpdate] {
        let startedAt = currentUptimeNanoseconds()
        var gapRecord: PerformanceDiagnosticRecord?
        let updates: [SessionScreenObservationUpdate] = withLock {
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
                gapRecord = gapDiagnostic(
                    for: entry.snapshot.session,
                    requestedRevision: revision,
                    currentRevision: currentRevision,
                    retainedDeltaCount: entry.deltas.count,
                    elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
                )
                return [SessionScreenObservationUpdate.structuredGap(currentRevision: currentRevision)]
            }

            let sortedDeltas = matchingDeltas.sorted { $0.revision < $1.revision }
            var previousRevision = revision
            for (expectedRevision, delta) in zip(expectedRevisions, sortedDeltas) {
                guard delta.baseRevision == previousRevision, delta.revision == expectedRevision else {
                    gapRecord = gapDiagnostic(
                        for: entry.snapshot.session,
                        requestedRevision: revision,
                        currentRevision: currentRevision,
                        retainedDeltaCount: entry.deltas.count,
                        elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
                    )
                    return [SessionScreenObservationUpdate.structuredGap(currentRevision: currentRevision)]
                }
                previousRevision = delta.revision
            }

            return sortedDeltas.map(SessionScreenObservationUpdate.structuredDelta)
        }
        if let gapRecord {
            recordPerformanceDiagnostic(gapRecord)
        }
        return updates
    }

    private func ensureCurrentEntryLocked(for screen: SessionScreen) -> EntryResolution {
        guard var entry = entries[screen.session.id] else {
            let initialEntry = Entry(
                snapshot: StructuredSessionObservationSnapshot(revision: 0, screen: screen),
                deltas: []
            )
            entries[screen.session.id] = initialEntry
            return EntryResolution(entry: initialEntry, deltaBuildSummary: nil)
        }

        let deltaStartedAt = currentUptimeNanoseconds()
        let changes = makeChanges(from: entry.snapshot, to: screen)
        let deltaElapsedMilliseconds = elapsedMilliseconds(since: deltaStartedAt)
        guard changes.isEmpty == false else {
            let refreshedEntry = Entry(
                snapshot: StructuredSessionObservationSnapshot(revision: entry.snapshot.revision, screen: screen),
                deltas: entry.deltas
            )
            entries[screen.session.id] = refreshedEntry
            return EntryResolution(entry: refreshedEntry, deltaBuildSummary: nil)
        }

        let baseRevision = entry.snapshot.revision
        let nextRevision = baseRevision + 1
        let delta = StructuredSessionObservationDelta(
            baseRevision: baseRevision,
            revision: nextRevision,
            changes: changes
        )
        entry.snapshot = StructuredSessionObservationSnapshot(revision: nextRevision, screen: screen)
        entry.deltas.append(delta)
        if entry.deltas.count > maxRetainedDeltas {
            entry.deltas.removeFirst(entry.deltas.count - maxRetainedDeltas)
        }
        entries[screen.session.id] = entry
        return EntryResolution(
            entry: entry,
            deltaBuildSummary: DeltaBuildSummary(
                baseRevision: baseRevision,
                revision: nextRevision,
                changes: changes,
                snapshot: entry.snapshot,
                elapsedMilliseconds: deltaElapsedMilliseconds
            )
        )
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
        if snapshot.providerFacts != screen.providerFacts {
            changes.append(.replaceProviderFacts(screen.providerFacts))
        }
        if snapshot.finalOutputDiagnostic != screen.finalOutputDiagnostic {
            changes.append(.replaceFinalOutputDiagnostic(screen.finalOutputDiagnostic))
        }
        if snapshot.isAgentTurnInProgress != screen.isAgentTurnInProgress {
            changes.append(.setAgentTurnInProgress(screen.isAgentTurnInProgress))
        }

        return changes
    }

    private func activityItemChanges(
        from existingItems: [SessionActivityItem],
        to newItems: [SessionActivityItem]
    ) -> [StructuredSessionObservationChange] {
        guard existingItems.count <= newItems.count else {
            return [.replaceActivityItems(newItems)]
        }

        let sharedCount = existingItems.count
        var firstChangedIndex: Int?
        var changedIndices: [Int] = []

        for index in 0..<sharedCount {
            guard existingItems[index].id == newItems[index].id else {
                return [.replaceActivityItems(newItems)]
            }
            if existingItems[index] != newItems[index] {
                if firstChangedIndex == nil {
                    firstChangedIndex = index
                }
                changedIndices.append(index)
            }
        }

        if let firstChangedIndex {
            if changedIndices.count == 1,
               newItems.count == existingItems.count {
                return [.replaceActivityItem(newItems[firstChangedIndex])]
            }

            return [
                .replaceActivityItemRange(
                    startIndex: firstChangedIndex,
                    items: Array(newItems.dropFirst(firstChangedIndex))
                )
            ]
        }

        let appendedItems = Array(newItems.dropFirst(sharedCount))
        return appendedItems.isEmpty ? [] : [.appendActivityItems(appendedItems)]
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

    private func makeTrace(for session: Session) -> PerformanceDiagnosticTrace {
        PerformanceDiagnosticTrace(
            operation: .structuredSessionObservation,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            sessionID: session.id,
            recordedAt: currentDate(),
            currentUptimeNanoseconds: currentUptimeNanoseconds
        )
    }

    private func snapshotMetrics(from snapshot: StructuredSessionObservationSnapshot) -> [String: Int] {
        [
            "snapshotBuildCount": 1,
            "structuredRevision": snapshot.revision,
            "activityItemCount": snapshot.activityItems.count,
            "approvalRequestCount": snapshot.approvalRequests.count,
            "providerEventCount": snapshot.providerEvents.count,
            "slashCommandCount": snapshot.slashCommands?.count ?? 0,
            "transcriptCharacterCount": snapshot.transcript.count,
            "extensionDialogVisibleCount": snapshot.extensionUI == nil ? 0 : 1,
            "agentTurnInProgressCount": snapshot.isAgentTurnInProgress ? 1 : 0
        ].merging(finalOutputMetrics(from: snapshot.finalOutputDiagnostic)) { _, new in new }
    }

    private func deltaDiagnostic(for session: Session, summary: DeltaBuildSummary) -> PerformanceDiagnosticRecord {
        PerformanceDiagnosticRecord(
            operation: .structuredSessionObservation,
            outcome: .success,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            sessionID: session.id,
            totalElapsedMilliseconds: summary.elapsedMilliseconds,
            steps: [
                PerformanceDiagnosticStep(
                    name: "buildStructuredDelta",
                    elapsedMilliseconds: summary.elapsedMilliseconds
                )
            ],
            metrics: deltaMetrics(from: summary),
            recordedAt: currentDate()
        )
    }

    private func deltaMetrics(from summary: DeltaBuildSummary) -> [String: Int] {
        let fullReplaceActivityItemsCount = summary.changes.reduce(into: 0) { count, change in
            if case .replaceActivityItems = change {
                count += 1
            }
        }
        let activityItemRangeReplaceCount = summary.changes.reduce(into: 0) { count, change in
            if case .replaceActivityItemRange = change {
                count += 1
            }
        }
        let fullReplaceProviderEventsCount = summary.changes.reduce(into: 0) { count, change in
            if case .replaceProviderEvents = change {
                count += 1
            }
        }

        var metrics = snapshotMetrics(from: summary.snapshot)
        metrics["snapshotBuildCount"] = 0
        metrics["deltaBuildCount"] = 1
        metrics["baseRevision"] = summary.baseRevision
        metrics["structuredRevision"] = summary.revision
        metrics["changeCount"] = summary.changes.count
        metrics["activityItemRangeReplaceCount"] = activityItemRangeReplaceCount
        metrics["fullReplaceActivityItemsCount"] = fullReplaceActivityItemsCount
        metrics["fullReplaceProviderEventsCount"] = fullReplaceProviderEventsCount
        metrics["fullReplaceFallbackCount"] = fullReplaceActivityItemsCount + fullReplaceProviderEventsCount
        return metrics
    }

    private func finalOutputMetrics(from diagnostic: StructuredSessionFinalOutputDiagnostic?) -> [String: Int] {
        guard let diagnostic else {
            return [:]
        }

        return [
            "finalOutputLatencyCount": 1,
            "finalOutputProviderEventSequence": diagnostic.providerEventSequence,
            "finalOutputProviderRuntimeMilliseconds": diagnostic.providerRuntimeLatencyMilliseconds,
            "finalOutputServiceObservationMilliseconds": diagnostic.serviceObservationLatencyMilliseconds ?? 0,
            "finalOutputTriggerTextDeltaCount": diagnostic.trigger == .textDelta ? 1 : 0,
            "finalOutputTriggerTurnEndCount": diagnostic.trigger == .turnEnd ? 1 : 0,
            "finalOutputThinkingIndicatorVisibleCount": diagnostic.expectedThinkingIndicatorVisible ? 1 : 0
        ]
    }

    private func screenWithObservedFinalOutputDiagnostic(_ screen: SessionScreen) -> SessionScreen {
        guard let diagnostic = screen.finalOutputDiagnostic,
              diagnostic.serviceObservationLatencyMilliseconds == nil,
              let anchor = diagnostic.serviceObservationAnchorUptimeNanoseconds else {
            return screen
        }

        let observedDiagnostic = diagnostic.observed(
            serviceObservationLatencyMilliseconds: elapsedMilliseconds(since: anchor)
        )
        return SessionScreen(
            session: screen.session,
            primarySurface: screen.primarySurface,
            controller: screen.controller,
            transcript: screen.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows,
            activityItems: screen.activityItems,
            approvalRequests: screen.approvalRequests,
            extensionUI: screen.extensionUI,
            slashCommands: screen.slashCommands,
            providerEvents: screen.providerEvents,
            providerFacts: screen.providerFacts,
            finalOutputDiagnostic: observedDiagnostic,
            isAgentTurnInProgress: screen.isAgentTurnInProgress,
            visibleLines: screen.visibleLines,
            styledVisibleLines: screen.styledVisibleLines,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
            cursorVisible: screen.cursorVisible
        )
    }

    private func gapDiagnostic(
        for session: Session,
        requestedRevision: Int,
        currentRevision: Int,
        retainedDeltaCount: Int,
        elapsedMilliseconds: Int
    ) -> PerformanceDiagnosticRecord {
        PerformanceDiagnosticRecord(
            operation: .structuredSessionObservation,
            outcome: .success,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            sessionID: session.id,
            totalElapsedMilliseconds: elapsedMilliseconds,
            steps: [
                PerformanceDiagnosticStep(
                    name: "resolveStructuredGap",
                    elapsedMilliseconds: elapsedMilliseconds
                )
            ],
            metrics: [
                "gapFallbackCount": 1,
                "requestedRevision": requestedRevision,
                "currentRevision": currentRevision,
                "retainedDeltaCount": retainedDeltaCount
            ],
            recordedAt: currentDate()
        )
    }

    private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        Int(currentUptimeNanoseconds().saturatingSubtract(startedAt) / 1_000_000)
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
