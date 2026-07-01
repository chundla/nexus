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
    public let showsExpandedSystemCard: Bool

    public init(
        id: UUID,
        title: String,
        systemImage: String,
        text: String,
        detailText: String? = nil,
        isDetailTextTruncated: Bool = false,
        emphasis: StructuredSessionActivityEmphasis,
        conversationPresentation: StructuredSessionConversationPresentation? = nil,
        showsExpandedSystemCard: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.text = text
        self.detailText = detailText
        self.isDetailTextTruncated = isDetailTextTruncated
        self.emphasis = emphasis
        self.conversationPresentation = conversationPresentation
        self.showsExpandedSystemCard =
            showsExpandedSystemCard
            ?? structuredSessionActivityRowShowsExpandedSystemCard(text: text, detailText: detailText)
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

public struct StructuredSessionActivityRowChunk: Identifiable, Equatable {
    public let id: Int
    public let rows: [StructuredSessionActivityRow]

    public init(id: Int, rows: [StructuredSessionActivityRow]) {
        self.id = id
        self.rows = rows
    }
}

public struct StructuredSessionFeedPresentation: Equatable {
    public let copy: StructuredSessionPresentationCopy
    public let activityRows: [StructuredSessionActivityRow]
    public let activityRowChunks: [StructuredSessionActivityRowChunk]
    /// Pi v1 composite feed segments (ADR 0037). `nil` when the client should use flat `activityRows`.
    public let feedSegments: [StructuredSessionFeedSegment]?
    /// Standalone Pi rows hidden because their body duplicates a closed-turn final answer.
    public let hiddenStandaloneFeedSegmentIDs: Set<UUID>
    public let pendingApprovalRequests: [SessionApprovalRequest]
    public let thinkingIndicator: StructuredSessionThinkingIndicator?

    /// Row order for feed `LazyVStack` iteration (same as `activityRows`).
    public let feedActivityRowIDs: [UUID]

    /// Feed items for scroll/reveal policy: segment IDs when composite projection is active (ADR 0037).
    public var feedScrollItemCount: Int {
        structuredSessionFeedScrollItemCount(for: self)
    }

    public var feedScrollItemIDs: [UUID] {
        structuredSessionFeedScrollItemIDs(for: self)
    }

    public init(
        copy: StructuredSessionPresentationCopy,
        activityRows: [StructuredSessionActivityRow],
        activityRowChunks: [StructuredSessionActivityRowChunk]? = nil,
        feedSegments: [StructuredSessionFeedSegment]? = nil,
        pendingApprovalRequests: [SessionApprovalRequest],
        thinkingIndicator: StructuredSessionThinkingIndicator?
    ) {
        let canonicalChunks = activityRowChunks ?? structuredSessionActivityRowChunks(for: activityRows)
        let canonicalRows = canonicalChunks.flatMap(\.rows)

        self.copy = copy
        self.activityRows = canonicalRows
        self.activityRowChunks = canonicalChunks
        self.feedSegments = feedSegments
        self.hiddenStandaloneFeedSegmentIDs = structuredSessionPiHiddenStandaloneFeedSegmentIDs(
            in: feedSegments ?? []
        )
        self.pendingApprovalRequests = pendingApprovalRequests
        self.thinkingIndicator = thinkingIndicator
        self.feedActivityRowIDs = canonicalRows.map(\.id)
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
    public let isStreaming: Bool

    public init(
        role: StructuredSessionConversationRole,
        text: String,
        isStreaming: Bool = false
    ) {
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

/// Feed markdown is limited to assistant message bodies (including live drafts and finalized output).
/// Command rows, command/detail output, and system rows stay plain or monospaced in the UI (#227).
public func structuredSessionConversationRoleUsesFeedMarkdownParsing(
    _ role: StructuredSessionConversationRole
) -> Bool {
    switch role {
    case .assistant:
        true
    case .user, .command, .error, .system:
        false
    }
}

public func structuredSessionFeedConversationTextUsesMarkdownParsing(
    for conversation: StructuredSessionConversationPresentation
) -> Bool {
    structuredSessionConversationRoleUsesFeedMarkdownParsing(conversation.role)
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

public struct FocusedStructuredSessionPresentation: Equatable {
    public let session: Session
    public let feed: StructuredSessionFeedPresentation
    public let autoScrollTrigger: StructuredSessionAutoScrollTrigger

    public init(
        session: Session,
        feed: StructuredSessionFeedPresentation,
        autoScrollTrigger: StructuredSessionAutoScrollTrigger
    ) {
        self.session = session
        self.feed = feed
        self.autoScrollTrigger = autoScrollTrigger
    }

    public var structuredSessionFeedScrollTarget: StructuredSessionFeedScrollTarget {
        NexusSessionPresentation.structuredSessionFeedScrollTarget(for: self)
    }

    public var structuredSessionFeedScrollSnapshot: StructuredSessionFeedScrollSnapshot {
        NexusSessionPresentation.structuredSessionFeedScrollSnapshot(for: self)
    }

    public func structuredSessionShouldRequestBottomScroll(
        previous: StructuredSessionFeedScrollSnapshot,
        isPinnedToBottom: Bool
    ) -> Bool {
        NexusSessionPresentation.structuredSessionShouldRequestBottomScroll(
            previous: previous,
            current: structuredSessionFeedScrollSnapshot,
            isPinnedToBottom: isPinnedToBottom
        )
    }
}

public struct FocusedStructuredSessionChromePresentation: Equatable {
    public let session: Session
    public let extensionUI: SessionExtensionUIState?
    public let isAgentTurnInProgress: Bool
    public let tokenUsage: StructuredSessionTokenUsagePresentation?
    public let slashCommands: [StructuredSessionSlashCommand]

    public init(
        session: Session,
        extensionUI: SessionExtensionUIState?,
        isAgentTurnInProgress: Bool,
        tokenUsage: StructuredSessionTokenUsagePresentation?,
        slashCommands: [StructuredSessionSlashCommand]
    ) {
        self.session = session
        self.extensionUI = extensionUI
        self.isAgentTurnInProgress = isAgentTurnInProgress
        self.tokenUsage = tokenUsage
        self.slashCommands = slashCommands
    }
}

public final class FocusedStructuredSessionPresenter {
    private let feedPresenter = StructuredSessionFeedPresenter()

    public init() {}

    public func presentation(for screen: SessionScreen) -> FocusedStructuredSessionPresentation? {
        guard screen.primarySurface == .structuredActivityFeed else {
            return nil
        }

        return FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: feedPresenter.presentation(for: screen),
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
    }
}

public final class FocusedStructuredSessionChromePresenter {
    private let tokenUsagePresenter: StructuredSessionTokenUsagePresenter
    private let slashCommandBuilder: (SessionScreen) -> [StructuredSessionSlashCommand]

    /// Last chrome presentation returned while the row-affecting inputs were stable.
    /// Mirrors the guard in StructuredSessionHistoryPagingController.presentation to keep
    /// chrome from mutating on pure providerFacts / diagnostic / turn-progress churn when
    /// activityItems and isAgentTurnInProgress are unchanged (#208).
    /// Slash commands and extension UI still invalidate so composer menus stay current after `/clear`
    /// and when Pi repopulates live skill commands.
    private var lastStablePresentation: FocusedStructuredSessionChromePresentation?
    private var lastSourceActivityItems: [SessionActivityItem] = []
    private var lastIsAgent: Bool = false
    private var lastSourceSlashCommands: [SessionSlashCommand]?
    private var lastSourceExtensionUI: SessionExtensionUIState?

    public init() {
        self.tokenUsagePresenter = StructuredSessionTokenUsagePresenter()
        self.slashCommandBuilder = structuredSessionSlashCommands(for:)
    }

    init(
        tokenUsagePresenter: StructuredSessionTokenUsagePresenter,
        slashCommandBuilder: @escaping (SessionScreen) -> [StructuredSessionSlashCommand]
    ) {
        self.tokenUsagePresenter = tokenUsagePresenter
        self.slashCommandBuilder = slashCommandBuilder
    }

    public func presentation(for screen: SessionScreen) -> FocusedStructuredSessionChromePresentation? {
        guard screen.primarySurface == .structuredActivityFeed else {
            return nil
        }

        // Cheap delta: activityItems (row source) + isAgentTurnInProgress (controls draft visibility in feed,
        // but chrome itself only re-publishes when the visible chrome inputs change).
        // ProviderFacts (tokenUsage), finalOutputDiagnostic, extensionUI, and pure isAgent toggles without
        // row change must not force a new chrome value during dwells.
        if let last = lastStablePresentation,
            last.session.id == screen.session.id,
            screen.activityItems == lastSourceActivityItems,
            screen.isAgentTurnInProgress == lastIsAgent,
            screen.slashCommands == lastSourceSlashCommands,
            screen.extensionUI == lastSourceExtensionUI
        {
            return last
        }

        let pres = FocusedStructuredSessionChromePresentation(
            session: screen.session,
            extensionUI: screen.extensionUI,
            isAgentTurnInProgress: screen.isAgentTurnInProgress,
            tokenUsage: tokenUsagePresenter.presentation(for: screen),
            slashCommands: slashCommandBuilder(screen)
        )
        lastStablePresentation = pres
        lastSourceActivityItems = screen.activityItems
        lastIsAgent = screen.isAgentTurnInProgress
        lastSourceSlashCommands = screen.slashCommands
        lastSourceExtensionUI = screen.extensionUI
        return pres
    }
}

public func focusedStructuredSessionChromePresentation(
    for screen: SessionScreen
) -> FocusedStructuredSessionChromePresentation? {
    FocusedStructuredSessionChromePresenter().presentation(for: screen)
}

public final class StructuredSessionFeedPresenter {
    private struct LiveAssistantDraftState {
        let rowID: UUID
        let text: String
    }

    private let rowBuilder: ([SessionActivityItem]) -> [StructuredSessionActivityRow]
    private let chunkSize: Int
    private let liveTailChunkSize: Int

    private var cachedSessionID: UUID?
    private var cachedActivityItems: [SessionActivityItem] = []
    private var cachedActivityRows: [StructuredSessionActivityRow] = []
    private var cachedActivityRowChunks: [StructuredSessionActivityRowChunk] = []
    private var presentedRowIDByActivityItemID: [UUID: UUID] = [:]
    private var liveAssistantDraft: LiveAssistantDraftState?

    /// Test-only counters for rebuild vs incremental activity-row paths (#216).
    private(set) var activityRowFullRebuildCount = 0
    private(set) var activityRowIncrementalAppendCount = 0
    private(set) var activityRowTailRebuildCount = 0

    public init() {
        self.rowBuilder = structuredSessionActivityRows(for:)
        self.chunkSize = structuredSessionDefaultActivityRowChunkSize
        self.liveTailChunkSize = structuredSessionDefaultLiveTailActivityRowChunkSize
    }

    init(
        chunkSize: Int = structuredSessionDefaultActivityRowChunkSize,
        liveTailChunkSize: Int = structuredSessionDefaultLiveTailActivityRowChunkSize,
        _ rowBuilder: @escaping ([SessionActivityItem]) -> [StructuredSessionActivityRow]
    ) {
        let normalizedChunkSize = max(1, chunkSize)
        self.rowBuilder = rowBuilder
        self.chunkSize = normalizedChunkSize
        self.liveTailChunkSize = max(1, min(liveTailChunkSize, normalizedChunkSize))
    }

    public func presentation(for screen: SessionScreen) -> StructuredSessionFeedPresentation {
        if cachedSessionID != screen.session.id {
            presentedRowIDByActivityItemID.removeAll(keepingCapacity: true)
            liveAssistantDraft = nil
        }

        let feedState = presentedFeedState(for: screen, baseRows: activityRows(for: screen))
        return structuredSessionFeedPresentation(
            for: screen,
            activityRows: feedState.rows,
            activityRowChunks: feedState.chunks
        )
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

        let stablePrefixCount = structuredSessionCommonPrefixCount(cachedActivityItems, screen.activityItems)
        if stablePrefixCount == cachedActivityItems.count,
            screen.activityItems.count > cachedActivityItems.count
        {
            let appendedItems = Array(screen.activityItems.dropFirst(cachedActivityItems.count))
            let appendedRows = annotateStructuredSessionActivityRows(
                rowBuilder(appendedItems),
                providerDisplayName: providerDisplayName
            )
            cachedActivityItems = screen.activityItems
            cachedActivityRows.append(contentsOf: appendedRows)
            cachedActivityRowChunks = appendStructuredSessionActivityRowChunks(
                cachedActivityRowChunks,
                rows: appendedRows,
                liveTailChunkSize: liveTailChunkSize
            )
            activityRowIncrementalAppendCount += 1
            return cachedActivityRows
        }

        if stablePrefixCount > 0 {
            return rebuildAffectedTailRows(
                for: screen.activityItems,
                stablePrefixCount: stablePrefixCount,
                providerDisplayName: providerDisplayName
            )
        }

        return rebuildActivityRows(
            for: screen.activityItems,
            sessionID: screen.session.id,
            providerDisplayName: providerDisplayName
        )
    }

    @discardableResult
    private func rebuildAffectedTailRows(
        for activityItems: [SessionActivityItem],
        stablePrefixCount: Int,
        providerDisplayName: String
    ) -> [StructuredSessionActivityRow] {
        let rebuildStartIndex = structuredSessionActivityRowChunkStartIndex(
            for: stablePrefixCount,
            cachedChunks: cachedActivityRowChunks
        )
        let rebuiltRows = annotateStructuredSessionActivityRows(
            rowBuilder(Array(activityItems.dropFirst(rebuildStartIndex))),
            providerDisplayName: providerDisplayName
        )
        let preservedRows = Array(cachedActivityRows.prefix(rebuildStartIndex))
        let rebuiltChunks = structuredSessionActivityRowChunks(
            for: rebuiltRows,
            chunkSize: chunkSize,
            liveTailChunkSize: liveTailChunkSize
        ).map { chunk in
            StructuredSessionActivityRowChunk(id: chunk.id + rebuildStartIndex, rows: chunk.rows)
        }

        cachedActivityItems = activityItems
        cachedActivityRows = preservedRows + rebuiltRows
        cachedActivityRowChunks = Array(cachedActivityRowChunks.prefix { $0.id < rebuildStartIndex }) + rebuiltChunks
        activityRowTailRebuildCount += 1
        return cachedActivityRows
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
        cachedActivityRowChunks = structuredSessionActivityRowChunks(
            for: rows,
            chunkSize: chunkSize,
            liveTailChunkSize: liveTailChunkSize
        )
        structuredSessionPrewarmAssistantMarkdownCache(for: rows, providerDisplayName: providerDisplayName)
        activityRowFullRebuildCount += 1
        return rows
    }

    private func presentedFeedState(
        for screen: SessionScreen,
        baseRows: [StructuredSessionActivityRow]
    ) -> (rows: [StructuredSessionActivityRow], chunks: [StructuredSessionActivityRowChunk]) {
        let currentActivityItemIDs = Set(screen.activityItems.map(\.id))
        presentedRowIDByActivityItemID = presentedRowIDByActivityItemID.filter {
            currentActivityItemIDs.contains($0.key)
        }

        var liveDraftRow: StructuredSessionActivityRow?
        if structuredSessionAgentTurnFeedSegments(for: screen) != nil {
            liveAssistantDraft = nil
            liveDraftRow = nil
        } else if let draftText = structuredSessionLiveAssistantDraftText(for: screen) {
            let rowID = liveAssistantDraft?.rowID ?? UUID()
            liveAssistantDraft = LiveAssistantDraftState(rowID: rowID, text: draftText)
            liveDraftRow = structuredSessionLiveAssistantDraftRow(
                id: rowID,
                text: draftText,
                providerDisplayName: screen.session.providerID.displayName
            )
        } else {
            if let liveAssistantDraft,
                let finalizedItem = screen.activityItems.reversed().first(where: {
                    $0.kind == .message
                        && structuredSessionDraftMatchesFinalizedMessage(
                            draftText: liveAssistantDraft.text, finalizedText: $0.text)
                })
            {
                presentedRowIDByActivityItemID[finalizedItem.id] = liveAssistantDraft.rowID
            }
            self.liveAssistantDraft = nil
            liveDraftRow = nil
        }

        var rows = baseRows.map { row in
            guard let presentedRowID = presentedRowIDByActivityItemID[row.id] else {
                return row
            }
            return structuredSessionActivityRow(row, replacingIDWith: presentedRowID)
        }

        var chunks = cachedActivityRowChunks
        if presentedRowIDByActivityItemID.isEmpty == false {
            chunks = chunks.map { chunk in
                StructuredSessionActivityRowChunk(
                    id: chunk.id,
                    rows: chunk.rows.map { row in
                        guard let presentedRowID = presentedRowIDByActivityItemID[row.id] else {
                            return row
                        }
                        return structuredSessionActivityRow(row, replacingIDWith: presentedRowID)
                    }
                )
            }
        }

        if let liveDraftRow {
            rows.append(liveDraftRow)
            chunks = structuredSessionChunksByUpdatingLiveDraftRow(
                chunks,
                liveDraftRow: liveDraftRow,
                liveTailChunkSize: liveTailChunkSize
            )
        }

        return (rows, chunks)
    }
}

private func structuredSessionChunksByUpdatingLiveDraftRow(
    _ chunks: [StructuredSessionActivityRowChunk],
    liveDraftRow: StructuredSessionActivityRow,
    liveTailChunkSize: Int
) -> [StructuredSessionActivityRowChunk] {
    if let lastChunkIndex = chunks.indices.last,
        let rowIndex = chunks[lastChunkIndex].rows.firstIndex(where: { $0.id == liveDraftRow.id })
    {
        var updatedRows = chunks[lastChunkIndex].rows
        updatedRows[rowIndex] = liveDraftRow
        var updatedChunks = chunks
        updatedChunks[lastChunkIndex] = StructuredSessionActivityRowChunk(
            id: chunks[lastChunkIndex].id,
            rows: updatedRows
        )
        return updatedChunks
    }

    return appendStructuredSessionActivityRowChunks(
        chunks,
        rows: [liveDraftRow],
        liveTailChunkSize: liveTailChunkSize
    )
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
        let plainText = TerminalEscapeSequences.stripForPlainDisplay(item.text)
        let plainDetailText = item.detailText.map { TerminalEscapeSequences.stripForPlainDisplay($0) }
        let detailPreview = plainDetailText.map { structuredSessionDetailTextPreview(for: $0) }

        return StructuredSessionActivityRow(
            id: item.id,
            title: structuredSessionActivityTitle(for: item.kind),
            systemImage: structuredSessionActivitySystemImage(for: item.kind),
            text: plainText,
            detailText: detailPreview?.text,
            isDetailTextTruncated: detailPreview?.isTruncated ?? false,
            emphasis: structuredSessionActivityEmphasis(for: item.kind)
        )
    }
}

private func structuredSessionActivityRow(
    _ row: StructuredSessionActivityRow,
    replacingIDWith id: UUID
) -> StructuredSessionActivityRow {
    StructuredSessionActivityRow(
        id: id,
        title: row.title,
        systemImage: row.systemImage,
        text: row.text,
        detailText: row.detailText,
        isDetailTextTruncated: row.isDetailTextTruncated,
        emphasis: row.emphasis,
        conversationPresentation: row.conversationPresentation,
        showsExpandedSystemCard: row.showsExpandedSystemCard
    )
}

private func structuredSessionLiveAssistantDraftRow(
    id: UUID,
    text: String,
    providerDisplayName: String
) -> StructuredSessionActivityRow {
    let baseRow = StructuredSessionActivityRow(
        id: id,
        title: "Message",
        systemImage: structuredSessionActivitySystemImage(for: .message),
        text: text,
        emphasis: structuredSessionActivityEmphasis(for: .message)
    )
    let conversation = structuredSessionConversationPresentation(
        for: baseRow,
        providerDisplayName: providerDisplayName
    )

    return StructuredSessionActivityRow(
        id: baseRow.id,
        title: baseRow.title,
        systemImage: baseRow.systemImage,
        text: baseRow.text,
        detailText: baseRow.detailText,
        isDetailTextTruncated: baseRow.isDetailTextTruncated,
        emphasis: baseRow.emphasis,
        conversationPresentation: StructuredSessionConversationPresentation(
            role: conversation.role,
            text: conversation.text,
            isStreaming: true
        ),
        showsExpandedSystemCard: baseRow.showsExpandedSystemCard
    )
}

private func structuredSessionLiveAssistantDraftText(for screen: SessionScreen) -> String? {
    guard screen.isAgentTurnInProgress else {
        return nil
    }

    switch screen.session.providerID {
    case .pi:
        if let text = screen.providerFacts.liveAssistantDraftText {
            return "Pi: \(text)"
        }
        guard let text = piStructuredSessionLiveAssistantDraftText(from: screen.providerEvents) else {
            return nil
        }
        return "Pi: \(text)"
    case .codex, .ibmBob, .claude:
        return nil
    }
}

private func piStructuredSessionLiveAssistantDraftText(from providerEvents: [SessionProviderEvent]) -> String? {
    var draft = ""

    for event in providerEvents {
        guard let payload = structuredSessionJSONObject(from: event.rawPayload),
            let type = structuredSessionTrimmedString(in: payload, keys: ["type"])
        else {
            continue
        }

        switch type {
        case "message_update":
            guard let assistantMessageEvent = payload["assistantMessageEvent"] as? [String: Any],
                structuredSessionTrimmedString(in: assistantMessageEvent, keys: ["type"]) == "text_delta",
                let delta = assistantMessageEvent["delta"] as? String
            else {
                continue
            }
            draft += delta
        case "turn_end":
            draft = ""
        case "message_end":
            if let message = payload["message"] as? [String: Any],
                structuredSessionTrimmedString(in: message, keys: ["role"]) == "assistant"
            {
                draft = ""
            }
        default:
            continue
        }
    }

    let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedDraft.isEmpty ? nil : trimmedDraft
}

private func structuredSessionDraftMatchesFinalizedMessage(draftText: String, finalizedText: String) -> Bool {
    let normalizedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedFinalized = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedDraft.isEmpty == false, normalizedFinalized.isEmpty == false else {
        return false
    }
    return normalizedFinalized.hasPrefix(normalizedDraft)
}

private let structuredSessionActivityRowChunkSize = 40
private let structuredSessionLiveTailActivityRowChunkSize = 8

/// macOS structured feed startup: one row per sealed chunk so `LazyVStack` does not eager-layout 96 rows inside a `VStack` (#225).
private let structuredSessionMacOSActivityRowChunkSize = 1
private let structuredSessionMacOSLiveTailActivityRowChunkSize = 16

var structuredSessionDefaultActivityRowChunkSize: Int {
    #if os(macOS)
        structuredSessionMacOSActivityRowChunkSize
    #else
        structuredSessionActivityRowChunkSize
    #endif
}

var structuredSessionDefaultLiveTailActivityRowChunkSize: Int {
    #if os(macOS)
        structuredSessionMacOSLiveTailActivityRowChunkSize
    #else
        structuredSessionLiveTailActivityRowChunkSize
    #endif
}

func structuredSessionActivityRowChunks(
    for activityRows: [StructuredSessionActivityRow],
    chunkSize: Int = structuredSessionDefaultActivityRowChunkSize,
    liveTailChunkSize: Int = structuredSessionDefaultLiveTailActivityRowChunkSize
) -> [StructuredSessionActivityRowChunk] {
    guard activityRows.isEmpty == false else {
        return []
    }

    let normalizedChunkSize = max(1, chunkSize)
    let normalizedLiveTailChunkSize = max(1, min(liveTailChunkSize, normalizedChunkSize))
    let sealedRowCount = (activityRows.count / normalizedChunkSize) * normalizedChunkSize

    var chunks: [StructuredSessionActivityRowChunk] = []
    var startIndex = 0

    while startIndex < sealedRowCount {
        let endIndex = startIndex + normalizedChunkSize
        chunks.append(
            StructuredSessionActivityRowChunk(
                id: startIndex,
                rows: Array(activityRows[startIndex..<endIndex])
            ))
        startIndex = endIndex
    }

    while startIndex < activityRows.count {
        let endIndex = min(startIndex + normalizedLiveTailChunkSize, activityRows.count)
        chunks.append(
            StructuredSessionActivityRowChunk(
                id: startIndex,
                rows: Array(activityRows[startIndex..<endIndex])
            ))
        startIndex = endIndex
    }

    return chunks
}

private func structuredSessionCommonPrefixCount<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
    var count = 0

    for (lhsItem, rhsItem) in zip(lhs, rhs) {
        guard lhsItem == rhsItem else {
            break
        }
        count += 1
    }

    return count
}

private func structuredSessionActivityRowChunkStartIndex(
    for rowIndex: Int,
    cachedChunks: [StructuredSessionActivityRowChunk]
) -> Int {
    for chunk in cachedChunks.reversed() {
        let upperBound = chunk.id + chunk.rows.count
        if rowIndex >= chunk.id && rowIndex < upperBound {
            return chunk.id
        }
    }

    return rowIndex
}

private func appendStructuredSessionActivityRowChunks(
    _ chunks: [StructuredSessionActivityRowChunk],
    rows: [StructuredSessionActivityRow],
    liveTailChunkSize: Int
) -> [StructuredSessionActivityRowChunk] {
    guard rows.isEmpty == false else {
        return chunks
    }

    let normalizedLiveTailChunkSize = max(1, liveTailChunkSize)
    var updatedChunks = chunks
    var remainingRows = ArraySlice(rows)

    if let lastChunk = updatedChunks.last, lastChunk.rows.count < normalizedLiveTailChunkSize {
        let appendedCount = min(normalizedLiveTailChunkSize - lastChunk.rows.count, remainingRows.count)
        updatedChunks[updatedChunks.count - 1] = StructuredSessionActivityRowChunk(
            id: lastChunk.id,
            rows: lastChunk.rows + remainingRows.prefix(appendedCount)
        )
        remainingRows = remainingRows.dropFirst(appendedCount)
    }

    var nextChunkID = updatedChunks.last.map { $0.id + $0.rows.count } ?? 0
    while remainingRows.isEmpty == false {
        let chunkRows = Array(remainingRows.prefix(normalizedLiveTailChunkSize))
        updatedChunks.append(StructuredSessionActivityRowChunk(id: nextChunkID, rows: chunkRows))
        nextChunkID += chunkRows.count
        remainingRows = remainingRows.dropFirst(chunkRows.count)
    }

    return updatedChunks
}

private func structuredSessionFeedPresentation(
    for screen: SessionScreen,
    activityRows: [StructuredSessionActivityRow],
    activityRowChunks: [StructuredSessionActivityRowChunk]? = nil
) -> StructuredSessionFeedPresentation {
    let pendingApprovalRequests = screen.approvalRequests.filter { $0.state == .pending }
    return StructuredSessionFeedPresentation(
        copy: structuredSessionPresentationCopy(for: screen),
        activityRows: activityRows,
        activityRowChunks: activityRowChunks,
        feedSegments: structuredSessionAgentTurnFeedSegments(for: screen),
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

    public init(
        lastActivityRowID: UUID?,
        pendingApprovalRequestIDs: [UUID],
        pendingDialogIDs: [String]
    ) {
        self.lastActivityRowID = lastActivityRowID
        self.pendingApprovalRequestIDs = pendingApprovalRequestIDs
        self.pendingDialogIDs = pendingDialogIDs
    }
}

public enum StructuredSessionAutoScrollAnimation: Equatable {
    case immediate
    case animated
}

/// Coalesces bursty bottom-scroll requests onto the next scheduled UI turn.
public final class StructuredSessionAutoScrollCoordinator: @unchecked Sendable {
    private let schedule: (@escaping @Sendable () -> Void) -> Void
    private var hasScheduledFlush = false
    private var pendingScroll: (() -> Void)?

    public init(
        schedule: @escaping (@escaping @Sendable () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        self.schedule = schedule
    }

    public func request(
        _ animation: StructuredSessionAutoScrollAnimation,
        perform: @escaping (StructuredSessionAutoScrollAnimation) -> Void
    ) {
        pendingScroll = {
            perform(animation)
        }

        guard hasScheduledFlush == false else {
            return
        }

        hasScheduledFlush = true
        schedule { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        hasScheduledFlush = false
        let pendingScroll = pendingScroll
        self.pendingScroll = nil
        pendingScroll?()
    }
}

public func structuredSessionAutoScrollAnimation(
    previous: StructuredSessionAutoScrollTrigger,
    current: StructuredSessionAutoScrollTrigger
) -> StructuredSessionAutoScrollAnimation {
    if previous.lastActivityRowID != current.lastActivityRowID {
        return .immediate
    }

    return .animated
}

public let structuredSessionFeedBottomSentinelID = "conversation-bottom"

public enum StructuredSessionFeedScrollTarget: Equatable {
    case activityRow(UUID)
    case bottomSentinel

    public var scrollTargetID: AnyHashable {
        switch self {
        case .activityRow(let id):
            return id
        case .bottomSentinel:
            return structuredSessionFeedBottomSentinelID
        }
    }
}

/// Inputs for bottom-scroll policy separate from raw `StructuredSessionAutoScrollTrigger` churn.
public struct StructuredSessionFeedScrollSnapshot: Equatable {
    public let feedScrollTarget: StructuredSessionFeedScrollTarget
    public let autoScrollTrigger: StructuredSessionAutoScrollTrigger
    /// Non-nil while a live assistant draft row is visible; changes when draft text grows.
    public let liveDraftGrowthToken: String?
    /// While **Thinking…** is shown (`isAgentTurnInProgress`); disables bottom-edge binding and programmatic tail scroll.
    public let suppressesProgrammaticBottomScroll: Bool

    public init(
        feedScrollTarget: StructuredSessionFeedScrollTarget,
        autoScrollTrigger: StructuredSessionAutoScrollTrigger,
        liveDraftGrowthToken: String?,
        suppressesProgrammaticBottomScroll: Bool = false
    ) {
        self.feedScrollTarget = feedScrollTarget
        self.autoScrollTrigger = autoScrollTrigger
        self.liveDraftGrowthToken = liveDraftGrowthToken
        self.suppressesProgrammaticBottomScroll = suppressesProgrammaticBottomScroll
    }
}

public enum StructuredSessionBottomScrollIntent: Equatable {
    case none
    case immediate
    case animated
    case draftGrowthCoalesced
}

/// Coarse draft-length bucket for scroll policy (#224). Small per-tick text deltas during streaming
/// should not change scroll snapshots and force bottom scroll + layout on every provider event.
public func structuredSessionLiveDraftScrollGrowthToken(for draftText: String) -> String {
    let bucket = max(0, draftText.count) / 96
    return "bucket-\(bucket)"
}

public func structuredSessionBottomScrollIntent(
    previous: StructuredSessionFeedScrollSnapshot,
    current: StructuredSessionFeedScrollSnapshot,
    isPinnedToBottom: Bool
) -> StructuredSessionBottomScrollIntent {
    guard isPinnedToBottom else {
        return .none
    }

    if current.suppressesProgrammaticBottomScroll {
        return .none
    }

    if previous.autoScrollTrigger.lastActivityRowID != current.autoScrollTrigger.lastActivityRowID {
        if previous.feedScrollTarget == current.feedScrollTarget,
            case .activityRow = current.feedScrollTarget
        {
            return .none
        }
        return .immediate
    }

    if previous.autoScrollTrigger.pendingApprovalRequestIDs != current.autoScrollTrigger.pendingApprovalRequestIDs
        || previous.autoScrollTrigger.pendingDialogIDs != current.autoScrollTrigger.pendingDialogIDs
    {
        return .animated
    }

    if previous.liveDraftGrowthToken != nil,
        current.liveDraftGrowthToken != nil,
        previous.feedScrollTarget == current.feedScrollTarget,
        previous.liveDraftGrowthToken != current.liveDraftGrowthToken
    {
        return .draftGrowthCoalesced
    }

    return .none
}

public func structuredSessionShouldRequestBottomScroll(
    previous: StructuredSessionFeedScrollSnapshot,
    current: StructuredSessionFeedScrollSnapshot,
    isPinnedToBottom: Bool
) -> Bool {
    structuredSessionBottomScrollIntent(previous: previous, current: current, isPinnedToBottom: isPinnedToBottom)
        != .none
}

/// Returns nil when scroll-policy inputs are unchanged — avoids `@State` churn from recomputed snapshots.
public func structuredSessionFeedScrollSnapshotIfScrollPolicyChanged(
    previous: StructuredSessionFeedScrollSnapshot?,
    current: StructuredSessionFeedScrollSnapshot
) -> StructuredSessionFeedScrollSnapshot? {
    guard let previous else {
        return current
    }
    return previous == current ? nil : current
}

public func structuredSessionAutoScrollAnimation(
    for intent: StructuredSessionBottomScrollIntent
) -> StructuredSessionAutoScrollAnimation? {
    switch intent {
    case .none:
        return nil
    case .immediate, .draftGrowthCoalesced:
        return .immediate
    case .animated:
        return .animated
    }
}

/// Distance from the scroll content bottom to the visible viewport bottom (points). Zero when flush with bottom.
public func structuredSessionIsPinnedToBottomFromBottomDistance(
    _ distanceFromBottom: CGFloat,
    pinThreshold: CGFloat = 48
) -> Bool {
    distanceFromBottom <= pinThreshold
}

/// Scroll metrics sampled from `ScrollView` geometry for pin/follow policy.
public struct StructuredSessionScrollGeometrySample: Equatable {
    public let distanceFromBottom: CGFloat
    public let contentOffsetY: CGFloat

    public init(distanceFromBottom: CGFloat, contentOffsetY: CGFloat) {
        self.distanceFromBottom = distanceFromBottom
        self.contentOffsetY = contentOffsetY
    }
}

/// Tracks whether the feed should keep following new tail content vs the user reading history.
public struct StructuredSessionFeedPinState: Equatable {
    public var isFollowingBottom: Bool
    /// User scrolled away from the bottom (not merely content growing while offset stayed at top).
    public var userHasDetachedFromBottom: Bool

    public init(isFollowingBottom: Bool = true, userHasDetachedFromBottom: Bool = false) {
        self.isFollowingBottom = isFollowingBottom
        self.userHasDetachedFromBottom = userHasDetachedFromBottom
    }
}

public func structuredSessionFeedPinState(
    previous: StructuredSessionFeedPinState,
    distanceFromBottom: CGFloat,
    contentOffsetY: CGFloat,
    pinThreshold: CGFloat = 48,
    topContentOffsetTolerance: CGFloat = 8
) -> StructuredSessionFeedPinState {
    structuredSessionFeedPinState(
        previous: previous,
        sample: StructuredSessionScrollGeometrySample(
            distanceFromBottom: distanceFromBottom,
            contentOffsetY: contentOffsetY
        ),
        pinThreshold: pinThreshold,
        topContentOffsetTolerance: topContentOffsetTolerance
    )
}

public func structuredSessionFeedPinState(
    previous: StructuredSessionFeedPinState,
    sample: StructuredSessionScrollGeometrySample,
    pinThreshold: CGFloat = 48,
    topContentOffsetTolerance: CGFloat = 8
) -> StructuredSessionFeedPinState {
    if sample.distanceFromBottom <= pinThreshold {
        return StructuredSessionFeedPinState(isFollowingBottom: true, userHasDetachedFromBottom: false)
    }

    // Content grew (or first layout) while the scroll offset is still at the top — keep following.
    if sample.contentOffsetY <= topContentOffsetTolerance {
        return StructuredSessionFeedPinState(
            isFollowingBottom: previous.userHasDetachedFromBottom == false,
            userHasDetachedFromBottom: previous.userHasDetachedFromBottom
        )
    }

    return StructuredSessionFeedPinState(isFollowingBottom: false, userHasDetachedFromBottom: true)
}

/// Returns nil when pin state is unchanged — avoids `@State` churn from scroll geometry (expensive updates on main).
public func structuredSessionFeedPinStateIfChanged(
    previous: StructuredSessionFeedPinState,
    sample: StructuredSessionScrollGeometrySample,
    pinThreshold: CGFloat = 48,
    topContentOffsetTolerance: CGFloat = 8
) -> StructuredSessionFeedPinState? {
    let next = structuredSessionFeedPinState(
        previous: previous,
        sample: sample,
        pinThreshold: pinThreshold,
        topContentOffsetTolerance: topContentOffsetTolerance
    )
    return next == previous ? nil : next
}

public func structuredSessionRequestBottomScroll(
    intent: StructuredSessionBottomScrollIntent,
    coordinator: StructuredSessionAutoScrollCoordinator,
    draftGrowthThrottle: StructuredSessionDraftGrowthScrollThrottle,
    performScroll: @escaping (StructuredSessionAutoScrollAnimation) -> Void
) {
    guard let animation = structuredSessionAutoScrollAnimation(for: intent) else {
        return
    }

    switch intent {
    case .none:
        return
    case .draftGrowthCoalesced:
        draftGrowthThrottle.requestIfDue {
            coordinator.request(animation, perform: performScroll)
        }
    case .immediate, .animated:
        coordinator.request(animation, perform: performScroll)
    }
}

/// Buckets rapid live-draft growth scroll cues (~100–150ms) while pinned to bottom.
public final class StructuredSessionDraftGrowthScrollThrottle: @unchecked Sendable {
    private let minimumInterval: TimeInterval
    private let now: () -> TimeInterval
    private var lastPerformedAt: TimeInterval?

    public init(
        minimumInterval: TimeInterval = 0.12,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.minimumInterval = minimumInterval
        self.now = now
    }

    @discardableResult
    public func requestIfDue(_ perform: () -> Void) -> Bool {
        let current = now()
        if let lastPerformedAt,
            current - lastPerformedAt < minimumInterval
        {
            return false
        }
        lastPerformedAt = current
        perform()
        return true
    }
}

public func structuredSessionPresentationCopy(for screen: SessionScreen) -> StructuredSessionPresentationCopy {
    structuredSessionPresentationCopy(providerDisplayName: screen.session.providerID.displayName)
}

private func structuredSessionPresentationCopy(providerDisplayName: String) -> StructuredSessionPresentationCopy {
    StructuredSessionPresentationCopy(
        emptyStateTitle: "No Session activity yet",
        emptyStateDescription: "Send a prompt to start the \(providerDisplayName) Session.",
        composerPlaceholder: "Send a prompt to \(providerDisplayName)"
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
    guard structuredSessionEffectiveAgentTurnInProgress(for: screen),
        hasPendingApprovalRequests == false
    else {
        return nil
    }

    return StructuredSessionThinkingIndicator(text: "Thinking…")
}

public func structuredSessionComposerPresentation(
    for screen: SessionScreen,
    hasWriterAuthority: Bool
) -> StructuredSessionComposerPresentation {
    structuredSessionComposerPresentation(
        providerDisplayName: screen.session.providerID.displayName,
        hasWriterAuthority: hasWriterAuthority
    )
}

public func structuredSessionComposerPresentation(
    for chrome: FocusedStructuredSessionChromePresentation,
    hasWriterAuthority: Bool
) -> StructuredSessionComposerPresentation {
    structuredSessionComposerPresentation(
        providerDisplayName: chrome.session.providerID.displayName,
        hasWriterAuthority: hasWriterAuthority
    )
}

private func structuredSessionComposerPresentation(
    providerDisplayName: String,
    hasWriterAuthority: Bool
) -> StructuredSessionComposerPresentation {
    let copy = structuredSessionPresentationCopy(providerDisplayName: providerDisplayName)
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

public func structuredSessionStatusBarPresentation(
    for chrome: FocusedStructuredSessionChromePresentation,
    workspaceLocation: String
) -> StructuredSessionStatusBarPresentation {
    StructuredSessionStatusBarPresentation(
        workspaceLocation: workspaceLocation,
        tokenUsage: chrome.tokenUsage
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

public final class StructuredSessionTokenUsagePresenter {
    private let providerEventUsageParser: (SessionProviderEvent) -> StructuredSessionTokenUsagePresentation?
    private let activityItemUsageParser: (SessionActivityItem) -> StructuredSessionTokenUsagePresentation?
    private let inferredContextWindowResolver: (SessionScreen) -> Int?

    private var cachedSessionID: UUID?
    private var cachedProviderEvents: [SessionProviderEvent] = []
    private var cachedProviderEventUsage: StructuredSessionTokenUsagePresentation?
    private var cachedActivityItems: [SessionActivityItem] = []
    private var cachedActivityItemUsage: StructuredSessionTokenUsagePresentation?

    public init() {
        self.providerEventUsageParser = structuredSessionTokenUsagePresentation(from:)
        self.activityItemUsageParser = structuredSessionTokenUsagePresentation(from:)
        self.inferredContextWindowResolver = inferredStructuredSessionContextWindow(for:)
    }

    init(
        providerEventUsageParser: @escaping (SessionProviderEvent) -> StructuredSessionTokenUsagePresentation?,
        activityItemUsageParser: @escaping (SessionActivityItem) -> StructuredSessionTokenUsagePresentation?,
        inferredContextWindowResolver: @escaping (SessionScreen) -> Int?
    ) {
        self.providerEventUsageParser = providerEventUsageParser
        self.activityItemUsageParser = activityItemUsageParser
        self.inferredContextWindowResolver = inferredContextWindowResolver
    }

    public func presentation(for screen: SessionScreen) -> StructuredSessionTokenUsagePresentation? {
        if let usage = screen.providerFacts.tokenUsage {
            resetCache(for: screen.session.id)
            return StructuredSessionTokenUsagePresentation(
                usedTokens: usage.usedTokens,
                totalTokens: usage.totalTokens,
                percent: usage.percent
            )
        }

        if cachedSessionID != screen.session.id {
            resetCache(for: screen.session.id)
        }

        if let usage = resolveProviderEventUsage(from: screen.providerEvents) {
            return usage
        }

        if let usage = resolveActivityItemUsage(from: screen.activityItems) {
            return usage
        }

        guard let inferredContextWindow = inferredContextWindowResolver(screen) else {
            return nil
        }

        return StructuredSessionTokenUsagePresentation(
            usedTokens: 0,
            totalTokens: inferredContextWindow,
            percent: 0
        )
    }

    private func resetCache(for sessionID: UUID) {
        cachedSessionID = sessionID
        cachedProviderEvents = []
        cachedProviderEventUsage = nil
        cachedActivityItems = []
        cachedActivityItemUsage = nil
    }

    private func resolveProviderEventUsage(
        from providerEvents: [SessionProviderEvent]
    ) -> StructuredSessionTokenUsagePresentation? {
        if providerEvents == cachedProviderEvents {
            return cachedProviderEventUsage
        }

        if structuredSessionIsAppendOnlyUpdate(cachedProviderEvents, newItems: providerEvents) {
            for event in providerEvents.suffix(providerEvents.count - cachedProviderEvents.count).reversed() {
                if let usage = providerEventUsageParser(event) {
                    cachedProviderEvents = providerEvents
                    cachedProviderEventUsage = usage
                    return usage
                }
            }

            cachedProviderEvents = providerEvents
            return cachedProviderEventUsage
        }

        cachedProviderEvents = providerEvents
        cachedProviderEventUsage = nil
        for event in providerEvents.reversed() {
            if let usage = providerEventUsageParser(event) {
                cachedProviderEventUsage = usage
                return usage
            }
        }

        return nil
    }

    private func resolveActivityItemUsage(
        from activityItems: [SessionActivityItem]
    ) -> StructuredSessionTokenUsagePresentation? {
        if activityItems == cachedActivityItems {
            return cachedActivityItemUsage
        }

        if structuredSessionIsAppendOnlyUpdate(cachedActivityItems, newItems: activityItems) {
            for item in activityItems.suffix(activityItems.count - cachedActivityItems.count).reversed() {
                if let usage = activityItemUsageParser(item) {
                    cachedActivityItems = activityItems
                    cachedActivityItemUsage = usage
                    return usage
                }
            }

            cachedActivityItems = activityItems
            return cachedActivityItemUsage
        }

        cachedActivityItems = activityItems
        cachedActivityItemUsage = nil
        for item in activityItems.reversed() {
            if let usage = activityItemUsageParser(item) {
                cachedActivityItemUsage = usage
                return usage
            }
        }

        return nil
    }
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

private func structuredSessionAssistantMarkdownRenderTexts(
    for rows: [StructuredSessionActivityRow],
    providerDisplayName: String
) -> [String] {
    var texts: [String] = []
    texts.reserveCapacity(rows.count)

    for row in rows {
        guard row.conversationPresentation?.isStreaming != true else {
            continue
        }
        let conversation =
            row.conversationPresentation
            ?? structuredSessionConversationPresentation(for: row, providerDisplayName: providerDisplayName)
        guard case .assistant = conversation.role else {
            continue
        }
        let body = conversation.text
        if structuredSessionShouldCollapseStreamingMarkdownPreview(body, charactersPerLine: 72) {
            texts.append(structuredSessionFeedAssistantMarkdownBoundedPreviewText(for: body))
        } else {
            texts.append(body)
        }
    }

    return texts
}

private func structuredSessionPrewarmAssistantMarkdownCache(
    for rows: [StructuredSessionActivityRow],
    providerDisplayName: String
) {
    guard #available(macOS 12.0, iOS 15.0, *) else {
        return
    }
    #if os(macOS)
        // Row onAppear hydration owns first paint; bulk prewarm contended with utility parse + main-thread flushes (#225).
        return
    #else
        let renderTexts = structuredSessionAssistantMarkdownRenderTexts(
            for: rows,
            providerDisplayName: providerDisplayName
        )
        guard renderTexts.isEmpty == false else {
            return
        }
        StructuredSessionAssistantMarkdownPrewarmScheduler.schedule(renderTexts: renderTexts)
    #endif
}

/// Defers markdown parse/typeset off the main thread during first structured feed paint (#225).
@available(macOS 12.0, iOS 15.0, *)
public enum StructuredSessionAssistantMarkdownPrewarmScheduler {
    private actor Queue {
        var pendingRenderTexts: [[String]] = []
        var isDraining = false

        func enqueue(_ renderTexts: [String]) -> Bool {
            pendingRenderTexts.append(renderTexts)
            guard isDraining == false else {
                return false
            }
            isDraining = true
            return true
        }

        func dequeueBatch() -> [[String]] {
            let batch = pendingRenderTexts
            pendingRenderTexts = []
            return batch
        }

        func markIdleIfEmpty() -> Bool {
            guard pendingRenderTexts.isEmpty else {
                return false
            }
            isDraining = false
            return true
        }

        func waitUntilIdle() async {
            while isDraining || pendingRenderTexts.isEmpty == false {
                await Task.yield()
            }
        }
    }

    private static let queue = Queue()

    static func schedule(renderTexts: [String]) {
        Task.detached(priority: .utility) {
            let shouldStartDrain = await queue.enqueue(renderTexts)
            guard shouldStartDrain else {
                return
            }
            await drainUntilIdle()
        }
    }

    private static func drainUntilIdle() async {
        while true {
            let batch = await queue.dequeueBatch()
            guard batch.isEmpty == false else {
                _ = await queue.markIdleIfEmpty()
                return
            }

            renderPrewarmBatch(batch)
        }
    }

    private static func renderPrewarmBatch(_ batch: [[String]]) {
        for texts in batch {
            for text in texts {
                _ = StructuredSessionMarkdownRenderer.shared.renderContent(text)
            }
        }
    }

    /// Waits until scheduled prewarm work finishes; for tests only.
    public static func drainForTesting() async {
        await queue.waitUntilIdle()
    }
}

func annotateStructuredSessionActivityRows(
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
                ?? structuredSessionConversationPresentation(for: row, providerDisplayName: providerDisplayName),
            showsExpandedSystemCard: row.showsExpandedSystemCard
        )
    }
}

public func structuredSessionSlashCommandMenuPresentation(
    for draft: String,
    screen: SessionScreen
) -> StructuredSessionSlashCommandMenuPresentation {
    structuredSessionSlashCommandMenuPresentation(
        for: draft,
        commands: structuredSessionSlashCommands(for: screen)
    )
}

public func structuredSessionSlashCommandMenuPresentation(
    for draft: String,
    chrome: FocusedStructuredSessionChromePresentation
) -> StructuredSessionSlashCommandMenuPresentation {
    structuredSessionSlashCommandMenuPresentation(
        for: draft,
        commands: chrome.slashCommands
    )
}

private func structuredSessionSlashCommandMenuPresentation(
    for draft: String,
    commands: [StructuredSessionSlashCommand]
) -> StructuredSessionSlashCommandMenuPresentation {
    guard let context = structuredSessionSlashCommandContext(for: draft) else {
        return StructuredSessionSlashCommandMenuPresentation(isVisible: false, commands: [])
    }

    let normalizedQuery = context.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // Unlike normalizedQuery, this preserves a trailing space so suggestionQueryPrefix gates
    // (e.g. "model ") activate as soon as the prefix is typed, not after the next character.
    let suggestionQuery = context.query.lowercased()

    func passesSuggestionQueryPrefixGate(_ command: StructuredSessionSlashCommand) -> Bool {
        guard let requiredPrefix = command.suggestionQueryPrefix?.lowercased() else {
            return true
        }
        return suggestionQuery.hasPrefix(requiredPrefix)
    }

    // A command with no further argument suggestions has nothing left to show once its full
    // name is typed and a space follows it; hide it immediately rather than waiting for the
    // next keystroke. Commands that opt into acceptsArguments keep matching so their row can
    // stay visible while the user types free-form argument text.
    func hasNoFurtherSuggestionsAfterTrailingSpace(_ command: StructuredSessionSlashCommand) -> Bool {
        guard command.acceptsArguments == false, suggestionQuery.hasSuffix(" ") else {
            return false
        }
        return command.matchText.lowercased() == normalizedQuery
    }

    let prefixMatches = commands.filter { command in
        guard passesSuggestionQueryPrefixGate(command), hasNoFurtherSuggestionsAfterTrailingSpace(command) == false
        else {
            return false
        }
        let normalizedCommand = command.matchText.lowercased()
        if normalizedQuery.isEmpty || normalizedCommand.hasPrefix(normalizedQuery) {
            return true
        }
        return command.acceptsArguments && normalizedQuery.hasPrefix(normalizedCommand + " ")
    }

    let fallbackMatches =
        prefixMatches.isEmpty
        ? commands.filter { command in
            guard passesSuggestionQueryPrefixGate(command),
                hasNoFurtherSuggestionsAfterTrailingSpace(command) == false
            else {
                return false
            }
            let normalizedCommand = command.matchText.lowercased()
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
                StructuredSessionSlashCommand(
                    matchText: "model", displayText: "/model", insertionText: "/model",
                    summary: "Switch models or reasoning effort."),
                StructuredSessionSlashCommand(
                    matchText: "review", displayText: "/review", insertionText: "/review",
                    summary: "Review your current code changes."),
                StructuredSessionSlashCommand(
                    matchText: "status", displayText: "/status", insertionText: "/status",
                    summary: "Show the current model, approvals, and token usage."),
                StructuredSessionSlashCommand(
                    matchText: "new", displayText: "/new", insertionText: "/new", summary: "Start a new chat."),
                StructuredSessionSlashCommand(
                    matchText: "resume", displayText: "/resume", insertionText: "/resume",
                    summary: "Resume a saved chat."),
                StructuredSessionSlashCommand(
                    matchText: "fork", displayText: "/fork", insertionText: "/fork", summary: "Fork the current chat."),
                StructuredSessionSlashCommand(
                    matchText: "init", displayText: "/init", insertionText: "/init",
                    summary: "Create an AGENTS.md file with project guidance."),
                StructuredSessionSlashCommand(
                    matchText: "compact", displayText: "/compact", insertionText: "/compact",
                    summary: "Summarize the conversation to free context."),
                StructuredSessionSlashCommand(
                    matchText: "goal", displayText: "/goal <objective>", insertionText: "/goal ",
                    summary: "Set or view the goal for a long-running task.", acceptsArguments: true),
                StructuredSessionSlashCommand(
                    matchText: "side", displayText: "/side", insertionText: "/side",
                    summary: "Start a side conversation in an ephemeral fork."),
                StructuredSessionSlashCommand(
                    matchText: "copy", displayText: "/copy", insertionText: "/copy",
                    summary: "Copy the latest agent response as Markdown."),
                StructuredSessionSlashCommand(
                    matchText: "diff", displayText: "/diff", insertionText: "/diff",
                    summary: "Show the current git diff, including untracked files."),
                StructuredSessionSlashCommand(
                    matchText: "mcp", displayText: "/mcp", insertionText: "/mcp", summary: "List configured MCP tools."),
                StructuredSessionSlashCommand(
                    matchText: "ide", displayText: "/ide [on|off|status]", insertionText: "/ide ",
                    summary: "Control IDE context sharing.", acceptsArguments: true),
                StructuredSessionSlashCommand(
                    matchText: "keymap", displayText: "/keymap", insertionText: "/keymap",
                    summary: "Remap TUI shortcuts."),
                StructuredSessionSlashCommand(
                    matchText: "plugins", displayText: "/plugins", insertionText: "/plugins",
                    summary: "Browse and manage plugins."),
                StructuredSessionSlashCommand(
                    matchText: "clear", displayText: "/clear", insertionText: "/clear",
                    summary: "Clear the terminal and start a new chat."),
                StructuredSessionSlashCommand(
                    matchText: "quit", displayText: "/quit", insertionText: "/quit", summary: "Exit Codex."),
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
                ),
            ],
            liveCommands: (screen.slashCommands ?? []).map(structuredSessionSlashCommand(from:))
        )
    case .ibmBob:
        return mergeStructuredSessionSlashCommands(
            staticCommands: [
                StructuredSessionSlashCommand(
                    matchText: "help", displayText: "/help", insertionText: "/help",
                    summary: "Show available Bob commands."),
                StructuredSessionSlashCommand(
                    matchText: "editor", displayText: "/editor", insertionText: "/editor",
                    summary: "Configure your preferred editor."),
                StructuredSessionSlashCommand(
                    matchText: "memory show", displayText: "/memory show", insertionText: "/memory show",
                    summary: "View the current memory context."),
                StructuredSessionSlashCommand(
                    matchText: "memory refresh", displayText: "/memory refresh", insertionText: "/memory refresh",
                    summary: "Reload memory and context files."),
                StructuredSessionSlashCommand(
                    matchText: "restore", displayText: "/restore <checkpoint_file>", insertionText: "/restore ",
                    summary: "Restore a checkpoint.", acceptsArguments: true),
                StructuredSessionSlashCommand(
                    matchText: "ide enable", displayText: "/ide enable", insertionText: "/ide enable",
                    summary: "Enable IDE context integration."),
                StructuredSessionSlashCommand(
                    matchText: "ide disable", displayText: "/ide disable", insertionText: "/ide disable",
                    summary: "Disable IDE context integration."),
                StructuredSessionSlashCommand(
                    matchText: "ide status", displayText: "/ide status", insertionText: "/ide status",
                    summary: "Show IDE integration status."),
                StructuredSessionSlashCommand(
                    matchText: "ide install", displayText: "/ide install", insertionText: "/ide install",
                    summary: "Install the Bob IDE companion extension."),
                StructuredSessionSlashCommand(
                    matchText: "mode plan", displayText: "/mode plan", insertionText: "/mode plan",
                    summary: "Switch to Plan mode."),
                StructuredSessionSlashCommand(
                    matchText: "mode code", displayText: "/mode code", insertionText: "/mode code",
                    summary: "Switch to Code mode."),
                StructuredSessionSlashCommand(
                    matchText: "mode advanced", displayText: "/mode advanced", insertionText: "/mode advanced",
                    summary: "Switch to Advanced mode."),
                StructuredSessionSlashCommand(
                    matchText: "mode ask", displayText: "/mode ask", insertionText: "/mode ask",
                    summary: "Switch to Ask mode."),
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
    let summary =
        (trimmedDescription?.isEmpty == false ? trimmedDescription : nil)
        ?? structuredSessionSlashCommandSummaryFallback(for: command)

    let resolvedDisplayName = command.displayName ?? command.name
    let resolvedInsertionText = command.insertionText ?? command.name

    return StructuredSessionSlashCommand(
        matchText: command.name,
        displayText: "/\(resolvedDisplayName)\(locationSuffix)",
        insertionText: "/\(resolvedInsertionText)",
        summary: summary,
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
    if let usage = resolvedStructuredSessionTokenUsage(from: screen.providerFacts.tokenUsage) {
        return usage
    }

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

private func resolvedStructuredSessionTokenUsage(
    from usage: StructuredSessionProviderTokenUsage?
) -> StructuredSessionResolvedTokenUsage? {
    guard let usage else {
        return nil
    }

    return StructuredSessionResolvedTokenUsage(
        usedTokens: usage.usedTokens,
        totalTokens: usage.totalTokens,
        percent: usage.percent
    )
}

private func structuredSessionTokenUsage(from providerEvents: [SessionProviderEvent])
    -> StructuredSessionResolvedTokenUsage?
{
    for event in providerEvents.reversed() {
        if let usage = structuredSessionTokenUsage(from: event) {
            return usage
        }
    }
    return nil
}

private func structuredSessionTokenUsage(from event: SessionProviderEvent) -> StructuredSessionResolvedTokenUsage? {
    guard let payload = structuredSessionJSONObject(from: event.rawPayload),
        let usage = structuredSessionTokenUsage(from: payload)
    else {
        return nil
    }
    return usage
}

private func structuredSessionTokenUsage(from activityItems: [SessionActivityItem])
    -> StructuredSessionResolvedTokenUsage?
{
    for item in activityItems.reversed() {
        if let usage = structuredSessionTokenUsage(from: item) {
            return usage
        }
    }
    return nil
}

private func structuredSessionTokenUsage(from item: SessionActivityItem) -> StructuredSessionResolvedTokenUsage? {
    if let usage = structuredSessionTokenUsage(from: item.text) {
        return usage
    }
    if let detailText = item.detailText,
        let usage = structuredSessionTokenUsage(from: detailText)
    {
        return usage
    }
    return nil
}

private func structuredSessionTokenUsage(from value: Any) -> StructuredSessionResolvedTokenUsage? {
    switch value {
    case let object as [String: Any]:
        if let directUsage = directStructuredSessionTokenUsage(from: object) {
            return directUsage
        }

        let priorityKeys = [
            "contextUsage", "tokenUsage", "usage", "data", "result", "params", "context", "thread", "turn", "item",
            "message",
        ]
        for key in priorityKeys {
            if let nestedValue = object[key],
                let usage = structuredSessionTokenUsage(from: nestedValue)
            {
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
    let totalTokens = structuredSessionIntValue(
        in: object, keys: ["contextWindow", "context_window", "maxTokens", "max_tokens", "totalTokens", "total_tokens"])

    let explicitUsedTokens =
        structuredSessionIntValue(
            in: object, keys: ["tokens", "usedTokens", "used_tokens", "tokenCount", "token_count"])
        ?? structuredSessionSummedIntValue(
            in: object, keyPairs: [("inputTokens", "outputTokens"), ("input_tokens", "output_tokens")])
    let explicitPercent = structuredSessionIntValue(in: object, keys: ["percent", "usagePercent", "usage_percent"])

    guard let totalTokens else {
        return nil
    }

    let usedTokens =
        explicitUsedTokens ?? explicitPercent.map { max(0, Int((Double(totalTokens) * Double($0)) / 100.0)) }
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
        let percentRange = Range(match.range(at: 3), in: text)
    else {
        return nil
    }

    let usedText = text[usedRange].replacingOccurrences(of: ",", with: "")
    let totalText = text[totalRange].replacingOccurrences(of: ",", with: "")
    let percentText = text[percentRange]

    guard let usedTokens = Int(usedText),
        let totalTokens = Int(totalText),
        let percent = Int(percentText)
    else {
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
    if let modelIdentifier = screen.providerFacts.modelIdentifier {
        return modelIdentifier
    }

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
            let modelID = structuredSessionTrimmedString(in: model, keys: ["id"])
        else {
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
        let target =
            suffix.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
            ?? String(suffix)
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
            let model = structuredSessionTrimmedString(in: result, keys: ["model"])
        {
            return model
        }

        if let params = payload["params"] as? [String: Any],
            let model = structuredSessionTrimmedString(in: params, keys: ["model"])
        {
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

    if normalized.contains("claude") || normalized.contains("sonnet") || normalized.contains("haiku")
        || normalized.contains("opus")
    {
        return 200_000
    }

    return nil
}

private func structuredSessionJSONObject(from rawPayload: String) -> [String: Any]? {
    guard let data = rawPayload.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }

    return object
}

private func structuredSessionTokenUsagePresentation(
    from usage: StructuredSessionResolvedTokenUsage
) -> StructuredSessionTokenUsagePresentation {
    StructuredSessionTokenUsagePresentation(
        usedTokens: usage.usedTokens,
        totalTokens: usage.totalTokens,
        percent: usage.percent
    )
}

private func structuredSessionTokenUsagePresentation(
    from event: SessionProviderEvent
) -> StructuredSessionTokenUsagePresentation? {
    structuredSessionTokenUsage(from: event).map(structuredSessionTokenUsagePresentation(from:))
}

private func structuredSessionTokenUsagePresentation(
    from item: SessionActivityItem
) -> StructuredSessionTokenUsagePresentation? {
    structuredSessionTokenUsage(from: item).map(structuredSessionTokenUsagePresentation(from:))
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
            let rhsValue = structuredSessionCoerceInt(object[rhs])
        {
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

private func structuredSessionIsAppendOnlyUpdate<T: Equatable>(_ cachedItems: [T], newItems: [T]) -> Bool {
    guard newItems.count >= cachedItems.count else {
        return false
    }

    for (cachedItem, newItem) in zip(cachedItems, newItems) where cachedItem != newItem {
        return false
    }

    return true
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
        label.count <= 24
    else {
        return nil
    }
    return (label, body)
}

private func structuredSessionActivityRowShowsExpandedSystemCard(text: String, detailText: String?) -> Bool {
    detailText != nil || text.contains("\n") || text.count > 80
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

private func structuredSessionActivityEmphasis(for kind: SessionActivityItem.Kind) -> StructuredSessionActivityEmphasis
{
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

// MARK: - Feed row content collapse decisions (for live streaming draft + long detail bounding)

/// Pure, cheap, testable predicates that decide when to bound live assistant previews
/// and long command/system detail output inside structured feed rows.
///
/// These power the truncation branches in `ContentView` and `RemoteClientHomeView`
/// so rapid tail appends and ~200 ms streaming draft growth (see `StructuredFeedProfilingFixture`)
/// do not feed unbounded `ViewLayoutEngine` / `explicitAlignment` work.
/// The `charactersPerLine` is platform-tuned (higher on macOS for wider rendering,
/// lower on iOS). Thresholds and behavior are the locked contract for row geometry stability.
/// These thresholds drive live draft bounding, finalized assistant preview collapse, and long detail output.
public func structuredSessionShouldCollapseStreamingMarkdownPreview(_ text: String, charactersPerLine: Int) -> Bool {
    structuredSessionEstimatedWrappedLineCount(for: text, charactersPerLine: charactersPerLine) > 18
        || text.count > 6_000
}

public func structuredSessionShouldCollapseDetailPreview(_ text: String, charactersPerLine: Int) -> Bool {
    structuredSessionEstimatedWrappedLineCount(for: text, charactersPerLine: charactersPerLine) > 10
}

/// Fixed viewport height (points) for collapsed command/system detail previews in the structured feed.
/// Matches the `frame(height:)` used in macOS and iOS session views so layout does not grow with full output.
public let structuredSessionFeedCollapsedDetailViewportHeight: CGFloat = 200

/// Line cap for bounded assistant markdown previews (streaming and finalized) in feed rows.
public let structuredSessionFeedAssistantMarkdownPreviewLineLimit = 18

/// Footnote shown under bounded finalized assistant markdown in the structured feed.
public let structuredSessionFeedAssistantMarkdownCollapsedFootnote =
    "Long response preview truncated for smooth scrolling."

/// Action label that opens the dedicated full-response reader for a bounded finalized assistant row.
public let structuredSessionFeedAssistantMarkdownShowFullResponseTitle = "Show full response"

/// Payload for presenting the MarkdownUI-backed assistant full-response reader (#226).
public struct StructuredSessionAssistantFullResponsePresentation: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let markdown: String

    public init(id: UUID, markdown: String) {
        self.id = id
        self.markdown = markdown
    }
}

public func structuredSessionAssistantFullResponsePresentation(
    rowID: UUID,
    markdown: String
) -> StructuredSessionAssistantFullResponsePresentation {
    StructuredSessionAssistantFullResponsePresentation(id: rowID, markdown: markdown)
}

public struct StructuredSessionFeedAssistantMarkdownDisplayPolicy: Equatable {
    public let showsCollapsedPreview: Bool
    public let previewLineLimit: Int
    public let collapsedFootnote: String
    public let showFullResponseTitle: String

    public init(
        showsCollapsedPreview: Bool,
        previewLineLimit: Int,
        collapsedFootnote: String = structuredSessionFeedAssistantMarkdownCollapsedFootnote,
        showFullResponseTitle: String = structuredSessionFeedAssistantMarkdownShowFullResponseTitle
    ) {
        self.showsCollapsedPreview = showsCollapsedPreview
        self.previewLineLimit = previewLineLimit
        self.collapsedFootnote = collapsedFootnote
        self.showFullResponseTitle = showFullResponseTitle
    }
}

/// Decides when finalized (non-streaming) assistant responses should use bounded preview layout
/// instead of full multiline markdown layout during scroll.
public func structuredSessionFeedAssistantMarkdownDisplayPolicy(
    for text: String,
    charactersPerLine: Int
) -> StructuredSessionFeedAssistantMarkdownDisplayPolicy {
    let collapse = structuredSessionShouldCollapseStreamingMarkdownPreview(text, charactersPerLine: charactersPerLine)
    return StructuredSessionFeedAssistantMarkdownDisplayPolicy(
        showsCollapsedPreview: collapse,
        previewLineLimit: structuredSessionFeedAssistantMarkdownPreviewLineLimit
    )
}

/// Final answer inside an agent-turn stack (ADR 0037) always renders in full — no bounded preview / Show full response.
public func structuredSessionFeedAgentTurnFinalAnswerMarkdownDisplayPolicy(
    for text: String,
    charactersPerLine: Int
) -> StructuredSessionFeedAssistantMarkdownDisplayPolicy {
    _ = charactersPerLine
    _ = text
    return StructuredSessionFeedAssistantMarkdownDisplayPolicy(
        showsCollapsedPreview: false,
        previewLineLimit: structuredSessionFeedAssistantMarkdownPreviewLineLimit
    )
}

public func structuredSessionLatestFinalizedAssistantActivityRowID(
    in rows: [StructuredSessionActivityRow]
) -> UUID? {
    for row in rows.reversed() {
        guard let conversation = row.conversationPresentation,
            conversation.isStreaming == false
        else {
            continue
        }
        guard case .assistant = conversation.role else {
            continue
        }
        return row.id
    }

    return nil
}

/// Keeps the latest long finalized assistant response fully readable without immediately paying full markdown layout cost.
public func structuredSessionFeedAssistantAutoExpandedLatestResponsePrefersPlainText(
    policy: StructuredSessionFeedAssistantMarkdownDisplayPolicy,
    isLatestFinalizedAssistantRow: Bool,
    isExplicitlyExpanded: Bool
) -> Bool {
    policy.showsCollapsedPreview && isLatestFinalizedAssistantRow && isExplicitlyExpanded == false
}

/// Idle-gated inline markdown for the latest visible assistant response (#229).
public enum StructuredSessionLatestAssistantInlineMarkdownIdleGatePolicy {
    #if os(iOS)
        public static var usesIdleGatedInlineMarkdownHydration: Bool { true }
        public static var scrollIdleInterval: TimeInterval { 0.15 }
    #else
        public static var usesIdleGatedInlineMarkdownHydration: Bool { false }
        public static var scrollIdleInterval: TimeInterval { 0 }
    #endif
}

/// Whether the latest assistant row may upgrade from plain text to formatted inline markdown.
public func structuredSessionFeedAllowsLatestAssistantInlineMarkdownHydration(
    prefersPlainTextInitialRender: Bool,
    feedReaderIsScrollIdle: Bool,
    feedTailIsStableForInlineMarkdown: Bool
) -> Bool {
    guard prefersPlainTextInitialRender else { return true }
    guard StructuredSessionLatestAssistantInlineMarkdownIdleGatePolicy.usesIdleGatedInlineMarkdownHydration else {
        return true
    }
    return feedReaderIsScrollIdle && feedTailIsStableForInlineMarkdown
}

/// Updates scroll-idle tracking from successive `ScrollView` geometry samples.
public func structuredSessionFeedScrollReaderIdleState(
    previousSample: StructuredSessionScrollGeometrySample?,
    currentSample: StructuredSessionScrollGeometrySample,
    now: Date,
    lastMovementAt: Date,
    idleInterval: TimeInterval = StructuredSessionLatestAssistantInlineMarkdownIdleGatePolicy.scrollIdleInterval
) -> (lastMovementAt: Date, isScrollIdle: Bool) {
    let offsetDelta = previousSample.map { abs($0.contentOffsetY - currentSample.contentOffsetY) } ?? 0
    let distanceDelta = previousSample.map { abs($0.distanceFromBottom - currentSample.distanceFromBottom) } ?? 0
    let contentMoved = previousSample == nil || offsetDelta > 0.5 || distanceDelta > 0.5
    let updatedLastMovement = contentMoved ? now : lastMovementAt
    let isScrollIdle = now.timeIntervalSince(updatedLastMovement) >= idleInterval
    return (updatedLastMovement, isScrollIdle)
}

/// Feed tail churn defers inline markdown until the follow scroll token stabilizes (#229).
public func structuredSessionFeedTailIsStableForInlineMarkdown(
    feedFollowScrollToken: String,
    lastStableFeedFollowScrollToken: String
) -> Bool {
    feedFollowScrollToken == lastStableFeedFollowScrollToken
}

/// Trims assistant markdown before bounded preview layout so first paint does not parse or typeset the full body (#225).
public func structuredSessionFeedAssistantMarkdownBoundedPreviewText(
    for text: String,
    maximumLines: Int = structuredSessionFeedAssistantMarkdownPreviewLineLimit
) -> String {
    structuredSessionDetailTextPreview(for: text, maximumLines: maximumLines).text
}

public struct StructuredSessionFeedStreamingAssistantDisplayPolicy: Equatable {
    public let usesBoundedViewport: Bool
    public let previewLineLimit: Int

    public init(usesBoundedViewport: Bool, previewLineLimit: Int) {
        self.usesBoundedViewport = usesBoundedViewport
        self.previewLineLimit = previewLineLimit
    }
}

/// Bounds live assistant draft layout when estimated wrapped lines exceed the streaming preview cap (#224).
public func structuredSessionFeedStreamingAssistantDisplayPolicy(
    for text: String,
    charactersPerLine: Int
) -> StructuredSessionFeedStreamingAssistantDisplayPolicy {
    let collapse = structuredSessionShouldCollapseStreamingMarkdownPreview(text, charactersPerLine: charactersPerLine)
    return StructuredSessionFeedStreamingAssistantDisplayPolicy(
        usesBoundedViewport: collapse,
        previewLineLimit: structuredSessionFeedAssistantMarkdownPreviewLineLimit
    )
}

/// Text bound for live assistant `Text` during streaming (#224). When the viewport is bounded,
/// typeset only the trimmed preview — not the full growing draft on every Pi tick.
public func structuredSessionFeedStreamingAssistantDisplayText(
    for text: String,
    policy: StructuredSessionFeedStreamingAssistantDisplayPolicy
) -> String {
    guard policy.usesBoundedViewport else {
        return text
    }
    return structuredSessionFeedAssistantMarkdownBoundedPreviewText(
        for: text,
        maximumLines: policy.previewLineLimit
    )
}

private func structuredSessionEstimatedWrappedLineCount(for text: String, charactersPerLine: Int) -> Int {
    let clampedCharactersPerLine = max(12, charactersPerLine)
    let wrappedLineCount =
        text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .reduce(into: 0) { count, line in
            let lineLength = max(1, line.count)
            count += max(1, Int(ceil(Double(lineLength) / Double(clampedCharactersPerLine))))
        }

    return max(1, wrappedLineCount)
}
