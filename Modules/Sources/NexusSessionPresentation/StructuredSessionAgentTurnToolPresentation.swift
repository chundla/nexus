import Foundation

/// Scannable one-line label for an individual tool bubble (Pi / Codex / IBM Bob).
public func structuredSessionAgentTurnToolCollapsedCommandLine(callPreview: String) -> String {
    let trimmed = callPreview.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
        return "Tool"
    }

    if trimmed.hasPrefix("/") {
        let withoutSlash = String(trimmed.dropFirst())
        if let space = withoutSlash.firstIndex(of: " ") {
            let verb = String(withoutSlash[..<space])
            let remainder = String(withoutSlash[withoutSlash.index(after: space)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.isEmpty == false {
                return "\(structuredSessionAgentTurnToolDisplayVerb(verb)) \(remainder)"
            }
        }
        return trimmed
    }

    if let space = trimmed.firstIndex(of: " "),
        trimmed[..<space].contains(":") == false
    {
        let verb = String(trimmed[..<space])
        let remainder = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.isEmpty == false {
            return "\(structuredSessionAgentTurnToolDisplayVerb(verb)) \(remainder)"
        }
    }

    if let colon = trimmed.firstIndex(of: ":") {
        let head = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty == false, tail.isEmpty == false {
            return "\(structuredSessionAgentTurnToolDisplayVerb(head)) \(tail)"
        }
    }

    return trimmed
}

private func structuredSessionAgentTurnToolDisplayVerb(_ raw: String) -> String {
    let lower = raw.lowercased()
    switch lower {
    case "read", "cat":
        return "Read"
    case "write":
        return "Write"
    case "edit", "strreplace", "apply_patch":
        return "Edit"
    case "bash", "shell":
        return "Bash"
    case "grep", "rg", "search":
        return "Search"
    case "find", "glob", "ls", "list":
        return "List"
    case "subagent":
        return "Subagent"
    default:
        if raw.first?.isUppercase == true {
            return raw
        }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

/// Collapsed one-line preview for a single reasoning block (last paragraph within that block).
public func structuredSessionAgentTurnReasoningCollapsedPreview(markdownBody: String) -> String {
    let trimmed = markdownBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
        return ""
    }
    let paragraphs =
        trimmed
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
    return paragraphs.last ?? trimmed
}

public func structuredSessionAgentTurnToolExpandedCopyPayload(
    callPreview: String,
    detailText: String?,
    subagentOutputs: [String]
) -> String {
    var sections: [String] = [callPreview.trimmingCharacters(in: .whitespacesAndNewlines)]
    if let detail = detailText?.trimmingCharacters(in: .whitespacesAndNewlines), detail.isEmpty == false {
        sections.append(detail)
    }
    for output in subagentOutputs {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty == false {
            sections.append(line)
        }
    }
    return sections.joined(separator: "\n\n")
}

public func structuredSessionAgentTurnToolRawJSONCandidate(
    callPreview: String,
    detailText: String?
) -> String? {
    let detail = detailText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if detail.hasPrefix("{") || detail.hasPrefix("[") {
        return detail
    }
    let preview = callPreview.trimmingCharacters(in: .whitespacesAndNewlines)
    if preview.hasPrefix("{") || preview.hasPrefix("[") {
        return preview
    }
    return nil
}
