import LaTeXSwiftUI
import MarkdownUI
import SwiftUI

/// Feed assistant / reasoning markdown with block structure (headings, tables, rules, lists, code).
@available(macOS 12.0, iOS 15.0, *)
@MainActor
public struct StructuredSessionFeedRichMarkdownView: View {
    private let markdown: String
    private let font: Font
    private let color: Color
    private let codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy

    public init(
        markdown: String,
        font: Font,
        color: Color,
        codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy =
            structuredSessionAssistantFullResponseCodeBlockPolicy()
    ) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.codeBlockPolicy = codeBlockPolicy
    }

    public var body: some View {
        if structuredSessionFeedDisplayMathUsesPlainFallback(for: markdown) {
            displayMathSegmentStack(
                markdown: markdown,
                font: font,
                color: color,
                codeBlockPolicy: codeBlockPolicy
            )
        } else if structuredSessionAssistantFullResponseProseContainsExtractedInlineMath(in: markdown) {
            structuredSessionFeedLaTeXProseView(
                markdown: markdown,
                font: font,
                color: color,
                codeBlockPolicy: codeBlockPolicy
            )
        } else {
            Markdown(markdown)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    structuredSessionFeedRichMarkdownCodeBlock(
                        configuration: configuration,
                        policy: codeBlockPolicy
                    )
                }
                .markdownTextStyle(\.text) {
                    FontSize(.em(1))
                    ForegroundColor(color)
                }
                .markdownTextStyle(\.code) {
                    FontFamilyVariant(.monospaced)
                }
                .font(font)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func displayMathSegmentStack(
        markdown: String,
        font: Font,
        color: Color,
        codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy
    ) -> some View {
        let policy = structuredSessionAssistantFullResponseDisplayMathPolicy()
        VStack(alignment: .leading, spacing: 12) {
            ForEach(
                Array(structuredSessionAssistantFullResponseReaderSegments(in: markdown, policy: policy).enumerated()),
                id: \.offset
            ) { _, segment in
                if let chunk = segment.markdownChunk {
                    structuredSessionFeedLaTeXProseView(
                        markdown: chunk,
                        font: font,
                        color: color,
                        codeBlockPolicy: codeBlockPolicy
                    )
                } else if let math = segment.displayMath {
                    LaTeX("\\[\(math.latex)\\]")
                        .blockMode(.blockViews)
                        .errorMode(.original)
                        .padding(.vertical, policy.blockVerticalPaddingPoints)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
@MainActor
@ViewBuilder
private func structuredSessionFeedRichMarkdownCodeBlock(
    configuration: CodeBlockConfiguration,
    policy: StructuredSessionAssistantFullResponseCodeBlockPolicy
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        if policy.showsCopyAction {
            HStack(spacing: 8) {
                Text(configuration.language ?? "code")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Button("Copy") {
                    let content = configuration.content
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
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(policy.contentPaddingPoints)
    }
    .background(structuredSessionFeedRichMarkdownCodeBlockBackgroundColor())
    .clipShape(RoundedRectangle(cornerRadius: policy.blockCornerRadiusPoints, style: .continuous))
    .markdownMargin(top: 0, bottom: 12)
}

@available(macOS 12.0, iOS 15.0, *)
private func structuredSessionFeedRichMarkdownCodeBlockBackgroundColor() -> Color {
    #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
    #else
        Color(nsColor: .controlBackgroundColor)
    #endif
}
