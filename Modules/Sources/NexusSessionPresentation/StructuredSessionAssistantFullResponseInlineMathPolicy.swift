import Foundation

/// Presentation contract for inline math (`$…$`) in structured session markdown (#239).
public struct StructuredSessionAssistantFullResponseInlineMathPolicy: Equatable, Sendable {
    public let detectsSingleDollarDelimiters: Bool
    /// Guardrail: cap MathJax work per document (#239, #230).
    public let maxInlineMathExpressionsPerDocument: Int

    public init(
        detectsSingleDollarDelimiters: Bool,
        maxInlineMathExpressionsPerDocument: Int
    ) {
        self.detectsSingleDollarDelimiters = detectsSingleDollarDelimiters
        self.maxInlineMathExpressionsPerDocument = maxInlineMathExpressionsPerDocument
    }
}

public func structuredSessionAssistantFullResponseInlineMathPolicy()
    -> StructuredSessionAssistantFullResponseInlineMathPolicy
{
    StructuredSessionAssistantFullResponseInlineMathPolicy(
        detectsSingleDollarDelimiters: true,
        maxInlineMathExpressionsPerDocument: 64
    )
}

/// One text run or inline LaTeX expression inside assistant markdown prose (#239).
public enum StructuredSessionAssistantFullResponseProseSegment: Equatable, Sendable {
    case text(String)
    case inlineMath(latex: String)
}

public func structuredSessionAssistantFullResponseProseContainsExtractedInlineMath(
    in markdown: String,
    policy: StructuredSessionAssistantFullResponseInlineMathPolicy =
        structuredSessionAssistantFullResponseInlineMathPolicy()
) -> Bool {
    structuredSessionAssistantFullResponseProseSegments(in: markdown, policy: policy)
        .contains { segment in
            if case .inlineMath = segment { return true }
            return false
        }
}

/// Feed AttributedString path bypasses parse when display or inline LaTeX needs the rich stack (#235, #239).
public func structuredSessionFeedLaTeXMathUsesPlainAttributedFallback(for text: String) -> Bool {
    structuredSessionFeedDisplayMathUsesPlainFallback(for: text)
        || structuredSessionAssistantFullResponseProseContainsExtractedInlineMath(in: text)
}

public func structuredSessionAssistantFullResponseProseSegments(
    in markdown: String,
    policy: StructuredSessionAssistantFullResponseInlineMathPolicy =
        structuredSessionAssistantFullResponseInlineMathPolicy()
) -> [StructuredSessionAssistantFullResponseProseSegment] {
    guard markdown.isEmpty == false else {
        return []
    }
    guard policy.detectsSingleDollarDelimiters else {
        return [.text(markdown)]
    }

    var segments: [StructuredSessionAssistantFullResponseProseSegment] = []
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    var isInsideFencedCode = false
    var inlineMathCount = 0
    var textBuffer = ""

    func flushTextBuffer() {
        guard textBuffer.isEmpty == false else {
            return
        }
        segments.append(.text(textBuffer))
        textBuffer = ""
    }

    for lineIndex in lines.indices {
        let line = String(lines[lineIndex])
        if lineIndex > lines.startIndex, isInsideFencedCode == false {
            textBuffer.append("\n")
        }

        if structuredSessionAssistantFullResponseIsFencedCodeDelimiter(line) {
            if isInsideFencedCode {
                isInsideFencedCode = false
                textBuffer.append(line)
            } else {
                flushTextBuffer()
                isInsideFencedCode = true
                textBuffer.append(line)
            }
            continue
        }

        if isInsideFencedCode {
            if textBuffer.isEmpty == false, textBuffer.hasSuffix("\n") == false {
                textBuffer.append("\n")
            }
            textBuffer.append(line)
            continue
        }

        let lineSegments = structuredSessionAssistantFullResponseInlineMathSegments(
            in: line,
            policy: policy,
            inlineMathCount: &inlineMathCount
        )
        for segment in lineSegments {
            switch segment {
            case .text(let text):
                textBuffer.append(text)
            case .inlineMath(let latex):
                flushTextBuffer()
                segments.append(.inlineMath(latex: latex))
            }
        }
    }

    flushTextBuffer()
    return segments
}

private func structuredSessionAssistantFullResponseInlineMathSegments(
    in line: String,
    policy: StructuredSessionAssistantFullResponseInlineMathPolicy,
    inlineMathCount: inout Int
) -> [StructuredSessionAssistantFullResponseProseSegment] {
    var segments: [StructuredSessionAssistantFullResponseProseSegment] = []
    var index = line.startIndex
    var textStart = index

    func appendText(upTo end: String.Index) {
        guard end > textStart else {
            return
        }
        segments.append(.text(String(line[textStart..<end])))
    }

    while index < line.endIndex {
        let char = line[index]
        if char == "\\", line.index(after: index) < line.endIndex {
            let next = line[line.index(after: index)]
            if next == "$" {
                appendText(upTo: index)
                segments.append(.text("$"))
                index = line.index(index, offsetBy: 2)
                textStart = index
                continue
            }
        }

        if char == "$" {
            let nextIndex = line.index(after: index)
            if nextIndex < line.endIndex, line[nextIndex] == "$" {
                index = nextIndex
                continue
            }

            if inlineMathCount < policy.maxInlineMathExpressionsPerDocument {
                var scan = nextIndex
                var foundClose = false
                while scan < line.endIndex {
                    if line[scan] == "\\", line.index(after: scan) < line.endIndex,
                        line[line.index(after: scan)] == "$"
                    {
                        scan = line.index(scan, offsetBy: 2)
                        continue
                    }
                    if line[scan] == "$" {
                        let latexStart = nextIndex
                        let latexEnd = scan
                        let latex = String(line[latexStart..<latexEnd])
                        appendText(upTo: index)
                        segments.append(.inlineMath(latex: latex))
                        inlineMathCount += 1
                        index = line.index(after: scan)
                        textStart = index
                        foundClose = true
                        break
                    }
                    scan = line.index(after: scan)
                }
                if foundClose {
                    continue
                }
            }
        }

        index = line.index(after: index)
    }

    appendText(upTo: line.endIndex)
    return segments
}
