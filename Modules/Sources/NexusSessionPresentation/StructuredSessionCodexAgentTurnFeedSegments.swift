import Foundation
import NexusDomain

// MARK: - Composite feed segments (ADR 0037, Codex)

/// Codex composite feed projection. Returns `nil` for non-Codex **Sessions**.
public func structuredSessionCodexFeedSegments(for screen: SessionScreen) -> [StructuredSessionFeedSegment]? {
    guard screen.session.providerID == .codex else {
        return nil
    }

    return structuredSessionCodexFeedSegments(
        activityItems: screen.activityItems,
        isAgentTurnInProgress: screen.isAgentTurnInProgress,
        liveAssistantDraftText: screen.providerFacts.liveAssistantDraftText
    )
}

func structuredSessionCodexFeedSegments(
    activityItems: [SessionActivityItem],
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> [StructuredSessionFeedSegment] {
    var segments: [StructuredSessionFeedSegment] = []
    var index = 0

    while index < activityItems.count {
        let item = activityItems[index]

        if structuredSessionCodexFeedSegmentIsPromptAnchoredUserMessage(item),
            let userBody = structuredSessionCodexUserMessageBody(from: item)
        {
            segments.append(
                .userMessage(
                    StructuredSessionFeedUserMessageSegment(
                        activityItemID: item.id,
                        text: userBody
                    )))
            index += 1

            let turnSlice = structuredSessionCodexAgentTurnActivitySlice(
                activityItems: activityItems,
                startIndex: index,
                isAgentTurnInProgress: isAgentTurnInProgress,
                liveAssistantDraftText: liveAssistantDraftText
            )
            index = turnSlice.nextIndex

            if let turn = turnSlice.turn {
                segments.append(.agentTurn(turn))
            }
            continue
        }

        segments.append(.standalone(item))
        index += 1
    }

    return segments
}

private struct StructuredSessionCodexAgentTurnSlice {
    let nextIndex: Int
    let turn: StructuredSessionFeedAgentTurnSegment?
}

private func structuredSessionCodexAgentTurnActivitySlice(
    activityItems: [SessionActivityItem],
    startIndex: Int,
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> StructuredSessionCodexAgentTurnSlice {
    guard startIndex < activityItems.count else {
        return StructuredSessionCodexAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    var stackItems: [StructuredSessionFeedAgentTurnStackItem] = []
    var tools: [StructuredSessionFeedAgentTurnToolSegment] = []
    var openToolIndex: Int?
    var finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?
    var cursor = startIndex
    var consumedAny = false

    while cursor < activityItems.count {
        let item = activityItems[cursor]

        if structuredSessionCodexFeedSegmentIsPromptAnchoredUserMessage(item) {
            break
        }

        if structuredSessionCodexFeedSegmentIsOutsideStackRow(item) {
            break
        }

        if structuredSessionCodexFeedSegmentIsThoughtsStatus(item) {
            if let detail = item.detailText?.trimmingCharacters(in: .whitespacesAndNewlines),
                detail.isEmpty == false
            {
                stackItems.append(
                    .reasoning(
                        StructuredSessionFeedAgentTurnReasoningSegment(
                            activityItemID: item.id,
                            markdownBody: detail
                        )))
            }
            consumedAny = true
            cursor += 1
            continue
        }

        if let thinkingBody = structuredSessionCodexThinkingStreamBody(from: item) {
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
            if structuredSessionCodexFeedSegmentIsThinkingCommandAnnouncement(item) {
                consumedAny = true
                cursor += 1
                continue
            }
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

        if let toolOutput = structuredSessionCodexToolStreamOutputBody(from: item.text),
            let toolIndex = openToolIndex
        {
            var tool = tools[toolIndex]
            tool = StructuredSessionFeedAgentTurnToolSegment(
                activityItemID: tool.activityItemID,
                callPreview: tool.callPreview,
                detailText: tool.detailText,
                subagentOutputs: tool.subagentOutputs + [toolOutput]
            )
            tools[toolIndex] = tool
            structuredSessionAgentTurnSyncStackTool(tool, in: &stackItems)
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionCodexFeedSegmentIsPrimaryCodexAssistantMessage(item) {
            if isAgentTurnInProgress == false,
                let body = structuredSessionCodexPrimaryAssistantBody(from: item.text)
            {
                finalAnswer = StructuredSessionFeedAgentTurnFinalAnswerSegment(text: body, isStreaming: false)
            }
            consumedAny = true
            cursor += 1
            if isAgentTurnInProgress {
                continue
            }
            break
        }

        break
    }

    let isOpenTurn = isAgentTurnInProgress && finalAnswer == nil

    guard consumedAny else {
        return StructuredSessionCodexAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    let turnID = activityItems[startIndex].id
    let turn = StructuredSessionFeedAgentTurnSegment(
        id: turnID,
        isOpen: isOpenTurn,
        stackItems: stackItems,
        finalAnswer: finalAnswer
    )

    return StructuredSessionCodexAgentTurnSlice(nextIndex: cursor, turn: turn)
}

private func structuredSessionCodexFeedSegmentIsPromptAnchoredUserMessage(_ item: SessionActivityItem) -> Bool {
    if item.prompt != nil {
        return true
    }
    guard item.kind == .message else {
        return false
    }
    return structuredSessionCodexUserMessageBody(from: item) != nil
}

private func structuredSessionCodexUserMessageBody(from item: SessionActivityItem) -> String? {
    if let prompt = item.prompt {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    guard let split = structuredSessionCodexConversationPrefixSplit(for: item.text),
        split.label.caseInsensitiveCompare("you") == .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private let structuredSessionCodexThoughtsStatusLabel = "thoughts:"

private func structuredSessionCodexFeedSegmentIsThoughtsStatus(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .status else {
        return false
    }
    return item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(structuredSessionCodexThoughtsStatusLabel) == .orderedSame
}

private func structuredSessionCodexFeedSegmentIsThinkingCommandAnnouncement(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .command else {
        return false
    }
    let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.caseInsensitiveCompare("thinking") == .orderedSame
}

private func structuredSessionCodexThinkingStreamBody(from item: SessionActivityItem) -> String? {
    guard item.kind == .message else {
        return nil
    }
    guard let split = structuredSessionCodexConversationPrefixSplit(for: item.text),
        split.label.caseInsensitiveCompare("thinking") == .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionCodexFeedSegmentIsOutsideStackRow(_ item: SessionActivityItem) -> Bool {
    switch item.kind {
    case .status:
        return structuredSessionCodexFeedSegmentIsThoughtsStatus(item) == false
    case .message:
        if structuredSessionCodexFeedSegmentIsPromptAnchoredUserMessage(item) {
            return false
        }
        if structuredSessionCodexFeedSegmentIsPrimaryCodexAssistantMessage(item) {
            return false
        }
        if structuredSessionCodexThinkingStreamBody(from: item) != nil {
            return false
        }
        return structuredSessionCodexToolStreamOutputBody(from: item.text) == nil
    case .progress, .completion, .error, .approvalRequest, .approvalDecision, .diff:
        return true
    case .command:
        return false
    }
}

func structuredSessionCodexFeedSegmentIsPrimaryCodexAssistantMessage(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .message else {
        return false
    }
    guard let split = structuredSessionCodexConversationPrefixSplit(for: item.text) else {
        return false
    }
    return split.label.caseInsensitiveCompare("Codex") == .orderedSame
}

private func structuredSessionCodexPrimaryAssistantBody(from text: String) -> String? {
    guard let split = structuredSessionCodexConversationPrefixSplit(for: text) else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionCodexToolStreamOutputBody(from text: String) -> String? {
    guard let split = structuredSessionCodexConversationPrefixSplit(for: text) else {
        return nil
    }
    let label = split.label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard label.caseInsensitiveCompare("Codex") != .orderedSame,
        label.caseInsensitiveCompare("you") != .orderedSame,
        label.caseInsensitiveCompare("thinking") != .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionCodexConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
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

/// Composite feed segments for structured **Sessions** that use agent-turn projection (Pi, Codex, IBM Bob).
public func structuredSessionAgentTurnFeedSegments(for screen: SessionScreen) -> [StructuredSessionFeedSegment]? {
    if let segments = structuredSessionPiFeedSegments(for: screen) {
        return segments
    }
    if let segments = structuredSessionCodexFeedSegments(for: screen) {
        return segments
    }
    return structuredSessionIBMBobFeedSegments(for: screen)
}
