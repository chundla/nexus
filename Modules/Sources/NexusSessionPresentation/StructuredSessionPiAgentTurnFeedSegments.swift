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

public struct StructuredSessionFeedAgentTurnReasoningSegment: Equatable, Identifiable, Sendable {
    public let activityItemID: UUID
    public let markdownBody: String

    public var id: UUID { activityItemID }

    public init(activityItemID: UUID, markdownBody: String) {
        self.activityItemID = activityItemID
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

public enum StructuredSessionFeedAgentTurnNotice: Equatable, Sendable {
    case progress(String)
    case error(String)
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
    /// Reasoning blocks and tools in **Session** activity order.
    public let stackItems: [StructuredSessionFeedAgentTurnStackItem]
    /// Turn-level progress / errors with no open tool (e.g. `message_end` abort) — shown inside the agent-turn card.
    public let turnNotices: [StructuredSessionFeedAgentTurnNotice]
    public let finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?

    public init(
        id: UUID,
        isOpen: Bool,
        stackItems: [StructuredSessionFeedAgentTurnStackItem] = [],
        turnNotices: [StructuredSessionFeedAgentTurnNotice] = [],
        finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment? = nil
    ) {
        self.id = id
        self.isOpen = isOpen
        self.stackItems = stackItems
        self.turnNotices = turnNotices
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
        isAgentTurnInProgress: structuredSessionPiFeedSegmentTurnInProgress(for: screen),
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
            let userBody = structuredSessionPiUserMessageBody(from: item)
        {
            segments.append(
                .userMessage(
                    StructuredSessionFeedUserMessageSegment(
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

    var stackItems: [StructuredSessionFeedAgentTurnStackItem] = []
    var tools: [StructuredSessionFeedAgentTurnToolSegment] = []
    var openToolIndex: Int?
    var finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment?
    var turnNotices: [StructuredSessionFeedAgentTurnNotice] = []
    var cursor = startIndex
    var consumedAny = false

    while cursor < activityItems.count {
        let item = activityItems[cursor]

        if structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage(item) {
            break
        }

        if structuredSessionPiFeedSegmentIsInTurnProgressRow(item) {
            structuredSessionPiAgentTurnAppendProgressNotice(item.text, to: &turnNotices)
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsInTurnToolErrorRow(item) {
            structuredSessionPiAgentTurnAbsorbErrorText(
                item.text,
                to: &tools,
                openToolIndex: &openToolIndex,
                stackItems: &stackItems,
                turnNotices: &turnNotices
            )
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsInTurnSessionStatusRow(item) {
            structuredSessionPiAgentTurnAppendSessionStatusNotice(from: item, to: &turnNotices)
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsInTurnCompletionOrDiffRow(item) {
            structuredSessionPiAgentTurnAppendProgressNotice(item.text, to: &turnNotices)
            consumedAny = true
            cursor += 1
            continue
        }

        if item.kind == .message,
            let lastAssistant = structuredSessionPiLastAssistantMessageBody(from: item.text)
        {
            structuredSessionPiAgentTurnAppendProgressNotice(
                "Last assistant message: \(lastAssistant)",
                to: &turnNotices
            )
            consumedAny = true
            cursor += 1
            continue
        }

        if item.kind == .message,
            let bashOutput = structuredSessionPiBashOutputBody(from: item.text)
        {
            structuredSessionPiAgentTurnAttachBashOutput(
                bashOutput,
                to: &tools,
                openToolIndex: &openToolIndex,
                stackItems: &stackItems,
                turnNotices: &turnNotices
            )
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsOutsideStackRow(item) {
            break
        }

        if structuredSessionPiFeedSegmentIsThoughtsStatus(item) {
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

        if let subagentOutput = structuredSessionPiSubagentOutputBody(from: item.text),
            let toolIndex = openToolIndex
        {
            var tool = tools[toolIndex]
            tool = StructuredSessionFeedAgentTurnToolSegment(
                activityItemID: tool.activityItemID,
                callPreview: tool.callPreview,
                detailText: tool.detailText,
                subagentOutputs: tool.subagentOutputs + [subagentOutput]
            )
            tools[toolIndex] = tool
            structuredSessionAgentTurnSyncStackTool(tool, in: &stackItems)
            consumedAny = true
            cursor += 1
            continue
        }

        if structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(item) {
            if isAgentTurnInProgress {
                // Interim assistant lines render as standalone bubbles after the open turn; do not stick scroll to them.
                break
            }
            if let body = structuredSessionPiPrimaryAssistantBody(from: item.text) {
                finalAnswer = StructuredSessionFeedAgentTurnFinalAnswerSegment(text: body, isStreaming: false)
            }
            consumedAny = true
            cursor += 1
            continue
        }

        break
    }

    let isOpenTurn = isAgentTurnInProgress

    guard consumedAny else {
        return StructuredSessionPiAgentTurnSlice(nextIndex: startIndex, turn: nil)
    }

    let turnID = activityItems[startIndex].id
    let turn = StructuredSessionFeedAgentTurnSegment(
        id: turnID,
        isOpen: isOpenTurn,
        stackItems: stackItems,
        turnNotices: turnNotices,
        finalAnswer: finalAnswer
    )

    return StructuredSessionPiAgentTurnSlice(nextIndex: cursor, turn: turn)
}

private func structuredSessionPiFeedSegmentIsInTurnProgressRow(_ item: SessionActivityItem) -> Bool {
    item.kind == .progress
}

private func structuredSessionPiFeedSegmentIsInTurnSessionStatusRow(_ item: SessionActivityItem) -> Bool {
    guard item.kind == .status else {
        return false
    }
    return structuredSessionPiFeedSegmentIsThoughtsStatus(item) == false
}

private func structuredSessionPiFeedSegmentIsInTurnCompletionOrDiffRow(_ item: SessionActivityItem) -> Bool {
    item.kind == .completion || item.kind == .diff
}

private func structuredSessionPiLastAssistantMessageBody(from text: String) -> String? {
    guard let split = structuredSessionPiConversationPrefixSplit(for: text) else {
        return nil
    }
    guard split.label.caseInsensitiveCompare("Last assistant message") == .orderedSame else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionPiAgentTurnAppendSessionStatusNotice(
    from item: SessionActivityItem,
    to turnNotices: inout [StructuredSessionFeedAgentTurnNotice]
) {
    let headline = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = item.detailText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let combined: String
    if headline.isEmpty {
        combined = detail
    } else if detail.isEmpty {
        combined = headline
    } else {
        combined = headline + "\n" + detail
    }
    structuredSessionPiAgentTurnAppendProgressNotice(combined, to: &turnNotices)
}

private func structuredSessionPiBashOutputBody(from text: String) -> String? {
    guard let split = structuredSessionPiConversationPrefixSplit(for: text) else {
        return nil
    }
    guard split.label.caseInsensitiveCompare("bash") == .orderedSame else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private func structuredSessionPiAgentTurnAttachBashOutput(
    _ output: String,
    to tools: inout [StructuredSessionFeedAgentTurnToolSegment],
    openToolIndex: inout Int?,
    stackItems: inout [StructuredSessionFeedAgentTurnStackItem],
    turnNotices: inout [StructuredSessionFeedAgentTurnNotice]
) {
    guard let toolIndex = openToolIndex, tools.indices.contains(toolIndex) else {
        structuredSessionPiAgentTurnAppendProgressNotice(output, to: &turnNotices)
        return
    }

    structuredSessionPiAgentTurnMergeDetailLine(output, into: &tools[toolIndex])
    structuredSessionAgentTurnSyncStackTool(tools[toolIndex], in: &stackItems)
}

private func structuredSessionPiAgentTurnAppendProgressNotice(
    _ rawText: String,
    to turnNotices: inout [StructuredSessionFeedAgentTurnNotice]
) {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.isEmpty == false else {
        return
    }
    turnNotices.append(.progress(text))
}

private func structuredSessionPiFeedSegmentIsInTurnToolErrorRow(_ item: SessionActivityItem) -> Bool {
    item.kind == .error
}

private func structuredSessionPiAgentTurnAbsorbErrorText(
    _ rawText: String,
    to tools: inout [StructuredSessionFeedAgentTurnToolSegment],
    openToolIndex: inout Int?,
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

    structuredSessionPiAgentTurnMergeDetailLine(errorText, into: &tools[toolIndex])
    structuredSessionAgentTurnSyncStackTool(tools[toolIndex], in: &stackItems)
}

/// Appends tool output / errors in arrival order (newline-separated).
private func structuredSessionPiAgentTurnMergeDetailLine(
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

func structuredSessionPiFeedSegmentIsPromptAnchoredUserMessage(_ item: SessionActivityItem) -> Bool {
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
        split.label.caseInsensitiveCompare("you") == .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}

private let structuredSessionPiThoughtsStatusLabel = "thoughts:"

func structuredSessionPiFeedSegmentIsThoughtsStatus(_ item: SessionActivityItem) -> Bool {
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
        if structuredSessionPiBashOutputBody(from: item.text) != nil {
            return false
        }
        if structuredSessionPiLastAssistantMessageBody(from: item.text) != nil {
            return false
        }
        return structuredSessionPiSubagentOutputBody(from: item.text) == nil
    case .progress, .completion, .error, .approvalRequest, .approvalDecision, .diff:
        return true
    case .command:
        return false
    }
}

func structuredSessionPiFeedSegmentIsPrimaryPiAssistantMessage(_ item: SessionActivityItem) -> Bool {
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
        label.count <= 24
    else {
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
        label.caseInsensitiveCompare("you") != .orderedSame,
        label.caseInsensitiveCompare("bash") != .orderedSame
    else {
        return nil
    }
    let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}
