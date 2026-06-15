import CoreGraphics
import Foundation

/// Presentation contract for display math in the assistant full-response reader (#235).
public struct StructuredSessionAssistantFullResponseDisplayMathPolicy: Equatable, Sendable {
    public let detectsDoubleDollarDelimiters: Bool
    public let detectsBracketDelimiters: Bool
    /// Guardrail: cap MathJax work per reader document (#235, #230).
    public let maxDisplayMathBlocksPerDocument: Int
    public let blockVerticalPaddingPoints: CGFloat

    public init(
        detectsDoubleDollarDelimiters: Bool,
        detectsBracketDelimiters: Bool,
        maxDisplayMathBlocksPerDocument: Int,
        blockVerticalPaddingPoints: CGFloat
    ) {
        self.detectsDoubleDollarDelimiters = detectsDoubleDollarDelimiters
        self.detectsBracketDelimiters = detectsBracketDelimiters
        self.maxDisplayMathBlocksPerDocument = maxDisplayMathBlocksPerDocument
        self.blockVerticalPaddingPoints = blockVerticalPaddingPoints
    }
}

public func structuredSessionAssistantFullResponseDisplayMathPolicy() -> StructuredSessionAssistantFullResponseDisplayMathPolicy {
    StructuredSessionAssistantFullResponseDisplayMathPolicy(
        detectsDoubleDollarDelimiters: true,
        detectsBracketDelimiters: true,
        maxDisplayMathBlocksPerDocument: 32,
        blockVerticalPaddingPoints: 12
    )
}

public enum StructuredSessionAssistantFullResponseDisplayMathDelimiter: Equatable, Sendable {
    case doubleDollar
    case bracket
}

/// One display-math block extracted from assistant markdown for reader rendering (#235).
public struct StructuredSessionAssistantFullResponseDisplayMathBlock: Equatable, Sendable {
    public let latex: String
    public let delimiter: StructuredSessionAssistantFullResponseDisplayMathDelimiter

    public init(latex: String, delimiter: StructuredSessionAssistantFullResponseDisplayMathDelimiter) {
        self.latex = latex
        self.delimiter = delimiter
    }
}

/// Interleaved markdown and display-math segments for the full-response reader (#235).
public struct StructuredSessionAssistantFullResponseReaderSegment: Equatable, Sendable {
    public let markdownChunk: String?
    public let displayMath: StructuredSessionAssistantFullResponseDisplayMathBlock?

    public init(
        markdownChunk: String? = nil,
        displayMath: StructuredSessionAssistantFullResponseDisplayMathBlock? = nil
    ) {
        self.markdownChunk = markdownChunk
        self.displayMath = displayMath
    }
}

/// Feed bodies with display math keep plain text until a deferred feed math slice (#235, CONTEXT).
public func structuredSessionFeedDisplayMathUsesPlainFallback(for text: String) -> Bool {
    !structuredSessionAssistantFullResponseDisplayMathBlocks(in: text).isEmpty
}

public func structuredSessionAssistantFullResponseDisplayMathBlocks(
    in markdown: String,
    policy: StructuredSessionAssistantFullResponseDisplayMathPolicy = structuredSessionAssistantFullResponseDisplayMathPolicy()
) -> [StructuredSessionAssistantFullResponseDisplayMathBlock] {
    structuredSessionAssistantFullResponseReaderSegments(in: markdown, policy: policy)
        .compactMap(\.displayMath)
}

public func structuredSessionAssistantFullResponseReaderSegments(
    in markdown: String,
    policy: StructuredSessionAssistantFullResponseDisplayMathPolicy = structuredSessionAssistantFullResponseDisplayMathPolicy()
) -> [StructuredSessionAssistantFullResponseReaderSegment] {
    guard markdown.isEmpty == false else {
        return []
    }

    var segments: [StructuredSessionAssistantFullResponseReaderSegment] = []
    var displayMathCount = 0
    var markdownLines: [String] = []
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    var index = lines.startIndex
    var isInsideFencedCode = false

    func flushMarkdownLines() {
        guard markdownLines.isEmpty == false else {
            return
        }
        let chunk = markdownLines.joined(separator: "\n")
        markdownLines = []
        guard chunk.isEmpty == false else {
            return
        }
        segments.append(StructuredSessionAssistantFullResponseReaderSegment(markdownChunk: chunk))
    }

    while index < lines.endIndex {
        let line = String(lines[index])
        if structuredSessionAssistantFullResponseIsFencedCodeDelimiter(line) {
            markdownLines.append(line)
            isInsideFencedCode.toggle()
            index = lines.index(after: index)
            continue
        }

        if isInsideFencedCode {
            markdownLines.append(line)
            index = lines.index(after: index)
            continue
        }

        if policy.detectsDoubleDollarDelimiters,
           line.trimmingCharacters(in: .whitespaces) == "$$",
           displayMathCount < policy.maxDisplayMathBlocksPerDocument {
            var latexLines: [String] = []
            var scan = lines.index(after: index)
            var foundClose = false
            while scan < lines.endIndex {
                let scanLine = String(lines[scan])
                if scanLine.trimmingCharacters(in: .whitespaces) == "$$" {
                    foundClose = true
                    displayMathCount += 1
                    flushMarkdownLines()
                    let latex = latexLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    segments.append(
                        StructuredSessionAssistantFullResponseReaderSegment(
                            displayMath: StructuredSessionAssistantFullResponseDisplayMathBlock(
                                latex: latex,
                                delimiter: .doubleDollar
                            )
                        )
                    )
                    index = lines.index(after: scan)
                    break
                }
                latexLines.append(scanLine)
                scan = lines.index(after: scan)
            }
            if foundClose {
                continue
            }
        }

        if policy.detectsBracketDelimiters,
           line.trimmingCharacters(in: .whitespaces) == "\\[",
           displayMathCount < policy.maxDisplayMathBlocksPerDocument {
            var latexLines: [String] = []
            var scan = lines.index(after: index)
            var foundClose = false
            while scan < lines.endIndex {
                let scanLine = String(lines[scan])
                if scanLine.trimmingCharacters(in: .whitespaces) == "\\]" {
                    foundClose = true
                    displayMathCount += 1
                    flushMarkdownLines()
                    let latex = latexLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    segments.append(
                        StructuredSessionAssistantFullResponseReaderSegment(
                            displayMath: StructuredSessionAssistantFullResponseDisplayMathBlock(
                                latex: latex,
                                delimiter: .bracket
                            )
                        )
                    )
                    index = lines.index(after: scan)
                    break
                }
                latexLines.append(scanLine)
                scan = lines.index(after: scan)
            }
            if foundClose {
                continue
            }
        }

        markdownLines.append(line)
        index = lines.index(after: index)
    }

    flushMarkdownLines()
    return segments
}