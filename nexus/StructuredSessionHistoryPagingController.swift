import Foundation
import NexusDomain
import NexusIPC
import NexusSessionPresentation

@MainActor
final class StructuredSessionHistoryPagingController {
    typealias FetchPage = @Sendable (UUID, Int, StructuredSessionHistoryCursor?) async throws -> StructuredSessionHistoryPage

    private let pageSize: Int
    private let fetchPage: FetchPage
    private let feedPresenter = StructuredSessionFeedPresenter()

    private var currentSessionID: UUID?
    private var currentSessionSupportsPaging = false
    private var hasLoadedFirstPage = false
    private var nextCursor: StructuredSessionHistoryCursor?
    private var historicalActivityItems: [SessionActivityItem] = []

    private(set) var canLoadOlder = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(pageSize: Int = 200, fetchPage: @escaping FetchPage) {
        self.pageSize = max(1, pageSize)
        self.fetchPage = fetchPage
    }

    func applyLiveScreen(_ screen: SessionScreen?) {
        let sessionID = screen?.session.id
        let supportsPaging = supportsPaging(for: screen)

        guard sessionID == currentSessionID,
              supportsPaging == currentSessionSupportsPaging else {
            reset(sessionID: sessionID, supportsPaging: supportsPaging)
            return
        }

        refreshAvailability()
    }

    func recoverPersistedGapIfNeeded(from previousScreen: SessionScreen?, to screen: SessionScreen) async {
        guard supportsPaging(for: screen),
              let previousScreen,
              previousScreen.session.id == screen.session.id,
              currentSessionID == screen.session.id else {
            return
        }

        let missingFirstActivityItemID = missingFirstActivityItemID(from: previousScreen, to: screen)
        guard missingFirstActivityItemID != nil else {
            return
        }

        var cursor: StructuredSessionHistoryCursor?
        var recoveredActivityItems: [SessionActivityItem] = []

        while true {
            let page: StructuredSessionHistoryPage
            do {
                page = try await fetchPage(screen.session.id, pageSize, cursor)
            } catch {
                return
            }

            guard page.sessionID == screen.session.id,
                  currentSessionID == screen.session.id else {
                return
            }

            recoveredActivityItems = prependHistoricalActivityItems(page.activityItems, to: recoveredActivityItems)

            let recoveredMissingActivityItem = missingFirstActivityItemID.map { missingID in
                recoveredActivityItems.contains(where: { $0.id == missingID })
            } ?? true
            if recoveredMissingActivityItem {
                break
            }

            guard let nextPageCursor = page.nextCursor else {
                break
            }
            cursor = nextPageCursor
        }

        historicalActivityItems = prependHistoricalActivityItems(recoveredActivityItems, to: historicalActivityItems)
        refreshAvailability()
    }

    func loadOlderHistory(for screen: SessionScreen) async {
        guard supportsPaging(for: screen),
              currentSessionID == screen.session.id,
              isLoading == false else {
            return
        }
        guard hasLoadedFirstPage == false || nextCursor != nil else {
            refreshAvailability()
            return
        }

        isLoading = true
        errorMessage = nil
        canLoadOlder = false
        let cursor = hasLoadedFirstPage ? nextCursor : nil

        do {
            let page = try await fetchPage(screen.session.id, pageSize, cursor)
            guard page.sessionID == screen.session.id,
                  currentSessionID == screen.session.id else {
                isLoading = false
                refreshAvailability()
                return
            }

            hasLoadedFirstPage = true
            nextCursor = page.nextCursor
            historicalActivityItems = prependHistoricalActivityItems(
                page.activityItems,
                to: historicalActivityItems
            )
            errorMessage = nil
        } catch {
            guard currentSessionID == screen.session.id else {
                isLoading = false
                refreshAvailability()
                return
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
        refreshAvailability()
    }

    func presentation(for screen: SessionScreen) -> FocusedStructuredSessionPresentation? {
        guard screen.primarySurface == .structuredActivityFeed else {
            return nil
        }

        return FocusedStructuredSessionPresentation(
            session: screen.session,
            feed: feedPresenter.presentation(for: mergedScreen(for: screen)),
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )
    }

    private func mergedScreen(for screen: SessionScreen) -> SessionScreen {
        guard currentSessionSupportsPaging,
              currentSessionID == screen.session.id,
              historicalActivityItems.isEmpty == false else {
            return screen
        }

        let mergedActivityItems = mergeHistoricalActivityItems(
            historicalActivityItems,
            with: screen.activityItems
        )
        guard mergedActivityItems != screen.activityItems else {
            return screen
        }

        return SessionScreen(
            session: screen.session,
            primarySurface: screen.primarySurface,
            controller: screen.controller,
            transcript: screen.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows,
            activityItems: mergedActivityItems,
            approvalRequests: screen.approvalRequests,
            extensionUI: screen.extensionUI,
            slashCommands: screen.slashCommands,
            providerEvents: screen.providerEvents,
            providerFacts: screen.providerFacts,
            finalOutputDiagnostic: screen.finalOutputDiagnostic,
            isAgentTurnInProgress: screen.isAgentTurnInProgress,
            visibleLines: screen.visibleLines,
            styledVisibleLines: screen.styledVisibleLines,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
            cursorVisible: screen.cursorVisible
        )
    }

    private func reset(sessionID: UUID?, supportsPaging: Bool) {
        currentSessionID = sessionID
        currentSessionSupportsPaging = supportsPaging
        hasLoadedFirstPage = false
        nextCursor = nil
        historicalActivityItems = []
        isLoading = false
        errorMessage = nil
        refreshAvailability()
    }

    private func refreshAvailability() {
        canLoadOlder = currentSessionSupportsPaging
            && isLoading == false
            && (hasLoadedFirstPage == false || nextCursor != nil)
    }

    private func supportsPaging(for screen: SessionScreen?) -> Bool {
        guard let screen else {
            return false
        }

        return screen.primarySurface == .structuredActivityFeed
    }

    private func missingFirstActivityItemID(from previousScreen: SessionScreen, to currentScreen: SessionScreen) -> UUID? {
        guard let currentFirstID = currentScreen.activityItems.first?.id,
              previousScreen.activityItems.isEmpty == false else {
            return nil
        }

        let knownIDs = Set(mergeHistoricalActivityItems(historicalActivityItems, with: previousScreen.activityItems).map(\.id))
        guard knownIDs.contains(currentFirstID) == false else {
            return nil
        }

        return previousScreen.activityItems.first?.id
    }

    private func prependHistoricalActivityItems(
        _ olderItems: [SessionActivityItem],
        to existingItems: [SessionActivityItem]
    ) -> [SessionActivityItem] {
        var seen = Set<UUID>()
        var merged: [SessionActivityItem] = []

        for item in olderItems + existingItems where seen.insert(item.id).inserted {
            merged.append(item)
        }

        return merged
    }

    private func mergeHistoricalActivityItems(
        _ historicalItems: [SessionActivityItem],
        with liveItems: [SessionActivityItem]
    ) -> [SessionActivityItem] {
        var seen = Set<UUID>()
        var merged: [SessionActivityItem] = []

        for item in historicalItems + liveItems where seen.insert(item.id).inserted {
            merged.append(item)
        }

        return merged
    }

}
