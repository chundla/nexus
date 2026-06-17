import Combine
import Foundation

/// Per-turn sticky expansion for reasoning/tool rows in the attached **Session** (not persisted).
@available(macOS 12.0, iOS 15.0, *)
public final class StructuredSessionAgentTurnDisclosureState: ObservableObject, @unchecked Sendable {
    private struct TurnOverrides: Equatable {
        var tools: Bool?
        var activity: Bool?
        var reasoningRows: [UUID: Bool] = [:]
        var toolRows: [UUID: Bool] = [:]
    }

    private var overridesByTurnID: [UUID: TurnOverrides] = [:]

    public init() {}

    public func reset() {
        objectWillChange.send()
        overridesByTurnID = [:]
    }

    public func toolsIsExpanded(for turn: StructuredSessionFeedAgentTurnSegment) -> Bool {
        if let override = overridesByTurnID[turn.id]?.tools {
            return override
        }
        return structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn).tools
    }

    public func activityIsExpanded(for turn: StructuredSessionFeedAgentTurnSegment) -> Bool {
        if let override = overridesByTurnID[turn.id]?.activity {
            return override
        }
        return structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn).activity
    }

    public func reasoningRowIsExpanded(turnID: UUID, reasoningID: UUID, defaultExpanded: Bool) -> Bool {
        if let override = overridesByTurnID[turnID]?.reasoningRows[reasoningID] {
            return override
        }
        return defaultExpanded
    }

    public func toolRowIsExpanded(turnID: UUID, toolID: UUID, defaultExpanded: Bool) -> Bool {
        if let override = overridesByTurnID[turnID]?.toolRows[toolID] {
            return override
        }
        return defaultExpanded
    }

    public func setReasoningRowExpanded(turnID: UUID, reasoningID: UUID, isExpanded: Bool) {
        objectWillChange.send()
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.reasoningRows[reasoningID] = isExpanded
        overridesByTurnID[turnID] = entry
    }

    public func setToolsExpanded(turnID: UUID, isExpanded: Bool) {
        objectWillChange.send()
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.tools = isExpanded
        overridesByTurnID[turnID] = entry
    }

    public func setActivityExpanded(turnID: UUID, isExpanded: Bool) {
        objectWillChange.send()
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.activity = isExpanded
        overridesByTurnID[turnID] = entry
    }

    public func setToolRowExpanded(turnID: UUID, toolID: UUID, isExpanded: Bool) {
        objectWillChange.send()
        var entry = overridesByTurnID[turnID] ?? TurnOverrides()
        entry.toolRows[toolID] = isExpanded
        overridesByTurnID[turnID] = entry
    }
}
