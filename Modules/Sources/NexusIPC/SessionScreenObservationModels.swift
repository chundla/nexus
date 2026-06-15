import Foundation
import NexusDomain

public struct StructuredSessionObservationSnapshot: Codable, Equatable, Sendable {
    public let revision: Int
    public let session: Session
    public let controller: SessionController
    public let transcript: String
    public let terminalColumns: Int
    public let terminalRows: Int
    public let activityItems: [SessionActivityItem]
    public let approvalRequests: [SessionApprovalRequest]
    public let extensionUI: SessionExtensionUIState?
    public let slashCommands: [SessionSlashCommand]?
    public let providerEvents: [SessionProviderEvent]
    public let providerFacts: StructuredSessionProviderFacts
    public let finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic?
    public let isAgentTurnInProgress: Bool
    public let visibleLines: [String]
    public let styledVisibleLines: [TerminalLine]
    public let cursorRow: Int
    public let cursorColumn: Int
    public let cursorVisible: Bool

    public init(revision: Int, screen: SessionScreen) {
        self.revision = revision
        self.session = screen.session
        self.controller = screen.controller
        self.transcript = screen.transcript
        self.terminalColumns = screen.terminalColumns
        self.terminalRows = screen.terminalRows
        self.activityItems = screen.activityItems
        self.approvalRequests = screen.approvalRequests
        self.extensionUI = screen.extensionUI
        self.slashCommands = screen.slashCommands
        self.providerEvents = screen.providerEvents
        self.providerFacts = screen.providerFacts
        self.finalOutputDiagnostic = screen.finalOutputDiagnostic
        self.isAgentTurnInProgress = screen.isAgentTurnInProgress
        self.visibleLines = screen.visibleLines
        self.styledVisibleLines = screen.styledVisibleLines
        self.cursorRow = screen.cursorRow
        self.cursorColumn = screen.cursorColumn
        self.cursorVisible = screen.cursorVisible
    }

    public var screen: SessionScreen {
        SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: controller,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: extensionUI,
            slashCommands: slashCommands,
            providerEvents: providerEvents,
            providerFacts: providerFacts,
            finalOutputDiagnostic: finalOutputDiagnostic,
            isAgentTurnInProgress: isAgentTurnInProgress,
            visibleLines: visibleLines,
            styledVisibleLines: styledVisibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            cursorVisible: cursorVisible
        )
    }
}

public enum StructuredSessionObservationChange: Codable, Equatable, Sendable {
    case replaceSession(Session)
    case setController(SessionController)
    case setTranscript(String)
    case setTerminalSize(columns: Int, rows: Int)
    case appendActivityItems([SessionActivityItem])
    case replaceActivityItem(SessionActivityItem)
    case replaceActivityItemRange(startIndex: Int, items: [SessionActivityItem])
    case replaceActivityItems([SessionActivityItem])
    case replaceApprovalRequests([SessionApprovalRequest])
    case replaceExtensionUI(SessionExtensionUIState?)
    case replaceSlashCommands([SessionSlashCommand]?)
    case appendProviderEvents([SessionProviderEvent])
    case replaceProviderEvents([SessionProviderEvent])
    case replaceProviderFacts(StructuredSessionProviderFacts)
    case replaceFinalOutputDiagnostic(StructuredSessionFinalOutputDiagnostic?)
    case setAgentTurnInProgress(Bool)
}

public struct StructuredSessionObservationDelta: Codable, Equatable, Sendable {
    public let baseRevision: Int
    public let revision: Int
    public let changes: [StructuredSessionObservationChange]

    public init(baseRevision: Int, revision: Int, changes: [StructuredSessionObservationChange]) {
        self.baseRevision = baseRevision
        self.revision = revision
        self.changes = changes
    }
}

public struct SessionScreenObservationStart: Codable, Sendable {
    public let observationID: UUID
    public let screen: SessionScreen
    public let structuredSnapshot: StructuredSessionObservationSnapshot?

    public init(
        observationID: UUID,
        screen: SessionScreen,
        structuredSnapshot: StructuredSessionObservationSnapshot? = nil
    ) {
        self.observationID = observationID
        self.screen = screen
        self.structuredSnapshot = structuredSnapshot
    }
}

public struct SessionScreenObservationSnapshotResponse: Codable, Equatable, Sendable {
    public let screen: SessionScreen
    public let structuredSnapshot: StructuredSessionObservationSnapshot?

    public init(screen: SessionScreen, structuredSnapshot: StructuredSessionObservationSnapshot? = nil) {
        self.screen = screen
        self.structuredSnapshot = structuredSnapshot
    }
}

public enum SessionScreenObservationUpdate: Codable, Equatable, Sendable {
    case screen(SessionScreen)
    case structuredDelta(StructuredSessionObservationDelta)
    case structuredGap(currentRevision: Int)
}

public enum SessionScreenObservationGapError: Error, Equatable, Sendable {
    case structuredGap(expectedRevision: Int?, currentRevision: Int)
}

