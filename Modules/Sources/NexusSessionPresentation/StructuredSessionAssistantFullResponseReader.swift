import LaTeXSwiftUI
import MarkdownUI
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Dedicated full assistant response reader for structured Session feed rows (#226, #228).
@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionAssistantFullResponseReader: View {
    private let markdown: String
    private let codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy
    private let displayMathPolicy: StructuredSessionAssistantFullResponseDisplayMathPolicy

    public init(
        markdown: String,
        codeBlockPolicy: StructuredSessionAssistantFullResponseCodeBlockPolicy =
            structuredSessionAssistantFullResponseCodeBlockPolicy(),
        displayMathPolicy: StructuredSessionAssistantFullResponseDisplayMathPolicy =
            structuredSessionAssistantFullResponseDisplayMathPolicy()
    ) {
        self.markdown = markdown
        self.codeBlockPolicy = codeBlockPolicy
        self.displayMathPolicy = displayMathPolicy
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(
                        structuredSessionAssistantFullResponseReaderSegments(in: markdown, policy: displayMathPolicy)
                            .enumerated()), id: \.offset
                ) { _, segment in
                    if let chunk = segment.markdownChunk {
                        Markdown(chunk)
                            .markdownBlockStyle(\.codeBlock) { configuration in
                                structuredSessionAssistantFullResponseCodeBlock(
                                    configuration: configuration,
                                    policy: codeBlockPolicy
                                )
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let math = segment.displayMath {
                        LaTeX("\\[\(math.latex)\\]")
                            .blockMode(.blockViews)
                            .errorMode(.original)
                            .padding(.vertical, displayMathPolicy.blockVerticalPaddingPoints)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func structuredSessionAssistantFullResponseCodeBlock(
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
                        structuredSessionAssistantFullResponseCopyToPasteboard(configuration.content)
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
                        structuredSessionAssistantFullResponseCodeBlockLabel(
                            configuration: configuration, policy: policy)
                    }
                } else {
                    structuredSessionAssistantFullResponseCodeBlockLabel(configuration: configuration, policy: policy)
                }
            }
            .padding(policy.contentPaddingPoints)
        }
        .background(structuredSessionAssistantFullResponseCodeBlockBackgroundColor())
        .clipShape(RoundedRectangle(cornerRadius: policy.blockCornerRadiusPoints, style: .continuous))
        .markdownMargin(top: 0, bottom: 16)
    }

    @ViewBuilder
    private func structuredSessionAssistantFullResponseCodeBlockLabel(
        configuration: CodeBlockConfiguration,
        policy: StructuredSessionAssistantFullResponseCodeBlockPolicy
    ) -> some View {
        let label = configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(policy.lineSpacingEm))
            .markdownTextStyle {
                if policy.usesMonospacedPresentation {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(policy.monospacedFontScale))
                }
            }

        if policy.enablesPerBlockTextSelection {
            label.textSelection(.enabled)
        } else {
            label
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
private func structuredSessionAssistantFullResponseCodeBlockBackgroundColor() -> Color {
    #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
    #else
        Color(nsColor: .controlBackgroundColor)
    #endif
}

@available(macOS 12.0, iOS 15.0, *)
private func structuredSessionAssistantFullResponseCopyToPasteboard(_ text: String) {
    #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    #elseif os(iOS)
        UIPasteboard.general.string = text
    #endif
}
