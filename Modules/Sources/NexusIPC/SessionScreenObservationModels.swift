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
            case let .screen(screen):
                guard screen != currentScreenValue else {
                    return nil
                }
                currentScreenValue = screen
                currentStructuredSnapshot = nil
                return currentScreenValue

            case let .structuredGap(currentRevision):
                throw SessionScreenObservationGapError.structuredGap(
                    expectedRevision: currentStructuredSnapshot?.revision,
                    currentRevision: currentRevision
                )

            case let .structuredDelta(delta):
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
        isAgentTurnInProgress = snapshot.isAgentTurnInProgress
        visibleLines = snapshot.visibleLines
        styledVisibleLines = snapshot.styledVisibleLines
        cursorRow = snapshot.cursorRow
        cursorColumn = snapshot.cursorColumn
        cursorVisible = snapshot.cursorVisible
    }

    mutating func apply(_ change: StructuredSessionObservationChange) {
        switch change {
        case let .replaceSession(updatedSession):
            session = updatedSession
        case let .setController(updatedController):
            controller = updatedController
        case let .setTranscript(updatedTranscript):
            transcript = updatedTranscript
        case let .setTerminalSize(columns, rows):
            terminalColumns = columns
            terminalRows = rows
        case let .appendActivityItems(items):
            activityItems.append(contentsOf: items)
        case let .replaceActivityItem(item):
            guard let index = activityItems.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            activityItems[index] = item
        case let .replaceActivityItemRange(startIndex, items):
            guard startIndex <= activityItems.count else {
                activityItems = items
                return
            }
            activityItems.replaceSubrange(startIndex..<activityItems.count, with: items)
        case let .replaceActivityItems(items):
            activityItems = items
        case let .replaceApprovalRequests(updatedApprovalRequests):
            approvalRequests = updatedApprovalRequests
        case let .replaceExtensionUI(updatedExtensionUI):
            extensionUI = updatedExtensionUI
        case let .replaceSlashCommands(updatedSlashCommands):
            slashCommands = updatedSlashCommands
        case let .appendProviderEvents(events):
            providerEvents.append(contentsOf: events)
        case let .replaceProviderEvents(events):
            providerEvents = events
        case let .setAgentTurnInProgress(updatedIsAgentTurnInProgress):
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
