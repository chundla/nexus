import LaTeXSwiftUI
import MarkdownUI
import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
@MainActor
@ViewBuilder
func structuredSessionFeedLaTeXProseView(
    markdown: String,
    font: Font,
    color: Color,
    codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy =
        structuredSessionAssistantFullResponseCodeBlockPolicy()
) -> some View {
    let segments = structuredSessionAssistantFullResponseProseSegments(in: markdown)
    let hasInlineMath = segments.contains { segment in
        if case .inlineMath = segment { return true }
        return false
    }
    if hasInlineMath {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if text.isEmpty == false {
                        StructuredSessionFeedRichMarkdownView(
                            markdown: text,
                            font: font,
                            color: color,
                            codeBlockPolicy: codeBlockPolicy
                        )
                    }
                case .inlineMath(let latex):
                    LaTeX("$\(latex)$")
                        .blockMode(.alwaysInline)
                        .errorMode(.original)
                        .font(font)
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
        StructuredSessionFeedRichMarkdownView(
            markdown: markdown,
            font: font,
            color: color,
            codeBlockPolicy: codeBlockPolicy
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
@MainActor
@ViewBuilder
func structuredSessionAssistantFullResponseMarkdownChunkView(
    markdown: String,
    codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy
) -> some View {
    let segments = structuredSessionAssistantFullResponseProseSegments(in: markdown)
    let hasInlineMath = segments.contains { segment in
        if case .inlineMath = segment { return true }
        return false
    }
    if hasInlineMath {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if text.isEmpty == false {
                        Markdown(text)
                            .markdownBlockStyle(\.codeBlock) { configuration in
                                structuredSessionAssistantFullResponseStyledCodeBlock(
                                    configuration: configuration,
                                    policy: codeBlockPolicy
                                )
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .inlineMath(let latex):
                    LaTeX("$\(latex)$")
                        .blockMode(.alwaysInline)
                        .errorMode(.original)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
        Markdown(markdown)
            .markdownBlockStyle(\.codeBlock) { configuration in
                structuredSessionAssistantFullResponseStyledCodeBlock(
                    configuration: configuration,
                    policy: codeBlockPolicy
                )
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
