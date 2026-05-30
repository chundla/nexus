import Foundation
import NexusDomain

public enum StructuredSessionActivityEmphasis: Equatable {
    case neutral
    case accent
    case critical
    case success
}

public struct StructuredSessionActivityRow: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let systemImage: String
    public let text: String
    public let emphasis: StructuredSessionActivityEmphasis

    public init(id: UUID, title: String, systemImage: String, text: String, emphasis: StructuredSessionActivityEmphasis) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.text = text
        self.emphasis = emphasis
    }
}

public struct StructuredSessionPresentationCopy: Equatable {
    public let emptyStateTitle: String
    public let emptyStateDescription: String
    public let composerPlaceholder: String

    public init(emptyStateTitle: String, emptyStateDescription: String, composerPlaceholder: String) {
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateDescription = emptyStateDescription
        self.composerPlaceholder = composerPlaceholder
    }
}

public struct StructuredSessionThinkingIndicator: Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct StructuredSessionFeedPresentation: Equatable {
    public let copy: StructuredSessionPresentationCopy
    public let activityRows: [StructuredSessionActivityRow]
    public let pendingApprovalRequests: [SessionApprovalRequest]
    public let thinkingIndicator: StructuredSessionThinkingIndicator?

    public init(
        copy: StructuredSessionPresentationCopy,
        activityRows: [StructuredSessionActivityRow],
        pendingApprovalRequests: [SessionApprovalRequest],
        thinkingIndicator: StructuredSessionThinkingIndicator?
    ) {
        self.copy = copy
        self.activityRows = activityRows
        self.pendingApprovalRequests = pendingApprovalRequests
        self.thinkingIndicator = thinkingIndicator
    }
}

public struct StructuredSessionComposerPresentation: Equatable {
    public let placeholder: String
    public let isEnabled: Bool
    public let disabledReason: String?

