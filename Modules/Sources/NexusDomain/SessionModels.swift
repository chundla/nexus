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
    public let resolvedExecutable: String
    public let resolvedWorkingDirectory: String

    public init(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        resolvedExecutable: String,
        resolvedWorkingDirectory: String
    ) {
        self.sessionID = sessionID
        self.workspaceID = workspaceID
        self.providerID = providerID
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

public struct SessionActivityItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case status
        case message
    }

    public let id: UUID
    public let kind: Kind
    public let text: String

    public init(id: UUID = UUID(), kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public struct SessionScreen: Codable, Equatable, Sendable {
    public let session: Session
    public let controller: SessionController
    public let transcript: String
    public let terminalColumns: Int
    public let terminalRows: Int
    public let activityItems: [SessionActivityItem]
    public let visibleLines: [String]
    public let styledVisibleLines: [TerminalLine]
    public let cursorRow: Int
    public let cursorColumn: Int
    public let cursorVisible: Bool

    public init(
        session: Session,
        controller: SessionController = .mac,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        activityItems: [SessionActivityItem] = [],
        visibleLines: [String]? = nil,
        styledVisibleLines: [TerminalLine]? = nil,
        cursorRow: Int? = nil,
        cursorColumn: Int? = nil,
        cursorVisible: Bool = true
    ) {
        let viewport = Self.makeViewport(
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows
        )
        let resolvedVisibleLines = visibleLines ?? viewport.visibleLines

        self.session = session
        self.controller = controller
        self.transcript = transcript
        self.terminalColumns = terminalColumns
        self.terminalRows = terminalRows
        self.activityItems = activityItems
        self.visibleLines = resolvedVisibleLines
        self.styledVisibleLines = styledVisibleLines ?? resolvedVisibleLines.map(Self.defaultStyledLine)
        self.cursorRow = cursorRow ?? viewport.cursorRow
        self.cursorColumn = cursorColumn ?? viewport.cursorColumn
        self.cursorVisible = cursorVisible
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
