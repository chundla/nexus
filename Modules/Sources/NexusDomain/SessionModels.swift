import Foundation

public enum SessionInputKey: String, Codable, CaseIterable, Sendable {
    case enter
    case tab
    case escape
    case backspace
    case deleteForward
    case endOfTransmission
    case interrupt
    case home
    case end
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
}

public struct SessionPromptImage: Codable, Equatable, Sendable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct SessionPrompt: Codable, Equatable, Sendable {
    public let text: String
    public let images: [SessionPromptImage]

    public init(text: String, images: [SessionPromptImage] = []) {
        self.text = text
        self.images = images
    }
}

public struct Session: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let workspaceID: UUID
    public let providerID: ProviderID
    public let name: String?
    public let isDefault: Bool
    public let state: State
    public let failureMessage: String?

    public init(
        id: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        name: String? = nil,
        isDefault: Bool,
        state: State,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.name = name
        self.isDefault = isDefault
        self.state = state
        self.failureMessage = failureMessage
    }

    public enum State: String, Codable, Hashable, Sendable {
        case ready
        case interrupted
        case exited
        case failed
    }
}

public struct LaunchSnapshot: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let workspaceID: UUID
    public let providerID: ProviderID
    public let primarySurface: SessionSurface
    public let resolvedExecutable: String
    public let resolvedWorkingDirectory: String

    public init(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        primarySurface: SessionSurface = .terminal,
        resolvedExecutable: String,
        resolvedWorkingDirectory: String
    ) {
        self.sessionID = sessionID
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.primarySurface = primarySurface
        self.resolvedExecutable = resolvedExecutable
        self.resolvedWorkingDirectory = resolvedWorkingDirectory
    }
}

public struct TerminalColor: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case ansi256
        case rgb
    }

    public let kind: Kind
    public let index: Int?
    public let red: Int?
    public let green: Int?
    public let blue: Int?

    public init(kind: Kind, index: Int? = nil, red: Int? = nil, green: Int? = nil, blue: Int? = nil) {
        self.kind = kind
        self.index = index
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static func ansi256(_ index: Int) -> TerminalColor {
        TerminalColor(kind: .ansi256, index: index)
    }

    public static func rgb(red: Int, green: Int, blue: Int) -> TerminalColor {
        TerminalColor(kind: .rgb, red: red, green: green, blue: blue)
    }
}

public struct TerminalStyle: Codable, Equatable, Sendable {
    public let foregroundColor: TerminalColor?
    public let backgroundColor: TerminalColor?
    public let isBold: Bool
    public let isDim: Bool
    public let isItalic: Bool
    public let isInverse: Bool

    public init(
        foregroundColor: TerminalColor? = nil,
        backgroundColor: TerminalColor? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isInverse: Bool = false
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isInverse = isInverse
    }
}

public struct TerminalCell: Codable, Equatable, Sendable {
    public let text: String
    public let style: TerminalStyle

    public init(text: String, style: TerminalStyle = TerminalStyle()) {
        self.text = text
        self.style = style
    }
}

public struct TerminalLine: Codable, Equatable, Sendable {
    public let cells: [TerminalCell]

    public init(cells: [TerminalCell] = []) {
        self.cells = cells
    }

    public var text: String {
        cells.map(\.text).joined()
    }
}

public enum SessionController: Codable, Equatable, Sendable {
    case mac
    case pairedDevice(UUID)
}

public enum SessionSurface: String, Codable, Equatable, Sendable {
    case terminal
    case structuredActivityFeed
}

public enum SessionSurfaceSupport: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
}

public struct SessionActivityItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case status
        case message
        case approvalRequest
        case approvalDecision
        case progress
        case command
        case diff
        case error
        case completion
    }

    public let id: UUID
    public let kind: Kind
    public let text: String
    public let detailText: String?
    public let prompt: SessionPrompt?

    public init(id: UUID = UUID(), kind: Kind, text: String, detailText: String? = nil, prompt: SessionPrompt? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detailText = detailText
        self.prompt = prompt
    }

    public init(id: UUID = UUID(), kind: Kind, text: String) {
        self.init(id: id, kind: kind, text: text, detailText: nil, prompt: nil)
    }
}

