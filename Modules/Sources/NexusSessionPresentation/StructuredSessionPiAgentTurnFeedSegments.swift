import Foundation
import NexusDomain

// MARK: - Composite feed segments (ADR 0037, Pi v1)

public struct StructuredSessionFeedUserMessageSegment: Equatable, Identifiable, Sendable {
    public let activityItemID: UUID
    public let text: String

    public var id: UUID { activityItemID }

    public init(activityItemID: UUID, text: String) {
        self.activityItemID = activityItemID
        self.text = text
    }
}

public struct StructuredSessionFeedAgentTurnReasoningSegment: Equatable, Sendable {
    public let markdownBody: String

    public init(markdownBody: String) {
        self.markdownBody = markdownBody
    }
}

public struct StructuredSessionFeedAgentTurnToolSegment: Equatable, Identifiable, Sendable {
    public let activityItemID: UUID
    public let callPreview: String
    public let detailText: String?
    public let subagentOutputs: [String]

    public var id: UUID { activityItemID }

    public init(
        activityItemID: UUID,
        callPreview: String,
        detailText: String? = nil,
        subagentOutputs: [String] = []
    ) {
        self.activityItemID = activityItemID
        self.callPreview = callPreview
        self.detailText = detailText
        self.subagentOutputs = subagentOutputs
    }
}

public struct StructuredSessionFeedAgentTurnFinalAnswerSegment: Equatable, Sendable {
    public let text: String
    public let isStreaming: Bool

    public init(text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }
}

public struct StructuredSessionFeedAgentTurnSegment: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let isOpen: Bool
    public let reasoning: StructuredSessionFeedAgentTurnReasoningSegment?
    public let tools: [StructuredSessionFeedAgentTurnToolSegment]
    public let finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?

    public init(
        id: UUID,
        isOpen: Bool,
        reasoning: StructuredSessionFeedAgentTurnReasoningSegment? = nil,
        tools: [StructuredSessionFeedAgentTurnToolSegment] = [],
        finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment? = nil
    ) {
        self.id = id
        self.isOpen = isOpen
        self.reasoning = reasoning
        self.tools = tools
        self.finalAnswer = finalAnswer
    }
}

public enum StructuredSessionFeedSegment: Equatable, Identifiable, Sendable {
    case userMessage(StructuredSessionFeedUserMessageSegment)
    case agentTurn(StructuredSessionFeedAgentTurnSegment)
    case standalone(SessionActivityItem)

    public var id: UUID {
        switch self {
        case .userMessage(let segment):
            segment.id
        case .agentTurn(let segment):
            segment.id
        case .standalone(let item):
            item.id
        }
    }
}

/// Pi v1 composite feed projection. Returns `nil` for non-Pi **Sessions** so clients keep flat row iteration.
public func structuredSessionPiFeedSegments(for screen: SessionScreen) -> [StructuredSessionFeedSegment]? {
    guard screen.session.providerID == .pi else {
        return nil
    }

    return structuredSessionPiFeedSegments(
        activityItems: screen.activityItems,
        isAgentTurnInProgress: screen.isAgentTurnInProgress,
        liveAssistantDraftText: screen.providerFacts.liveAssistantDraftText
    )
}

