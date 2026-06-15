import Foundation
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionAssistantFullResponseReaderTests {
    @Test func structuredSessionAssistantFullResponseCodeBlockPolicyEnablesCopyAndHorizontalScrollOnBothPlatforms() {
        let policy = structuredSessionAssistantFullResponseCodeBlockPolicy()

        #expect(policy.showsCopyAction)
        #expect(policy.enablesPerBlockTextSelection)
        #expect(policy.usesHorizontalScrolling)
        #expect(policy.usesMonospacedPresentation)
        #expect(policy.contentPaddingPoints > 0)
        #expect(policy.blockCornerRadiusPoints > 0)
    }

    @Test func structuredSessionAssistantFullResponseCodeBlockPolicyUsesReadableMonospaceScale() {
        let policy = structuredSessionAssistantFullResponseCodeBlockPolicy()

        #expect(policy.monospacedFontScale > 0.75)
        #expect(policy.monospacedFontScale < 1.0)
        #expect(policy.lineSpacingEm > 0)
    }

    @Test func structuredSessionAssistantFullResponseExtractsFencedCodeBlocksForCopyActions() {
        let markdown = """
        Intro

        ```swift
        let x = 1
        print(x)
        ```

        ```bash
        git status
        ```
        """

        let blocks = structuredSessionAssistantFullResponseFencedCodeBlocks(in: markdown)

        #expect(blocks.count == 2)
        #expect(blocks[0].language == "swift")
        #expect(blocks[0].content == "let x = 1\nprint(x)")
        #expect(blocks[1].language == "bash")
        #expect(blocks[1].content == "git status")
    }

    @Test func structuredSessionAssistantFullResponseDisplayMathPolicyDetectsDoubleDollarDelimiters() {
        let policy = structuredSessionAssistantFullResponseDisplayMathPolicy()

        #expect(policy.detectsDoubleDollarDelimiters)
        #expect(policy.detectsBracketDelimiters)
        #expect(policy.maxDisplayMathBlocksPerDocument > 0)
    }

    @Test func structuredSessionAssistantFullResponseExtractsDisplayMathBlocksFromDoubleDollarFences() {
        let markdown = """
        Before

        $$
        E = mc^2
        $$

        After
        """

        let blocks = structuredSessionAssistantFullResponseDisplayMathBlocks(in: markdown)

        #expect(blocks.count == 1)
        #expect(blocks[0].latex == "E = mc^2")
        #expect(blocks[0].delimiter == .doubleDollar)
    }

    @Test func structuredSessionAssistantFullResponseExtractsDisplayMathFromBracketDelimiters() {
        let markdown = """
        \\[
        \\int_0^1 x\\,dx
        \\]
        """

        let blocks = structuredSessionAssistantFullResponseDisplayMathBlocks(in: markdown)

        #expect(blocks.count == 1)
        #expect(blocks[0].latex == "\\int_0^1 x\\,dx")
        #expect(blocks[0].delimiter == .bracket)
    }

    @Test func structuredSessionAssistantFullResponseSegmentsInterleaveMarkdownAndDisplayMath() {
        let markdown = """
        ## Result

        $$
        a^2 + b^2 = c^2
        $$

        Done.
        """

        let segments = structuredSessionAssistantFullResponseReaderSegments(in: markdown)

        #expect(segments.count == 3)
        #expect(segments[0].markdownChunk?.contains("## Result") == true)
        #expect(segments[1].displayMath?.latex == "a^2 + b^2 = c^2")
        #expect(segments[2].markdownChunk?.contains("Done.") == true)
    }

    @Test func structuredSessionFeedPlainFallbackBypassesMarkdownParseForDisplayMath() {
        let markdown = """
        Summary

        $$
        \\sum_{i=1}^n i
        $$
        """

        #expect(structuredSessionFeedDisplayMathUsesPlainFallback(for: markdown))

        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString("parsed: \(text)")
            }
        )

        let rendered = renderer.renderContent(markdown)

        #expect(rendered == .plain(markdown))
        #expect(parseCallCount == 0)
    }

    @Test func structuredSessionAssistantFullResponseIgnoresDisplayMathInsideFencedCode() {
        let markdown = """
        ```text
        $$
        not math
        $$
        ```
        """

        let blocks = structuredSessionAssistantFullResponseDisplayMathBlocks(in: markdown)
        #expect(blocks.isEmpty)
    }
}