    public init(placeholder: String, isEnabled: Bool, disabledReason: String?) {
        self.placeholder = placeholder
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

public struct StructuredSessionComposerSendAffordance: Equatable {
    public let isVisible: Bool
    public let isEnabled: Bool

    public init(isVisible: Bool, isEnabled: Bool) {
        self.isVisible = isVisible
        self.isEnabled = isEnabled
    }
}

public struct StructuredSessionApprovalRequestPresentation: Equatable {
    public let actionsAreEnabled: Bool
    public let disabledReason: String?

    public init(actionsAreEnabled: Bool, disabledReason: String?) {
        self.actionsAreEnabled = actionsAreEnabled
        self.disabledReason = disabledReason
    }
}

public enum StructuredSessionConversationRole: Equatable {
    case user
    case assistant(label: String)
    case command
    case error
    case system
}

public struct StructuredSessionConversationPresentation: Equatable {
    public let role: StructuredSessionConversationRole
    public let text: String

    public init(role: StructuredSessionConversationRole, text: String) {
        self.role = role
        self.text = text
    }
}

public struct StructuredSessionSlashCommand: Identifiable, Equatable {
    public let matchText: String
    public let displayText: String
    public let insertionText: String
    public let summary: String
    public let acceptsArguments: Bool
    public let suggestionQueryPrefix: String?

    public var id: String { displayText }

    public init(
        matchText: String,
        displayText: String,
        insertionText: String,
        summary: String,
        acceptsArguments: Bool = false,
        suggestionQueryPrefix: String? = nil
    ) {
        self.matchText = matchText
        self.displayText = displayText
        self.insertionText = insertionText
        self.summary = summary
        self.acceptsArguments = acceptsArguments
        self.suggestionQueryPrefix = suggestionQueryPrefix
    }
}

public struct StructuredSessionSlashCommandMenuPresentation: Equatable {
    public let isVisible: Bool
    public let commands: [StructuredSessionSlashCommand]

    public init(isVisible: Bool, commands: [StructuredSessionSlashCommand]) {
        self.isVisible = isVisible
        self.commands = commands
    }

    public func applying(_ command: StructuredSessionSlashCommand, to draft: String) -> String {
        applyStructuredSessionSlashCommand(command, to: draft)
    }
}

public struct StructuredSessionPresentation: Equatable {
    public let feed: StructuredSessionFeedPresentation
    public let composer: StructuredSessionComposerPresentation
    public let sendAffordance: StructuredSessionComposerSendAffordance
    public let approvalRequest: StructuredSessionApprovalRequestPresentation
    public let slashCommandMenu: StructuredSessionSlashCommandMenuPresentation

    public init(
        screen: SessionScreen,
        hasWriterAuthority: Bool,
        draft: String,
        isPerformingAction: Bool
    ) {
        let composer = structuredSessionComposerPresentation(for: screen, hasWriterAuthority: hasWriterAuthority)
        self.feed = structuredSessionFeedPresentation(for: screen)
        self.composer = composer
        self.sendAffordance = structuredSessionComposerSendAffordance(
            for: draft,
            composer: composer,
            isPerformingAction: isPerformingAction
        )
        self.approvalRequest = structuredSessionApprovalRequestPresentation(hasWriterAuthority: hasWriterAuthority)
        self.slashCommandMenu = structuredSessionSlashCommandMenuPresentation(for: draft, screen: screen)
    }
}

public func structuredSessionActivityRows(for screen: SessionScreen) -> [StructuredSessionActivityRow] {
    screen.activityItems.map { item in
        StructuredSessionActivityRow(
            id: item.id,
            title: structuredSessionActivityTitle(for: item.kind),
            systemImage: structuredSessionActivitySystemImage(for: item.kind),
            text: item.text,
            emphasis: structuredSessionActivityEmphasis(for: item.kind)
        )
    }
}

public func structuredSessionFeedPresentation(for screen: SessionScreen) -> StructuredSessionFeedPresentation {
    let pendingApprovalRequests = screen.approvalRequests.filter { $0.state == .pending }
    return StructuredSessionFeedPresentation(
        copy: structuredSessionPresentationCopy(for: screen),
        activityRows: structuredSessionActivityRows(for: screen),
        pendingApprovalRequests: pendingApprovalRequests,
        thinkingIndicator: structuredSessionThinkingIndicator(
            for: screen,
            hasPendingApprovalRequests: pendingApprovalRequests.isEmpty == false
        )
    )
}

public func structuredSessionPresentationCopy(for screen: SessionScreen) -> StructuredSessionPresentationCopy {
    StructuredSessionPresentationCopy(
        emptyStateTitle: "No Session activity yet",
        emptyStateDescription: "Send a prompt to start the \(screen.session.providerID.displayName) Session.",
        composerPlaceholder: "Send a prompt to \(screen.session.providerID.displayName)"
    )
}

public func structuredSessionThinkingIndicator(
    for screen: SessionScreen,
    hasPendingApprovalRequests: Bool
) -> StructuredSessionThinkingIndicator? {
    guard screen.isAgentTurnInProgress, hasPendingApprovalRequests == false else {
        return nil
    }

    return StructuredSessionThinkingIndicator(text: "Thinking…")
}

public func structuredSessionComposerPresentation(
    for screen: SessionScreen,
    hasWriterAuthority: Bool
) -> StructuredSessionComposerPresentation {
    let copy = structuredSessionPresentationCopy(for: screen)
    return StructuredSessionComposerPresentation(
        placeholder: copy.composerPlaceholder,
        isEnabled: hasWriterAuthority,
        disabledReason: hasWriterAuthority ? nil : "Take Controller to send a prompt from this iPhone."
    )
}

public func structuredSessionComposerSendAffordance(
    for draft: String,
    composer: StructuredSessionComposerPresentation,
    isPerformingAction: Bool
) -> StructuredSessionComposerSendAffordance {
    let hasSendableDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    return StructuredSessionComposerSendAffordance(
        isVisible: composer.isEnabled && hasSendableDraft,
        isEnabled: composer.isEnabled && hasSendableDraft && isPerformingAction == false
    )
}

public func structuredSessionApprovalRequestPresentation(
    hasWriterAuthority: Bool
) -> StructuredSessionApprovalRequestPresentation {
    StructuredSessionApprovalRequestPresentation(
        actionsAreEnabled: hasWriterAuthority,
        disabledReason: hasWriterAuthority ? nil : "Take Controller to respond to Approval Requests from this iPhone."
    )
}

public func structuredSessionConversationPresentation(
    for row: StructuredSessionActivityRow,
    screen: SessionScreen
) -> StructuredSessionConversationPresentation {
    if row.title == "Message", let split = structuredSessionConversationPrefixSplit(for: row.text) {
        if split.label.caseInsensitiveCompare("you") == .orderedSame {
            return StructuredSessionConversationPresentation(role: .user, text: split.body)
        }
        return StructuredSessionConversationPresentation(role: .assistant(label: split.label), text: split.body)
    }

    let role: StructuredSessionConversationRole
    switch row.title {
    case "Command", "Diff":
        role = .command
    case "Error":
        role = .error
    case "Message":
        role = .assistant(label: screen.session.providerID.displayName)
    default:
        role = .system
    }

    return StructuredSessionConversationPresentation(role: role, text: row.text)
}

public func structuredSessionSlashCommandMenuPresentation(
    for draft: String,
    screen: SessionScreen
) -> StructuredSessionSlashCommandMenuPresentation {
    guard let context = structuredSessionSlashCommandContext(for: draft) else {
        return StructuredSessionSlashCommandMenuPresentation(isVisible: false, commands: [])
    }

    let commands = structuredSessionSlashCommands(for: screen)
    let normalizedQuery = context.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    let prefixMatches = commands.filter { command in
        let normalizedCommand = command.matchText.lowercased()
        if let requiredPrefix = command.suggestionQueryPrefix?.lowercased(),
           normalizedQuery.hasPrefix(requiredPrefix) == false {
            return false
        }
        if normalizedQuery.isEmpty || normalizedCommand.hasPrefix(normalizedQuery) {
            return true
        }
        return command.acceptsArguments && normalizedQuery.hasPrefix(normalizedCommand + " ")
    }

    let fallbackMatches = prefixMatches.isEmpty
        ? commands.filter { command in
            let normalizedCommand = command.matchText.lowercased()
            if let requiredPrefix = command.suggestionQueryPrefix?.lowercased(),
               normalizedQuery.hasPrefix(requiredPrefix) == false {
                return false
            }
            return normalizedQuery.isEmpty == false && normalizedCommand.contains(normalizedQuery)
        }
        : []

    let visibleCommands = prefixMatches.isEmpty ? fallbackMatches : prefixMatches
    return StructuredSessionSlashCommandMenuPresentation(
        isVisible: visibleCommands.isEmpty == false,
        commands: visibleCommands
    )
}

public func applyStructuredSessionSlashCommand(_ command: StructuredSessionSlashCommand, to draft: String) -> String {
    let leadingWhitespace = structuredSessionSlashCommandContext(for: draft)?.leadingWhitespace ?? ""
    return leadingWhitespace + command.insertionText
}

public func structuredSessionSlashCommands(for screen: SessionScreen) -> [StructuredSessionSlashCommand] {
    switch screen.session.providerID {
    case .codex:
        return mergeStructuredSessionSlashCommands(
            staticCommands: [
                StructuredSessionSlashCommand(matchText: "model", displayText: "/model", insertionText: "/model", summary: "Switch models or reasoning effort."),
                StructuredSessionSlashCommand(matchText: "review", displayText: "/review", insertionText: "/review", summary: "Review your current code changes."),
                StructuredSessionSlashCommand(matchText: "status", displayText: "/status", insertionText: "/status", summary: "Show the current model, approvals, and token usage."),
                StructuredSessionSlashCommand(matchText: "new", displayText: "/new", insertionText: "/new", summary: "Start a new chat."),
                StructuredSessionSlashCommand(matchText: "resume", displayText: "/resume", insertionText: "/resume", summary: "Resume a saved chat."),
                StructuredSessionSlashCommand(matchText: "fork", displayText: "/fork", insertionText: "/fork", summary: "Fork the current chat."),
                StructuredSessionSlashCommand(matchText: "init", displayText: "/init", insertionText: "/init", summary: "Create an AGENTS.md file with project guidance."),
                StructuredSessionSlashCommand(matchText: "compact", displayText: "/compact", insertionText: "/compact", summary: "Summarize the conversation to free context."),
                StructuredSessionSlashCommand(matchText: "goal", displayText: "/goal <objective>", insertionText: "/goal ", summary: "Set or view the goal for a long-running task.", acceptsArguments: true),
                StructuredSessionSlashCommand(matchText: "side", displayText: "/side", insertionText: "/side", summary: "Start a side conversation in an ephemeral fork."),
                StructuredSessionSlashCommand(matchText: "copy", displayText: "/copy", insertionText: "/copy", summary: "Copy the latest agent response as Markdown."),
                StructuredSessionSlashCommand(matchText: "diff", displayText: "/diff", insertionText: "/diff", summary: "Show the current git diff, including untracked files."),
                StructuredSessionSlashCommand(matchText: "mcp", displayText: "/mcp", insertionText: "/mcp", summary: "List configured MCP tools."),
                StructuredSessionSlashCommand(matchText: "ide", displayText: "/ide [on|off|status]", insertionText: "/ide ", summary: "Control IDE context sharing.", acceptsArguments: true),
                StructuredSessionSlashCommand(matchText: "keymap", displayText: "/keymap", insertionText: "/keymap", summary: "Remap TUI shortcuts."),
                StructuredSessionSlashCommand(matchText: "plugins", displayText: "/plugins", insertionText: "/plugins", summary: "Browse and manage plugins."),
                StructuredSessionSlashCommand(matchText: "clear", displayText: "/clear", insertionText: "/clear", summary: "Clear the terminal and start a new chat."),
                StructuredSessionSlashCommand(matchText: "quit", displayText: "/quit", insertionText: "/quit", summary: "Exit Codex.")
            ],
            liveCommands: (screen.slashCommands ?? []).map(structuredSessionSlashCommand(from:))
        )
    case .pi:
        return mergeStructuredSessionSlashCommands(
            staticCommands: [
                StructuredSessionSlashCommand(
                    matchText: "model",
                    displayText: "/model <provider>/<model>",
                    insertionText: "/model ",
                    summary: "Switch Pi to a configured provider/model."
                ),
                StructuredSessionSlashCommand(
                    matchText: "thinking",
                    displayText: "/thinking <level>",
                    insertionText: "/thinking ",
                    summary: "Set Pi's thinking level."
                ),
                StructuredSessionSlashCommand(
                    matchText: "steer",
                    displayText: "/steer <message>",
                    insertionText: "/steer ",
                    summary: "Queue a steering message while Pi is running.",
                    acceptsArguments: true
                ),
                StructuredSessionSlashCommand(
                    matchText: "follow-up",
                    displayText: "/follow-up <message>",
                    insertionText: "/follow-up ",
                    summary: "Queue a follow-up message for after Pi finishes.",
                    acceptsArguments: true
                ),
                StructuredSessionSlashCommand(
                    matchText: "abort",
                    displayText: "/abort",
                    insertionText: "/abort",
                    summary: "Abort the current Pi run."
                ),
                StructuredSessionSlashCommand(
                    matchText: "steering-mode",
                    displayText: "/steering-mode <mode>",
                    insertionText: "/steering-mode ",
                    summary: "Set how Pi delivers queued steering messages."
                ),
                StructuredSessionSlashCommand(
                    matchText: "follow-up-mode",
                    displayText: "/follow-up-mode <mode>",
                    insertionText: "/follow-up-mode ",
                    summary: "Set how Pi delivers queued follow-up messages."
                )
            ],
            liveCommands: (screen.slashCommands ?? []).map(structuredSessionSlashCommand(from:))
        )
    case .ibmBob:
        return mergeStructuredSessionSlashCommands(
            staticCommands: [
                StructuredSessionSlashCommand(matchText: "help", displayText: "/help", insertionText: "/help", summary: "Show available Bob commands."),
                StructuredSessionSlashCommand(matchText: "editor", displayText: "/editor", insertionText: "/editor", summary: "Configure your preferred editor."),
                StructuredSessionSlashCommand(matchText: "memory show", displayText: "/memory show", insertionText: "/memory show", summary: "View the current memory context."),
                StructuredSessionSlashCommand(matchText: "memory refresh", displayText: "/memory refresh", insertionText: "/memory refresh", summary: "Reload memory and context files."),
                StructuredSessionSlashCommand(matchText: "restore", displayText: "/restore <checkpoint_file>", insertionText: "/restore ", summary: "Restore a checkpoint.", acceptsArguments: true),
                StructuredSessionSlashCommand(matchText: "ide enable", displayText: "/ide enable", insertionText: "/ide enable", summary: "Enable IDE context integration."),
                StructuredSessionSlashCommand(matchText: "ide disable", displayText: "/ide disable", insertionText: "/ide disable", summary: "Disable IDE context integration."),
                StructuredSessionSlashCommand(matchText: "ide status", displayText: "/ide status", insertionText: "/ide status", summary: "Show IDE integration status."),
                StructuredSessionSlashCommand(matchText: "ide install", displayText: "/ide install", insertionText: "/ide install", summary: "Install the Bob IDE companion extension."),
                StructuredSessionSlashCommand(matchText: "mode plan", displayText: "/mode plan", insertionText: "/mode plan", summary: "Switch to Plan mode."),
                StructuredSessionSlashCommand(matchText: "mode code", displayText: "/mode code", insertionText: "/mode code", summary: "Switch to Code mode."),
                StructuredSessionSlashCommand(matchText: "mode advanced", displayText: "/mode advanced", insertionText: "/mode advanced", summary: "Switch to Advanced mode."),
                StructuredSessionSlashCommand(matchText: "mode ask", displayText: "/mode ask", insertionText: "/mode ask", summary: "Switch to Ask mode.")
            ],
            liveCommands: (screen.slashCommands ?? []).map(structuredSessionSlashCommand(from:))
        )
    case .claude:
        return []
    }
}

private func mergeStructuredSessionSlashCommands(
    staticCommands: [StructuredSessionSlashCommand],
    liveCommands: [StructuredSessionSlashCommand]
) -> [StructuredSessionSlashCommand] {
    var merged = staticCommands
    let existingMatchTexts = Set(staticCommands.map(\.matchText))
    merged.append(contentsOf: liveCommands.filter { existingMatchTexts.contains($0.matchText) == false })
    return merged
}

private func structuredSessionSlashCommand(from command: SessionSlashCommand) -> StructuredSessionSlashCommand {
    let locationSuffix: String
    switch command.location {
    case .user:
        locationSuffix = " [u]"
    case .project:
        locationSuffix = " [p]"
    case .path:
        locationSuffix = " [x]"
    case nil:
        locationSuffix = ""
    }

    let trimmedDescription = command.description?.trimmingCharacters(in: .whitespacesAndNewlines)
    let summary = (trimmedDescription?.isEmpty == false ? trimmedDescription : nil)
        ?? structuredSessionSlashCommandSummaryFallback(for: command)

    let resolvedDisplayName = command.displayName ?? command.name
    let resolvedInsertionText = command.insertionText ?? command.name

    return StructuredSessionSlashCommand(
        matchText: command.name,
        displayText: "/\(resolvedDisplayName)\(locationSuffix)",
        insertionText: "/\(resolvedInsertionText)",
        summary: summary,
        acceptsArguments: true,
        suggestionQueryPrefix: command.suggestionQueryPrefix
    )
}

private func structuredSessionSlashCommandSummaryFallback(for command: SessionSlashCommand) -> String {
    switch command.source {
    case .builtIn:
        return "Built-in command"
    case .extension:
        return "Extension command"
    case .prompt:
        return "Prompt template"
    case .skill:
        return "Skill command"
    }
}

private func structuredSessionConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
    guard let separatorRange = text.range(of: ": ") else {
        return nil
    }

    let label = String(text[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = String(text[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard label.isEmpty == false, body.isEmpty == false, label.count <= 24 else {
        return nil
    }
    return (label, body)
}

private struct StructuredSessionSlashCommandContext {
    let leadingWhitespace: String
    let query: String
}

private func structuredSessionSlashCommandContext(for draft: String) -> StructuredSessionSlashCommandContext? {
    guard draft.contains("\n") == false else {
        return nil
    }

    let leadingWhitespace = String(draft.prefix { $0.isWhitespace && $0.isNewline == false })
    let remainder = draft.dropFirst(leadingWhitespace.count)
    guard remainder.first == "/" else {
        return nil
    }

    return StructuredSessionSlashCommandContext(
        leadingWhitespace: leadingWhitespace,
        query: String(remainder.dropFirst())
    )
}

private func structuredSessionActivityTitle(for kind: SessionActivityItem.Kind) -> String {
    switch kind {
    case .status:
        "Status"
    case .message:
        "Message"
    case .approvalRequest:
        "Approval Request"
    case .approvalDecision:
        "Approval Decision"
    case .progress:
        "Progress"
    case .command:
        "Command"
    case .diff:
        "Diff"
    case .error:
        "Error"
    case .completion:
        "Completion"
    }
}

private func structuredSessionActivitySystemImage(for kind: SessionActivityItem.Kind) -> String {
    switch kind {
    case .status:
        "dot.radiowaves.left.and.right"
    case .message:
        "message"
    case .approvalRequest:
        "hand.raised"
    case .approvalDecision:
        "checkmark.shield"
    case .progress:
        "hourglass"
    case .command:
        "terminal"
    case .diff:
        "square.and.pencil"
    case .error:
        "exclamationmark.triangle"
    case .completion:
        "checkmark.circle"
    }
}

private func structuredSessionActivityEmphasis(for kind: SessionActivityItem.Kind) -> StructuredSessionActivityEmphasis {
    switch kind {
    case .status, .command:
        .neutral
    case .message, .approvalRequest, .progress, .diff:
        .accent
    case .approvalDecision:
        .success
    case .error:
        .critical
    case .completion:
        .success
    }
}
