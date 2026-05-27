import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceStructuredSessionCopyTests {
    @Test func structuredInterruptedSessionFailureMessageUsesProviderDisplayName() {
        #expect(structuredInterruptedSessionFailureMessage(for: .pi) == "Pi Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime.")
        #expect(structuredInterruptedSessionFailureMessage(for: .codex) == "Codex Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime.")
    }
}
