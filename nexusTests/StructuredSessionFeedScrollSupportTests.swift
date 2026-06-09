import NexusSessionPresentation
import SwiftUI
import Testing
@testable import nexus

@MainActor
struct StructuredSessionFeedScrollSupportTests {
    @Test func scheduleFollowBottomScrollPerformsSingleScrollByDefault() {
        StructuredSessionFeedScrollSupport.resetScrollToBottomInvocationCountForTesting()
        var scrollPosition = ScrollPosition(edge: .bottom)
        let binding = Binding(get: { scrollPosition }, set: { scrollPosition = $0 })

        StructuredSessionFeedScrollSupport.scheduleFollowBottomScroll(
            position: binding,
            animation: .immediate
        )

        #expect(StructuredSessionFeedScrollSupport.scrollToBottomInvocationCountForTesting == 1)
    }

    @Test func scheduleFollowBottomScrollPerformsLayoutRetryOnlyWhenRequested() {
        StructuredSessionFeedScrollSupport.resetScrollToBottomInvocationCountForTesting()
        var scrollPosition = ScrollPosition(edge: .bottom)
        let binding = Binding(get: { scrollPosition }, set: { scrollPosition = $0 })
        var scheduledRetries = 0

        StructuredSessionFeedScrollSupport.scheduleFollowBottomScroll(
            position: binding,
            animation: .animated,
            layoutRetry: true,
            schedulePostLayoutRetry: { work in
                scheduledRetries += 1
                work()
            }
        )

        #expect(scheduledRetries == 1)
        #expect(StructuredSessionFeedScrollSupport.scrollToBottomInvocationCountForTesting == 2)
    }

    @Test func structuredSessionRequestBottomScrollInvokesPerformScrollOncePerCoalescedFlush() {
        StructuredSessionFeedScrollSupport.resetScrollToBottomInvocationCountForTesting()
        var scrollPosition = ScrollPosition(edge: .bottom)
        let binding = Binding(get: { scrollPosition }, set: { scrollPosition = $0 })
        var scheduled: [() -> Void] = []
        let coordinator = StructuredSessionAutoScrollCoordinator { work in
            scheduled.append(work)
        }

        structuredSessionRequestBottomScroll(
            intent: .immediate,
            coordinator: coordinator,
            draftGrowthThrottle: StructuredSessionDraftGrowthScrollThrottle(minimumInterval: 0.12, now: { 0 }),
            performScroll: { animation in
                StructuredSessionFeedScrollSupport.scheduleFollowBottomScroll(
                    position: binding,
                    animation: animation
                )
            }
        )

        #expect(scheduled.count == 1)
        scheduled.first?()
        #expect(StructuredSessionFeedScrollSupport.scrollToBottomInvocationCountForTesting == 1)
    }
}