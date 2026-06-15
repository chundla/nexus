import Foundation

/// Per-turn sticky DisclosureGroup expansion for the attached **Session** (CONTEXT.md; not persisted).
@available(macOS 12.0, iOS 15.0, *)
public final class StructuredSessionAgentTurnDisclosureState: ObservableObject, @unchecked Sendable {
    private struct TurnOverrides: Equatable {
        var reasoning: Bool?
        var tools: Bool?
        var toolRows: [UUID: Bool] = [:]
    }

    private var overridesByTurnID: [UUID: TurnOverrides] = [:]

    public init() {}

    public func reset() {
        overridesByTurnID = [:]
    }

    public func reasoningIsExpanded(for turn: StructuredSessionFeedAgentTurnSegment) -> Bool {
        if let override = overridesByTurnID[turn.id]?.reasoning {
            return override
        }
        return structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn).reasoning
    }

    public func toolsIsExpanded(for turn: StructuredSessionFeedAgentTurnSegment) -> Bool {
        if let override = overridesByTurnID[turn.id]?.tools {
            return override
        }
        return structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn).tools
    }

    public func toolRowIsExpanded(turnID: UUID, toolID: UUID, defaultExpanded: Bool) -> Bool {
        if let override = overridesByTurnID[turnID]?.toolRows[toolID] {
            return override
        }
        return defaultExpanded
    }

    public func setReasoningExpanded(turnID: UUID, isExpanded: Bool) {
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.reasoning = isExpanded
        overridesByTurnID[turnID] = entry
    }

    public func setToolsExpanded(turnID: UUID, isExpanded: Bool) {
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.tools = isExpanded
        overridesByTurnID[turnID] = entry
    }

    public func setToolRowExpanded(turnID: UUID, toolID: UUID, isExpanded: Bool) {
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.toolRows[toolID] = isExpanded
        overridesByTurnID[turnID] = entry
    }
}