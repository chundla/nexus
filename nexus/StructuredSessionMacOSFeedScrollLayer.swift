#if os(macOS)
    import NexusSessionPresentation
    import SwiftUI

    /// Isolates the structured-feed `ScrollView` modifier chain so `ContentView` type-checks.
    @MainActor
    struct MacStructuredSessionFeedScrollLayer<Content: View>: View {
        let presentation: FocusedStructuredSessionPresentation
        let feedPresentation: StructuredSessionFeedPresentation
        @Binding var scrollPosition: ScrollPosition
        @Binding var pinState: StructuredSessionFeedPinState
        @Binding var scrollSnapshot: StructuredSessionFeedScrollSnapshot?
        @Binding var visibleTailRowCount: Int
        let coordinator: StructuredSessionAutoScrollCoordinator
        let draftGrowthThrottle: StructuredSessionDraftGrowthScrollThrottle
        let onAppearSetup: () -> Void
        let onSessionIdentityChange: () -> Void
        @ViewBuilder let content: () -> Content

        private var usesBottomEdgeBinding: Bool {
            structuredSessionFeedUsesBottomEdgeScrollPositionBinding(for: presentation)
        }

        private var effectiveTurnOpen: Bool {
            structuredSessionEffectiveAgentTurnInProgress(for: presentation)
        }

        var body: some View {
            ScrollView {
                content()
            }
            .scrollPosition($scrollPosition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onScrollGeometryChange(for: StructuredSessionScrollGeometrySample.self) { geometry in
                StructuredSessionScrollGeometrySample(
                    distanceFromBottom: max(
                        0,
                        geometry.contentSize.height
                            - geometry.contentOffset.y
                            - geometry.containerSize.height
                    ),
                    contentOffsetY: geometry.contentOffset.y
                )
            } action: { _, sample in
                if let next = structuredSessionFeedPinStateIfChangedDuringOpenAgentTurn(
                    previous: pinState,
                    sample: sample,
                    effectiveTurnInProgress: effectiveTurnOpen
                ) {
                    pinState = next
                }
            }
            .onAppear {
                onAppearSetup()
                applyScrollSnapshotTransition(previous: nil, current: presentation.structuredSessionFeedScrollSnapshot)
            }
            .onChange(of: effectiveTurnOpen) { _, turnOpen in
                if turnOpen {
                    scrollPosition = ScrollPosition()
                    pinState = StructuredSessionFeedPinState(isFollowingBottom: false, userHasDetachedFromBottom: true)
                    reanchorScrollToOpenTurnIfNeeded()
                } else {
                    scrollPosition = ScrollPosition(edge: .bottom)
                }
            }
            .onChange(of: structuredSessionFeedFollowScrollToken(for: presentation)) { _, _ in
                reanchorScrollToOpenTurnIfNeeded()
            }
            .onChange(of: presentation.session.id) { _, _ in
                onSessionIdentityChange()
            }
            .onChange(of: presentation.structuredSessionFeedScrollSnapshot) { _, current in
                guard
                    structuredSessionFeedScrollSnapshotIfScrollPolicyChanged(
                        previous: scrollSnapshot,
                        current: current
                    ) != nil
                else {
                    return
                }
                applyScrollSnapshotTransition(previous: scrollSnapshot, current: current)
            }
            .onChange(of: feedPresentation.feedScrollItemCount) { _, total in
                let synced = StructuredSessionFeedSegmentRevealPolicy.synchronizedVisibleTailSegmentCount(
                    currentVisibleCount: visibleTailRowCount,
                    totalFeedSegmentCount: total
                )
                if synced != visibleTailRowCount {
                    visibleTailRowCount = synced
                }
            }
        }

        private func reanchorScrollToOpenTurnIfNeeded() {
            guard effectiveTurnOpen,
                let turnID = structuredSessionFeedScrollAnchorTurnID(in: feedPresentation.feedSegments)
            else {
                return
            }
            var position = ScrollPosition()
            position.scrollTo(id: turnID)
            scrollPosition = position
        }

        private func applyScrollSnapshotTransition(
            previous: StructuredSessionFeedScrollSnapshot?,
            current: StructuredSessionFeedScrollSnapshot
        ) {
            scrollSnapshot = StructuredSessionFeedScrollSupport.applyStructuredSessionFeedScrollSnapshotTransition(
                previous: previous,
                current: current,
                isFollowingBottom: pinState.isFollowingBottom,
                coordinator: coordinator,
                draftGrowthThrottle: draftGrowthThrottle,
                scrollPosition: $scrollPosition,
                scrollPositionUsesBottomEdge: usesBottomEdgeBinding
            )
        }
    }
#endif
