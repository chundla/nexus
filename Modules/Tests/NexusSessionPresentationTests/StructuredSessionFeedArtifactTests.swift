import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

struct StructuredSessionFeedArtifactTests {
    @Test func piExportedSessionHTMLStatusMapsToArtifactPresentation() {
        let itemID = UUID()
        let item = SessionActivityItem(
            id: itemID,
            kind: .status,
            text: "Exported session HTML to /tmp/pi-session.html"
        )

        let artifact = structuredSessionFeedArtifactPresentation(for: item)

        #expect(artifact?.activityItemID == itemID)
        #expect(artifact?.kind == .piExportedSessionHTML)
        #expect(artifact?.fileName == "pi-session.html")
        #expect(artifact?.hostPath == "/tmp/pi-session.html")
        #expect(artifact?.title == "Session HTML export")
    }

    @Test func piExportedSessionHTMLWithoutPathStillMapsToArtifact() {
        let item = SessionActivityItem(kind: .status, text: "Exported session HTML")

        let artifact = structuredSessionFeedArtifactPresentation(for: item)

        #expect(artifact?.kind == .piExportedSessionHTML)
        #expect(artifact?.fileName == "session.html")
        #expect(artifact?.hostPath == nil)
    }

    @Test func unrelatedStatusRowsDoNotMapToArtifacts() {
        let item = SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")

        #expect(structuredSessionFeedArtifactPresentation(for: item) == nil)
    }

    @Test func piFeedSegmentsKeepExportArtifactAsStandaloneOutsideAgentTurn() throws {
        let exportID = UUID()
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: export", prompt: SessionPrompt(text: "export")),
                SessionActivityItem(kind: .message, text: "Pi: done"),
                SessionActivityItem(
                    id: exportID,
                    kind: .status,
                    text: "Exported session HTML to /tmp/out.html"
                ),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 3)
        guard case .standalone(let export) = segments[2] else {
            Issue.record("Expected export status as standalone segment")
            return
        }
        #expect(export.id == exportID)
        #expect(structuredSessionFeedArtifactPresentation(for: export)?.hostPath == "/tmp/out.html")
    }

    @Test func remoteClientArtifactActionsRequireControllerForDownload() {
        let artifact = StructuredSessionFeedArtifactPresentation(
            activityItemID: UUID(),
            kind: .piExportedSessionHTML,
            title: "Session HTML export",
            fileName: "out.html",
            hostPath: "/tmp/out.html"
        )

        let viewer = structuredSessionFeedArtifactActionPresentation(
            for: artifact,
            hasWriterAuthority: false,
            usesHostArtifactFetch: true
        )
        #expect(viewer.canDownload == false)
        #expect(viewer.canOpenOnHost == false)
        #expect(viewer.disabledReason?.contains("Controller") == true)

        let controller = structuredSessionFeedArtifactActionPresentation(
            for: artifact,
            hasWriterAuthority: true,
            usesHostArtifactFetch: true
        )
        #expect(controller.canDownload == true)
        #expect(controller.canOpenOnHost == false)
    }

    @Test func macOSArtifactActionsAllowOpenWhenHostPathPresent() {
        let artifact = StructuredSessionFeedArtifactPresentation(
            activityItemID: UUID(),
            kind: .piExportedSessionHTML,
            title: "Session HTML export",
            fileName: "out.html",
            hostPath: "/tmp/out.html"
        )

        let actions = structuredSessionFeedArtifactActionPresentation(
            for: artifact,
            hasWriterAuthority: true,
            usesHostArtifactFetch: false
        )
        #expect(actions.canOpenOnHost == true)
        #expect(actions.canDownload == false)
    }
}
