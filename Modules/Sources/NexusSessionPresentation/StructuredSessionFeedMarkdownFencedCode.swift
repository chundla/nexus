import CoreGraphics
import Foundation
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

public struct StructuredSessionFeedFencedCodeBlockPolicy: Equatable, Sendable {
    public let showsCopyAction: Bool
    public let usesHorizontalScrolling: Bool
    public let usesMonospacedPresentation: Bool
    public let monospacedFontScale: CGFloat
    public let lineSpacingEm: CGFloat
    public let contentPaddingPoints: CGFloat
    public let blockCornerRadiusPoints: CGFloat
    public let enablesLightweightSyntaxHighlight: Bool

    public init(
        showsCopyAction: Bool,
        usesHorizontalScrolling: Bool,
        usesMonospacedPresentation: Bool,
        monospacedFontScale: CGFloat,
        lineSpacingEm: CGFloat,
        contentPaddingPoints: CGFloat,
        blockCornerRadiusPoints: CGFloat,
        enablesLightweightSyntaxHighlight: Bool
    ) {
        self.showsCopyAction = showsCopyAction
        self.usesHorizontalScrolling = usesHorizontalScrolling
        self.usesMonospacedPresentation = usesMonospacedPresentation
        self.monospacedFontScale = monospacedFontScale
        self.lineSpacingEm = lineSpacingEm
        self.contentPaddingPoints = contentPaddingPoints
        self.blockCornerRadiusPoints = blockCornerRadiusPoints
        self.enablesLightweightSyntaxHighlight = enablesLightweightSyntaxHighlight
    }
}

public func structuredSessionFeedFencedCodeBlockPolicy() -> StructuredSessionFeedFencedCodeBlockPolicy {
    StructuredSessionFeedFencedCodeBlockPolicy(
        showsCopyAction: true,
        usesHorizontalScrolling: true,
        usesMonospacedPresentation: true,
        monospacedFontScale: 0.88,
        lineSpacingEm: 0.22,
        contentPaddingPoints: 12,
        blockCornerRadiusPoints: 8,
        enablesLightweightSyntaxHighlight: true
    )
}

public enum StructuredSessionFeedMarkdownSegment: Equatable, Sendable {
    case prose(String)
    case fencedCode(language: String?, content: String)
}

public struct StructuredSessionFeedMarkdownParseResult: Equatable, Sendable {
    public let segments: [StructuredSessionFeedMarkdownSegment]
    public let scannedLineCount: Int
    public let fencedBlockCount: Int
    public let stoppedEarlyDueToBounds: Bool
}

public struct StructuredSessionFeedMarkdownParseBounds: Equatable, Sendable {
    public let maxFencedBlocks: Int
    public let maxScannedLines: Int

    public static let feedDefault = StructuredSessionFeedMarkdownParseBounds(
        maxFencedBlocks: 32,
        maxScannedLines: 4_096
    )
}

func structuredSessionFeedMarkdownTrimProseSegmentEdges(_ prose: String) -> String {
    var trimmed = prose
    while trimmed.first == "\n" {
        trimmed.removeFirst()
    }
    while trimmed.last == "\n" {
        trimmed.removeLast()
    }
    return trimmed
}

public func structuredSessionFeedMarkdownParse(
    _ markdown: String,
    bounds: StructuredSessionFeedMarkdownParseBounds = .feedDefault
) -> StructuredSessionFeedMarkdownParseResult {
    var segments: [StructuredSessionFeedMarkdownSegment] = []
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    var index = lines.startIndex
    var scannedLineCount = 0
    var fencedBlockCount = 0
    var stoppedEarly = false
    var proseBuffer: [String] = []
    var isInsideFence = false
    var fenceLanguage: String?
    var fenceLines: [String] = []

    func flushProse() {
        guard proseBuffer.isEmpty == false else { return }
        let prose = structuredSessionFeedMarkdownTrimProseSegmentEdges(
            proseBuffer.joined(separator: "\n")
        )
        if prose.isEmpty == false {
            segments.append(.prose(prose))
        }
        proseBuffer = []
    }

    while index < lines.endIndex {
        if scannedLineCount >= bounds.maxScannedLines {
            stoppedEarly = true
            if isInsideFence {
                fenceLines.append(String(lines[index]))
            } else {
                proseBuffer.append(String(lines[index]))
            }
            index = lines.index(after: index)
            scannedLineCount += 1
            continue
        }

        let line = String(lines[index])
        scannedLineCount += 1

        if structuredSessionFeedMarkdownIsFencedDelimiter(line) {
            if isInsideFence {
                flushProse()
                segments.append(.fencedCode(language: fenceLanguage, content: fenceLines.joined(separator: "\n")))
                fencedBlockCount += 1
                fenceLanguage = nil
                fenceLines = []
                isInsideFence = false
                if fencedBlockCount >= bounds.maxFencedBlocks {
                    stoppedEarly = true
                    index = lines.index(after: index)
                    while index < lines.endIndex {
                        proseBuffer.append(String(lines[index]))
                        index = lines.index(after: index)
                    }
                    flushProse()
                    break
                }
            } else {
                flushProse()
                fenceLanguage = structuredSessionFeedMarkdownFenceLanguage(from: line)
                fenceLines = []
                isInsideFence = true
            }
            index = lines.index(after: index)
            continue
        }

        if isInsideFence {
            fenceLines.append(line)
        } else {
            proseBuffer.append(line)
        }
        index = lines.index(after: index)
    }

    if isInsideFence {
        flushProse()
        segments.append(.fencedCode(language: fenceLanguage, content: fenceLines.joined(separator: "\n")))
        fencedBlockCount += 1
    } else {
        flushProse()
    }

    return StructuredSessionFeedMarkdownParseResult(
        segments: segments,
        scannedLineCount: scannedLineCount,
        fencedBlockCount: fencedBlockCount,
        stoppedEarlyDueToBounds: stoppedEarly
    )
}

