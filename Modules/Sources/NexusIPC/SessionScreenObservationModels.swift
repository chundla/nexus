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
            isAgentTurnInProgress: isAgentTurnInProgress
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
                guard var snapshot = currentStructuredSnapshot else {
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

                for change in delta.changes {
                    apply(change, to: &snapshot)
                }
                snapshot = StructuredSessionObservationSnapshot(revision: delta.revision, screen: snapshot.screen)
                currentStructuredSnapshot = snapshot
                currentScreenValue = snapshot.screen
                return currentScreenValue
            }
        }
    }

    private func apply(
        _ change: StructuredSessionObservationChange,
        to snapshot: inout StructuredSessionObservationSnapshot
    ) {
        switch change {
        case let .replaceSession(session):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .setController(controller):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .setTranscript(transcript):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .setTerminalSize(columns, rows):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: columns,
                    terminalRows: rows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .appendActivityItems(items):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems + items,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .replaceActivityItem(item):
            let updatedItems = snapshot.activityItems.map { $0.id == item.id ? item : $0 }
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: updatedItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .replaceActivityItems(items):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: items,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .replaceApprovalRequests(approvalRequests):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .replaceExtensionUI(extensionUI):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .replaceSlashCommands(slashCommands):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .appendProviderEvents(providerEvents):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents + providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .replaceProviderEvents(providerEvents):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: providerEvents,
                    isAgentTurnInProgress: snapshot.isAgentTurnInProgress
                )
            )
        case let .setAgentTurnInProgress(isAgentTurnInProgress):
            snapshot = StructuredSessionObservationSnapshot(
                revision: snapshot.revision,
                screen: SessionScreen(
                    session: snapshot.session,
                    primarySurface: .structuredActivityFeed,
                    controller: snapshot.controller,
                    transcript: snapshot.transcript,
                    terminalColumns: snapshot.terminalColumns,
                    terminalRows: snapshot.terminalRows,
                    activityItems: snapshot.activityItems,
                    approvalRequests: snapshot.approvalRequests,
                    extensionUI: snapshot.extensionUI,
                    slashCommands: snapshot.slashCommands,
                    providerEvents: snapshot.providerEvents,
                    isAgentTurnInProgress: isAgentTurnInProgress
                )
            )
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
