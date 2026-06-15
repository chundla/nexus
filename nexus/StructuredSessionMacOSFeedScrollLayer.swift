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
                // Geometry-driven pin updates fight growing final-answer layout on AppKit (#hang).
                guard effectiveTurnOpen == false else {
                    if let next = structuredSessionFeedPinStateIfChangedDuringOpenAgentTurn(
                        previous: pinState,
                        sample: sample,
                        effectiveTurnInProgress: true
                    ) {
                        pinState = next
                    }
                    return
                }
            }
            .onAppear {
                onAppearSetup()
                applyScrollSnapshotTransition(previous: nil, current: presentation.structuredSessionFeedScrollSnapshot)
            }
            .onChange(of: effectiveTurnOpen) { _, turnOpen in
                if turnOpen {
                    // Detach bottom-edge binding only; do not `scrollTo(turnID)` — that pins the viewport
                    // while the agent-turn card grows and leaves interim `Pi:` stuck at the bottom.
                    scrollPosition = ScrollPosition()
                    pinState = StructuredSessionFeedPinState(isFollowingBottom: false, userHasDetachedFromBottom: true)
                } else {
                    // Do not bind bottom edge or re-enable tail-follow while final markdown lays out.
                    scrollPosition = ScrollPosition()
                    pinState = StructuredSessionFeedPinState(isFollowingBottom: false, userHasDetachedFromBottom: true)
                }
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
