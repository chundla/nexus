#if os(macOS)
import Foundation
import NexusDomain

enum StructuredSessionLiveHistoryRetention {
    static let maxTranscriptCharacters = 128_000
    static let maxRetainedActivityItems = 2_000
    static let maxRetainedProviderEvents = 1_000

    static func normalizedScreen(_ screen: SessionScreen) -> SessionScreen {
        guard screen.primarySurface == .structuredActivityFeed else {
            return screen
        }

        let transcript = retainedTranscript(screen.transcript)
        let activityItems = retainedActivityItems(screen.activityItems)
        let providerEvents = retainedProviderEvents(screen.providerEvents)
        guard transcript != screen.transcript
                || activityItems != screen.activityItems
                || providerEvents != screen.providerEvents else {
            return screen
        }

        return SessionScreen(
            session: screen.session,
            primarySurface: screen.primarySurface,
            controller: screen.controller,
            transcript: transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows,
            activityItems: activityItems,
            approvalRequests: screen.approvalRequests,
            extensionUI: screen.extensionUI,
            slashCommands: screen.slashCommands,
            providerEvents: providerEvents,
            isAgentTurnInProgress: screen.isAgentTurnInProgress,
            visibleLines: screen.visibleLines,
            styledVisibleLines: screen.styledVisibleLines,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
            cursorVisible: screen.cursorVisible
        )
    }

    static func retainedActivityItems(_ activityItems: [SessionActivityItem]) -> [SessionActivityItem] {
        guard activityItems.count > maxRetainedActivityItems else {
            return activityItems
        }
        return Array(activityItems.suffix(maxRetainedActivityItems))
    }

    static func retainedProviderEvents(_ providerEvents: [SessionProviderEvent]) -> [SessionProviderEvent] {
        guard providerEvents.count > maxRetainedProviderEvents else {
            return providerEvents
        }
        return Array(providerEvents.suffix(maxRetainedProviderEvents))
    }

    static func retainedTranscriptEntries(_ entries: [String]) -> [String] {
        guard entries.isEmpty == false else {
            return entries
        }

        var retained = entries
        var totalCharacterCount = retained.reduce(into: max(0, retained.count - 1)) { partialResult, entry in
            partialResult += entry.count
        }

        while retained.count > 1, totalCharacterCount > maxTranscriptCharacters {
            totalCharacterCount -= retained.removeFirst().count
            totalCharacterCount -= 1
        }

        if totalCharacterCount > maxTranscriptCharacters, let last = retained.last {
            retained[retained.count - 1] = String(last.suffix(maxTranscriptCharacters))
        }

        return retained
    }

    static func retainedTranscript(_ transcript: String) -> String {
        guard transcript.count > maxTranscriptCharacters else {
            return transcript
        }

        let retainedLines = retainedTranscriptEntries(
            transcript.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        )
        return retainedLines.joined(separator: "\n")
    }
}
#endif
