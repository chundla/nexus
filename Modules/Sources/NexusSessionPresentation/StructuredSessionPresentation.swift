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
    public let detailText: String?
    public let isDetailTextTruncated: Bool
    public let emphasis: StructuredSessionActivityEmphasis
    public let conversationPresentation: StructuredSessionConversationPresentation?

    public init(
        id: UUID,
        title: String,
        systemImage: String,
        text: String,
        detailText: String? = nil,
        isDetailTextTruncated: Bool = false,
        emphasis: StructuredSessionActivityEmphasis,
        conversationPresentation: StructuredSessionConversationPresentation? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.text = text
        self.detailText = detailText
        self.isDetailTextTruncated = isDetailTextTruncated
        self.emphasis = emphasis
        self.conversationPresentation = conversationPresentation
    }
}

public struct StructuredSessionDetailTextPreview: Equatable {
    public let text: String
    public let isTruncated: Bool

    public init(text: String, isTruncated: Bool) {
        self.text = text
        self.isTruncated = isTruncated
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

public struct StructuredSessionTokenUsagePresentation: Equatable {
    public let usedTokens: Int
    public let totalTokens: Int
    public let percent: Int

    public init(usedTokens: Int, totalTokens: Int, percent: Int) {
        self.usedTokens = usedTokens
        self.totalTokens = totalTokens
        self.percent = percent
    }

    public var summaryText: String {
        "\(formatStructuredSessionTokenCount(usedTokens))/\(formatStructuredSessionTokenCount(totalTokens)) \(percent)%"
    }
}

public struct StructuredSessionStatusBarPresentation: Equatable {
    public let workspaceLocation: String
    public let tokenUsage: StructuredSessionTokenUsagePresentation?

    public init(workspaceLocation: String, tokenUsage: StructuredSessionTokenUsagePresentation?) {
        self.workspaceLocation = workspaceLocation
        self.tokenUsage = tokenUsage
    }

    public var tokenUsageText: String {
        tokenUsage?.summaryText ?? "—"
    }

    public var tokenUsagePercent: Int? {
        tokenUsage?.percent
    }

    public var isTokenUsageAvailable: Bool {
        tokenUsage != nil
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

public final class StructuredSessionFeedPresenter {
    private let rowBuilder: ([SessionActivityItem]) -> [StructuredSessionActivityRow]

    private var cachedSessionID: UUID?
    private var cachedActivityItems: [SessionActivityItem] = []
    private var cachedActivityRows: [StructuredSessionActivityRow] = []

    public init() {
        self.rowBuilder = structuredSessionActivityRows(for:)
    }

    init(_ rowBuilder: @escaping ([SessionActivityItem]) -> [StructuredSessionActivityRow]) {
        self.rowBuilder = rowBuilder
    }

    public func presentation(for screen: SessionScreen) -> StructuredSessionFeedPresentation {
        structuredSessionFeedPresentation(for: screen, activityRows: activityRows(for: screen))
    }

    private func activityRows(for screen: SessionScreen) -> [StructuredSessionActivityRow] {
        let providerDisplayName = screen.session.providerID.displayName

        guard cachedSessionID == screen.session.id else {
            return rebuildActivityRows(
                for: screen.activityItems,
                sessionID: screen.session.id,
                providerDisplayName: providerDisplayName
            )
        }

        if screen.activityItems == cachedActivityItems {
            return cachedActivityRows
        }

        if screen.activityItems.count >= cachedActivityItems.count,
           screen.activityItems.starts(with: cachedActivityItems) {
            let appendedItems = Array(screen.activityItems.dropFirst(cachedActivityItems.count))
            cachedActivityItems = screen.activityItems
            cachedActivityRows.append(contentsOf: annotateStructuredSessionActivityRows(
                rowBuilder(appendedItems),
                providerDisplayName: providerDisplayName
            ))
            return cachedActivityRows
        }

        return rebuildActivityRows(
            for: screen.activityItems,
            sessionID: screen.session.id,
            providerDisplayName: providerDisplayName
        )
    }

    @discardableResult
    private func rebuildActivityRows(
        for activityItems: [SessionActivityItem],
        sessionID: UUID,
        providerDisplayName: String
    ) -> [StructuredSessionActivityRow] {
        let rows = annotateStructuredSessionActivityRows(
            rowBuilder(activityItems),
            providerDisplayName: providerDisplayName
        )
        cachedSessionID = sessionID
        cachedActivityItems = activityItems
        cachedActivityRows = rows
        return rows
    }
}

public func structuredSessionActivityRows(for screen: SessionScreen) -> [StructuredSessionActivityRow] {
    structuredSessionActivityRows(for: screen.activityItems)
}

public func structuredSessionFeedPresentation(for screen: SessionScreen) -> StructuredSessionFeedPresentation {
    structuredSessionFeedPresentation(
        for: screen,
        activityRows: annotateStructuredSessionActivityRows(
            structuredSessionActivityRows(for: screen.activityItems),
            providerDisplayName: screen.session.providerID.displayName
        )
    )
}

func structuredSessionActivityRows(for activityItems: [SessionActivityItem]) -> [StructuredSessionActivityRow] {
    activityItems.map { item in
        let detailPreview = item.detailText.map { structuredSessionDetailTextPreview(for: $0) }

        return StructuredSessionActivityRow(
            id: item.id,
            title: structuredSessionActivityTitle(for: item.kind),
            systemImage: structuredSessionActivitySystemImage(for: item.kind),
            text: item.text,
            detailText: detailPreview?.text,
            isDetailTextTruncated: detailPreview?.isTruncated ?? false,
            emphasis: structuredSessionActivityEmphasis(for: item.kind)
        )
    }
}

private func structuredSessionFeedPresentation(
    for screen: SessionScreen,
    activityRows: [StructuredSessionActivityRow]
) -> StructuredSessionFeedPresentation {
    let pendingApprovalRequests = screen.approvalRequests.filter { $0.state == .pending }
    return StructuredSessionFeedPresentation(
        copy: structuredSessionPresentationCopy(for: screen),
        activityRows: activityRows,
        pendingApprovalRequests: pendingApprovalRequests,
        thinkingIndicator: structuredSessionThinkingIndicator(
            for: screen,
            hasPendingApprovalRequests: pendingApprovalRequests.isEmpty == false
        )
    )
}

public struct StructuredSessionAutoScrollTrigger: Equatable {
    public let lastActivityRowID: UUID?
    public let pendingApprovalRequestIDs: [UUID]
    public let pendingDialogIDs: [String]
    public let notificationIDs: [UUID]

    public init(
        lastActivityRowID: UUID?,
        pendingApprovalRequestIDs: [UUID],
        pendingDialogIDs: [String],
        notificationIDs: [UUID]
    ) {
        self.lastActivityRowID = lastActivityRowID
        self.pendingApprovalRequestIDs = pendingApprovalRequestIDs
        self.pendingDialogIDs = pendingDialogIDs
        self.notificationIDs = notificationIDs
    }
}

public func structuredSessionAutoScrollTrigger(for screen: SessionScreen) -> StructuredSessionAutoScrollTrigger {
    StructuredSessionAutoScrollTrigger(
        lastActivityRowID: screen.activityItems.last?.id,
        pendingApprovalRequestIDs: screen.approvalRequests
            .filter { $0.state == .pending }
            .map(\.id),
        pendingDialogIDs: screen.extensionUI?.pendingDialogs.map(\.id) ?? [],
        notificationIDs: screen.extensionUI?.notifications.map(\.id) ?? []
    )
}

public func structuredSessionPresentationCopy(for screen: SessionScreen) -> StructuredSessionPresentationCopy {
    StructuredSessionPresentationCopy(
        emptyStateTitle: "No Session activity yet",
        emptyStateDescription: "Send a prompt to start the \(screen.session.providerID.displayName) Session.",
        composerPlaceholder: "Send a prompt to \(screen.session.providerID.displayName)"
    )
}

public func structuredSessionDetailTextPreview(
    for text: String,
    maximumLines: Int = 12,
    maximumCharacters: Int = 4_000
) -> StructuredSessionDetailTextPreview {
    guard maximumLines > 0, maximumCharacters > 0 else {
        return StructuredSessionDetailTextPreview(text: "", isTruncated: text.isEmpty == false)
    }

    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let lineLimitedText: String
    var isTruncated = false

    if lines.count > maximumLines {
        lineLimitedText = lines.prefix(maximumLines).joined(separator: "\n")
        isTruncated = true
    } else {
        lineLimitedText = text
    }

    if lineLimitedText.count > maximumCharacters {
        let endIndex = lineLimitedText.index(lineLimitedText.startIndex, offsetBy: maximumCharacters)
        return StructuredSessionDetailTextPreview(
            text: String(lineLimitedText[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines),
            isTruncated: true
        )
    }

    return StructuredSessionDetailTextPreview(text: lineLimitedText, isTruncated: isTruncated)
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

public func structuredSessionStatusBarPresentation(
    for screen: SessionScreen,
    workspaceLocation: String
) -> StructuredSessionStatusBarPresentation {
    StructuredSessionStatusBarPresentation(
        workspaceLocation: workspaceLocation,
        tokenUsage: structuredSessionTokenUsagePresentation(for: screen)
    )
}

public func structuredSessionTokenUsagePresentation(
    for screen: SessionScreen
) -> StructuredSessionTokenUsagePresentation? {
    guard let usage = resolvedStructuredSessionTokenUsage(for: screen) else {
        return nil
    }

    return StructuredSessionTokenUsagePresentation(
        usedTokens: usage.usedTokens,
        totalTokens: usage.totalTokens,
        percent: usage.percent
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
    structuredSessionConversationPresentation(
        for: row,
        providerDisplayName: screen.session.providerID.displayName
    )
}

public func structuredSessionConversationPresentation(
    for row: StructuredSessionActivityRow,
    providerDisplayName: String
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
        role = .assistant(label: providerDisplayName)
    default:
        role = .system
    }

    return StructuredSessionConversationPresentation(role: role, text: row.text)
}

private func annotateStructuredSessionActivityRows(
    _ rows: [StructuredSessionActivityRow],
    providerDisplayName: String
) -> [StructuredSessionActivityRow] {
    rows.map { row in
        StructuredSessionActivityRow(
            id: row.id,
            title: row.title,
            systemImage: row.systemImage,
            text: row.text,
            detailText: row.detailText,
            isDetailTextTruncated: row.isDetailTextTruncated,
            emphasis: row.emphasis,
            conversationPresentation: row.conversationPresentation
                ?? structuredSessionConversationPresentation(for: row, providerDisplayName: providerDisplayName)
        )
    }
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
                    matchText: "cycle-model",
                    displayText: "/cycle-model",
                    insertionText: "/cycle-model",
                    summary: "Cycle Pi to the next available model."
                ),
                StructuredSessionSlashCommand(
                    matchText: "cycle-thinking-level",
                    displayText: "/cycle-thinking-level",
                    insertionText: "/cycle-thinking-level",
                    summary: "Cycle Pi to the next available thinking level."
                ),
                StructuredSessionSlashCommand(
                    matchText: "new",
                    displayText: "/new",
                    insertionText: "/new",
                    summary: "Start a new chat and clear the current session history."
                ),
                StructuredSessionSlashCommand(
                    matchText: "clear",
                    displayText: "/clear",
                    insertionText: "/clear",
                    summary: "Start a new chat and clear the current session history."
                ),
                StructuredSessionSlashCommand(
                    matchText: "compact",
                    displayText: "/compact [instructions]",
                    insertionText: "/compact ",
                    summary: "Compact the current Pi Session context.",
                    acceptsArguments: true
                ),
                StructuredSessionSlashCommand(
                    matchText: "auto-compaction",
                    displayText: "/auto-compaction <on|off>",
                    insertionText: "/auto-compaction ",
                    summary: "Enable or disable Pi auto-compaction.",
                    acceptsArguments: true
                ),
                StructuredSessionSlashCommand(
                    matchText: "auto-retry",
                    displayText: "/auto-retry <on|off>",
                    insertionText: "/auto-retry ",
                    summary: "Enable or disable Pi auto-retry.",
                    acceptsArguments: true
                ),
                StructuredSessionSlashCommand(
                    matchText: "abort-retry",
                    displayText: "/abort-retry",
                    insertionText: "/abort-retry",
                    summary: "Abort the current Pi retry delay."
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

private struct StructuredSessionResolvedTokenUsage {
    let usedTokens: Int
    let totalTokens: Int
    let percent: Int
}

private func resolvedStructuredSessionTokenUsage(for screen: SessionScreen) -> StructuredSessionResolvedTokenUsage? {
    if let usage = structuredSessionTokenUsage(from: screen.providerEvents) {
        return usage
    }

    if let usage = structuredSessionTokenUsage(from: screen.activityItems) {
        return usage
    }

    guard let inferredContextWindow = inferredStructuredSessionContextWindow(for: screen) else {
        return nil
    }

    return StructuredSessionResolvedTokenUsage(usedTokens: 0, totalTokens: inferredContextWindow, percent: 0)
}

private func structuredSessionTokenUsage(from providerEvents: [SessionProviderEvent]) -> StructuredSessionResolvedTokenUsage? {
    for event in providerEvents.reversed() {
        guard let payload = structuredSessionJSONObject(from: event.rawPayload),
              let usage = structuredSessionTokenUsage(from: payload) else {
            continue
        }
        return usage
    }
    return nil
}

private func structuredSessionTokenUsage(from activityItems: [SessionActivityItem]) -> StructuredSessionResolvedTokenUsage? {
    for item in activityItems.reversed() {
        if let usage = structuredSessionTokenUsage(from: item.text) {
            return usage
        }
        if let detailText = item.detailText,
           let usage = structuredSessionTokenUsage(from: detailText) {
            return usage
        }
    }
    return nil
}

private func structuredSessionTokenUsage(from value: Any) -> StructuredSessionResolvedTokenUsage? {
    switch value {
    case let object as [String: Any]:
        if let directUsage = directStructuredSessionTokenUsage(from: object) {
            return directUsage
        }

        let priorityKeys = ["contextUsage", "tokenUsage", "usage", "data", "result", "params", "context", "thread", "turn", "item", "message"]
        for key in priorityKeys {
            if let nestedValue = object[key],
               let usage = structuredSessionTokenUsage(from: nestedValue) {
                return usage
            }
        }

        for nestedValue in object.values {
            if let usage = structuredSessionTokenUsage(from: nestedValue) {
                return usage
            }
        }
    case let array as [Any]:
        for nestedValue in array.reversed() {
            if let usage = structuredSessionTokenUsage(from: nestedValue) {
                return usage
            }
        }
    default:
        break
    }

    return nil
}

private func directStructuredSessionTokenUsage(from object: [String: Any]) -> StructuredSessionResolvedTokenUsage? {
    let totalTokens = structuredSessionIntValue(in: object, keys: ["contextWindow", "context_window", "maxTokens", "max_tokens", "totalTokens", "total_tokens"])

    let explicitUsedTokens = structuredSessionIntValue(in: object, keys: ["tokens", "usedTokens", "used_tokens", "tokenCount", "token_count"])
        ?? structuredSessionSummedIntValue(in: object, keyPairs: [("inputTokens", "outputTokens"), ("input_tokens", "output_tokens")])
    let explicitPercent = structuredSessionIntValue(in: object, keys: ["percent", "usagePercent", "usage_percent"])

    guard let totalTokens else {
        return nil
    }

    let usedTokens = explicitUsedTokens ?? explicitPercent.map { max(0, Int((Double(totalTokens) * Double($0)) / 100.0)) }
    guard let usedTokens else {
        return nil
    }

    let percent = explicitPercent ?? (totalTokens > 0 ? Int((Double(usedTokens) / Double(totalTokens)) * 100.0) : 0)
    return StructuredSessionResolvedTokenUsage(
        usedTokens: max(0, usedTokens),
        totalTokens: max(1, totalTokens),
        percent: max(0, min(100, percent))
    )
}

private func structuredSessionTokenUsage(from text: String) -> StructuredSessionResolvedTokenUsage? {
    let pattern = #"([0-9,]+)\s*/\s*([0-9,]+)\s+tokens\s*\((\d+)%\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges == 4,
          let usedRange = Range(match.range(at: 1), in: text),
          let totalRange = Range(match.range(at: 2), in: text),
          let percentRange = Range(match.range(at: 3), in: text) else {
        return nil
    }

    let usedText = text[usedRange].replacingOccurrences(of: ",", with: "")
    let totalText = text[totalRange].replacingOccurrences(of: ",", with: "")
    let percentText = text[percentRange]

    guard let usedTokens = Int(usedText),
          let totalTokens = Int(totalText),
          let percent = Int(percentText) else {
        return nil
    }

    return StructuredSessionResolvedTokenUsage(
        usedTokens: usedTokens,
        totalTokens: totalTokens,
        percent: percent
    )
}

private func inferredStructuredSessionContextWindow(for screen: SessionScreen) -> Int? {
    if let modelIdentifier = structuredSessionModelIdentifier(for: screen) {
        return structuredSessionContextWindow(forModelIdentifier: modelIdentifier)
    }

    return nil
}

private func structuredSessionModelIdentifier(for screen: SessionScreen) -> String? {
    switch screen.session.providerID {
    case .pi:
        if let modelIdentifier = piStructuredSessionModelIdentifier(from: screen.providerEvents) {
            return modelIdentifier
        }
        return piStructuredSessionModelIdentifier(from: screen.activityItems)
    case .codex:
        return codexStructuredSessionModelIdentifier(from: screen.providerEvents)
    case .ibmBob, .claude:
        return nil
    }
}

private func piStructuredSessionModelIdentifier(from providerEvents: [SessionProviderEvent]) -> String? {
    for event in providerEvents.reversed() {
        guard let payload = structuredSessionJSONObject(from: event.rawPayload),
              let data = payload["data"] as? [String: Any],
              let model = data["model"] as? [String: Any],
              let provider = structuredSessionTrimmedString(in: model, keys: ["provider"]),
              let modelID = structuredSessionTrimmedString(in: model, keys: ["id"]) else {
            continue
        }
        return "\(provider)/\(modelID)"
    }

    return nil
}

private func piStructuredSessionModelIdentifier(from activityItems: [SessionActivityItem]) -> String? {
    for item in activityItems.reversed() {
        guard item.text.hasPrefix("Current Model: ") else {
            continue
        }

        let suffix = item.text.dropFirst("Current Model: ".count)
        let target = suffix.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(suffix)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTarget.isEmpty == false {
            return trimmedTarget
        }
    }

    return nil
}

private func codexStructuredSessionModelIdentifier(from providerEvents: [SessionProviderEvent]) -> String? {
    for event in providerEvents.reversed() {
        guard let payload = structuredSessionJSONObject(from: event.rawPayload) else {
            continue
        }

        if let result = payload["result"] as? [String: Any],
           let model = structuredSessionTrimmedString(in: result, keys: ["model"]) {
            return model
        }

        if let params = payload["params"] as? [String: Any],
           let model = structuredSessionTrimmedString(in: params, keys: ["model"]) {
            return model
        }
    }

    return nil
}

private func structuredSessionContextWindow(forModelIdentifier modelIdentifier: String) -> Int? {
    let normalized = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.isEmpty == false else {
        return nil
    }

    if normalized.contains("gpt-5") || normalized.contains("codex") {
        return 272_000
    }

    if normalized.contains("claude") || normalized.contains("sonnet") || normalized.contains("haiku") || normalized.contains("opus") {
        return 200_000
    }

    return nil
}

private func structuredSessionJSONObject(from rawPayload: String) -> [String: Any]? {
    guard let data = rawPayload.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    return object
}

private func structuredSessionTrimmedString(in object: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let string = object[key] as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
    }

    return nil
}

private func structuredSessionIntValue(in object: [String: Any], keys: [String]) -> Int? {
    for key in keys {
        if let value = structuredSessionCoerceInt(object[key]) {
            return value
        }
    }

    return nil
}

private func structuredSessionSummedIntValue(in object: [String: Any], keyPairs: [(String, String)]) -> Int? {
    for (lhs, rhs) in keyPairs {
        if let lhsValue = structuredSessionCoerceInt(object[lhs]),
           let rhsValue = structuredSessionCoerceInt(object[rhs]) {
            return lhsValue + rhsValue
        }
    }

    return nil
}

private func structuredSessionCoerceInt(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
        return value
    case let value as NSNumber:
        return value.intValue
    case let value as String:
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
        return nil
    }
}

private func formatStructuredSessionTokenCount(_ value: Int) -> String {
    let absoluteValue = abs(value)

    switch absoluteValue {
    case 1_000_000...:
        let millions = Double(value) / 1_000_000.0
        return millions.rounded() == millions ? "\(Int(millions))m" : String(format: "%.1fm", millions)
    case 1_000...:
        let thousands = Double(value) / 1_000.0
        return thousands.rounded() == thousands ? "\(Int(thousands))k" : String(format: "%.1fk", thousands)
    default:
        return String(value)
    }
}

private func structuredSessionConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
    guard let separatorRange = text.range(of: ": ") else {
        return nil
    }

    let label = String(text[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = String(text[separatorRange.upperBound...])
    guard label.isEmpty == false,
          body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
          label.count <= 24 else {
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