public enum ApprovalRequestDecision: String, Codable, CaseIterable, Sendable {
    case approve
    case deny
}

public struct SessionApprovalRequest: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case pending
        case approved
        case denied
    }

    public let id: UUID
    public let title: String
    public let text: String
    public let state: State

    public init(id: UUID = UUID(), title: String, text: String, state: State) {
        self.id = id
        self.title = title
        self.text = text
        self.state = state
    }
}

public enum SessionExtensionUIDialogKind: String, Codable, CaseIterable, Sendable {
    case select
    case confirm
    case input
    case editor
}

public struct SessionExtensionUIDialog: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: SessionExtensionUIDialogKind
    public let title: String
    public let message: String?
    public let options: [String]
    public let placeholder: String?
    public let prefill: String?
    public let timeoutMilliseconds: Int?

    public init(
        id: String,
        kind: SessionExtensionUIDialogKind,
        title: String,
        message: String? = nil,
        options: [String] = [],
        placeholder: String? = nil,
        prefill: String? = nil,
        timeoutMilliseconds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.options = options
        self.placeholder = placeholder
        self.prefill = prefill
        self.timeoutMilliseconds = timeoutMilliseconds
    }
}

public enum SessionExtensionUINotificationKind: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct SessionExtensionUINotification: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: SessionExtensionUINotificationKind
    public let message: String

    public init(id: UUID = UUID(), kind: SessionExtensionUINotificationKind, message: String) {
        self.id = id
        self.kind = kind
        self.message = message
    }
}

public struct SessionExtensionUIStatus: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let text: String

    public var id: String { key }

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

public enum SessionExtensionUIWidgetPlacement: String, Codable, Equatable, Sendable {
    case aboveEditor
    case belowEditor
}

public struct SessionExtensionUIWidget: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let lines: [String]
    public let placement: SessionExtensionUIWidgetPlacement

    public var id: String { key }

    public init(key: String, lines: [String], placement: SessionExtensionUIWidgetPlacement = .aboveEditor) {
        self.key = key
        self.lines = lines
        self.placement = placement
    }
}

public struct SessionExtensionUIState: Codable, Equatable, Sendable {
    public let title: String?
    public let pendingDialogs: [SessionExtensionUIDialog]
    public let notifications: [SessionExtensionUINotification]
    public let statuses: [SessionExtensionUIStatus]
    public let widgets: [SessionExtensionUIWidget]
    public let editorText: String?

    public init(
        title: String? = nil,
        pendingDialogs: [SessionExtensionUIDialog] = [],
        notifications: [SessionExtensionUINotification] = [],
        statuses: [SessionExtensionUIStatus] = [],
        widgets: [SessionExtensionUIWidget] = [],
        editorText: String? = nil
    ) {
        self.title = title
        self.pendingDialogs = pendingDialogs
        self.notifications = notifications
        self.statuses = statuses
        self.widgets = widgets
        self.editorText = editorText
    }
}

public struct SessionExtensionUIDialogResponse: Codable, Equatable, Sendable {
    public let value: String?
    public let confirmed: Bool?
    public let cancelled: Bool

    public init(value: String? = nil, confirmed: Bool? = nil, cancelled: Bool = false) {
        self.value = value
        self.confirmed = confirmed
        self.cancelled = cancelled
    }

    public static func value(_ value: String) -> SessionExtensionUIDialogResponse {
        SessionExtensionUIDialogResponse(value: value)
    }

    public static func confirmed(_ confirmed: Bool) -> SessionExtensionUIDialogResponse {
        SessionExtensionUIDialogResponse(confirmed: confirmed)
    }

