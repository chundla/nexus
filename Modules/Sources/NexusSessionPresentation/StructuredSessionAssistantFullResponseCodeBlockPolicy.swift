import CoreGraphics
import Foundation

/// Presentation contract for fenced code in the assistant full-response reader (#228).
public struct StructuredSessionAssistantFullResponseCodeBlockPolicy: Equatable, Sendable {
    public let showsCopyAction: Bool
    public let enablesPerBlockTextSelection: Bool
    public let usesHorizontalScrolling: Bool
    public let usesMonospacedPresentation: Bool
    public let monospacedFontScale: CGFloat
    public let lineSpacingEm: CGFloat
    public let contentPaddingPoints: CGFloat
    public let blockCornerRadiusPoints: CGFloat

    public init(
        showsCopyAction: Bool,
        enablesPerBlockTextSelection: Bool,
        usesHorizontalScrolling: Bool,
        usesMonospacedPresentation: Bool,
        monospacedFontScale: CGFloat,
        lineSpacingEm: CGFloat,
        contentPaddingPoints: CGFloat,
        blockCornerRadiusPoints: CGFloat
    ) {
        self.showsCopyAction = showsCopyAction
        self.enablesPerBlockTextSelection = enablesPerBlockTextSelection
        self.usesHorizontalScrolling = usesHorizontalScrolling
        self.usesMonospacedPresentation = usesMonospacedPresentation
        self.monospacedFontScale = monospacedFontScale
        self.lineSpacingEm = lineSpacingEm
        self.contentPaddingPoints = contentPaddingPoints
        self.blockCornerRadiusPoints = blockCornerRadiusPoints
    }
}

public func structuredSessionAssistantFullResponseCodeBlockPolicy()
    -> StructuredSessionAssistantFullResponseCodeBlockPolicy
{
    StructuredSessionAssistantFullResponseCodeBlockPolicy(
        showsCopyAction: true,
        enablesPerBlockTextSelection: true,
        usesHorizontalScrolling: true,
        usesMonospacedPresentation: true,
        monospacedFontScale: 0.88,
        lineSpacingEm: 0.22,
        contentPaddingPoints: 12,
        blockCornerRadiusPoints: 8
    )
}

/// One fenced code block extracted from assistant markdown for copy affordances (#228).
public struct StructuredSessionAssistantFullResponseFencedCodeBlock: Equatable, Sendable {
    public let language: String?
    public let content: String

    public init(language: String?, content: String) {
        self.language = language
        self.content = content
    }
}

public func structuredSessionAssistantFullResponseFencedCodeBlocks(
    in markdown: String
) -> [StructuredSessionAssistantFullResponseFencedCodeBlock] {
    var blocks: [StructuredSessionAssistantFullResponseFencedCodeBlock] = []
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    var index = lines.startIndex
    var isInsideFence = false
    var fenceLanguage: String?
    var fenceLines: [String] = []

    while index < lines.endIndex {
        let line = String(lines[index])
        if structuredSessionAssistantFullResponseIsFencedCodeDelimiter(line) {
            if isInsideFence {
                blocks.append(
                    StructuredSessionAssistantFullResponseFencedCodeBlock(
                        language: fenceLanguage,
                        content: fenceLines.joined(separator: "\n")
                    )
                )
                fenceLanguage = nil
                fenceLines = []
                isInsideFence = false
            } else {
                fenceLanguage = structuredSessionAssistantFullResponseFenceLanguage(from: line)
                fenceLines = []
                isInsideFence = true
            }
            index = lines.index(after: index)
            continue
        }

        if isInsideFence {
            fenceLines.append(line)
        }
        index = lines.index(after: index)
    }

    return blocks
}

func structuredSessionAssistantFullResponseIsFencedCodeDelimiter(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
}

private func structuredSessionAssistantFullResponseFenceLanguage(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("```") else {
        return nil
    }
    let remainder = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
    return remainder.isEmpty ? nil : String(remainder)
}
