import Foundation
import NexusDomain
import NexusSessionPresentation

enum FocusedSessionSurface: Equatable {
    case terminal
    case structuredActivityFeed
}

enum StructuredSessionActivityEmphasis: Equatable {
    case neutral
    case accent
    case critical
    case success
}

struct StructuredSessionActivityRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let systemImage: String
    let text: String
    let emphasis: StructuredSessionActivityEmphasis
}

struct StructuredSessionPresentationCopy: Equatable {
    let emptyStateTitle: String
    let emptyStateDescription: String
    let composerPlaceholder: String
}

struct StructuredSessionThinkingIndicator: Equatable {
    let text: String
}

struct StructuredSessionFeedPresentation: Equatable {
    let copy: StructuredSessionPresentationCopy
    let activityRows: [StructuredSessionActivityRow]
    let pendingApprovalRequests: [SessionApprovalRequest]
    let thinkingIndicator: StructuredSessionThinkingIndicator?
}

struct StructuredSessionComposerPresentation: Equatable {
    let placeholder: String
    let isEnabled: Bool
    let disabledReason: String?
}

struct StructuredSessionComposerSendAffordance: Equatable {
    let isVisible: Bool
    let isEnabled: Bool
}

struct StructuredSessionApprovalRequestPresentation: Equatable {
    let actionsAreEnabled: Bool
    let disabledReason: String?
}

struct StructuredSessionSlashCommand: Identifiable, Equatable {
    let matchText: String
    let displayText: String
    let insertionText: String
    let summary: String
    let acceptsArguments: Bool
    let suggestionQueryPrefix: String?

    var id: String { displayText }
}

struct StructuredSessionSlashCommandMenuPresentation: Equatable {
    let isVisible: Bool
    let commands: [StructuredSessionSlashCommand]
}

func focusedSessionSurface(for screen: SessionScreen) -> FocusedSessionSurface {
    switch screen.primarySurface {
    case .terminal:
        .terminal
    case .structuredActivityFeed:
        .structuredActivityFeed
    }
}

func structuredSessionActivityRows(for screen: SessionScreen) -> [StructuredSessionActivityRow] {
    NexusSessionPresentation.structuredSessionActivityRows(for: screen).map(mapStructuredSessionActivityRow)
}

func structuredSessionFeedPresentation(for screen: SessionScreen) -> StructuredSessionFeedPresentation {
    mapStructuredSessionFeedPresentation(NexusSessionPresentation.structuredSessionFeedPresentation(for: screen))
}

func structuredSessionPresentationCopy(for screen: SessionScreen) -> StructuredSessionPresentationCopy {
    mapStructuredSessionPresentationCopy(NexusSessionPresentation.structuredSessionPresentationCopy(for: screen))
}

func structuredSessionThinkingIndicator(
    for screen: SessionScreen,
    hasPendingApprovalRequests: Bool
) -> StructuredSessionThinkingIndicator? {
    NexusSessionPresentation.structuredSessionThinkingIndicator(
        for: screen,
        hasPendingApprovalRequests: hasPendingApprovalRequests
    ).map(mapStructuredSessionThinkingIndicator)
}

func structuredSessionComposerPresentation(for screen: SessionScreen, isController: Bool) -> StructuredSessionComposerPresentation {
    mapStructuredSessionComposerPresentation(
        NexusSessionPresentation.structuredSessionComposerPresentation(
            for: screen,
            hasWriterAuthority: isController
        )
    )
}

func structuredSessionComposerSendAffordance(
    for draft: String,
    composer: StructuredSessionComposerPresentation,
    isPerformingAction: Bool
) -> StructuredSessionComposerSendAffordance {
    mapStructuredSessionComposerSendAffordance(
        NexusSessionPresentation.structuredSessionComposerSendAffordance(
            for: draft,
            composer: NexusSessionPresentation.StructuredSessionComposerPresentation(
                placeholder: composer.placeholder,
                isEnabled: composer.isEnabled,
                disabledReason: composer.disabledReason
            ),
            isPerformingAction: isPerformingAction
        )
    )
}

func structuredSessionApprovalRequestPresentation(isController: Bool) -> StructuredSessionApprovalRequestPresentation {
    mapStructuredSessionApprovalRequestPresentation(
        NexusSessionPresentation.structuredSessionApprovalRequestPresentation(hasWriterAuthority: isController)
    )
}

func structuredSessionSlashCommandMenuPresentation(
    for draft: String,
    screen: SessionScreen
) -> StructuredSessionSlashCommandMenuPresentation {
    mapStructuredSessionSlashCommandMenuPresentation(
        NexusSessionPresentation.structuredSessionSlashCommandMenuPresentation(for: draft, screen: screen)
    )
}

