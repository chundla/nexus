#if os(macOS)
    import NexusSessionPresentation
    import SwiftUI

    private struct MacEquatableStructuredSessionActivityRow<Content: View>: View, Equatable {
        let row: StructuredSessionActivityRow
        @ViewBuilder let content: () -> Content

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.row == rhs.row
        }

        var body: some View {
            content()
        }
    }

    /// Extracted from `ContentView` so the structured-feed `LazyVStack` type-checks.
    @MainActor
    struct MacStructuredSessionFeedScrollContent<HistoryPaging: View, ActivityRow: View, ThinkingIndicator: View>: View
    {
        let structuredPresentation: FocusedStructuredSessionPresentation
        let feedPresentation: StructuredSessionFeedPresentation
        let visibleTailRowCount: Int
        let disclosureState: StructuredSessionAgentTurnDisclosureState
        @ViewBuilder let historyPaging: () -> HistoryPaging
        let activityRow: (StructuredSessionActivityRow) -> ActivityRow
        let onShowFullAssistantResponse: (StructuredSessionAssistantFullResponsePresentation) -> Void
        @ViewBuilder let thinkingIndicator: (StructuredSessionThinkingIndicator) -> ThinkingIndicator

        var body: some View {
            LazyVStack(alignment: .leading, spacing: 8) {
                historyPaging()
                    .padding(.bottom, 6)

                feedBody

                Color.clear
                    .frame(height: 1)
                    .id(structuredSessionFeedBottomSentinelID)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .scrollTargetLayout()
            .environment(
                \.structuredSessionFeedMarkdownHydrationAllowed,
                StructuredSessionFeedMacOSStartupPolicy.isFeedMarkdownHydrationAllowed(
                    visibleTailRowCount: visibleTailRowCount,
                    totalActivityRowCount: feedPresentation.feedScrollItemCount
                )
            )
        }

        @ViewBuilder
        private var feedBody: some View {
            if feedPresentation.activityRowChunks.isEmpty {
                ContentUnavailableView(
                    feedPresentation.copy.emptyStateTitle,
                    systemImage: "message",
                    description: Text(feedPresentation.copy.emptyStateDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if feedPresentation.activityRows.isEmpty == false {
                MacStructuredSessionFeedVisibleItems(
                    structuredPresentation: structuredPresentation,
                    feedPresentation: feedPresentation,
                    visibleTailRowCount: visibleTailRowCount,
                    disclosureState: disclosureState,
                    activityRow: activityRow,
                    onShowFullAssistantResponse: onShowFullAssistantResponse
                )

                if StructuredSessionFeedMacOSStartupPolicy.shouldShowThinkingIndicator(
                    in: feedPresentation,
                    visibleTailRowCount: visibleTailRowCount
                ), let indicator = feedPresentation.thinkingIndicator {
                    thinkingIndicator(indicator)
                        .id("structured-session-thinking-indicator")
                }
            }
        }
    }

    @MainActor
    private struct MacStructuredSessionFeedVisibleItems<ActivityRow: View>: View {
        let structuredPresentation: FocusedStructuredSessionPresentation
        let feedPresentation: StructuredSessionFeedPresentation
        let visibleTailRowCount: Int
        let disclosureState: StructuredSessionAgentTurnDisclosureState
        let activityRow: (StructuredSessionActivityRow) -> ActivityRow
        let onShowFullAssistantResponse: (StructuredSessionAssistantFullResponsePresentation) -> Void

        var body: some View {
            if feedPresentation.feedSegments != nil {
                segmentList
            } else {
                flatRowList
            }
        }

        private var visibleSegments: [StructuredSessionFeedSegment] {
            let all = feedPresentation.feedSegments ?? []
            let raw =
                structuredSessionVisibleFeedSegments(
                    in: feedPresentation,
                    visibleTailItemCount: visibleTailRowCount
                ) ?? []
            return raw.filter { segment in
                guard case .standalone(let item) = segment else {
                    return true
                }
                return structuredSessionPiShouldRenderStandaloneFeedSegment(item: item, in: all)
            }
        }

        @ViewBuilder
        private var segmentList: some View {
            ForEach(visibleSegments) { segment in
                StructuredSessionPiFeedSegmentView(
                    segment: segment,
                    providerDisplayName: structuredPresentation.session.providerID.displayName,
                    style: macOSPiStructuredSessionFeedSegmentStyle(),
                    disclosureState: disclosureState,
                    standaloneRow: { row in
                        AnyView(activityRow(row))
                    },
                    onShowFullAssistantResponse: onShowFullAssistantResponse,
                    artifactActions: { artifact in
                        structuredSessionFeedArtifactActionPresentation(
                            for: artifact,
                            hasWriterAuthority: true,
                            usesHostArtifactFetch: false
                        )
                    },
                    onArtifactOpenOnHost: { artifact in
                        guard let path = artifact.hostPath else { return }
                        StructuredSessionFeedArtifactHostActions.openOnHost(path: path)
                    }
                )
                .id(segment.id)
            }
        }

        @ViewBuilder
        private var flatRowList: some View {
            let visibleRows = StructuredSessionFeedMacOSStartupPolicy.visibleActivityRows(
                in: feedPresentation,
                visibleTailRowCount: visibleTailRowCount
            )
            ForEach(visibleRows) { row in
                MacEquatableStructuredSessionActivityRow(row: row) {
                    activityRow(row)
                }
                .equatable()
                .id(row.id)
            }
        }
    }
#endif
