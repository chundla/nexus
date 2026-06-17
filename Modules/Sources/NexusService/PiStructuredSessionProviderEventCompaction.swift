#if os(macOS)
    import Foundation
    import NexusDomain

    enum PiStructuredSessionProviderEventCompaction {
        static func compacted(_ event: SessionProviderEvent) -> SessionProviderEvent {
            guard event.providerID == .pi,
                let data = event.rawPayload.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return event
            }

            return compacted(
                sequence: event.sequence,
                type: event.type,
                family: event.family,
                command: event.command,
                rawPayload: event.rawPayload,
                object: object
            )
        }

        static func compacted(events: [SessionProviderEvent], providerID: ProviderID) -> [SessionProviderEvent] {
            guard providerID == .pi else {
                return events
            }
            return events.map(compacted)
        }

        static func compacted(
            sequence: Int,
            type: String,
            family: SessionProviderEvent.Family,
            command: String?,
            rawPayload: String,
            object: [String: Any]
        ) -> SessionProviderEvent {
            let compactedRawPayload = compactedRawPayload(type: type, command: command, object: object)
            let retainedRawPayload: String
            if let compactedRawPayload,
                compactedRawPayload.count < rawPayload.count
            {
                retainedRawPayload = compactedRawPayload
            } else {
                retainedRawPayload = rawPayload
            }

            return SessionProviderEvent(
                sequence: sequence,
                providerID: .pi,
                type: type,
                family: family,
                command: command,
                rawPayload: retainedRawPayload
            )
        }

        private static func compactedRawPayload(type: String, command: String?, object: [String: Any]) -> String? {
            switch normalized(type) {
            case "agent_end":
                return jsonString(["type": "agent_end"])
            case "message_update":
                return compactedMessageUpdate(object)
            case "message_end":
                return compactedMessageEnd(object)
            case "tool_execution_start":
                return compactedToolExecutionStart(object)
            case "tool_execution_update":
                return compactedToolExecutionUpdate(object)
            case "tool_execution_end":
                return compactedToolExecutionEnd(object)
            case "turn_end":
                return jsonString(["type": "turn_end"])
            case "response":
                return compactedResponse(command: command, object: object)
            default:
                return nil
            }
        }

        private static func compactedMessageUpdate(_ object: [String: Any]) -> String? {
            var payload: [String: Any] = ["type": "message_update"]
            guard let assistantMessageEvent = object["assistantMessageEvent"] as? [String: Any] else {
                return jsonString(payload)
            }

            var compactAssistantMessageEvent: [String: Any] = [:]
            if let assistantEventType = trimmedString(in: assistantMessageEvent, keys: ["type"]) {
                compactAssistantMessageEvent["type"] = assistantEventType
            }
            if let delta = assistantMessageEvent["delta"] as? String {
                compactAssistantMessageEvent["delta"] = delta
            }
            if compactAssistantMessageEvent.isEmpty == false {
                payload["assistantMessageEvent"] = compactAssistantMessageEvent
            }

            return jsonString(payload)
        }

        private static func compactedMessageEnd(_ object: [String: Any]) -> String? {
            var payload: [String: Any] = ["type": "message_end"]
            if let message = object["message"] as? [String: Any] {
                var compactMessage: [String: Any] = [:]
                if let role = trimmedString(in: message, keys: ["role"]) {
                    compactMessage["role"] = role
                }
                if let stopReason = trimmedString(in: message, keys: ["stopReason"]) {
                    compactMessage["stopReason"] = stopReason
                }
                if compactMessage.isEmpty == false {
                    payload["message"] = compactMessage
                }
            }
            return jsonString(payload)
        }

        private static func compactedToolExecutionStart(_ object: [String: Any]) -> String? {
            var payload: [String: Any] = ["type": "tool_execution_start"]
            if let toolCallID = trimmedString(in: object, keys: ["toolCallId"]) {
                payload["toolCallId"] = toolCallID
            }
            if let toolName = trimmedString(in: object, keys: ["toolName"]) {
                payload["toolName"] = toolName
            }
            if let args = object["args"] as? [String: Any] {
                var compactArgs: [String: Any] = [:]
                if let agent = trimmedString(in: args, keys: ["agent"]) {
                    compactArgs["agent"] = agent
                }
                if let task = trimmedString(in: args, keys: ["task"]) {
                    compactArgs["task"] = truncatedText(task, limit: 256)
                }
                if compactArgs.isEmpty == false {
                    payload["args"] = compactArgs
                }
            }
            return jsonString(payload)
        }

        private static func compactedToolExecutionUpdate(_ object: [String: Any]) -> String? {
            var payload: [String: Any] = ["type": "tool_execution_update"]
            if let toolCallID = trimmedString(in: object, keys: ["toolCallId"]) {
                payload["toolCallId"] = toolCallID
            }
            if let text = compactedToolExecutionText(from: object["partialResult"]) {
                payload["partialResult"] = ["text": text]
            }
            return jsonString(payload)
        }

        private static func compactedToolExecutionEnd(_ object: [String: Any]) -> String? {
            var payload: [String: Any] = ["type": "tool_execution_end"]
            if let toolCallID = trimmedString(in: object, keys: ["toolCallId"]) {
                payload["toolCallId"] = toolCallID
            }
            if let toolName = trimmedString(in: object, keys: ["toolName"]) {
                payload["toolName"] = toolName
            }
            if let isError = object["isError"] as? Bool {
                payload["isError"] = isError
            }
            if let text = compactedToolExecutionText(from: object["result"]) {
                payload["result"] = ["text": text]
            }
            return jsonString(payload)
        }

        private static func compactedToolExecutionText(from value: Any?) -> String? {
            let text = toolExecutionResultText(from: value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else {
                return nil
            }
            return truncatedText(text, limit: 1_024)
        }

        private static func compactedResponse(command: String?, object: [String: Any]) -> String? {
            switch normalized(command) {
            case "get_session_stats":
                var payload: [String: Any] = [
                    "type": "response",
                    "command": "get_session_stats",
                ]
                if let contextUsage = compactContextUsage(from: object) {
                    payload["data"] = ["contextUsage": contextUsage]
                }
                return jsonString(payload)
            case "get_state":
                var payload: [String: Any] = [
                    "type": "response",
                    "command": "get_state",
                ]
                var data: [String: Any] = [:]
                if let sourceData = object["data"] as? [String: Any] {
                    if let sessionID = trimmedString(in: sourceData, keys: ["sessionId"]) {
                        data["sessionId"] = sessionID
                    }
                    if let model = compactModel(from: sourceData) {
                        data["model"] = model
                    }
                }
                if data.isEmpty == false {
                    payload["data"] = data
                }
                return jsonString(payload)
            default:
                return nil
            }
        }

        private static func compactContextUsage(from object: [String: Any]) -> [String: Any]? {
            guard let data = object["data"] as? [String: Any],
                let contextUsage = data["contextUsage"] as? [String: Any]
            else {
                return nil
            }

            var compactContextUsage: [String: Any] = [:]
            if let tokens = intValue(in: contextUsage, keys: ["tokens"]) {
                compactContextUsage["tokens"] = tokens
            }
            if let contextWindow = intValue(in: contextUsage, keys: ["contextWindow"]) {
                compactContextUsage["contextWindow"] = contextWindow
            }
            if let percent = intValue(in: contextUsage, keys: ["percent"]) {
                compactContextUsage["percent"] = percent
            }
            return compactContextUsage.isEmpty ? nil : compactContextUsage
        }

        private static func compactModel(from sourceData: [String: Any]) -> [String: Any]? {
            guard let model = sourceData["model"] as? [String: Any] else {
                return nil
            }

            var compactModel: [String: Any] = [:]
            if let provider = trimmedString(in: model, keys: ["provider"]) {
                compactModel["provider"] = provider
            }
            if let id = trimmedString(in: model, keys: ["id"]) {
                compactModel["id"] = id
            }
            if let name = trimmedString(in: model, keys: ["name"]) {
                compactModel["name"] = name
            }
            return compactModel.isEmpty ? nil : compactModel
        }

        private static func toolExecutionResultText(from value: Any?) -> String {
            PiToolExecutionResultText.extract(from: value)
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

        private static func trimmedString(in object: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty == false {
                        return trimmed
                    }
                }
            }
            return nil
        }

        private static func truncatedText(_ text: String, limit: Int) -> String {
            guard text.count > limit else {
                return text
            }
            return String(text.prefix(max(0, limit - 1))) + "…"
        }

        private static func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        private static func jsonString(_ object: [String: Any]) -> String? {
            guard JSONSerialization.isValidJSONObject(object),
                let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                let json = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return json
        }
    }
#endif
