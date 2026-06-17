import Foundation
import NexusDomain

// MARK: - Composite feed segments (ADR 0037, Claude)

/// Claude composite feed projection. Returns `nil` for non-Claude **Sessions**.
public func structuredSessionClaudeFeedSegments(for screen: SessionScreen) -> [StructuredSessionFeedSegment]? {
    guard screen.session.providerID == .claude else {
        return nil
    }

    return structuredSessionClaudeFeedSegments(
        activityItems: screen.activityItems,
        isAgentTurnInProgress: screen.isAgentTurnInProgress,
        liveAssistantDraftText: screen.providerFacts.liveAssistantDraftText
    )
}

func structuredSessionClaudeFeedSegments(
    activityItems: [SessionActivityItem],
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> [StructuredSessionFeedSegment] {
    _ = liveAssistantDraftText

    var segments: [StructuredSessionFeedSegment] = []
    var index = 0

    while index < activityItems.count {
        let item = activityItems[index]

        if structuredSessionClaudeFeedSegmentIsPromptAnchoredUserMessage(item),
            let userBody = structuredSessionClaudeUserMessageBody(from: item)
        {
            segments.append(
                .userMessage(
                    StructuredSessionFeedUserMessageSegment(
                        activityItemID: item.id,
                        text: userBody
                    )))
            index += 1

            while index < activityItems.count {
                let candidate = activityItems[index]
                if structuredSessionClaudeFeedSegmentIsPromptAnchoredUserMessage(candidate) {
                    break
                }

                let turnSlice = structuredSessionClaudeAgentTurnActivitySlice(
                    activityItems: activityItems,
                    startIndex: index,
                    isAgentTurnInProgress: isAgentTurnInProgress,
                    liveAssistantDraftText: liveAssistantDraftText
                )

                if let turn = turnSlice.turn {
                    segments.append(.agentTurn(turn))
                    index = turnSlice.nextIndex
                    continue
                }

                segments.append(.standalone(candidate))
                index += 1
            }
            continue
        }

        segments.append(.standalone(item))
        index += 1
    }

    return segments
}

private struct StructuredSessionClaudeAgentTurnSlice {
    let nextIndex: Int
    let turn: StructuredSessionFeedAgentTurnSegment?
}

private func structuredSessionClaudeAgentTurnActivitySlice(
    activityItems: [SessionActivityItem],
    startIndex: Int,
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> StructuredSessionClaudeAgentTurnSlice {
    _ = liveAssistantDraftText

    guard startIndex < activityItems.count else {
        return StructuredSessionClaudeAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    var stackItems: [StructuredSessionFeedAgentTurnStackItem] = []
    var tools: [StructuredSessionFeedAgentTurnToolSegment] = []
    var openToolIndex: Int?
    var finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?
    var turnNotices: [StructuredSessionFeedAgentTurnNotice] = []
    var cursor = startIndex
    var consumedAny = false

    while cursor < activityItems.count {
        let item = activityItems[cursor]

        if structuredSessionClaudeFeedSegmentIsPromptAnchoredUserMessage(item) {
            break
        }

        if item.kind == .error {
            structuredSessionClaudeAgentTurnAbsorbErrorText(
                item.text,
                to: &tools,
                openToolIndex: openToolIndex,
                stackItems: &stackItems,
                turnNotices: &turnNotices
            )
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionClaudeFeedSegmentIsOutsideStackRow(item) {
            break
        }

        if let thinkingBody = structuredSessionClaudeThinkingStreamBody(from: item) {
            stackItems.append(
                .reasoning(
                    StructuredSessionFeedAgentTurnReasoningSegment(
                        activityItemID: item.id,
                        markdownBody: thinkingBody
                    )))
            consumedAny = true
            cursor += 1
            continue
        }

        if item.kind == .command {
            let tool = StructuredSessionFeedAgentTurnToolSegment(
                activityItemID: item.id,
                callPreview: item.text,
                detailText: item.detailText
            )
            tools.append(tool)
            stackItems.append(.tool(tool))
            openToolIndex = tools.count - 1
            consumedAny = true
            cursor += 1
            continue
        }

        if let toolOutput = structuredSessionClaudeToolStreamOutputBody(from: item.text),
            let toolIndex = openToolIndex
        {
            structuredSessionClaudeAgentTurnMergeDetailLine(toolOutput, into: &tools[toolIndex])
            structuredSessionAgentTurnSyncStackTool(tools[toolIndex], in: &stackItems)
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionClaudeFeedSegmentIsPrimaryAssistantMessage(item) {
            if let body = structuredSessionClaudePrimaryAssistantBody(from: item.text) {
                finalAnswer = structuredSessionClaudeMergedFinalAnswer(
                    existing: finalAnswer,
                    body: body,
                    isStreaming: isAgentTurnInProgress
                )
            }
            consumedAny = true
            cursor += 1
            if isAgentTurnInProgress {
                finalAnswer = nil
                continue
            }
            continue
        }

        break
    }

    let isOpenTurn = isAgentTurnInProgress && finalAnswer == nil

    guard consumedAny else {
        return StructuredSessionClaudeAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    return StructuredSessionClaudeAgentTurnSlice(
        nextIndex: cursor,
        turn: StructuredSessionFeedAgentTurnSegment(
            id: activityItems[startIndex].id,
            isOpen: isOpenTurn,
            stackItems: stackItems,
            turnNotices: turnNotices,
            finalAnswer: finalAnswer
        )
    )
}

private func structuredSessionClaudeFeedSegmentIsPromptAnchoredUserMessage(_ item: SessionActivityItem) -> Bool {
    if item.prompt != nil {
        return true
    }
    guard item.kind == .message else {
        return false
    }
    return structuredSessionClaudeUserMessageBody(from: item) != nil
}

private func structuredSessionClaudeUserMessageBody(from item: SessionActivityItem) -> String? {
    if let prompt = item.prompt {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    guard let split = structuredSessionClaudeConversationPrefixSplit(for: item.text),
        split.label.caseInsensitiveCompare("you") == .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionClaudeThinkingStreamBody(from item: SessionActivityItem) -> String? {
    guard item.kind == .message else {
        return nil
    }
    guard let split = structuredSessionClaudeConversationPrefixSplit(for: item.text),
        split.label.caseInsensitiveCompare("Claude (thinking)") == .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionClaudeFeedSegmentIsOutsideStackRow(_ item: SessionActivityItem) -> Bool {
    switch item.kind {
    case .status, .progress, .completion, .approvalRequest, .approvalDecision, .diff:
        return true
    case .error:
        return true
    case .message:
        if structuredSessionClaudeFeedSegmentIsPromptAnchoredUserMessage(item) {
            return false
        }
        if structuredSessionClaudeFeedSegmentIsPrimaryAssistantMessage(item) {
            return false
        }
        if structuredSessionClaudeThinkingStreamBody(from: item) != nil {
            return false
        }
        return structuredSessionClaudeToolStreamOutputBody(from: item.text) == nil
    case .command:
        return false
    }
}

private func structuredSessionClaudeFeedSegmentIsPrimaryAssistantMessage(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .message else {
        return false
    }
    guard let split = structuredSessionClaudeConversationPrefixSplit(for: item.text) else {
        return false
    }
    return split.label.caseInsensitiveCompare("Claude") == .orderedSame
}

private func structuredSessionClaudePrimaryAssistantBody(from text: String) -> String? {
    guard let split = structuredSessionClaudeConversationPrefixSplit(for: text),
        split.label.caseInsensitiveCompare("Claude") == .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionClaudeToolStreamOutputBody(from text: String) -> String? {
    guard let split = structuredSessionClaudeConversationPrefixSplit(for: text) else {
        return nil
    }
    let label = split.label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard label.caseInsensitiveCompare("Claude") != .orderedSame,
        label.caseInsensitiveCompare("Claude (thinking)") != .orderedSame,
        label.caseInsensitiveCompare("you") != .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionClaudeMergedFinalAnswer(
    existing: StructuredSessionFeedAgentTurnFinalAnswerSegment?,
    body: String,
    isStreaming: Bool
) -> StructuredSessionFeedAgentTurnFinalAnswerSegment {
    guard let existing else {
        return StructuredSessionFeedAgentTurnFinalAnswerSegment(text: body, isStreaming: isStreaming)
    }
    return StructuredSessionFeedAgentTurnFinalAnswerSegment(
        text: existing.text + "\n\n" + body,
        isStreaming: isStreaming
    )
}

private func structuredSessionClaudeAgentTurnAbsorbErrorText(
    _ rawText: String,
    to tools: inout [StructuredSessionFeedAgentTurnToolSegment],
    openToolIndex: Int?,
    stackItems: inout [StructuredSessionFeedAgentTurnStackItem],
    turnNotices: inout [StructuredSessionFeedAgentTurnNotice]
) {
    let errorText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard errorText.isEmpty == false else {
        return
    }

    guard let toolIndex = openToolIndex, tools.indices.contains(toolIndex) else {
        turnNotices.append(.error(errorText))
        return
    }

    structuredSessionClaudeAgentTurnMergeDetailLine(errorText, into: &tools[toolIndex])
    structuredSessionAgentTurnSyncStackTool(tools[toolIndex], in: &stackItems)
}

private func structuredSessionClaudeAgentTurnMergeDetailLine(
    _ line: String,
    into tool: inout StructuredSessionFeedAgentTurnToolSegment
) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
        return
    }
    let mergedDetail: String
    if let existing = tool.detailText?.trimmingCharacters(in: .whitespacesAndNewlines), existing.isEmpty == false {
        mergedDetail = existing + "\n" + trimmed
    } else {
        mergedDetail = trimmed
    }
    tool = StructuredSessionFeedAgentTurnToolSegment(
        activityItemID: tool.activityItemID,
        callPreview: tool.callPreview,
        detailText: mergedDetail,
        subagentOutputs: tool.subagentOutputs
    )
}

private func structuredSessionClaudeConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
    guard let separatorRange = text.range(of: ": ") else {
        return nil
    }

    let label = String(text[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = String(text[separatorRange.upperBound...])
    guard label.isEmpty == false,
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
        label.count <= 32
    else {
        return nil
    }
    return (label, body)
}
