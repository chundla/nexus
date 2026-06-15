import NexusDomain
import SwiftUI

public struct StructuredSessionPiFeedSegmentStyle {
    public var userBubbleBackground: Color
    public var userBubbleForeground: Color
    public var assistantBubbleBackground: Color
    public var assistantLabelForeground: Color
    public var assistantBodyForeground: Color
    public var toolAccent: Color
    public var mutedForeground: Color
    public var systemCapsuleBackground: Color
    public var bodyFont: (CGFloat, Font.TextStyle?, Font.Weight?) -> Font
    public var monoFont: (CGFloat, Font.TextStyle?) -> Font
    public var charactersPerLine: Int
    public var feedReaderIsScrollIdle: Bool
    public var allowsLatestAssistantInlineMarkdownHydration: Bool

    public init(
        userBubbleBackground: Color,
        userBubbleForeground: Color,
        assistantBubbleBackground: Color,
        assistantLabelForeground: Color,
        assistantBodyForeground: Color,
        toolAccent: Color,
        mutedForeground: Color,
        systemCapsuleBackground: Color,
        bodyFont: @escaping (CGFloat, Font.TextStyle?, Font.Weight?) -> Font,
        monoFont: @escaping (CGFloat, Font.TextStyle?) -> Font,
        charactersPerLine: Int,
        feedReaderIsScrollIdle: Bool = true,
        allowsLatestAssistantInlineMarkdownHydration: Bool = true
    ) {
        self.userBubbleBackground = userBubbleBackground
        self.userBubbleForeground = userBubbleForeground
        self.assistantBubbleBackground = assistantBubbleBackground
        self.assistantLabelForeground = assistantLabelForeground
        self.assistantBodyForeground = assistantBodyForeground
        self.toolAccent = toolAccent
        self.mutedForeground = mutedForeground
        self.systemCapsuleBackground = systemCapsuleBackground
        self.bodyFont = bodyFont
        self.monoFont = monoFont
        self.charactersPerLine = charactersPerLine
        self.feedReaderIsScrollIdle = feedReaderIsScrollIdle
        self.allowsLatestAssistantInlineMarkdownHydration = allowsLatestAssistantInlineMarkdownHydration
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionPiFeedSegmentView: View {
    public let segment: StructuredSessionFeedSegment
    public let providerDisplayName: String
    public let style: StructuredSessionPiFeedSegmentStyle
    public let disclosureState: StructuredSessionAgentTurnDisclosureState
    public let standaloneRow: (StructuredSessionActivityRow) -> AnyView
    public let onShowFullAssistantResponse: ((StructuredSessionAssistantFullResponsePresentation) -> Void)?
    public let artifactActions: (StructuredSessionFeedArtifactPresentation) -> StructuredSessionFeedArtifactActionPresentation
    public let onArtifactDownload: ((StructuredSessionFeedArtifactPresentation) -> Void)?
    public let onArtifactOpenOnHost: ((StructuredSessionFeedArtifactPresentation) -> Void)?

    public init(
        segment: StructuredSessionFeedSegment,
        providerDisplayName: String,
        style: StructuredSessionPiFeedSegmentStyle,
        disclosureState: StructuredSessionAgentTurnDisclosureState,
        standaloneRow: @escaping (StructuredSessionActivityRow) -> AnyView,
        onShowFullAssistantResponse: ((StructuredSessionAssistantFullResponsePresentation) -> Void)? = nil,
        artifactActions: @escaping (StructuredSessionFeedArtifactPresentation) -> StructuredSessionFeedArtifactActionPresentation = { artifact in
            structuredSessionFeedArtifactActionPresentation(
                for: artifact,
                hasWriterAuthority: true,
                usesHostArtifactFetch: false
            )
        },
        onArtifactDownload: ((StructuredSessionFeedArtifactPresentation) -> Void)? = nil,
        onArtifactOpenOnHost: ((StructuredSessionFeedArtifactPresentation) -> Void)? = nil
    ) {
        self.segment = segment
        self.providerDisplayName = providerDisplayName
        self.style = style
        self.disclosureState = disclosureState
        self.standaloneRow = standaloneRow
        self.onShowFullAssistantResponse = onShowFullAssistantResponse
        self.artifactActions = artifactActions
        self.onArtifactDownload = onArtifactDownload
        self.onArtifactOpenOnHost = onArtifactOpenOnHost
    }

    public var body: some View {
        switch segment {
        case .userMessage(let user):
            userMessageView(user)
        case .agentTurn(let turn):
            agentTurnView(turn)
        case .standalone(let item):
            if let artifact = structuredSessionFeedArtifactPresentation(for: item) {
                StructuredSessionFeedArtifactPreviewCard(
                    artifact: artifact,
                    actions: artifactActions(artifact),
                    onDownload: { onArtifactDownload?(artifact) },
                    onOpenOnHost: { onArtifactOpenOnHost?(artifact) }
                )
            } else {
                standaloneRow(structuredSessionAnnotatedActivityRow(for: item, providerDisplayName: providerDisplayName))
            }
        }
    }

    @ViewBuilder
    private func userMessageView(_ user: StructuredSessionFeedUserMessageSegment) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(user.text)
                .font(style.bodyFont(15, nil, nil))
                .foregroundStyle(style.userBubbleForeground)
                .structuredSessionFeedTextSelection()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(style.userBubbleBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 420, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .structuredSessionFeedRowCompositing()
    }

    @ViewBuilder
    private func agentTurnView(_ turn: StructuredSessionFeedAgentTurnSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reasoning = turn.reasoning {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { disclosureState.reasoningIsExpanded(for: turn) },
                        set: { disclosureState.setReasoningExpanded(turnID: turn.id, isExpanded: $0) }
                    )
                ) {
                    structuredSessionFeedMarkdownContentView(
                        markdown: reasoning.markdownBody,
                        font: style.bodyFont(14, nil, nil),
                        color: style.assistantBodyForeground
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text("Reasoning")
                        .font(style.bodyFont(12, .caption, .semibold))
                        .foregroundStyle(style.mutedForeground)
                }
            }

            if turn.tools.isEmpty == false {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { disclosureState.toolsIsExpanded(for: turn) },
                        set: { disclosureState.setToolsExpanded(turnID: turn.id, isExpanded: $0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(turn.tools) { tool in
                            toolRowView(turn: turn, tool: tool)
                        }
                    }
                } label: {
                    Text(structuredSessionAgentTurnToolsSummary(toolCount: turn.tools.count))
                        .font(style.bodyFont(12, .caption, .semibold))
                        .foregroundStyle(style.mutedForeground)
                }
            }

            if let finalAnswer = turn.finalAnswer {
                DisclosureGroup(
                    isExpanded: .constant(true)
                ) {
                    finalAnswerBody(finalAnswer, turnID: turn.id)
                } label: {
                    Text("Final answer")
                        .font(style.bodyFont(12, .caption, .semibold))
                        .foregroundStyle(style.mutedForeground)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(style.assistantBubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .structuredSessionFeedRowCompositing()
    }

    @ViewBuilder
    private func toolRowView(
        turn: StructuredSessionFeedAgentTurnSegment,
        tool: StructuredSessionFeedAgentTurnToolSegment
    ) -> some View {
        let defaultExpanded = structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn)
            .toolRows[safe: turn.tools.firstIndex(where: { $0.id == tool.id }) ?? 0] ?? false
        DisclosureGroup(
            isExpanded: Binding(
                get: { disclosureState.toolRowIsExpanded(turnID: turn.id, toolID: tool.id, defaultExpanded: defaultExpanded) },
                set: { disclosureState.setToolRowExpanded(turnID: turn.id, toolID: tool.id, isExpanded: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tool.callPreview)
                    .font(style.monoFont(12, .callout))
                    .foregroundStyle(style.assistantBodyForeground)
                    .structuredSessionFeedTextSelection()
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = tool.detailText {
                    Text(detail)
                        .font(style.monoFont(11, .caption))
                        .foregroundStyle(style.mutedForeground)
                        .structuredSessionFeedTextSelection()
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(tool.subagentOutputs.enumerated()), id: \.offset) { _, output in
                    Text(output)
                        .font(style.bodyFont(13, nil, nil))
                        .foregroundStyle(style.assistantBodyForeground.opacity(0.9))
                        .structuredSessionFeedTextSelection()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } label: {
            Text(structuredSessionAgentTurnToolPreview(callPreview: tool.callPreview))
                .font(style.monoFont(11, .caption))
                .foregroundStyle(style.toolAccent)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func finalAnswerBody(
        _ finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment,
        turnID: UUID
    ) -> some View {
        let conversation = StructuredSessionConversationPresentation(
            role: .assistant(label: "Pi"),
            text: finalAnswer.text,
            isStreaming: finalAnswer.isStreaming
        )
        StructuredSessionPiAgentTurnFinalAnswerView(
            conversation: conversation,
            turnID: turnID,
            style: style,
            onShowFullAssistantResponse: onShowFullAssistantResponse
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
private struct StructuredSessionPiAgentTurnFinalAnswerView: View {
    let conversation: StructuredSessionConversationPresentation
    let turnID: UUID
    let style: StructuredSessionPiFeedSegmentStyle
    let onShowFullAssistantResponse: ((StructuredSessionAssistantFullResponsePresentation) -> Void)?

    var body: some View {
        if conversation.isStreaming {
            streamingBody
        } else {
            finalizedBody
        }
    }

    @ViewBuilder
    private var streamingBody: some View {
        let policy = structuredSessionFeedStreamingAssistantDisplayPolicy(
            for: "Pi: \(conversation.text)",
            charactersPerLine: style.charactersPerLine
        )
        let display = structuredSessionFeedStreamingAssistantDisplayText(
            for: "Pi: \(conversation.text)",
            policy: policy
        )
        Text(verbatim: display.hasPrefix("Pi: ") ? String(display.dropFirst(4)) : display)
            .font(style.bodyFont(15, nil, nil))
            .foregroundStyle(style.assistantBodyForeground)
            .structuredSessionFeedTextSelection()
            .lineLimit(policy.previewLineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var finalizedBody: some View {
        let policy = structuredSessionFeedAgentTurnFinalAnswerMarkdownDisplayPolicy(
            for: conversation.text,
            charactersPerLine: style.charactersPerLine
        )
        let allowsHydration = structuredSessionFeedAllowsLatestAssistantInlineMarkdownHydration(
            prefersPlainTextInitialRender: false,
            feedReaderIsScrollIdle: style.feedReaderIsScrollIdle,
            feedTailIsStableForInlineMarkdown: true
        )
        structuredSessionFeedFinalAnswerMarkdownView(
            markdown: conversation.text,
            font: style.bodyFont(15, nil, nil),
            color: style.assistantBodyForeground,
            prefersPlainTextUntilIdle: false,
            allowsInlineMarkdownHydration: allowsHydration
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

public func structuredSessionAgentTurnToolsSummary(toolCount: Int) -> String {
    toolCount == 1 ? "Used 1 tool" : "Used \(toolCount) tools"
}

public func structuredSessionAgentTurnToolPreview(callPreview: String) -> String {
    let trimmed = callPreview.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 72 {
        return trimmed
    }
    let end = trimmed.index(trimmed.startIndex, offsetBy: 72)
    return String(trimmed[..<end]) + "…"
}

private func structuredSessionAnnotatedActivityRow(
    for item: SessionActivityItem,
    providerDisplayName: String
) -> StructuredSessionActivityRow {
    let base = structuredSessionActivityRows(for: [item])[0]
    let conversation = structuredSessionConversationPresentation(
        for: base,
        providerDisplayName: providerDisplayName
    )
    return StructuredSessionActivityRow(
        id: base.id,
        title: base.title,
        systemImage: base.systemImage,
        text: base.text,
        detailText: base.detailText,
        isDetailTextTruncated: base.isDetailTextTruncated,
        emphasis: base.emphasis,
        conversationPresentation: conversation,
        showsExpandedSystemCard: base.showsExpandedSystemCard
    )
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}