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
                // Drive pin/follow state from viewport distance at all times (including during
                // open agent turns with Thinking/tool rows/final streaming). The distance-based
                // rule (see structuredSessionFeedPinState / DuringOpenAgentTurn) sets
                // isFollowingBottom when distanceFromBottom <= pinThreshold. This gives classic
                // autoscroll-to-bottom unless the user has scrolled away to read history.
                // Scrolling the viewport back to the bottom (small distance) re-enables following
                // and subsequent snapshot transitions will request bottom scroll.
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
            .onChange(of: effectiveTurnOpen) { _, _ in
                // Turn open/close (Thinking / tool execution / final streaming) changes content height
                // dramatically. Reset the ScrollPosition binding (avoids sticking to a row ID that is
                // about to grow or be replaced). Do NOT hard-force pinState here.
                //
                // The live onScrollGeometryChange action always runs the distance-based pin logic
                // (structuredSessionFeedPinStateIfChangedDuringOpenAgentTurn → normal distance rule).
                // This restores classic autoscroll behavior:
                // - If viewport is near bottom (distance ≤ 48pt) → isFollowingBottom = true → follow new content.
                // - If user scrolled up to read history (distance > threshold) → detached; no auto-scroll.
                // - User scrolls back to bottom → geometry sample re-enables following for subsequent updates.
                scrollPosition = ScrollPosition()
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