func structuredSessionFeedMarkdownIsFencedDelimiter(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
}

func structuredSessionFeedMarkdownFenceLanguage(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("```") else { return nil }
    let remainder = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
    return remainder.isEmpty ? nil : String(remainder)
}

func structuredSessionFeedMarkdownCopyToPasteboard(_ text: String) {
    #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    #elseif os(iOS)
        UIPasteboard.general.string = text
    #endif
}

func structuredSessionFeedFencedCodeHighlightedContent(
    _ content: String,
    language: String?,
    baseForeground: Color,
    keywordForeground: Color,
    stringForeground: Color,
    commentForeground: Color,
    enabled: Bool
) -> AttributedString {
    guard enabled else { return AttributedString(content) }

    let normalizedLanguage = language?.lowercased() ?? ""
    let keywords: Set<String>
    switch normalizedLanguage {
    case "swift":
        keywords = [
            "import", "struct", "class", "enum", "func", "let", "var", "if", "else", "return", "true", "false", "nil",
        ]
    case "bash", "sh", "shell", "zsh":
        keywords = ["if", "then", "else", "fi", "for", "export", "cd", "echo", "git"]
    default:
        keywords = []
    }

    var attributed = AttributedString(content)
    attributed.foregroundColor = baseForeground
    guard keywords.isEmpty == false else { return attributed }

    let nsContent = content as NSString
    var searchRange = NSRange(location: 0, length: nsContent.length)
    while searchRange.location < nsContent.length {
        let nonAlpha = CharacterSet.alphanumerics.inverted
        let wordRange = nsContent.rangeOfCharacter(from: nonAlpha, options: [], range: searchRange)
        let tokenStart: Int
        let tokenEnd: Int
        if wordRange.location == NSNotFound {
            tokenStart = searchRange.location
            tokenEnd = nsContent.length
        } else if wordRange.location > searchRange.location {
            tokenStart = searchRange.location
            tokenEnd = wordRange.location
        } else {
            searchRange = NSRange(
                location: wordRange.location + wordRange.length,
                length: nsContent.length - wordRange.location - wordRange.length)
            continue
        }
        let token = nsContent.substring(with: NSRange(location: tokenStart, length: tokenEnd - tokenStart))
        if keywords.contains(token),
            let range = Range(NSRange(location: tokenStart, length: tokenEnd - tokenStart), in: content),
            let attributedRange = Range(range, in: attributed)
        {
            attributed[attributedRange].foregroundColor = keywordForeground
        }
        searchRange = NSRange(location: tokenEnd, length: nsContent.length - tokenEnd)
    }
    return attributed
}

@available(macOS 12.0, iOS 15.0, *)
struct StructuredSessionFeedFencedCodeBlockView: View {
    let language: String?
    let content: String
    let policy: StructuredSessionFeedFencedCodeBlockPolicy
    let monoFont: Font
    let foreground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if policy.showsCopyAction {
                HStack(spacing: 8) {
                    Text((language ?? "code").uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Copy") {
                        structuredSessionFeedMarkdownCopyToPasteboard(content)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, policy.contentPaddingPoints)
                .padding(.vertical, 8)
                Divider()
            }
            Group {
                if policy.usesHorizontalScrolling {
                    ScrollView(.horizontal, showsIndicators: true) { codeLabel }
                } else {
                    codeLabel
                }
            }
            .padding(policy.contentPaddingPoints)
        }
        .background(structuredSessionFeedFencedCodeBlockBackgroundColor())
        .clipShape(RoundedRectangle(cornerRadius: policy.blockCornerRadiusPoints, style: .continuous))
    }

    private var codeLabel: some View {
        Text(highlightedContent)
            .font(monoFont)
            .fixedSize(horizontal: false, vertical: true)
            .structuredSessionFeedTextSelection()
    }

    private var highlightedContent: AttributedString {
        structuredSessionFeedFencedCodeHighlightedContent(
            content,
            language: language,
            baseForeground: foreground,
            keywordForeground: foreground.opacity(0.95),
            stringForeground: Color(red: 0.75, green: 0.55, blue: 0.35),
            commentForeground: foreground.opacity(0.55),
            enabled: policy.enablesLightweightSyntaxHighlight
        )
    }
}

private func structuredSessionFeedFencedCodeBlockBackgroundColor() -> Color {
    #if os(macOS)
        Color(nsColor: .textBackgroundColor).opacity(0.65)
    #else
        Color(uiColor: .secondarySystemBackground)
    #endif
}
