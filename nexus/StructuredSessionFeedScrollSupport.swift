import NexusSessionPresentation
import SwiftUI

@MainActor
enum StructuredSessionFeedScrollSupport {
    /// Test hook: counts each `scrollToBottom` invocation (including optional layout retry).
    static var scrollToBottomInvocationCountForTesting = 0

    static func resetScrollToBottomInvocationCountForTesting() {
        scrollToBottomInvocationCountForTesting = 0
    }

    static func scrollToBottom(
        _ position: Binding<ScrollPosition>,
        animation: StructuredSessionAutoScrollAnimation
    ) {
        scrollToBottomInvocationCountForTesting += 1
        switch animation {
        case .immediate:
            position.wrappedValue.scrollTo(edge: .bottom)
        case .animated:
            withAnimation(.easeOut(duration: 0.18)) {
                position.wrappedValue.scrollTo(edge: .bottom)
            }
        }
    }

    /// Schedules at most one bottom scroll per follow event. Post-layout retry is opt-in only.
    static func scheduleFollowBottomScroll(
        position: Binding<ScrollPosition>,
        animation: StructuredSessionAutoScrollAnimation,
        layoutRetry: Bool = false,
        schedulePostLayoutRetry: (@escaping @MainActor () -> Void) -> Void = { work in
            Task { @MainActor in work() }
        }
    ) {
        scrollToBottom(position, animation: animation)
        guard layoutRetry else { return }
        schedulePostLayoutRetry {
            scrollToBottom(position, animation: .immediate)
        }
    }

    /// Applies bottom-scroll policy for a feed scroll snapshot transition; returns the snapshot to store.
    static func applyStructuredSessionFeedScrollSnapshotTransition(
        previous: StructuredSessionFeedScrollSnapshot?,
        current: StructuredSessionFeedScrollSnapshot,
        isFollowingBottom: Bool,
        coordinator: StructuredSessionAutoScrollCoordinator,
        draftGrowthThrottle: StructuredSessionDraftGrowthScrollThrottle,
        scrollPosition: Binding<ScrollPosition>,
        scrollPositionUsesBottomEdge: Bool = false
    ) -> StructuredSessionFeedScrollSnapshot {
        let performScroll = { (animation: StructuredSessionAutoScrollAnimation) in
            scheduleFollowBottomScroll(position: scrollPosition, animation: animation)
        }

        guard let previous else {
            if isFollowingBottom, scrollPositionUsesBottomEdge == false {
                structuredSessionRequestBottomScroll(
                    intent: .immediate,
                    coordinator: coordinator,
                    draftGrowthThrottle: draftGrowthThrottle,
                    performScroll: performScroll
                )
            }
            return current
        }

        let intent = structuredSessionBottomScrollIntent(
            previous: previous,
            current: current,
            isPinnedToBottom: isFollowingBottom
        )
        structuredSessionRequestBottomScroll(
            intent: intent,
            coordinator: coordinator,
            draftGrowthThrottle: draftGrowthThrottle,
            performScroll: performScroll
        )
        return current
    }
}