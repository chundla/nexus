import NexusSessionPresentation
import SwiftUI

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
        schedulePostLayoutRetry: (@escaping @Sendable () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        scrollToBottom(position, animation: animation)
        guard layoutRetry else { return }
        schedulePostLayoutRetry {
            scrollToBottom(position, animation: .immediate)
        }
    }
}