func applyStructuredSessionSlashCommand(_ command: StructuredSessionSlashCommand, to draft: String) -> String {
    NexusSessionPresentation.applyStructuredSessionSlashCommand(
        NexusSessionPresentation.StructuredSessionSlashCommand(
            matchText: command.matchText,
            displayText: command.displayText,
            insertionText: command.insertionText,
            summary: command.summary,
            acceptsArguments: command.acceptsArguments,
            suggestionQueryPrefix: command.suggestionQueryPrefix
        ),
        to: draft
    )
}

private func mapStructuredSessionActivityRow(
    _ row: NexusSessionPresentation.StructuredSessionActivityRow
) -> StructuredSessionActivityRow {
    StructuredSessionActivityRow(
        id: row.id,
        title: row.title,
        systemImage: row.systemImage,
        text: row.text,
        emphasis: mapStructuredSessionActivityEmphasis(row.emphasis)
    )
}

private func mapStructuredSessionActivityEmphasis(
    _ emphasis: NexusSessionPresentation.StructuredSessionActivityEmphasis
) -> StructuredSessionActivityEmphasis {
    switch emphasis {
    case .neutral:
        .neutral
    case .accent:
        .accent
    case .critical:
        .critical
    case .success:
        .success
    }
}

private func mapStructuredSessionPresentationCopy(
    _ copy: NexusSessionPresentation.StructuredSessionPresentationCopy
) -> StructuredSessionPresentationCopy {
    StructuredSessionPresentationCopy(
        emptyStateTitle: copy.emptyStateTitle,
        emptyStateDescription: copy.emptyStateDescription,
        composerPlaceholder: copy.composerPlaceholder
    )
}

private func mapStructuredSessionThinkingIndicator(
    _ indicator: NexusSessionPresentation.StructuredSessionThinkingIndicator
) -> StructuredSessionThinkingIndicator {
    StructuredSessionThinkingIndicator(text: indicator.text)
}

private func mapStructuredSessionFeedPresentation(
    _ presentation: NexusSessionPresentation.StructuredSessionFeedPresentation
) -> StructuredSessionFeedPresentation {
    StructuredSessionFeedPresentation(
        copy: mapStructuredSessionPresentationCopy(presentation.copy),
        activityRows: presentation.activityRows.map(mapStructuredSessionActivityRow),
        pendingApprovalRequests: presentation.pendingApprovalRequests,
        thinkingIndicator: presentation.thinkingIndicator.map(mapStructuredSessionThinkingIndicator)
    )
}

private func mapStructuredSessionComposerPresentation(
    _ presentation: NexusSessionPresentation.StructuredSessionComposerPresentation
) -> StructuredSessionComposerPresentation {
    StructuredSessionComposerPresentation(
        placeholder: presentation.placeholder,
        isEnabled: presentation.isEnabled,
        disabledReason: presentation.disabledReason
    )
}

private func mapStructuredSessionComposerSendAffordance(
    _ affordance: NexusSessionPresentation.StructuredSessionComposerSendAffordance
) -> StructuredSessionComposerSendAffordance {
    StructuredSessionComposerSendAffordance(
        isVisible: affordance.isVisible,
        isEnabled: affordance.isEnabled
    )
}

private func mapStructuredSessionApprovalRequestPresentation(
    _ presentation: NexusSessionPresentation.StructuredSessionApprovalRequestPresentation
) -> StructuredSessionApprovalRequestPresentation {
    StructuredSessionApprovalRequestPresentation(
        actionsAreEnabled: presentation.actionsAreEnabled,
        disabledReason: presentation.disabledReason
    )
}

private func mapStructuredSessionSlashCommand(
    _ command: NexusSessionPresentation.StructuredSessionSlashCommand
) -> StructuredSessionSlashCommand {
    StructuredSessionSlashCommand(
        matchText: command.matchText,
        displayText: command.displayText,
        insertionText: command.insertionText,
        summary: command.summary,
        acceptsArguments: command.acceptsArguments,
        suggestionQueryPrefix: command.suggestionQueryPrefix
    )
}

private func mapStructuredSessionSlashCommandMenuPresentation(
    _ presentation: NexusSessionPresentation.StructuredSessionSlashCommandMenuPresentation
) -> StructuredSessionSlashCommandMenuPresentation {
    StructuredSessionSlashCommandMenuPresentation(
        isVisible: presentation.isVisible,
        commands: presentation.commands.map(mapStructuredSessionSlashCommand)
    )
}
