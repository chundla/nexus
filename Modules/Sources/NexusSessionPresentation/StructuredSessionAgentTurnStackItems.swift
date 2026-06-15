import Foundation
import NexusDomain

/// One chronological row inside an **Agent Turn** stack (reasoning block or tool), ADR 0037.
public enum StructuredSessionFeedAgentTurnStackItem: Equatable, Identifiable, Sendable {
    case reasoning(StructuredSessionFeedAgentTurnReasoningSegment)
    case tool(StructuredSessionFeedAgentTurnToolSegment)

    public var id: UUID {
        switch self {
        case .reasoning(let segment):
            segment.id
        case .tool(let segment):
            segment.id
        }
    }
}

func structuredSessionAgentTurnSyncStackTool(
    _ tool: StructuredSessionFeedAgentTurnToolSegment,
    in stackItems: inout [StructuredSessionFeedAgentTurnStackItem]
) {
    guard
        let index = stackItems.firstIndex(where: { item in
            if case .tool(let existing) = item {
                return existing.id == tool.id
            }
            return false
        })
    else {
        return
    }
    stackItems[index] = .tool(tool)
}