    public static let cancelled = SessionExtensionUIDialogResponse(cancelled: true)
}

public enum SessionSlashCommandSource: String, Codable, Equatable, Sendable {
    case builtIn
    case `extension`
    case prompt
    case skill
}

public enum SessionSlashCommandLocation: String, Codable, Equatable, Sendable {
    case user
    case project
    case path
}

public struct SessionSlashCommand: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let displayName: String?
    public let insertionText: String?
    public let suggestionQueryPrefix: String?
    public let description: String?
    public let source: SessionSlashCommandSource
    public let location: SessionSlashCommandLocation?
    public let path: String?

    public var id: String { name }

    public init(
        name: String,
        displayName: String? = nil,
        insertionText: String? = nil,
        suggestionQueryPrefix: String? = nil,
        description: String? = nil,
        source: SessionSlashCommandSource,
        location: SessionSlashCommandLocation? = nil,
        path: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.insertionText = insertionText
        self.suggestionQueryPrefix = suggestionQueryPrefix
        self.description = description
        self.source = source
        self.location = location
        self.path = path
    }
}

public struct SessionProviderEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Family: String, Codable, Sendable {
        case response
        case agent
        case turn
        case message
        case toolExecution
        case queue
        case compaction
        case retry
        case extensionError
        case unknown
    }

    public let sequence: Int
    public let providerID: ProviderID
    public let type: String
    public let family: Family
    public let command: String?
    public let rawPayload: String

    public var id: Int { sequence }

    public init(
        sequence: Int,
        providerID: ProviderID,
        type: String,
        family: Family,
        command: String? = nil,
        rawPayload: String
    ) {
        self.sequence = sequence
        self.providerID = providerID
        self.type = type
        self.family = family
        self.command = command
        self.rawPayload = rawPayload
    }
}

public enum StructuredSessionFinalOutputTrigger: String, Codable, Equatable, Sendable {
    case textDelta
    case turnEnd
}

public struct StructuredSessionFinalOutputDiagnostic: Codable, Equatable, Sendable {
    public let trigger: StructuredSessionFinalOutputTrigger
    public let providerEventSequence: Int
    public let providerRuntimeLatencyMilliseconds: Int
    public let serviceObservationLatencyMilliseconds: Int?
    public let expectedActivityItemID: UUID?
    public let expectedActivityItemText: String?
    public let expectedThinkingIndicatorVisible: Bool
    public let serviceObservationAnchorUptimeNanoseconds: UInt64?

    public init(
        trigger: StructuredSessionFinalOutputTrigger,
        providerEventSequence: Int,
        providerRuntimeLatencyMilliseconds: Int,
        serviceObservationLatencyMilliseconds: Int? = nil,
        expectedActivityItemID: UUID? = nil,
        expectedActivityItemText: String? = nil,
        expectedThinkingIndicatorVisible: Bool,
        serviceObservationAnchorUptimeNanoseconds: UInt64? = nil
    ) {
        self.trigger = trigger
        self.providerEventSequence = providerEventSequence
        self.providerRuntimeLatencyMilliseconds = providerRuntimeLatencyMilliseconds
        self.serviceObservationLatencyMilliseconds = serviceObservationLatencyMilliseconds
        self.expectedActivityItemID = expectedActivityItemID
        self.expectedActivityItemText = expectedActivityItemText
        self.expectedThinkingIndicatorVisible = expectedThinkingIndicatorVisible
        self.serviceObservationAnchorUptimeNanoseconds = serviceObservationAnchorUptimeNanoseconds
    }

    public func observed(serviceObservationLatencyMilliseconds: Int) -> StructuredSessionFinalOutputDiagnostic {
        StructuredSessionFinalOutputDiagnostic(
            trigger: trigger,
            providerEventSequence: providerEventSequence,
            providerRuntimeLatencyMilliseconds: providerRuntimeLatencyMilliseconds,
            serviceObservationLatencyMilliseconds: serviceObservationLatencyMilliseconds,
            expectedActivityItemID: expectedActivityItemID,
            expectedActivityItemText: expectedActivityItemText,
            expectedThinkingIndicatorVisible: expectedThinkingIndicatorVisible,
            serviceObservationAnchorUptimeNanoseconds: nil
        )
    }
}

