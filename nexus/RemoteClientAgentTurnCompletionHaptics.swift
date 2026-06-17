import Foundation
import NexusDomain

protocol AgentTurnCompletionHapticFeedback: Sendable {
    func playSuccess()
}

struct NoOpAgentTurnCompletionHapticFeedback: AgentTurnCompletionHapticFeedback {
    func playSuccess() {}
}

#if os(iOS)
    import UIKit

    struct UINotificationAgentTurnCompletionHapticFeedback: AgentTurnCompletionHapticFeedback {
        func playSuccess() {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }
#endif

/// Whether a live agent turn completion should trigger success haptic feedback on the iOS Remote Client.
nonisolated func shouldPlayAgentTurnCompletionHaptic(
    previousScreen: SessionScreen?,
    newScreen: SessionScreen,
    isController: Bool,
    isLoadingOlderStructuredSessionHistory: Bool
) -> Bool {
    guard isController else {
        return false
    }
    guard isLoadingOlderStructuredSessionHistory == false else {
        return false
    }
    guard let previousScreen,
        previousScreen.session.id == newScreen.session.id
    else {
        return false
    }
    guard previousScreen.isAgentTurnInProgress,
        newScreen.isAgentTurnInProgress == false
    else {
        return false
    }
    return true
}
