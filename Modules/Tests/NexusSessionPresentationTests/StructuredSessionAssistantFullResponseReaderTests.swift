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
}