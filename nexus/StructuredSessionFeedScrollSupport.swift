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

    static func scheduleFollowBottomScroll(
        position: Binding<ScrollPosition>,
        animation: StructuredSessionAutoScrollAnimation
    ) {
        scrollToBottom(position, animation: animation)
        DispatchQueue.main.async {
            scrollToBottom(position, animation: .immediate)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            scrollToBottom(position, animation: .immediate)
        }
    }
}