import Foundation

/// Extracts user-visible tool output from Pi RPC `partialResult` / `result` payloads (see `docs/rpc.md`).
enum PiToolExecutionResultText {
    static func extract(from value: Any?) -> String {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let object as [String: Any]:
            if let text = trimmedString(in: object, keys: ["text", "delta", "message", "output", "summary"]) {
                return text
            }

            if let details = object["details"] as? [String: Any] {
                let fromDetails = extract(fromDetails: details)
                if fromDetails.isEmpty == false {
                    return fromDetails
                }
            }

            for key in ["content", "result", "partialResult"] {
                let text = extract(from: object[key])
                if text.isEmpty == false {
                    return text
                }
            }

            return ""
        case let array as [Any]:
            return
                array
                .map { extract(from: $0) }
                .filter { $0.isEmpty == false }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return ""
        }
    }

    private static func extract(fromDetails details: [String: Any]) -> String {
        if let output = trimmedString(in: details, keys: ["output"]) {
            return output
        }
        if let diff = trimmedString(in: details, keys: ["diff"]) {
            return diff
        }
        if let messages = details["messages"] as? [Any] {
            let text = extract(from: messages)
            if text.isEmpty == false {
                return text
            }
        }
        return ""
    }

    private static func trimmedString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let raw = object[key] as? String else {
                continue
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return nil
    }
}