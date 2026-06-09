import NexusSessionPresentation
import SwiftUI

enum StructuredSessionFeedScrollSupport {
    static func scrollToBottom(
        _ position: Binding<ScrollPosition>,
        animation: StructuredSessionAutoScrollAnimation
    ) {
        switch animation {
        case .immediate:
            position.wrappedValue.scrollTo(edge: .bottom)
        case .animated:
            withAnimation(.easeOut(duration: 0.18)) {
                position.wrappedValue.scrollTo(edge: .bottom)
            }
        }
    }

    /// One immediate scroll plus a single post-layout retry (run 3: triple scroll amplified main-thread work).
    static func scheduleFollowBottomScroll(
        position: Binding<ScrollPosition>,
        animation: StructuredSessionAutoScrollAnimation
    ) {
        scrollToBottom(position, animation: animation)
        DispatchQueue.main.async {
            scrollToBottom(position, animation: .immediate)
        }
    }
}