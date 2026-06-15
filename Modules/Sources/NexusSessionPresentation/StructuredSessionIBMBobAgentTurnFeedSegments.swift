import Foundation
import NexusDomain

// MARK: - Composite feed segments (ADR 0037, IBM Bob)

/// IBM Bob composite feed projection. Returns `nil` for non-Bob **Sessions**.
public func structuredSessionIBMBobFeedSegments(for screen: SessionScreen) -> [StructuredSessionFeedSegment]? {
    guard screen.session.providerID == .ibmBob else {
        return nil
    }

    return structuredSessionIBMBobFeedSegments(
        activityItems: screen.activityItems,
        isAgentTurnInProgress: screen.isAgentTurnInProgress,
        liveAssistantDraftText: screen.providerFacts.liveAssistantDraftText
    )
}

func structuredSessionIBMBobFeedSegments(
    activityItems: [SessionActivityItem],
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> [StructuredSessionFeedSegment] {
    var segments: [StructuredSessionFeedSegment] = []
    var index = 0

    while index < activityItems.count {
        let item = activityItems[index]

        if structuredSessionIBMBobFeedSegmentIsPromptAnchoredUserMessage(item),
           let userBody = structuredSessionIBMBobUserMessageBody(from: item) {
            segments.append(.userMessage(StructuredSessionFeedUserMessageSegment(
                activityItemID: item.id,
                text: userBody
            )))
            index += 1

            let turnSlice = structuredSessionIBMBobAgentTurnActivitySlice(
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

private struct StructuredSessionIBMBobAgentTurnSlice {
    let nextIndex: Int
    let turn: StructuredSessionFeedAgentTurnSegment?
}

private func structuredSessionIBMBobAgentTurnActivitySlice(
    activityItems: [SessionActivityItem],
    startIndex: Int,
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> StructuredSessionIBMBobAgentTurnSlice {
    guard startIndex < activityItems.count else {
        return StructuredSessionIBMBobAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    var reasoningParts: [String] = []
    var tools: [StructuredSessionFeedAgentTurnToolSegment] = []
    var openToolIndex: Int?
    var finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?
    var cursor = startIndex
    var consumedAny = false

    while cursor < activityItems.count {
        let item = activityItems[cursor]

        if structuredSessionIBMBobFeedSegmentIsPromptAnchoredUserMessage(item) {
            break
        }

        if structuredSessionIBMBobFeedSegmentIsOutsideStackRow(item) {
            break
        }

        if structuredSessionIBMBobFeedSegmentIsThoughtsStatus(item) {
            if let detail = item.detailText?.trimmingCharacters(in: .whitespacesAndNewlines),
               detail.isEmpty == false {
                reasoningParts.append(detail)
            }
            consumedAny = true
            cursor += 1
            continue
        }

        if let thinkingBody = structuredSessionIBMBobThinkingStreamBody(from: item) {
            reasoningParts.append(thinkingBody)
            consumedAny = true
            cursor += 1
            continue
        }

        if item.kind == .command {
            tools.append(StructuredSessionFeedAgentTurnToolSegment(
                activityItemID: item.id,
                callPreview: item.text,
                detailText: item.detailText
            ))
            openToolIndex = tools.count - 1
            consumedAny = true
            cursor += 1
            continue
        }

        if let plainBody = structuredSessionIBMBobPlainAssistantMessageBody(from: item),
           openToolIndex != nil {
            let toolIndex = openToolIndex!
            let hasFollowingPlainAssistant = structuredSessionIBMBobHasPlainAssistantMessage(
                in: activityItems,
                afterIndex: cursor
            )
            let toolAlreadyHasOutput = tools[toolIndex].subagentOutputs.isEmpty == false

            if hasFollowingPlainAssistant || toolAlreadyHasOutput == false {
                var tool = tools[toolIndex]
                tool = StructuredSessionFeedAgentTurnToolSegment(
                    activityItemID: tool.activityItemID,
                    callPreview: tool.callPreview,
                    detailText: tool.detailText,
                    subagentOutputs: tool.subagentOutputs + [plainBody]
                )
                tools[toolIndex] = tool
                consumedAny = true
                cursor += 1
                continue
            }

            finalAnswer = StructuredSessionFeedAgentTurnFinalAnswerSegment(text: plainBody, isStreaming: false)
            consumedAny = true
            cursor += 1
            break
        }

        if let plainBody = structuredSessionIBMBobPlainAssistantMessageBody(from: item) {
            finalAnswer = StructuredSessionFeedAgentTurnFinalAnswerSegment(text: plainBody, isStreaming: false)
            consumedAny = true
            cursor += 1
            break
        }

        break
    }

    let isOpenTurn = isAgentTurnInProgress && finalAnswer == nil

    guard consumedAny else {
        return StructuredSessionIBMBobAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    let reasoning: StructuredSessionFeedAgentTurnReasoningSegment?
    if reasoningParts.isEmpty {
        reasoning = nil
    } else {
        reasoning = StructuredSessionFeedAgentTurnReasoningSegment(
            markdownBody: reasoningParts.joined(separator: "\n\n")
        )
    }

    let turnID = activityItems[startIndex].id
    let turn = StructuredSessionFeedAgentTurnSegment(
        id: turnID,
        isOpen: isOpenTurn,
        reasoning: reasoning,
        tools: tools,
        finalAnswer: finalAnswer
    )

    return StructuredSessionIBMBobAgentTurnSlice(nextIndex: cursor, turn: turn)
}

private func structuredSessionIBMBobHasPlainAssistantMessage(
    in activityItems: [SessionActivityItem],
    afterIndex index: Int
) -> Bool {
    let next = index + 1
    guard next < activityItems.count else {
        return false
    }
    return structuredSessionIBMBobPlainAssistantMessageBody(from: activityItems[next]) != nil
}

private func structuredSessionIBMBobFeedSegmentIsPromptAnchoredUserMessage(_ item: SessionActivityItem) -> Bool {
    if item.prompt != nil {
        return true
    }
    guard item.kind == .message else {
        return false
    }
    return structuredSessionIBMBobUserMessageBody(from: item) != nil
}

private func structuredSessionIBMBobUserMessageBody(from item: SessionActivityItem) -> String? {
    if let prompt = item.prompt {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    guard let split = structuredSessionIBMBobConversationPrefixSplit(for: item.text),
          split.label.caseInsensitiveCompare("you") == .orderedSame else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private let structuredSessionIBMBobThoughtsStatusLabel = "thoughts:"

private func structuredSessionIBMBobFeedSegmentIsThoughtsStatus(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .status else {
        return false
    }
    return item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(structuredSessionIBMBobThoughtsStatusLabel) == .orderedSame
}

private func structuredSessionIBMBobThinkingStreamBody(from item: SessionActivityItem) -> String? {
    guard item.kind == .message else {
        return nil
    }
    guard let split = structuredSessionIBMBobConversationPrefixSplit(for: item.text),
          split.label.caseInsensitiveCompare("thinking") == .orderedSame else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionIBMBobFeedSegmentIsOutsideStackRow(_ item: SessionActivityItem) -> Bool {
    switch item.kind {
    case .status:
        return structuredSessionIBMBobFeedSegmentIsThoughtsStatus(item) == false
    case .message:
        if structuredSessionIBMBobFeedSegmentIsPromptAnchoredUserMessage(item) {
            return false
        }
        if structuredSessionIBMBobThinkingStreamBody(from: item) != nil {
            return false
        }
        return structuredSessionIBMBobPlainAssistantMessageBody(from: item) == nil
    case .progress, .completion, .error, .approvalRequest, .approvalDecision, .diff:
        return true
    case .command:
        return false
    }
}

private func structuredSessionIBMBobPlainAssistantMessageBody(from item: SessionActivityItem) -> String? {
    guard item.kind == .message else {
        return nil
    }
    if structuredSessionIBMBobFeedSegmentIsPromptAnchoredUserMessage(item) {
        return nil
    }
    if structuredSessionIBMBobThinkingStreamBody(from: item) != nil {
        return nil
    }
    if structuredSessionIBMBobConversationPrefixSplit(for: item.text) != nil {
        return nil
    }
    let body = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionIBMBobConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
    guard let separatorRange = text.range(of: ": ") else {
        return nil
    }

    let label = String(text[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = String(text[separatorRange.upperBound...])
    guard label.isEmpty == false,
          body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
          label.count <= 32 else {
        return nil
    }
    return (label, body)
}