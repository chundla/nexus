import NexusDomain
import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionAgentTurnReasoningCard: View {
    public let turn: StructuredSessionFeedAgentTurnSegment
    public let reasoning: StructuredSessionFeedAgentTurnReasoningSegment
    public let style: StructuredSessionPiFeedSegmentStyle
    @ObservedObject public var disclosureState: StructuredSessionAgentTurnDisclosureState

    public init(
        turn: StructuredSessionFeedAgentTurnSegment,
        reasoning: StructuredSessionFeedAgentTurnReasoningSegment,
        style: StructuredSessionPiFeedSegmentStyle,
        disclosureState: StructuredSessionAgentTurnDisclosureState
    ) {
        self.turn = turn
        self.reasoning = reasoning
        self.style = style
        self.disclosureState = disclosureState
    }

    public var body: some View {
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Reasoning")
                    .font(style.bodyFont(12, .caption, .semibold))
                    .foregroundStyle(style.mutedForeground)
                if disclosureState.reasoningIsExpanded(for: turn) == false {
                    Text(structuredSessionAgentTurnReasoningCollapsedPreview(markdownBody: reasoning.markdownBody))
                        .font(style.bodyFont(14, nil, nil))
                        .foregroundStyle(style.assistantBodyForeground.opacity(0.88))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(style.assistantBubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .structuredSessionFeedRowCompositing()
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionAgentTurnToolBubble: View {
    public let turn: StructuredSessionFeedAgentTurnSegment
    public let tool: StructuredSessionFeedAgentTurnToolSegment
    public let style: StructuredSessionPiFeedSegmentStyle
    @ObservedObject public var disclosureState: StructuredSessionAgentTurnDisclosureState

    @State private var showsRawJSON = false

    public init(
        turn: StructuredSessionFeedAgentTurnSegment,
        tool: StructuredSessionFeedAgentTurnToolSegment,
        style: StructuredSessionPiFeedSegmentStyle,
        disclosureState: StructuredSessionAgentTurnDisclosureState
    ) {
        self.turn = turn
        self.tool = tool
        self.style = style
        self.disclosureState = disclosureState
    }

    private var isExpanded: Bool {
        disclosureState.toolRowIsExpanded(
            turnID: turn.id,
            toolID: tool.id,
            defaultExpanded: false
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    disclosureState.setToolRowExpanded(
                        turnID: turn.id,
                        toolID: tool.id,
                        isExpanded: !isExpanded
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(style.mutedForeground)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(structuredSessionAgentTurnToolCollapsedCommandLine(callPreview: tool.callPreview))
                        .font(style.monoFont(13, .callout))
                        .foregroundStyle(style.assistantBodyForeground)
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(structuredSessionAgentTurnToolCollapsedCommandLine(callPreview: tool.callPreview))

            if isExpanded {
                expandedBody
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .background(
            style.assistantBubbleBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style.toolAccent.opacity(0.12), lineWidth: 1)
        )
        .structuredSessionFeedRowCompositing()
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .opacity(0.35)

            VStack(alignment: .leading, spacing: 4) {
                Text("Command")
                    .font(style.bodyFont(11, .caption2, .semibold))
                    .foregroundStyle(style.mutedForeground)
                Text(tool.callPreview)
                    .font(style.monoFont(12, .callout))
                    .foregroundStyle(style.assistantBodyForeground)
                    .structuredSessionFeedTextSelection()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail = tool.detailText?.trimmingCharacters(in: .whitespacesAndNewlines),
               detail.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output")
                        .font(style.bodyFont(11, .caption2, .semibold))
                        .foregroundStyle(style.mutedForeground)
                    if showsRawJSON, let raw = structuredSessionAgentTurnToolRawJSONCandidate(
                        callPreview: tool.callPreview,
                        detailText: tool.detailText
                    ) {
                        Text(raw)
                            .font(style.monoFont(11, .caption))
                            .foregroundStyle(style.mutedForeground)
                            .structuredSessionFeedTextSelection()
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(detail)
                            .font(style.monoFont(11, .caption))
                            .foregroundStyle(style.mutedForeground)
                            .structuredSessionFeedTextSelection()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(Array(tool.subagentOutputs.enumerated()), id: \.offset) { index, output in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.subagentOutputs.count == 1 ? "Subagent" : "Subagent \(index + 1)")
                        .font(style.bodyFont(11, .caption2, .semibold))
                        .foregroundStyle(style.mutedForeground)
                    structuredSessionFeedMarkdownContentView(
                        markdown: output,
                        font: style.bodyFont(13, nil, nil),
                        color: style.assistantBodyForeground.opacity(0.92)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Button("Copy") {
                    structuredSessionFeedMarkdownCopyToPasteboard(
                        structuredSessionAgentTurnToolExpandedCopyPayload(
                            callPreview: tool.callPreview,
                            detailText: tool.detailText,
                            subagentOutputs: tool.subagentOutputs
                        )
                    )
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)

                if structuredSessionAgentTurnToolRawJSONCandidate(
                    callPreview: tool.callPreview,
                    detailText: tool.detailText
                ) != nil {
                    Button(showsRawJSON ? "Hide raw JSON" : "View raw JSON") {
                        showsRawJSON.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionAgentTurnStackView: View {
    public let turn: StructuredSessionFeedAgentTurnSegment
    public let providerDisplayName: String
    public let style: StructuredSessionPiFeedSegmentStyle
    @ObservedObject public var disclosureState: StructuredSessionAgentTurnDisclosureState
    public let onShowFullAssistantResponse: ((StructuredSessionAssistantFullResponsePresentation) -> Void)?

    public init(
        turn: StructuredSessionFeedAgentTurnSegment,
        providerDisplayName: String,
        style: StructuredSessionPiFeedSegmentStyle,
        disclosureState: StructuredSessionAgentTurnDisclosureState,
        onShowFullAssistantResponse: ((StructuredSessionAssistantFullResponsePresentation) -> Void)? = nil
    ) {
        self.turn = turn
        self.providerDisplayName = providerDisplayName
        self.style = style
        self.disclosureState = disclosureState
        self.onShowFullAssistantResponse = onShowFullAssistantResponse
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reasoning = turn.reasoning {
                StructuredSessionAgentTurnReasoningCard(
                    turn: turn,
                    reasoning: reasoning,
                    style: style,
                    disclosureState: disclosureState
                )
            }

            ForEach(turn.tools) { tool in
                StructuredSessionAgentTurnToolBubble(
                    turn: turn,
                    tool: tool,
                    style: style,
                    disclosureState: disclosureState
                )
            }

            if turn.turnNotices.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(turn.turnNotices.enumerated()), id: \.offset) { _, notice in
                        switch notice {
                        case .progress(let text):
                            Text(text)
                                .font(style.bodyFont(13, nil, nil))
                                .foregroundStyle(style.mutedForeground)
                                .structuredSessionFeedTextSelection()
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        case .error(let text):
                            Text(text)
                                .font(style.bodyFont(13, nil, nil))
                                .foregroundStyle(Color.red.opacity(0.92))
                                .structuredSessionFeedTextSelection()
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }

            if turn.isOpen == false, let finalAnswer = turn.finalAnswer {
                finalAnswerBubble(finalAnswer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func finalAnswerBubble(_ finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment) -> some View {
        let conversation = StructuredSessionConversationPresentation(
            role: .assistant(label: providerDisplayName),
            text: finalAnswer.text,
            isStreaming: finalAnswer.isStreaming
        )
        HStack {
            StructuredSessionPiAgentTurnFinalAnswerView(
                conversation: conversation,
                turnID: turn.id,
                style: style,
                onShowFullAssistantResponse: onShowFullAssistantResponse
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 620, alignment: .leading)
            .background(style.assistantBubbleBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 48)
        }
        .structuredSessionFeedRowCompositing()
    }
}