public struct SessionScreen: Codable, Equatable, Sendable {
    public let session: Session
    public let primarySurface: SessionSurface
    public let controller: SessionController
    public let transcript: String
    public let terminalColumns: Int
    public let terminalRows: Int
    public let activityItems: [SessionActivityItem]
    public let approvalRequests: [SessionApprovalRequest]
    public let extensionUI: SessionExtensionUIState?
    public let slashCommands: [SessionSlashCommand]?
    public let providerEvents: [SessionProviderEvent]
    public let finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic?
    public let isAgentTurnInProgress: Bool
    public let visibleLines: [String]
    public let styledVisibleLines: [TerminalLine]
    public let cursorRow: Int
    public let cursorColumn: Int
    public let cursorVisible: Bool

    public init(
        session: Session,
        primarySurface: SessionSurface = .terminal,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        extensionUI: SessionExtensionUIState? = nil,
        slashCommands: [SessionSlashCommand]? = nil,
        providerEvents: [SessionProviderEvent] = [],
        isAgentTurnInProgress: Bool = false,
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        self.init(
            session: session,
            primarySurface: primarySurface,
            controller: controller,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: extensionUI,
            slashCommands: slashCommands,
            providerEvents: providerEvents,
            finalOutputDiagnostic: nil,
            isAgentTurnInProgress: isAgentTurnInProgress,
            visibleLines: visibleLines,
            styledVisibleLines: styledVisibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            cursorVisible: cursorVisible
        )
    }

    public init(
        session: Session,
        primarySurface: SessionSurface = .terminal,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        extensionUI: SessionExtensionUIState? = nil,
        slashCommands: [SessionSlashCommand]? = nil,
        providerEvents: [SessionProviderEvent] = [],
        finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic? = nil,
        isAgentTurnInProgress: Bool = false,
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        let resolvedVisibleLines: [String]
        let resolvedStyledVisibleLines: [TerminalLine]
        let resolvedCursorRow: Int
        let resolvedCursorColumn: Int

        if let visibleLines, let cursorRow, let cursorColumn {
            resolvedVisibleLines = visibleLines
            resolvedStyledVisibleLines = styledVisibleLines ?? visibleLines.map(Self.defaultStyledLine)
            resolvedCursorRow = cursorRow
            resolvedCursorColumn = cursorColumn
        } else {
            let viewport = Self.makeViewport(
                transcript: transcript,
                terminalColumns: terminalColumns,
                terminalRows: terminalRows
            )
            resolvedVisibleLines = visibleLines ?? viewport.visibleLines
            resolvedStyledVisibleLines = styledVisibleLines ?? resolvedVisibleLines.map(Self.defaultStyledLine)
            resolvedCursorRow = cursorRow ?? viewport.cursorRow
            resolvedCursorColumn = cursorColumn ?? viewport.cursorColumn
        }

        self.session = session
        self.primarySurface = primarySurface
        self.controller = controller
        self.transcript = transcript
        self.terminalColumns = terminalColumns
        self.terminalRows = terminalRows
        self.activityItems = activityItems
        self.approvalRequests = approvalRequests
        self.extensionUI = extensionUI
        self.slashCommands = slashCommands
        self.providerEvents = providerEvents
        self.finalOutputDiagnostic = finalOutputDiagnostic
        self.isAgentTurnInProgress = isAgentTurnInProgress
        self.visibleLines = resolvedVisibleLines
        self.styledVisibleLines = resolvedStyledVisibleLines
        self.cursorRow = resolvedCursorRow
        self.cursorColumn = resolvedCursorColumn
        self.cursorVisible = cursorVisible
    }

