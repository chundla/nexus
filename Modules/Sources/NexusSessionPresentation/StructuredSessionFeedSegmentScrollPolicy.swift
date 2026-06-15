import Foundation
import NexusDomain

// MARK: - Feed scroll / reveal item identity (ADR 0037, #233)

/// Scroll and progressive-reveal policies count **feed items**: composite segments when present, else activity rows.
public func structuredSessionFeedScrollItemCount(for feed: StructuredSessionFeedPresentation) -> Int {
    if let segments = feed.feedSegments {
        return segments.count
    }
    return feed.activityRows.count
}

public func structuredSessionFeedScrollItemIDs(for feed: StructuredSessionFeedPresentation) -> [UUID] {
    if let segments = feed.feedSegments {
        return segments.map(\.id)
    }
    return feed.feedActivityRowIDs
}

/// Activity rows whose scroll identity falls in the visible tail segment window (Pi composite feed).
public func structuredSessionActivityRows(
    in feed: StructuredSessionFeedPresentation,
    visibleTailItemCount: Int
) -> [StructuredSessionActivityRow] {
    guard feed.feedSegments != nil else {
        let rows = feed.activityRows
        guard visibleTailItemCount < rows.count else {
            return rows
        }
        guard visibleTailItemCount > 0 else {
            return []
        }
        return Array(rows.suffix(visibleTailItemCount))
    }

    guard let visibleSegments = structuredSessionVisibleFeedSegments(in: feed, visibleTailItemCount: visibleTailItemCount) else {
        return feed.activityRows
    }
    if visibleSegments.isEmpty {
        return []
    }

    let visibleIDs = Set(visibleSegments.map(\.id))
    var matched: [StructuredSessionActivityRow] = []
    for row in feed.activityRows where visibleIDs.contains(row.id) {
        matched.append(row)
    }
    if matched.isEmpty == false {
        return matched
    }
    return Array(feed.activityRows.suffix(visibleSegments.count))
}

public func structuredSessionVisibleFeedSegments(
    in feed: StructuredSessionFeedPresentation,
    visibleTailItemCount: Int
) -> [StructuredSessionFeedSegment]? {
    guard let segments = feed.feedSegments else {
        return nil
    }
    let total = segments.count
    guard visibleTailItemCount < total else {
        return segments
    }
    guard visibleTailItemCount > 0 else {
        return []
    }
    return Array(segments.suffix(visibleTailItemCount))
}

public func structuredSessionFeedRevealShowsFullTail(
    visibleTailItemCount: Int,
    totalFeedItemCount: Int
) -> Bool {
    visibleTailItemCount >= totalFeedItemCount
}

public func structuredSessionFeedScrollTarget(
    for presentation: FocusedStructuredSessionPresentation
) -> StructuredSessionFeedScrollTarget {
    if let segments = presentation.feed.feedSegments, segments.isEmpty == false {
        if let last = segments.last,
           case .agentTurn(let turn) = last,
           let final = turn.finalAnswer,
           final.isStreaming {
            return .activityRow(turn.id)
        }
        return .activityRow(segments.last!.id)
    }

    if let streamingRow = presentation.feed.activityRows.last,
       streamingRow.conversationPresentation?.isStreaming == true {
        return .activityRow(streamingRow.id)
    }

    if let lastRowID = presentation.feed.activityRows.last?.id {
        return .activityRow(lastRowID)
    }

    return .bottomSentinel
}

public func structuredSessionFeedScrollSnapshot(
    for presentation: FocusedStructuredSessionPresentation
) -> StructuredSessionFeedScrollSnapshot {
    let target = structuredSessionFeedScrollTarget(for: presentation)
    let growthToken: String?
    if case .activityRow(let rowID) = target {
        if let segments = presentation.feed.feedSegments,
           let last = segments.last,
           case .agentTurn(let turn) = last,
           turn.id == rowID,
           let final = turn.finalAnswer,
           final.isStreaming {
            growthToken = structuredSessionLiveDraftScrollGrowthToken(for: final.text)
        } else if let row = presentation.feed.activityRows.last,
                  row.id == rowID,
                  row.conversationPresentation?.isStreaming == true {
            growthToken = structuredSessionLiveDraftScrollGrowthToken(for: row.text)
        } else {
            growthToken = nil
        }
    } else {
        growthToken = nil
    }

    return StructuredSessionFeedScrollSnapshot(
        feedScrollTarget: target,
        autoScrollTrigger: presentation.autoScrollTrigger,
        liveDraftGrowthToken: growthToken
    )
}

public func structuredSessionFeedFollowScrollToken(
    for presentation: FocusedStructuredSessionPresentation
) -> String {
    if let segments = presentation.feed.feedSegments {
        let last = segments.last
        let draftSuffix: String
        if let last,
           case .agentTurn(let turn) = last,
           let final = turn.finalAnswer,
           final.isStreaming {
            draftSuffix = "-\(final.text.count)"
        } else {
            draftSuffix = ""
        }
        return "seg-\(segments.count)-\(last?.id.uuidString ?? "none")\(draftSuffix)"
    }

    let rows = presentation.feed.activityRows
    let lastRow = rows.last
    let draftSuffix = lastRow?.conversationPresentation?.isStreaming == true
        ? "-\(lastRow?.text.count ?? 0)"
        : ""
    return "\(rows.count)-\(lastRow?.id.uuidString ?? "none")\(draftSuffix)"
}

public func structuredSessionAutoScrollTrigger(for screen: SessionScreen) -> StructuredSessionAutoScrollTrigger {
    let lastScrollItemID: UUID?
    if let segments = structuredSessionAgentTurnFeedSegments(for: screen), let last = segments.last {
        lastScrollItemID = last.id
    } else {
        lastScrollItemID = screen.activityItems.last?.id
    }

    return StructuredSessionAutoScrollTrigger(
        lastActivityRowID: lastScrollItemID,
        pendingApprovalRequestIDs: screen.approvalRequests
            .filter { $0.state == .pending }
            .map(\.id),
        pendingDialogIDs: screen.extensionUI?.pendingDialogs.map(\.id) ?? []
    )
}

/// Live draft text busts row-affecting presentation cache while an agent turn is open (#208, #233).
public func structuredSessionHistoryPagingRowAffectingDraftKey(for screen: SessionScreen) -> String? {
    guard screen.isAgentTurnInProgress else {
        return nil
    }
    return screen.providerFacts.liveAssistantDraftText
}