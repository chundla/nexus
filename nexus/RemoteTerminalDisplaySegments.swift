import Foundation
import NexusDomain

func renderedRemoteTerminalDisplaySegments(for line: TerminalLine, row: Int, screen: SessionScreen)
    -> [RemoteTerminalDisplaySegment]
{
    let targetColumnCount = max(1, screen.terminalColumns)
    let cursorColumn = max(0, min(screen.cursorColumn, targetColumnCount - 1))
    var segments: [RemoteTerminalDisplaySegment] = []

    for column in 0..<targetColumnCount {
        let sourceCell = column < line.cells.count ? line.cells[column] : TerminalCell(text: " ")
        let isCursor = screen.cursorVisible && row == screen.cursorRow && column == cursorColumn

        if let lastIndex = segments.indices.last,
            segments[lastIndex].style == sourceCell.style,
            segments[lastIndex].isCursor == isCursor
        {
            segments[lastIndex].text.append(sourceCell.text)
            segments[lastIndex].columnCount += 1
        } else {
            segments.append(
                RemoteTerminalDisplaySegment(
                    text: sourceCell.text,
                    style: sourceCell.style,
                    columnCount: 1,
                    isCursor: isCursor
                )
            )
        }
    }

    return segments
}

struct RemoteTerminalDisplaySegment: Equatable {
    var text: String
    let style: TerminalStyle
    var columnCount: Int
    var isCursor = false

    var renderedText: String {
        if text.isEmpty {
            return String(repeating: "\u{00A0}", count: max(1, columnCount))
        }

        return text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