public final class SessionScreenObservationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var currentScreenValue: SessionScreen
    private var currentStructuredSnapshot: StructuredSessionObservationSnapshot?

    public init(start: SessionScreenObservationStart) {
        self.currentScreenValue = start.screen
        self.currentStructuredSnapshot = start.structuredSnapshot
    }

    public init(snapshot: SessionScreenObservationSnapshotResponse) {
        self.currentScreenValue = snapshot.screen
        self.currentStructuredSnapshot = snapshot.structuredSnapshot
    }

    public var currentScreen: SessionScreen {
        withLock { currentScreenValue }
    }

    public var currentStructuredRevision: Int? {
        withLock { currentStructuredSnapshot?.revision }
    }

    @discardableResult
    public func replace(with snapshot: SessionScreenObservationSnapshotResponse) -> SessionScreen {
        withLock {
            currentScreenValue = snapshot.screen
            currentStructuredSnapshot = snapshot.structuredSnapshot
            return currentScreenValue
        }
    }

    @discardableResult
    public func apply(_ update: SessionScreenObservationUpdate) throws -> SessionScreen? {
        try withLock {
            switch update {
            case .screen(let screen):
                guard screen != currentScreenValue else {
                    return nil
                }
                currentScreenValue = screen
                currentStructuredSnapshot = nil
                return currentScreenValue

            case .structuredGap(let currentRevision):
                throw SessionScreenObservationGapError.structuredGap(
                    expectedRevision: currentStructuredSnapshot?.revision,
                    currentRevision: currentRevision
                )

            case .structuredDelta(let delta):
                guard let snapshot = currentStructuredSnapshot else {
                    throw SessionScreenObservationGapError.structuredGap(
                        expectedRevision: nil,
                        currentRevision: delta.revision
                    )
                }
                guard snapshot.revision == delta.baseRevision else {
                    throw SessionScreenObservationGapError.structuredGap(
                        expectedRevision: snapshot.revision,
                        currentRevision: delta.revision
                    )
                }

                var state = StructuredSessionObservationMutableState(snapshot: snapshot)
                for change in delta.changes {
                    state.apply(change)
                }
                let updatedSnapshot = state.snapshot(revision: delta.revision)
                currentStructuredSnapshot = updatedSnapshot
                currentScreenValue = updatedSnapshot.screen
                return currentScreenValue
            }
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private struct StructuredSessionObservationMutableState {
    var session: Session
    var controller: SessionController
    var transcript: String
    var terminalColumns: Int
    var terminalRows: Int
    var activityItems: [SessionActivityItem]
    var approvalRequests: [SessionApprovalRequest]
    var extensionUI: SessionExtensionUIState?
    var slashCommands: [SessionSlashCommand]?
    var providerEvents: [SessionProviderEvent]
    var providerFacts: StructuredSessionProviderFacts
    var finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic?
    var isAgentTurnInProgress: Bool
    var visibleLines: [String]
    var styledVisibleLines: [TerminalLine]
    var cursorRow: Int
    var cursorColumn: Int
    var cursorVisible: Bool

    init(snapshot: StructuredSessionObservationSnapshot) {
        session = snapshot.session
        controller = snapshot.controller
        transcript = snapshot.transcript
        terminalColumns = snapshot.terminalColumns
        terminalRows = snapshot.terminalRows
        activityItems = snapshot.activityItems
        approvalRequests = snapshot.approvalRequests
        extensionUI = snapshot.extensionUI
        slashCommands = snapshot.slashCommands
        providerEvents = snapshot.providerEvents
        providerFacts = snapshot.providerFacts
        finalOutputDiagnostic = snapshot.finalOutputDiagnostic
        isAgentTurnInProgress = snapshot.isAgentTurnInProgress
        visibleLines = snapshot.visibleLines
        styledVisibleLines = snapshot.styledVisibleLines
        cursorRow = snapshot.cursorRow
        cursorColumn = snapshot.cursorColumn
        cursorVisible = snapshot.cursorVisible
    }

    mutating func apply(_ change: StructuredSessionObservationChange) {
        switch change {
        case .replaceSession(let updatedSession):
            session = updatedSession
        case .setController(let updatedController):
            controller = updatedController
        case .setTranscript(let updatedTranscript):
            transcript = updatedTranscript
        case .setTerminalSize(let columns, let rows):
            terminalColumns = columns
            terminalRows = rows
        case .appendActivityItems(let items):
            activityItems.append(contentsOf: items)
        case .replaceActivityItem(let item):
            guard let index = activityItems.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            activityItems[index] = item
        case .replaceActivityItemRange(let startIndex, let items):
            guard startIndex <= activityItems.count else {
                activityItems = items
                return
            }
            activityItems.replaceSubrange(startIndex..<activityItems.count, with: items)
        case .replaceActivityItems(let items):
            activityItems = items
        case .replaceApprovalRequests(let updatedApprovalRequests):
            approvalRequests = updatedApprovalRequests
        case .replaceExtensionUI(let updatedExtensionUI):
            extensionUI = updatedExtensionUI
        case .replaceSlashCommands(let updatedSlashCommands):
            slashCommands = updatedSlashCommands
        case .appendProviderEvents(let events):
            providerEvents.append(contentsOf: events)
        case .replaceProviderEvents(let events):
            providerEvents = events
        case .replaceProviderFacts(let updatedProviderFacts):
            providerFacts = updatedProviderFacts
        case .replaceFinalOutputDiagnostic(let updatedFinalOutputDiagnostic):
            finalOutputDiagnostic = updatedFinalOutputDiagnostic
        case .setAgentTurnInProgress(let updatedIsAgentTurnInProgress):
            isAgentTurnInProgress = updatedIsAgentTurnInProgress
        }
    }

    func snapshot(revision: Int) -> StructuredSessionObservationSnapshot {
        StructuredSessionObservationSnapshot(
            revision: revision,
            screen: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: controller,
                transcript: transcript,
                terminalColumns: terminalColumns,
                terminalRows: terminalRows,
                activityItems: activityItems,
                approvalRequests: approvalRequests,
                extensionUI: extensionUI,
                slashCommands: slashCommands,
                providerEvents: providerEvents,
                providerFacts: providerFacts,
                finalOutputDiagnostic: finalOutputDiagnostic,
                isAgentTurnInProgress: isAgentTurnInProgress,
                visibleLines: visibleLines,
                styledVisibleLines: styledVisibleLines,
                cursorRow: cursorRow,
                cursorColumn: cursorColumn,
                cursorVisible: cursorVisible
            )
        )
    }
}
