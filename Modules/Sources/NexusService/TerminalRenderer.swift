#if os(macOS)
    import Foundation
    import NexusDomain

    struct UTF8StreamDecoder {
        private var pending = Data()

        mutating func decode(_ data: Data) -> String {
            pending.append(data)
            guard pending.isEmpty == false else {
                return ""
            }

            let maxDeferredBytes = min(3, pending.count)
            for deferredBytes in 0...maxDeferredBytes {
                let prefixCount = pending.count - deferredBytes
                guard prefixCount > 0 else {
                    continue
                }

                let prefix = pending.prefix(prefixCount)
                guard let decoded = String(data: prefix, encoding: .utf8) else {
                    continue
                }

                pending = Data(pending.suffix(deferredBytes))
                return decoded
            }

            return ""
        }

        mutating func finish() -> String {
            guard pending.isEmpty == false else {
                return ""
            }

            let decoded = String(decoding: pending, as: UTF8.self)
            pending.removeAll()
            return decoded
        }
    }

    struct TerminalRenderState {
        let transcript: String
        let visibleLines: [String]
        let styledVisibleLines: [TerminalLine]
        let cursorRow: Int
        let cursorColumn: Int
        let cursorVisible: Bool
        let applicationCursorMode: Bool
    }

    enum TerminalRenderer {
        static func renderState(
            from transcript: String,
            terminalColumns: Int,
            terminalRows: Int
        ) -> TerminalRenderState {
            var lines: [[TerminalCell]] = [[]]
            var cursorLine = 0
            var cursorColumn = 0
            var cursorVisible = true
            var applicationCursorMode = false
            var originMode = false
            var savedCursorLine = 0
            var savedCursorColumn = 0
            var currentStyle = TerminalStyle()

            enum TerminalCharacterSet {
                case ascii
                case lineDrawing
            }

            var usingAlternateBuffer = false
            var pendingAutoWrap = false
            var scrollRegionTop = 0
            var scrollRegionBottom = max(0, terminalRows - 1)
            var hasExplicitScrollRegion = false
            var g0CharacterSet: TerminalCharacterSet = .ascii
            var g1CharacterSet: TerminalCharacterSet = .ascii
            var usingG1CharacterSet = false
            var lastRenderedCharacter: Character?
            var primaryBufferLines = lines
            var wrappedLineContinuations = [false]
            var primaryBufferWrappedLineContinuations = wrappedLineContinuations
            var primaryBufferCursorLine = cursorLine
            var primaryBufferCursorColumn = cursorColumn
            var primaryBufferCursorVisible = cursorVisible
            var primaryBufferApplicationCursorMode = applicationCursorMode
            var primaryBufferOriginMode = originMode
            var primaryBufferSavedCursorLine = savedCursorLine
            var primaryBufferSavedCursorColumn = savedCursorColumn
            var primaryBufferScrollRegionTop = scrollRegionTop
            var primaryBufferScrollRegionBottom = scrollRegionBottom
            var primaryBufferHasExplicitScrollRegion = hasExplicitScrollRegion
            var primaryBufferG0CharacterSet = g0CharacterSet
            var primaryBufferG1CharacterSet = g1CharacterSet
            var primaryBufferUsingG1CharacterSet = usingG1CharacterSet
            var primaryBufferStyle = currentStyle
            var iterator = transcript.unicodeScalars.makeIterator()

            func blankCell(style: TerminalStyle? = nil) -> TerminalCell {
                TerminalCell(text: " ", style: style ?? currentStyle)
            }

            func ensureLine(_ lineIndex: Int) {
                while lines.count <= lineIndex {
                    lines.append([])
                    wrappedLineContinuations.append(false)
                }
            }

            func ensureCurrentLine() {
                ensureLine(cursorLine)
            }

            func padCurrentLine(to column: Int, style: TerminalStyle? = nil) {
                ensureCurrentLine()
                while lines[cursorLine].count < column {
                    lines[cursorLine].append(blankCell(style: style))
                }
            }

            func advanceToNextLine(wrappedFromPrevious: Bool = false) {
                if let region = activeScrollRegion() {
                    if cursorLine == region.upperBound {
                        scrollUpWithinRegion(1)
                    } else {
                        cursorLine += 1
                    }
                } else {
                    cursorLine += 1
                }
                cursorColumn = 0
                ensureCurrentLine()
                wrappedLineContinuations[cursorLine] = wrappedFromPrevious
                pendingAutoWrap = false
            }

            func wrapIfNeededBeforeWriting() {
                guard pendingAutoWrap else {
                    return
                }
                advanceToNextLine(wrappedFromPrevious: true)
            }

            func activeScrollRegion() -> ClosedRange<Int>? {
                guard hasExplicitScrollRegion else {
                    return nil
                }

                let top = max(0, scrollRegionTop)
                let bottom = max(top, scrollRegionBottom)
                ensureLine(bottom)
                return top...bottom
            }

            func explicitScrollRegion() -> ClosedRange<Int> {
                let top = max(0, scrollRegionTop)
                let bottom = max(top, scrollRegionBottom)
                ensureLine(bottom)
                return top...bottom
            }

            func scrollUpWithinRegion(_ count: Int) {
                let region = explicitScrollRegion()
                let scrollCount = max(0, count)
                guard scrollCount > 0 else {
                    return
                }

                let regionHeight = region.count
                if scrollCount >= regionHeight {
                    for lineIndex in region {
                        lines[lineIndex] = []
                    }
                    return
                }

                lines.removeSubrange(region.lowerBound..<(region.lowerBound + scrollCount))
                wrappedLineContinuations.removeSubrange(region.lowerBound..<(region.lowerBound + scrollCount))
                lines.insert(
                    contentsOf: Array(repeating: [], count: scrollCount), at: region.upperBound - scrollCount + 1)
                wrappedLineContinuations.insert(
                    contentsOf: Array(repeating: false, count: scrollCount), at: region.upperBound - scrollCount + 1)
            }

            func scrollDownWithinRegion(_ count: Int) {
                let region = explicitScrollRegion()
                let scrollCount = max(0, count)
                guard scrollCount > 0 else {
                    return
                }

                let regionHeight = region.count
                if scrollCount >= regionHeight {
                    for lineIndex in region {
                        lines[lineIndex] = []
                    }
                    return
                }

                lines.removeSubrange((region.upperBound - scrollCount + 1)...region.upperBound)
                wrappedLineContinuations.removeSubrange((region.upperBound - scrollCount + 1)...region.upperBound)
                lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: region.lowerBound)
                wrappedLineContinuations.insert(
                    contentsOf: Array(repeating: false, count: scrollCount), at: region.lowerBound)
            }

            func insertBlankLinesWithinRegion(_ count: Int, at lineIndex: Int) {
                let region = explicitScrollRegion()
                guard region.contains(lineIndex) else {
                    return
                }

                let insertCount = min(max(0, count), region.upperBound - lineIndex + 1)
                guard insertCount > 0 else {
                    return
                }

                let regionSlice = Array(lines[lineIndex...region.upperBound])
                let continuationSlice = Array(wrappedLineContinuations[lineIndex...region.upperBound])
                let replacement =
                    Array(repeating: [TerminalCell](), count: insertCount) + Array(regionSlice.dropLast(insertCount))
                let continuationReplacement =
                    Array(repeating: false, count: insertCount) + Array(continuationSlice.dropLast(insertCount))
                lines.replaceSubrange(lineIndex...region.upperBound, with: replacement)
                wrappedLineContinuations.replaceSubrange(lineIndex...region.upperBound, with: continuationReplacement)
            }

            func deleteLinesWithinRegion(_ count: Int, at lineIndex: Int) {
                let region = explicitScrollRegion()
                guard region.contains(lineIndex) else {
                    return
                }

                let deleteCount = min(max(0, count), region.upperBound - lineIndex + 1)
                guard deleteCount > 0 else {
                    return
                }

                let regionSlice = Array(lines[lineIndex...region.upperBound])
                let continuationSlice = Array(wrappedLineContinuations[lineIndex...region.upperBound])
                let replacement =
                    Array(regionSlice.dropFirst(deleteCount)) + Array(repeating: [TerminalCell](), count: deleteCount)
                let continuationReplacement =
                    Array(continuationSlice.dropFirst(deleteCount)) + Array(repeating: false, count: deleteCount)
                lines.replaceSubrange(lineIndex...region.upperBound, with: replacement)
                wrappedLineContinuations.replaceSubrange(lineIndex...region.upperBound, with: continuationReplacement)
            }

            func csiParameters(_ parameters: String) -> [Int?] {
                guard parameters.isEmpty == false else {
                    return []
                }

                return
                    parameters
                    .split(separator: ";", omittingEmptySubsequences: false)
                    .map { segment in
                        guard segment.isEmpty == false else {
                            return nil
                        }
                        return Int(segment)
                    }
            }

            func skipStringCommand(allowBellTerminator: Bool) {
                while let scalar = iterator.next() {
                    if allowBellTerminator, scalar == "\u{0007}" {
                        return
                    }

                    if scalar == "\u{001B}", let terminator = iterator.next(), terminator == "\\" {
                        return
                    }
                }
            }

            func skipOperatingSystemCommand() {
                skipStringCommand(allowBellTerminator: true)
            }

            func characterSet(for designator: UnicodeScalar) -> TerminalCharacterSet? {
                switch designator {
                case "0":
                    .lineDrawing
                case "B":
                    .ascii
                default:
                    nil
                }
            }

            func renderedCharacter(for scalar: UnicodeScalar) -> Character {
                let activeCharacterSet = usingG1CharacterSet ? g1CharacterSet : g0CharacterSet
                guard activeCharacterSet == .lineDrawing else {
                    return Character(scalar)
                }

                switch scalar {
                case "j": return "┘"
                case "k": return "┐"
                case "l": return "┌"
                case "m": return "└"
                case "n": return "┼"
                case "q": return "─"
                case "t": return "├"
                case "u": return "┤"
                case "v": return "┴"
                case "w": return "┬"
                case "x": return "│"
                default: return Character(scalar)
                }
            }

            func setColor(_ color: TerminalColor?, isForeground: Bool) {
                currentStyle = TerminalStyle(
                    foregroundColor: isForeground ? color : currentStyle.foregroundColor,
                    backgroundColor: isForeground ? currentStyle.backgroundColor : color,
                    isBold: currentStyle.isBold,
                    isDim: currentStyle.isDim,
                    isItalic: currentStyle.isItalic,
                    isInverse: currentStyle.isInverse
                )
            }

            func applySGR(parameters: String) {
                let rawValues = csiParameters(parameters)
                let values = rawValues.isEmpty ? [0] : rawValues
                var index = 0

                while index < values.count {
                    let value = values[index] ?? 0

                    switch value {
                    case 0:
                        currentStyle = TerminalStyle()
                    case 1:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: true,
                            isDim: currentStyle.isDim,
                            isItalic: currentStyle.isItalic,
                            isInverse: currentStyle.isInverse
                        )
                    case 2:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: currentStyle.isBold,
                            isDim: true,
                            isItalic: currentStyle.isItalic,
                            isInverse: currentStyle.isInverse
                        )
                    case 3:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: currentStyle.isBold,
                            isDim: currentStyle.isDim,
                            isItalic: true,
                            isInverse: currentStyle.isInverse
                        )
                    case 22:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: false,
                            isDim: false,
                            isItalic: currentStyle.isItalic,
                            isInverse: currentStyle.isInverse
                        )
                    case 23:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: currentStyle.isBold,
                            isDim: currentStyle.isDim,
                            isItalic: false,
                            isInverse: currentStyle.isInverse
                        )
                    case 7:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: currentStyle.isBold,
                            isDim: currentStyle.isDim,
                            isItalic: currentStyle.isItalic,
                            isInverse: true
                        )
                    case 27:
                        currentStyle = TerminalStyle(
                            foregroundColor: currentStyle.foregroundColor,
                            backgroundColor: currentStyle.backgroundColor,
                            isBold: currentStyle.isBold,
                            isDim: currentStyle.isDim,
                            isItalic: currentStyle.isItalic,
                            isInverse: false
                        )
                    case 30...37:
                        setColor(.ansi256(value - 30), isForeground: true)
                    case 39:
                        setColor(nil, isForeground: true)
                    case 40...47:
                        setColor(.ansi256(value - 40), isForeground: false)
                    case 49:
                        setColor(nil, isForeground: false)
                    case 90...97:
                        setColor(.ansi256((value - 90) + 8), isForeground: true)
                    case 100...107:
                        setColor(.ansi256((value - 100) + 8), isForeground: false)
                    case 38, 48:
                        let isForeground = value == 38
                        guard index + 1 < values.count, let mode = values[index + 1] else {
                            break
                        }

                        switch mode {
                        case 5:
                            guard index + 2 < values.count, let colorIndex = values[index + 2] else {
                                break
                            }
                            setColor(.ansi256(colorIndex), isForeground: isForeground)
                            index += 2
                        case 2:
                            guard index + 4 < values.count,
                                let red = values[index + 2],
                                let green = values[index + 3],
                                let blue = values[index + 4]
                            else {
                                break
                            }
                            setColor(.rgb(red: red, green: green, blue: blue), isForeground: isForeground)
                            index += 4
                        default:
                            break
                        }
                    default:
                        break
                    }

                    index += 1
                }
            }

            func parseCSI(finalCharacter: UnicodeScalar, parameters: String) {
                let finalCharacter = Character(finalCharacter)
                let isPrivateMode = parameters.first == "?"
                let normalizedParameters = isPrivateMode ? String(parameters.dropFirst()) : parameters
                let values = csiParameters(normalizedParameters)
                let value = values.first.flatMap { $0 }
                let defaultValue = value ?? 1
                let eraseMode = value ?? 0

                if isPrivateMode {
                    switch finalCharacter {
                    case "h":
                        switch value {
                        case 1:
                            applicationCursorMode = true
                        case 6:
                            originMode = true
                        case 47, 1047, 1049:
                            guard usingAlternateBuffer == false else {
                                break
                            }
                            primaryBufferLines = lines
                            primaryBufferWrappedLineContinuations = wrappedLineContinuations
                            primaryBufferCursorLine = cursorLine
                            primaryBufferCursorColumn = cursorColumn
                            primaryBufferCursorVisible = cursorVisible
                            primaryBufferApplicationCursorMode = applicationCursorMode
                            primaryBufferOriginMode = originMode
                            primaryBufferSavedCursorLine = savedCursorLine
                            primaryBufferSavedCursorColumn = savedCursorColumn
                            primaryBufferScrollRegionTop = scrollRegionTop
                            primaryBufferScrollRegionBottom = scrollRegionBottom
                            primaryBufferHasExplicitScrollRegion = hasExplicitScrollRegion
                            primaryBufferG0CharacterSet = g0CharacterSet
                            primaryBufferG1CharacterSet = g1CharacterSet
                            primaryBufferUsingG1CharacterSet = usingG1CharacterSet
                            primaryBufferStyle = currentStyle
                            lines = [[]]
                            wrappedLineContinuations = [false]
                            cursorLine = 0
                            cursorColumn = 0
                            usingAlternateBuffer = true
                        case 25:
                            cursorVisible = true
                        case 1048:
                            savedCursorLine = cursorLine
                            savedCursorColumn = cursorColumn
                        default:
                            break
                        }
                    case "l":
                        switch value {
                        case 1:
                            applicationCursorMode = false
                        case 6:
                            originMode = false
                        case 25:
                            cursorVisible = false
                        case 47, 1047, 1049:
                            guard usingAlternateBuffer else {
                                break
                            }
                            lines = primaryBufferLines
                            wrappedLineContinuations = primaryBufferWrappedLineContinuations
                            cursorLine = primaryBufferCursorLine
                            cursorColumn = primaryBufferCursorColumn
                            cursorVisible = primaryBufferCursorVisible
                            applicationCursorMode = primaryBufferApplicationCursorMode
                            originMode = primaryBufferOriginMode
                            savedCursorLine = primaryBufferSavedCursorLine
                            savedCursorColumn = primaryBufferSavedCursorColumn
                            scrollRegionTop = primaryBufferScrollRegionTop
                            scrollRegionBottom = primaryBufferScrollRegionBottom
                            hasExplicitScrollRegion = primaryBufferHasExplicitScrollRegion
                            g0CharacterSet = primaryBufferG0CharacterSet
                            g1CharacterSet = primaryBufferG1CharacterSet
                            usingG1CharacterSet = primaryBufferUsingG1CharacterSet
                            currentStyle = primaryBufferStyle
                            usingAlternateBuffer = false
                        case 1048:
                            cursorLine = savedCursorLine
                            cursorColumn = savedCursorColumn
                            ensureCurrentLine()
                        default:
                            break
                        }
                    default:
                        break
                    }
                    return
                }

                switch finalCharacter {
                case "A":
                    pendingAutoWrap = false
                    cursorLine = max(0, cursorLine - defaultValue)
                    ensureCurrentLine()
                case "B", "e":
                    pendingAutoWrap = false
                    cursorLine += defaultValue
                    ensureCurrentLine()
                case "C", "a":
                    pendingAutoWrap = false
                    cursorColumn += defaultValue
                case "D":
                    pendingAutoWrap = false
                    cursorColumn = max(0, cursorColumn - defaultValue)
                case "E":
                    pendingAutoWrap = false
                    if let region = activeScrollRegion() {
                        for _ in 0..<defaultValue {
                            if cursorLine == region.upperBound {
                                scrollUpWithinRegion(1)
                            } else {
                                cursorLine += 1
                            }
                        }
                    } else {
                        cursorLine += defaultValue
                    }
                    cursorColumn = 0
                    ensureCurrentLine()
                case "F":
                    pendingAutoWrap = false
                    cursorLine = max(0, cursorLine - defaultValue)
                    cursorColumn = 0
                    ensureCurrentLine()
                case "G", "`":
                    pendingAutoWrap = false
                    cursorColumn = max(0, defaultValue - 1)
                case "H", "f":
                    pendingAutoWrap = false
                    let row = values.first.flatMap { $0 } ?? 1
                    let column = values.dropFirst().first.flatMap { $0 } ?? 1
                    if originMode, let region = activeScrollRegion() {
                        cursorLine = min(region.upperBound, region.lowerBound + max(0, row - 1))
                    } else {
                        cursorLine = max(0, row - 1)
                    }
                    cursorColumn = max(0, column - 1)
                    ensureCurrentLine()
                case "d":
                    pendingAutoWrap = false
                    let row = values.first.flatMap { $0 } ?? 1
                    if originMode, let region = activeScrollRegion() {
                        cursorLine = min(region.upperBound, region.lowerBound + max(0, row - 1))
                    } else {
                        cursorLine = max(0, row - 1)
                    }
                    ensureCurrentLine()
                case "J":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    switch eraseMode {
                    case 1:
                        if cursorLine > 0 {
                            for lineIndex in 0..<cursorLine {
                                lines[lineIndex].removeAll()
                            }
                        }
                        padCurrentLine(to: cursorColumn + 1)
                        for index in 0...cursorColumn {
                            lines[cursorLine][index] = blankCell()
                        }
                    case 2:
                        lines = [[]]
                        wrappedLineContinuations = [false]
                        cursorLine = 0
                        cursorColumn = 0
                    default:
                        if cursorColumn < lines[cursorLine].count {
                            lines[cursorLine].removeSubrange(cursorColumn...)
                        }
                        if cursorLine + 1 < lines.count {
                            lines.removeSubrange((cursorLine + 1)..<lines.count)
                        }
                    }
                case "K":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    switch eraseMode {
                    case 1:
                        padCurrentLine(to: cursorColumn + 1)
                        for index in 0...cursorColumn {
                            lines[cursorLine][index] = blankCell()
                        }
                    case 2:
                        lines[cursorLine].removeAll()
                    default:
                        if cursorColumn < lines[cursorLine].count {
                            lines[cursorLine].removeSubrange(cursorColumn...)
                        }
                    }
                case "@":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let insertCount = max(0, defaultValue)
                    guard insertCount > 0 else {
                        break
                    }
                    padCurrentLine(to: cursorColumn)
                    let blanks = Array(repeating: blankCell(), count: insertCount)
                    lines[cursorLine].insert(contentsOf: blanks, at: cursorColumn)
                case "L":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let insertCount = max(0, defaultValue)
                    guard insertCount > 0 else {
                        break
                    }
                    if activeScrollRegion()?.contains(cursorLine) == true {
                        insertBlankLinesWithinRegion(insertCount, at: cursorLine)
                    } else {
                        let blanks = Array(repeating: [TerminalCell](), count: insertCount)
                        lines.insert(contentsOf: blanks, at: cursorLine)
                        wrappedLineContinuations.insert(
                            contentsOf: Array(repeating: false, count: insertCount), at: cursorLine)
                    }
                case "M":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let deleteCount = max(0, defaultValue)
                    guard deleteCount > 0 else {
                        break
                    }
                    if activeScrollRegion()?.contains(cursorLine) == true {
                        deleteLinesWithinRegion(deleteCount, at: cursorLine)
                    } else {
                        let endLine = min(lines.count, cursorLine + deleteCount)
                        if cursorLine < endLine {
                            lines.removeSubrange(cursorLine..<endLine)
                            wrappedLineContinuations.removeSubrange(cursorLine..<endLine)
                        }
                        ensureCurrentLine()
                    }
                case "P":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    guard cursorColumn < lines[cursorLine].count else {
                        break
                    }
                    let endIndex = min(lines[cursorLine].count, cursorColumn + defaultValue)
                    lines[cursorLine].removeSubrange(cursorColumn..<endIndex)
                case "S":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let scrollCount = max(0, defaultValue)
                    guard scrollCount > 0 else {
                        break
                    }
                    if activeScrollRegion() != nil {
                        scrollUpWithinRegion(scrollCount)
                    } else {
                        let visibleLineCount = max(lines.count, cursorLine + 1)
                        if scrollCount >= visibleLineCount {
                            lines = Array(repeating: [], count: visibleLineCount)
                            wrappedLineContinuations = Array(repeating: false, count: visibleLineCount)
                        } else {
                            lines.removeFirst(scrollCount)
                            wrappedLineContinuations.removeFirst(scrollCount)
                            lines.append(contentsOf: Array(repeating: [], count: scrollCount))
                            wrappedLineContinuations.append(contentsOf: Array(repeating: false, count: scrollCount))
                        }
                    }
                    ensureCurrentLine()
                case "T":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let scrollCount = max(0, defaultValue)
                    guard scrollCount > 0 else {
                        break
                    }
                    if activeScrollRegion() != nil {
                        scrollDownWithinRegion(scrollCount)
                    } else {
                        let visibleLineCount = max(lines.count, cursorLine + 1)
                        if scrollCount >= visibleLineCount {
                            lines = Array(repeating: [], count: visibleLineCount)
                            wrappedLineContinuations = Array(repeating: false, count: visibleLineCount)
                        } else {
                            lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: 0)
                            wrappedLineContinuations.insert(
                                contentsOf: Array(repeating: false, count: scrollCount), at: 0)
                            let removeCount = min(scrollCount, lines.count)
                            lines.removeLast(removeCount)
                            wrappedLineContinuations.removeLast(removeCount)
                        }
                    }
                    ensureCurrentLine()
                case "m":
                    applySGR(parameters: normalizedParameters)
                case "r":
                    pendingAutoWrap = false
                    let requestedTop = max(1, values.first.flatMap { $0 } ?? 1)
                    let requestedBottom = max(requestedTop, values.dropFirst().first.flatMap { $0 } ?? terminalRows)
                    scrollRegionTop = min(max(0, requestedTop - 1), max(0, terminalRows - 1))
                    scrollRegionBottom = min(max(scrollRegionTop, requestedBottom - 1), max(0, terminalRows - 1))
                    hasExplicitScrollRegion = true
                    cursorLine = 0
                    cursorColumn = 0
                    ensureCurrentLine()
                case "X":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let eraseCount = max(0, defaultValue)
                    guard eraseCount > 0 else {
                        break
                    }
                    padCurrentLine(to: cursorColumn)
                    let endIndex = min(lines[cursorLine].count, cursorColumn + eraseCount)
                    if cursorColumn < endIndex {
                        for index in cursorColumn..<endIndex {
                            lines[cursorLine][index] = blankCell()
                        }
                    }
                case "b":
                    guard let repeatedCharacter = lastRenderedCharacter else {
                        break
                    }
                    for _ in 0..<defaultValue {
                        wrapIfNeededBeforeWriting()
                        ensureCurrentLine()
                        let cell = TerminalCell(text: String(repeatedCharacter), style: currentStyle)
                        if cursorColumn < lines[cursorLine].count {
                            lines[cursorLine][cursorColumn] = cell
                        } else {
                            padCurrentLine(to: cursorColumn)
                            lines[cursorLine].append(cell)
                        }
                        cursorColumn += 1
                        pendingAutoWrap = cursorColumn == max(1, terminalColumns)
                    }
                case "s":
                    pendingAutoWrap = false
                    guard parameters.isEmpty else {
                        break
                    }
                    savedCursorLine = cursorLine
                    savedCursorColumn = cursorColumn
                case "u":
                    pendingAutoWrap = false
                    guard parameters.isEmpty else {
                        break
                    }
                    cursorLine = savedCursorLine
                    cursorColumn = savedCursorColumn
                    ensureCurrentLine()
                default:
                    break
                }
            }

            while let scalar = iterator.next() {
                switch scalar {
                case "\u{001B}":
                    guard let next = iterator.next() else {
                        continue
                    }

                    if next == "[" {
                        var parameters = ""
                        while let scalar = iterator.next() {
                            if (0x40...0x7E).contains(scalar.value) {
                                parseCSI(finalCharacter: scalar, parameters: parameters)
                                break
                            }
                            parameters.unicodeScalars.append(scalar)
                        }
                    } else if next == "]" {
                        skipOperatingSystemCommand()
                    } else if next == "P" || next == "X" || next == "^" || next == "_" {
                        skipStringCommand(allowBellTerminator: false)
                    } else if next == "(" {
                        if let designator = iterator.next(), let characterSet = characterSet(for: designator) {
                            g0CharacterSet = characterSet
                        }
                    } else if next == ")" {
                        if let designator = iterator.next(), let characterSet = characterSet(for: designator) {
                            g1CharacterSet = characterSet
                        }
                    } else if next == "7" {
                        pendingAutoWrap = false
                        savedCursorLine = cursorLine
                        savedCursorColumn = cursorColumn
                    } else if next == "8" {
                        pendingAutoWrap = false
                        cursorLine = savedCursorLine
                        cursorColumn = savedCursorColumn
                        ensureCurrentLine()
                    } else if next == "D" {
                        pendingAutoWrap = false
                        if let region = activeScrollRegion() {
                            if cursorLine == region.upperBound {
                                scrollUpWithinRegion(1)
                            } else {
                                cursorLine += 1
                            }
                        } else {
                            let visibleLineCount = max(lines.count, cursorLine + 1)
                            if cursorLine + 1 < visibleLineCount {
                                cursorLine += 1
                            } else {
                                lines.removeFirst()
                                wrappedLineContinuations.removeFirst()
                                lines.append([])
                                wrappedLineContinuations.append(false)
                                cursorLine = max(0, visibleLineCount - 1)
                            }
                        }
                        ensureCurrentLine()
                    } else if next == "E" {
                        pendingAutoWrap = false
                        if let region = activeScrollRegion() {
                            if cursorLine == region.upperBound {
                                scrollUpWithinRegion(1)
                            } else {
                                cursorLine += 1
                            }
                        } else {
                            let visibleLineCount = max(lines.count, cursorLine + 1)
                            if cursorLine + 1 < visibleLineCount {
                                cursorLine += 1
                            } else {
                                lines.removeFirst()
                                wrappedLineContinuations.removeFirst()
                                lines.append([])
                                wrappedLineContinuations.append(false)
                                cursorLine = max(0, visibleLineCount - 1)
                            }
                        }
                        cursorColumn = 0
                        ensureCurrentLine()
                    } else if next == "M" {
                        pendingAutoWrap = false
                        if let region = activeScrollRegion() {
                            if cursorLine == region.lowerBound {
                                scrollDownWithinRegion(1)
                            } else {
                                cursorLine -= 1
                            }
                        } else if cursorLine > 0 {
                            cursorLine -= 1
                        } else {
                            let visibleLineCount = max(lines.count, 1)
                            lines.insert([], at: 0)
                            wrappedLineContinuations.insert(false, at: 0)
                            if lines.count > visibleLineCount {
                                let overflowCount = lines.count - visibleLineCount
                                lines.removeLast(overflowCount)
                                wrappedLineContinuations.removeLast(overflowCount)
                            }
                        }
                        ensureCurrentLine()
                    } else if next == "c" {
                        lines = [[]]
                        wrappedLineContinuations = [false]
                        cursorLine = 0
                        cursorColumn = 0
                        cursorVisible = true
                        applicationCursorMode = false
                        originMode = false
                        savedCursorLine = 0
                        savedCursorColumn = 0
                        currentStyle = TerminalStyle()
                        primaryBufferLines = lines
                        primaryBufferWrappedLineContinuations = wrappedLineContinuations
                        primaryBufferCursorLine = cursorLine
                        primaryBufferCursorColumn = cursorColumn
                        primaryBufferCursorVisible = cursorVisible
                        primaryBufferApplicationCursorMode = applicationCursorMode
                        primaryBufferOriginMode = originMode
                        primaryBufferSavedCursorLine = savedCursorLine
                        primaryBufferSavedCursorColumn = savedCursorColumn
                        primaryBufferStyle = currentStyle
                        usingAlternateBuffer = false
                        scrollRegionTop = 0
                        scrollRegionBottom = max(0, terminalRows - 1)
                        hasExplicitScrollRegion = false
                        primaryBufferScrollRegionTop = scrollRegionTop
                        primaryBufferScrollRegionBottom = scrollRegionBottom
                        primaryBufferHasExplicitScrollRegion = hasExplicitScrollRegion
                        g0CharacterSet = .ascii
                        g1CharacterSet = .ascii
                        usingG1CharacterSet = false
                        lastRenderedCharacter = nil
                        primaryBufferG0CharacterSet = g0CharacterSet
                        primaryBufferG1CharacterSet = g1CharacterSet
                        primaryBufferUsingG1CharacterSet = usingG1CharacterSet
                    }
                case "\u{000E}":
                    usingG1CharacterSet = true
                case "\u{000F}":
                    usingG1CharacterSet = false
                case "\u{0007}":
                    continue
                case "\u{0090}", "\u{0098}", "\u{009E}", "\u{009F}":
                    skipStringCommand(allowBellTerminator: false)
                case "\u{009D}":
                    skipStringCommand(allowBellTerminator: true)
                case "\r":
                    pendingAutoWrap = false
                    cursorColumn = 0
                case "\u{8}":
                    pendingAutoWrap = false
                    guard cursorColumn > 0 else {
                        continue
                    }
                    cursorColumn -= 1
                case "\u{7F}":
                    pendingAutoWrap = false
                    guard cursorColumn > 0 else {
                        continue
                    }
                    ensureCurrentLine()
                    cursorColumn -= 1
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine].remove(at: cursorColumn)
                    }
                case "\n":
                    advanceToNextLine()
                case "\t":
                    pendingAutoWrap = false
                    ensureCurrentLine()
                    let tabWidth = 8
                    let nextTabStop = ((cursorColumn / tabWidth) + 1) * tabWidth
                    padCurrentLine(to: nextTabStop)
                    cursorColumn = nextTabStop
                default:
                    let character = renderedCharacter(for: scalar)
                    wrapIfNeededBeforeWriting()
                    ensureCurrentLine()
                    let cell = TerminalCell(text: String(character), style: currentStyle)
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine][cursorColumn] = cell
                    } else {
                        padCurrentLine(to: cursorColumn)
                        lines[cursorLine].append(cell)
                    }
                    cursorColumn += 1
                    pendingAutoWrap = cursorColumn == max(1, terminalColumns)
                    lastRenderedCharacter = character
                }
            }

            let viewport = makeViewport(
                lines: lines,
                wrappedLineContinuations: wrappedLineContinuations,
                cursorLine: cursorLine,
                cursorColumn: cursorColumn,
                terminalColumns: terminalColumns,
                terminalRows: terminalRows
            )

            return TerminalRenderState(
                transcript: viewport.transcript,
                visibleLines: viewport.visibleLines,
                styledVisibleLines: viewport.styledVisibleLines,
                cursorRow: viewport.cursorRow,
                cursorColumn: viewport.cursorColumn,
                cursorVisible: cursorVisible,
                applicationCursorMode: applicationCursorMode
            )
        }

        private static func makeViewport(
            lines: [[TerminalCell]],
            wrappedLineContinuations: [Bool],
            cursorLine: Int,
            cursorColumn: Int,
            terminalColumns: Int,
            terminalRows: Int
        ) -> (
            transcript: String, visibleLines: [String], styledVisibleLines: [TerminalLine], cursorRow: Int,
            cursorColumn: Int
        ) {
            let columns = max(1, terminalColumns)
            let rows = max(1, terminalRows)
            let sourceLines = lines.isEmpty ? [[]] : lines
            let transcript = sourceLines.enumerated().reduce(into: "") { partialResult, entry in
                let (lineIndex, cells) = entry
                let isContinuation =
                    wrappedLineContinuations.indices.contains(lineIndex) ? wrappedLineContinuations[lineIndex] : false
                if lineIndex > 0, isContinuation == false {
                    partialResult.append("\n")
                }
                partialResult.append(cells.map(\.text).joined())
            }

            let visibleStartIndex = max(0, sourceLines.count - rows)
            let visibleSourceLines = Array(sourceLines.suffix(rows))
            let styledVisibleLines = visibleSourceLines.map { cells in
                TerminalLine(cells: Array(cells.prefix(columns)))
            }
            let visibleLines = styledVisibleLines.map(\.text)
            let cursorRow = max(0, cursorLine - visibleStartIndex)
            let visibleCursorColumn = min(cursorColumn, columns)

            return (
                transcript: transcript,
                visibleLines: visibleLines,
                styledVisibleLines: styledVisibleLines,
                cursorRow: cursorRow,
                cursorColumn: visibleCursorColumn
            )
        }
    }
#endif