func structuredSessionPiFeedSegments(
    activityItems: [SessionActivityItem],
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> [StructuredSessionFeedSegment] {
    var segments: [StructuredSessionFeedSegment] = []
    var index = 0

    while index < activityItems.count {
        let item = activityItems[index]

        if structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage(item),
           let userBody = structuredSessionPiUserMessageBody(from: item) {
            segments.append(.userMessage(StructuredSessionFeedUserMessageSegment(
                activityItemID: item.id,
                text: userBody
            )))
            index += 1

            let turnSlice = structuredSessionPiAgentTurnActivitySlice(
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

private struct StructuredSessionPiAgentTurnSlice {
    let nextIndex: Int
    let turn: StructuredSessionFeedAgentTurnSegment?
}

private func structuredSessionPiAgentTurnActivitySlice(
    activityItems: [SessionActivityItem],
    startIndex: Int,
    isAgentTurnInProgress: Bool,
    liveAssistantDraftText: String?
) -> StructuredSessionPiAgentTurnSlice {
    guard startIndex < activityItems.count else {
        return StructuredSessionPiAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    var reasoningParts: [String] = []
    var tools: [StructuredSessionFeedAgentTurnToolSegment] = []
    var openToolIndex: Int?
    var finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?
    var cursor = startIndex
    var consumedAny = false

    while cursor < activityItems.count {
        let item = activityItems[cursor]

        if structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage(item) {
            break
        }

        if structuredSessionPiFeedSegmentIsInTurnToolErrorRow(item) {
            structuredSessionPiAgentTurnAttachErrorText(item.text, to: &tools, openToolIndex: &openToolIndex)
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsOutsideStackRow(item) {
            break
        }

        if structuredSessionPiFeedSegmentIsThoughtsStatus(item) {
            if let detail = item.detailText?.trimmingCharacters(in: .whitespacesAndNewlines),
               detail.isEmpty == false {
                reasoningParts.append(detail)
            }
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

        if let subagentOutput = structuredSessionPiSubagentOutputBody(from: item.text),
           let toolIndex = openToolIndex {
            var tool = tools[toolIndex]
            tool = StructuredSessionFeedAgentTurnToolSegment(
                activityItemID: tool.activityItemID,
                callPreview: tool.callPreview,
                detailText: tool.detailText,
                subagentOutputs: tool.subagentOutputs + [subagentOutput]
            )
            tools[toolIndex] = tool
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(item) {
            if let body = structuredSessionPiPrimaryAssistantBody(from: item.text) {
                finalAnswer = StructuredSessionFeedAgentTurnFinalAnswerSegment(text: body, isStreaming: false)
            }
            consumedAny = true
            cursor += 1
            // Pi may emit interim `Pi:` lines before more thoughts/tools; keep absorbing until next user prompt or outside-stack row.
            continue
        }

        break
    }

    let isOpenTurn = isAgentTurnInProgress
    if isAgentTurnInProgress,
       finalAnswer == nil,
       let draft = liveAssistantDraftText?.trimmingCharacters(in: .whitespacesAndNewlines),
       draft.isEmpty == false {
        finalAnswer = StructuredSessionFeedAgentTurnFinalAnswerSegment(text: draft, isStreaming: true)
        consumedAny = true
    }

    guard consumedAny else {
        return StructuredSessionPiAgentTurnSlice(nextIndex: startIndex, turn: nil)
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

    return StructuredSessionPiAgentTurnSlice(nextIndex: cursor, turn: turn)
}

private func structuredSessionPiFeedSegmentIsInTurnToolErrorRow(_ item: SessionActivityItem) -> Bool {
    item.kind == .error
}

private func structuredSessionPiAgentTurnAttachErrorText(
    _ rawText: String,
    to tools: inout [StructuredSessionFeedAgentTurnToolSegment],
    openToolIndex: inout Int?
) {
    let errorText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard errorText.isEmpty == false else {
        return
    }

    guard let toolIndex = openToolIndex, tools.indices.contains(toolIndex) else {
        return
    }

    var tool = tools[toolIndex]
    let mergedDetail: String
    if let existing = tool.detailText?.trimmingCharacters(in: .whitespacesAndNewlines), existing.isEmpty == false {
        mergedDetail = existing + "\n" + errorText
    } else {
        mergedDetail = errorText
    }
    tool = StructuredSessionFeedAgentTurnToolSegment(
        activityItemID: tool.activityItemID,
        callPreview: tool.callPreview,
        detailText: mergedDetail,
        subagentOutputs: tool.subagentOutputs
    )
    tools[toolIndex] = tool
}

private func structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage(_ item: SessionActivityItem) -> Bool {
    if item.prompt != nil {
        return true
    }
    guard item.kind == .message else {
        return false
    }
    return structuredSessionPiUserMessageBody(from: item) != nil
}

private func structuredSessionPiUserMessageBody(from item: SessionActivityItem) -> String? {
    if let prompt = item.prompt {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    guard let split = structuredSessionPiConversationPrefixSplit(for: item.text),
          split.label.caseInsensitiveCompare("you") == .orderedSame else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private let structuredSessionPiThoughtsStatusLabel = "thoughts:"

private func structuredSessionPiFeedSegmentIsThoughtsStatus(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .status else {
        return false
    }
    return item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(structuredSessionPiThoughtsStatusLabel) == .orderedSame
}

private func structuredSessionPiFeedSegmentIsOutsideStackRow(_ item: SessionActivityItem) -> Bool {
    switch item.kind {
    case .status:
        return structuredSessionPiFeedSegmentIsThoughtsStatus(item) == false
    case .message:
        if structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage(item) {
            return false
        }
        if structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(item) {
            return false
        }
        return structuredSessionPiSubagentOutputBody(from: item.text) == nil
    case .progress, .completion, .error, .approvalRequest, .approvalDecision, .diff:
        return true
    case .command:
        return false
    }
}

private func structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .message else {
        return false
    }
    guard let split = structuredSessionPiConversationPrefixSplit(for: item.text) else {
        return false
    }
    return split.label.caseInsensitiveCompare("Pi") == .orderedSame
}

private func structuredSessionPiPrimaryAssistantBody(from text: String) -> String? {
    guard let split = structuredSessionPiConversationPrefixSplit(for: text) else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionPiConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
    guard let separatorRange = text.range(of: ": ") else {
        return nil
    }

    let label = String(text[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = String(text[separatorRange.upperBound...])
    guard label.isEmpty == false,
          body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
          label.count <= 24 else {
        return nil
    }
    return (label, body)
}

private func structuredSessionPiSubagentOutputBody(from text: String) -> String? {
    guard let split = structuredSessionPiConversationPrefixSplit(for: text) else {
        return nil
    }
    let label = split.label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard label.caseInsensitiveCompare("Pi") != .orderedSame,
          label.caseInsensitiveCompare("you") != .orderedSame else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}