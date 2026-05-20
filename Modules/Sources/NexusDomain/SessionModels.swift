import Foundation

public struct Session: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let workspaceID: UUID
    public let providerID: ProviderID
    public let isDefault: Bool
    public let state: State
    public let failureMessage: String?

    public init(
        id: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        isDefault: Bool,
        state: State,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.isDefault = isDefault
        self.state = state
        self.failureMessage = failureMessage
    }

    public enum State: String, Codable, Sendable {
        case ready
        case interrupted
        case exited
        case failed
    }
}

public struct SessionScreen: Codable, Equatable, Sendable {
    public let session: Session
    public let transcript: String
    public let terminalColumns: Int
    public let terminalRows: Int
    public let visibleLines: [String]

    public init(
        session: Session,
        transcript: String,
        terminalColumns: Int = 80,
        terminalRows: Int = 24,
        visibleLines: [String]? = nil
    ) {
        self.session = session
        self.transcript = transcript
        self.terminalColumns = terminalColumns
        self.terminalRows = terminalRows
        self.visibleLines = visibleLines ?? Self.makeVisibleLines(
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows
        )
    }

    private static func makeVisibleLines(
        transcript: String,
        terminalColumns: Int,
        terminalRows: Int
    ) -> [String] {
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
            return [""]
        }

        return Array(wrappedLines.suffix(rows))
    }
}
