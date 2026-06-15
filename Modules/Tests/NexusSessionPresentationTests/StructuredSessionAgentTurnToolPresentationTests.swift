import Foundation
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionAgentTurnToolPresentationTests {
    @Test func collapsedCommandLineFormatsReadAndSearch() {
        #expect(
            structuredSessionAgentTurnToolCollapsedCommandLine(callPreview: "read: crates/gpui/src/element.rs")
                == "Read crates/gpui/src/element.rs"
        )
        #expect(
            structuredSessionAgentTurnToolCollapsedCommandLine(callPreview: "grep: accessibility in crates/gpui/")
                == "Search accessibility in crates/gpui/"
        )
        #expect(
            structuredSessionAgentTurnToolCollapsedCommandLine(callPreview: "/bash ls -la")
                == "Bash ls -la"
        )
    }

    @Test func reasoningCollapsedPreviewUsesLastParagraph() {
        let body = "First thought.\n\nSecond thought.\n\nFinal thought."
        #expect(structuredSessionAgentTurnReasoningCollapsedPreview(markdownBody: body) == "Final thought.")
    }

    @Test func toolRawJSONCandidatePrefersDetailBody() {
        let json = "{\"path\":\"README.md\"}"
        #expect(
            structuredSessionAgentTurnToolRawJSONCandidate(callPreview: "read: README.md", detailText: json)
                == json
        )
        #expect(
            structuredSessionAgentTurnToolRawJSONCandidate(callPreview: "read: x.swift", detailText: "plain text")
                == nil
        )
    }
}