import Foundation

extension StructuredSessionFeedAgentTurnSegment {
    public var reasoningStackItems: [StructuredSessionFeedAgentTurnReasoningSegment] {
        stackItems.compactMap { item in
            if case .reasoning(let segment) = item {
                return segment
            }
            return nil
        }
    }

    public var toolStackItems: [StructuredSessionFeedAgentTurnToolSegment] {
        stackItems.compactMap { item in
            if case .tool(let segment) = item {
                return segment
            }
            return nil
        }
    }
}
