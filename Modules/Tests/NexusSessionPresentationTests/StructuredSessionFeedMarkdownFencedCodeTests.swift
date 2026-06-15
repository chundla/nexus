import Foundation
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionFeedMarkdownFencedCodeTests {
    @Test func feedMarkdownParseSplitsProseAndFencedBlocks() {
        let markdown = """
        Before

        ```swift
        let x = 1
        ```

        After
        """
        let result = structuredSessionFeedMarkdownParse(markdown)

        #expect(result.segments.count == 3)
        #expect(result.segments[0] == .prose("Before"))
        #expect(result.segments[1] == .fencedCode(language: "swift", content: "let x = 1"))
        #expect(result.segments[2] == .prose("After"))
        #expect(result.fencedBlockCount == 1)
        #expect(result.stoppedEarlyDueToBounds == false)
    }

    @Test func feedMarkdownParseBoundsCapFencedBlockCount() {
        var markdown = ""
        for index in 0 ..< 5 {
            markdown += "```txt\nblock\(index)\n```\n\n"
        }
        let bounds = StructuredSessionFeedMarkdownParseBounds(maxFencedBlocks: 2, maxScannedLines: 10_000)
        let result = structuredSessionFeedMarkdownParse(markdown, bounds: bounds)

        #expect(result.fencedBlockCount == 2)
        #expect(result.stoppedEarlyDueToBounds == true)
    }

    @Test func feedMarkdownParseBoundsCapScannedLines() {
        let lineCount = 50
        let markdown = (0 ..< lineCount).map { "line \($0)" }.joined(separator: "\n")
        let bounds = StructuredSessionFeedMarkdownParseBounds(maxFencedBlocks: 32, maxScannedLines: 20)
        let result = structuredSessionFeedMarkdownParse(markdown, bounds: bounds)

        #expect(result.scannedLineCount == lineCount)
        #expect(result.stoppedEarlyDueToBounds == true)
    }

    @Test func feedFencedCodeBlockPolicyEnablesCopyAndHighlight() {
        let policy = structuredSessionFeedFencedCodeBlockPolicy()
        #expect(policy.showsCopyAction)
        #expect(policy.enablesLightweightSyntaxHighlight)
    }

    @Test func rendererReturnsSegmentsWhenMarkdownContainsFences() {
        let renderer = StructuredSessionMarkdownRenderer(cacheLimit: 0)
        let markdown = """
        Intro
        ```bash
        git status
        ```
        """
        let rendered = renderer.renderContent(markdown)

        guard case .segments(let segments) = rendered else {
            Issue.record("Expected segments render path")
            return
        }
        #expect(segments.count == 2)
        #expect(segments[0] == .prose("Intro"))
        #expect(segments[1] == .fencedCode(language: "bash", content: "git status"))
    }
}
