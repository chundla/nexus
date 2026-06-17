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

    guard
        let visibleSegments = structuredSessionVisibleFeedSegments(in: feed, visibleTailItemCount: visibleTailItemCount)
    else {
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

/// Turn segment to pin scroll to while **Thinking…** is visible (not interim standalone assistant bubbles).
public func structuredSessionFeedScrollAnchorTurnID(
    in feedSegments: [StructuredSessionFeedSegment]?
) -> UUID? {
    guard let segments = feedSegments, segments.isEmpty == false else {
        return nil
    }
    for segment in segments.reversed() {
        if case .agentTurn(let turn) = segment {
            return turn.id
        }
    }
    return nil
}

public func structuredSessionFeedScrollTarget(
    for presentation: FocusedStructuredSessionPresentation
) -> StructuredSessionFeedScrollTarget {
    if structuredSessionEffectiveAgentTurnInProgress(for: presentation) {
        if let anchorTurnID = structuredSessionFeedScrollAnchorTurnID(in: presentation.feed.feedSegments) {
            return .activityRow(anchorTurnID)
        }
        return .bottomSentinel
    }

    if let segments = presentation.feed.feedSegments, segments.isEmpty == false {
        if let anchorTurnID = structuredSessionFeedScrollAnchorTurnIDForInterimPiLayout(in: segments) {
            return .activityRow(anchorTurnID)
        }
        if let last = segments.last,
            case .agentTurn(let turn) = last,
            let final = turn.finalAnswer,
            final.isStreaming
        {
            return .activityRow(turn.id)
        }
        return .activityRow(segments.last!.id)
    }

    if let streamingRow = presentation.feed.activityRows.last,
        streamingRow.conversationPresentation?.isStreaming == true
    {
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
    if structuredSessionEffectiveAgentTurnInProgress(for: presentation) {
        growthToken = nil
    } else if case .activityRow(let rowID) = target {
        if let segments = presentation.feed.feedSegments,
            let last = segments.last,
            case .agentTurn(let turn) = last,
            turn.id == rowID,
            let final = turn.finalAnswer,
            final.isStreaming
        {
            growthToken = structuredSessionLiveDraftScrollGrowthToken(for: final.text)
        } else if let row = presentation.feed.activityRows.last,
            row.id == rowID,
            row.conversationPresentation?.isStreaming == true
        {
            growthToken = structuredSessionLiveDraftScrollGrowthToken(for: row.text)
        } else {
            growthToken = nil
        }
    } else {
        growthToken = nil
    }

    // Only suppress programmatic bottom-follow for the narrow case of an interim standalone
    // Pi: assistant bubble that appears after an open agent turn (historical layout stickiness).
    // Normal open-turn content (tool rows, final streaming, Thinking indicator) should
    // follow the bottom when the user is pinned (distanceFromBottom <= threshold).
    // This restores classic "autoscroll unless user scrolled away" behavior.
    // Re-follow happens automatically because pinState is distance-driven even during turns.
    let suppressBottomScroll =
        structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(in: presentation.feed.feedSegments)

    return StructuredSessionFeedScrollSnapshot(
        feedScrollTarget: target,
        autoScrollTrigger: presentation.autoScrollTrigger,
        liveDraftGrowthToken: growthToken,
        suppressesProgrammaticBottomScroll: suppressBottomScroll
    )
}

/// `ScrollPosition(edge: .bottom)` tracks every content height change and can spin AppKit `ScrollView` layout.
/// Follow the tail via pin state + explicit `scrollTo` instead (macOS structured feed).
public func structuredSessionFeedUsesBottomEdgeScrollPositionBinding(
    for presentation: FocusedStructuredSessionPresentation
) -> Bool {
    _ = presentation
    return false
}

/// Distance-based pin/follow logic. Even while an agent turn is open (Thinking…, tool rows,
/// final streaming), we follow the tail **unless** the user has scrolled away far enough that
/// distanceFromBottom > pinThreshold. Scrolling back to within the threshold re-enables
/// automatic bottom following. This is the classic chat "stay at bottom unless user reads history"
/// behavior. Previous forcing of detached=true during open turns was removed to support
/// re-follow on scroll-to-bottom; snapshot suppression + draft throttling protect against
/// excessive scrolls during rapid content growth.
public func structuredSessionFeedPinStateDuringOpenAgentTurn(
    previous: StructuredSessionFeedPinState,
    sample: StructuredSessionScrollGeometrySample,
    effectiveTurnInProgress: Bool,
    pinThreshold: CGFloat = 48,
    topContentOffsetTolerance: CGFloat = 8
) -> StructuredSessionFeedPinState {
    // Use the normal distance-based rule regardless of whether a turn is open.
    // The effectiveTurnInProgress parameter is kept for call-site compatibility and
    // future policy tweaks, but no longer forces detached state.
    return structuredSessionFeedPinState(
        previous: previous,
        sample: sample,
        pinThreshold: pinThreshold,
        topContentOffsetTolerance: topContentOffsetTolerance
    )
}

public func structuredSessionFeedPinStateIfChangedDuringOpenAgentTurn(
    previous: StructuredSessionFeedPinState,
    sample: StructuredSessionScrollGeometrySample,
    effectiveTurnInProgress: Bool,
    pinThreshold: CGFloat = 48,
    topContentOffsetTolerance: CGFloat = 8
) -> StructuredSessionFeedPinState? {
    let next = structuredSessionFeedPinStateDuringOpenAgentTurn(
        previous: previous,
        sample: sample,
        effectiveTurnInProgress: effectiveTurnInProgress,
        pinThreshold: pinThreshold,
        topContentOffsetTolerance: topContentOffsetTolerance
    )
    guard next != previous else {
        return nil
    }
    return next
}

public func structuredSessionFeedFollowScrollToken(
    for presentation: FocusedStructuredSessionPresentation
) -> String {
    if structuredSessionEffectiveAgentTurnInProgress(for: presentation),
        let anchorTurnID = structuredSessionFeedScrollAnchorTurnID(in: presentation.feed.feedSegments)
    {
        return "thinking-anchor-\(anchorTurnID.uuidString)"
    }

    if let segments = presentation.feed.feedSegments {
        let last = segments.last
        let draftSuffix: String
        if let last,
            case .agentTurn(let turn) = last,
            let final = turn.finalAnswer,
            final.isStreaming
        {
            draftSuffix = "-\(structuredSessionLiveDraftScrollGrowthToken(for: final.text))"
        } else {
            draftSuffix = ""
        }
        return "seg-\(segments.count)-\(last?.id.uuidString ?? "none")\(draftSuffix)"
    }

    let rows = presentation.feed.activityRows
    let lastRow = rows.last
    let draftSuffix =
        lastRow?.conversationPresentation?.isStreaming == true
        ? "-\(lastRow?.text.count ?? 0)"
        : ""
    return "\(rows.count)-\(lastRow?.id.uuidString ?? "none")\(draftSuffix)"
}

/// Open turn + trailing interim `Pi:` — scroll must not follow the standalone bubble id.
func structuredSessionFeedScrollAnchorTurnIDForInterimPiLayout(
    in segments: [StructuredSessionFeedSegment]
) -> UUID? {
    guard structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(in: segments),
        let anchorTurnID = structuredSessionFeedScrollAnchorTurnID(in: segments)
    else {
        return nil
    }
    return anchorTurnID
}

public func structuredSessionAutoScrollTrigger(for screen: SessionScreen) -> StructuredSessionAutoScrollTrigger {
    let lastScrollItemID: UUID?
    if let segments = structuredSessionAgentTurnFeedSegments(for: screen) {
        let anchorForOpenTurn =
            structuredSessionEffectiveAgentTurnInProgress(for: screen)
            || structuredSessionFeedHasInterimPiAssistantAfterOpenTurn(in: segments)
        if anchorForOpenTurn,
            let anchorTurnID = structuredSessionFeedScrollAnchorTurnID(in: segments)
        {
            lastScrollItemID = anchorTurnID
        } else if let interimAnchor = structuredSessionFeedScrollAnchorTurnIDForInterimPiLayout(in: segments) {
            lastScrollItemID = interimAnchor
        } else if let last = segments.last {
            lastScrollItemID = last.id
        } else {
            lastScrollItemID = screen.activityItems.last?.id
        }
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
    guard structuredSessionEffectiveAgentTurnInProgress(for: screen) else {
        return nil
    }
    if let draft = screen.providerFacts.liveAssistantDraftText?.trimmingCharacters(in: .whitespacesAndNewlines),
        draft.isEmpty == false
    {
        return structuredSessionLiveDraftScrollGrowthToken(for: draft)
    }
    return "open-turn"
}