    public init(
        session: Session,
        primarySurface: SessionSurface = .terminal,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        extensionUI: SessionExtensionUIState? = nil,
        slashCommands: [SessionSlashCommand]? = nil,
        isAgentTurnInProgress: Bool = false,
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        self.init(
            session: session,
            primarySurface: primarySurface,
            controller: controller,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: extensionUI,
            slashCommands: slashCommands,
            providerEvents: [],
            finalOutputDiagnostic: nil,
            isAgentTurnInProgress: isAgentTurnInProgress,
            visibleLines: visibleLines,
            styledVisibleLines: styledVisibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            cursorVisible: cursorVisible
        )
    }

    public init(
        session: Session,
        primarySurface: SessionSurface = .terminal,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        extensionUI: SessionExtensionUIState? = nil,
        slashCommands: [SessionSlashCommand]? = nil,
        finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic? = nil,
        isAgentTurnInProgress: Bool = false,
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        self.init(
            session: session,
            primarySurface: primarySurface,
            controller: controller,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: extensionUI,
            slashCommands: slashCommands,
            providerEvents: [],
            finalOutputDiagnostic: finalOutputDiagnostic,
            isAgentTurnInProgress: isAgentTurnInProgress,
            visibleLines: visibleLines,
            styledVisibleLines: styledVisibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            cursorVisible: cursorVisible
        )
    }

    public init(
        session: Session,
        primarySurface: SessionSurface = .terminal,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        slashCommands: [SessionSlashCommand]? = nil,
        isAgentTurnInProgress: Bool = false,
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        self.init(
            session: session,
            primarySurface: primarySurface,
            controller: controller,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: nil,
            slashCommands: slashCommands,
            providerEvents: [],
            finalOutputDiagnostic: nil,
            isAgentTurnInProgress: isAgentTurnInProgress,
            visibleLines: visibleLines,
            styledVisibleLines: styledVisibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            cursorVisible: cursorVisible
        )
    }

    public init(
        session: Session,
        primarySurface: SessionSurface = .terminal,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        slashCommands: [SessionSlashCommand]? = nil,
        finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic? = nil,
        isAgentTurnInProgress: Bool = false,
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        self.init(
            session: session,
            primarySurface: primarySurface,
            controller: controller,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems,
            approvalRequests: approvalRequests,
            extensionUI: nil,
            slashCommands: slashCommands,
            providerEvents: [],
            finalOutputDiagnostic: finalOutputDiagnostic,
            isAgentTurnInProgress: isAgentTurnInProgress,
            visibleLines: visibleLines,
            styledVisibleLines: styledVisibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            cursorVisible: cursorVisible
        )
    }

    private static func defaultStyledLine(for line: String) -> TerminalLine {
        TerminalLine(cells: line.map { TerminalCell(text: String($0)) })
    }

    private static func makeViewport(
        transcript: String,
        terminalColumns: Int,
        terminalRows: Int
    ) -> (visibleLines: [String], cursorRow: Int, cursorColumn: Int) {
        let columns = max(1, terminalColumns)
        let rows = max(1, terminalRows)
        var wrappedLines: [String] = []

        for rawLine in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.isEmpty {
                wrappedLines.append("")
                continue
            }

            var startIndex = line.startIndex
            while startIndex < line.endIndex {
                let endIndex = line.index(startIndex, offsetBy: columns, limitedBy: line.endIndex) ?? line.endIndex
                wrappedLines.append(String(line[startIndex..<endIndex]))
                startIndex = endIndex
            }
        }

        if wrappedLines.isEmpty {
            wrappedLines = [""]
        }

        let cursorSourceLine = wrappedLines.last ?? ""
        let visibleLines = Array(wrappedLines.suffix(rows))
        let cursorRow = max(0, visibleLines.count - 1)
        let cursorColumn = min(cursorSourceLine.count, columns)
        return (visibleLines, cursorRow, cursorColumn)
    }
}
