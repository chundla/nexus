import Foundation

public struct StructuredSessionProviderTokenUsage: Codable, Equatable, Sendable {
    public let usedTokens: Int
    public let totalTokens: Int
    public let percent: Int

    public init(usedTokens: Int, totalTokens: Int, percent: Int) {
        self.usedTokens = max(0, usedTokens)
        self.totalTokens = max(1, totalTokens)
        self.percent = max(0, min(100, percent))
    }
}

public struct StructuredSessionProviderFacts: Codable, Equatable, Sendable {
    public let providerEventCount: Int
    public let lastProviderEventSequence: Int?
    public let lastProviderEventType: String?
    public let liveAssistantDraftText: String?
    public let tokenUsage: StructuredSessionProviderTokenUsage?
    public let modelIdentifier: String?

    public init(
        providerEventCount: Int = 0,
        lastProviderEventSequence: Int? = nil,
        lastProviderEventType: String? = nil,
        liveAssistantDraftText: String? = nil,
        tokenUsage: StructuredSessionProviderTokenUsage? = nil,
        modelIdentifier: String? = nil
    ) {
        self.providerEventCount = max(0, providerEventCount)
        self.lastProviderEventSequence = lastProviderEventSequence
        self.lastProviderEventType = lastProviderEventType
        self.liveAssistantDraftText = Self.normalizedText(liveAssistantDraftText)
        self.tokenUsage = tokenUsage
        self.modelIdentifier = Self.normalizedText(modelIdentifier)
    }

    public static let empty = StructuredSessionProviderFacts()

    public static func summarizing(providerEvents: [SessionProviderEvent]) -> StructuredSessionProviderFacts {
        providerEvents.enumerated().reduce(.empty) { facts, entry in
            facts.appending(entry.element, retainedProviderEventCount: entry.offset + 1)
        }
    }

    public func appending(
        _ event: SessionProviderEvent,
        retainedProviderEventCount: Int
    ) -> StructuredSessionProviderFacts {
        let payload = Self.jsonObject(from: event.rawPayload)
        return StructuredSessionProviderFacts(
            providerEventCount: retainedProviderEventCount,
            lastProviderEventSequence: event.sequence,
            lastProviderEventType: event.type,
            liveAssistantDraftText: Self.updatedLiveAssistantDraftText(
                currentDraft: liveAssistantDraftText,
                event: event,
                payload: payload
            ),
            tokenUsage: Self.tokenUsage(from: payload) ?? tokenUsage,
            modelIdentifier: Self.modelIdentifier(for: event.providerID, payload: payload) ?? modelIdentifier
        )
    }

    private static func updatedLiveAssistantDraftText(
        currentDraft: String?,
        event: SessionProviderEvent,
        payload: [String: Any]?
    ) -> String? {
        guard event.providerID == .pi else {
            return currentDraft
        }

        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentDraft = currentDraft ?? ""

        switch type {
        case "message_update":
            guard let payload,
                let assistantMessageEvent = payload["assistantMessageEvent"] as? [String: Any],
                trimmedString(in: assistantMessageEvent, keys: ["type"]) == "text_delta",
                let delta = assistantMessageEvent["delta"] as? String
            else {
                return Self.normalizedText(currentDraft)
            }
            return Self.normalizedText(currentDraft + delta)
        case "turn_end":
            return nil
        case "message_end":
            if let payload,
                let message = payload["message"] as? [String: Any],
                trimmedString(in: message, keys: ["role"]) == "assistant"
            {
                return nil
            }
            return Self.normalizedText(currentDraft)
        default:
            return Self.normalizedText(currentDraft)
        }
    }

    private static func modelIdentifier(
        for providerID: ProviderID,
        payload: [String: Any]?
    ) -> String? {
        guard let payload else {
            return nil
        }

        switch providerID {
        case .pi:
            guard let data = payload["data"] as? [String: Any],
                let model = data["model"] as? [String: Any],
                let provider = trimmedString(in: model, keys: ["provider"]),
                let modelID = trimmedString(in: model, keys: ["id"])
            else {
                return nil
            }
            return "\(provider)/\(modelID)"
        case .codex:
            if let result = payload["result"] as? [String: Any],
                let model = trimmedString(in: result, keys: ["model"])
            {
                return model
            }
            if let params = payload["params"] as? [String: Any],
                let model = trimmedString(in: params, keys: ["model"])
            {
                return model
            }
            return nil
        case .ibmBob, .claude:
            return nil
        }
    }

    private static func tokenUsage(from payload: [String: Any]?) -> StructuredSessionProviderTokenUsage? {
        guard let payload,
            let usage = resolvedTokenUsage(from: payload)
        else {
            return nil
        }
        return usage
    }

    private static func resolvedTokenUsage(from value: Any) -> StructuredSessionProviderTokenUsage? {
        switch value {
        case let object as [String: Any]:
            if let directUsage = directTokenUsage(from: object) {
                return directUsage
            }

            let priorityKeys = [
                "contextUsage", "tokenUsage", "usage", "data", "result", "params", "context", "thread", "turn", "item",
                "message",
            ]
            for key in priorityKeys {
                if let nestedValue = object[key],
                    let usage = resolvedTokenUsage(from: nestedValue)
                {
                    return usage
                }
            }

            for nestedValue in object.values {
                if let usage = resolvedTokenUsage(from: nestedValue) {
                    return usage
                }
            }
        case let array as [Any]:
            for nestedValue in array.reversed() {
                if let usage = resolvedTokenUsage(from: nestedValue) {
                    return usage
                }
            }
        default:
            break
        }

        return nil
    }

    private static func directTokenUsage(from object: [String: Any]) -> StructuredSessionProviderTokenUsage? {
        let totalTokens = intValue(
            in: object,
            keys: ["contextWindow", "context_window", "maxTokens", "max_tokens", "totalTokens", "total_tokens"])
        let explicitUsedTokens =
            intValue(in: object, keys: ["tokens", "usedTokens", "used_tokens", "tokenCount", "token_count"])
            ?? summedIntValue(
                in: object, keyPairs: [("inputTokens", "outputTokens"), ("input_tokens", "output_tokens")])
        let explicitPercent = intValue(in: object, keys: ["percent", "usagePercent", "usage_percent"])

        guard let totalTokens else {
            return nil
        }

        let usedTokens =
            explicitUsedTokens
            ?? explicitPercent.map { max(0, Int((Double(totalTokens) * Double($0)) / 100.0)) }
        guard let usedTokens else {
            return nil
        }

        let percent =
            explicitPercent
            ?? (totalTokens > 0 ? Int((Double(usedTokens) / Double(totalTokens)) * 100.0) : 0)
        return StructuredSessionProviderTokenUsage(
            usedTokens: usedTokens,
            totalTokens: totalTokens,
            percent: percent
        )
    }

    private static func intValue(in object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int {
                return value
            }
            if let value = object[key] as? Double {
                return Int(value)
            }
            if let value = object[key] as? String,
                let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                return intValue
            }
        }
        return nil
    }

    private static func summedIntValue(
        in object: [String: Any],
        keyPairs: [(String, String)]
    ) -> Int? {
        for (lhsKey, rhsKey) in keyPairs {
            guard let lhs = intValue(in: object, keys: [lhsKey]),
                let rhs = intValue(in: object, keys: [rhsKey])
            else {
                continue
            }
            return lhs + rhs
        }
        return nil
    }

    private static func trimmedString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return normalizedText(value)
            }
        }
        return nil
    }

    private static func jsonObject(from rawPayload: String) -> [String: Any]? {
        guard let data = rawPayload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }
}
