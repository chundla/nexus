import Foundation
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionMarkdownRendererTests {
    @Test func rendererSkipsMarkdownParsingForPlainText() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString(text.uppercased())
            }
        )

        let rendered = renderer.render("Plain status update")

        #expect(String(rendered.characters) == "Plain status update")
        #expect(parseCallCount == 0)
    }

    @Test func rendererReturnsPlainContentForPlainText() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString(text.uppercased())
            }
        )

        let rendered = renderer.renderContent("Plain status update")

        #expect(rendered == .plain("Plain status update"))
        #expect(parseCallCount == 0)
    }

    @Test func rendererReturnsAttributedContentForMarkdownText() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )

        let rendered = renderer.renderContent("**bold**")

        #expect(rendered == .attributed(AttributedString("rendered: **bold**")))
        #expect(parseCallCount == 1)
    }

    @Test func rendererCachesRepeatedMarkdownStrings() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )

        let first = renderer.render("**bold**")
        let second = renderer.render("**bold**")

        #expect(String(first.characters) == "rendered: **bold**")
        #expect(String(second.characters) == "rendered: **bold**")
        #expect(parseCallCount == 1)
    }

    @Test func rendererEvictsLeastRecentlyUsedMarkdownWhenCacheLimitIsReached() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 2,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )

        _ = renderer.render("**first**")
        _ = renderer.render("**second**")
        _ = renderer.render("**first**")
        _ = renderer.render("**third**")
        _ = renderer.render("**second**")

        #expect(parseCallCount == 4)
    }

    @Test func rendererTracksCacheAndParseMetrics() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 2,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )

        renderer.resetMetrics()
        _ = renderer.render("plain text")
        _ = renderer.render("**bold**")
        _ = renderer.render("**bold**")

        let metrics = renderer.metricsSnapshot()

        #expect(parseCallCount == 1)
        #expect(metrics.plainTextBypassCount == 1)
        #expect(metrics.parseCount == 1)
        #expect(metrics.cacheHitCount == 1)
        #expect(metrics.cacheMissCount == 1)
        #expect(metrics.cachedEntryCount == 1)
    }

    @Test func rendererPreservesListLineBreaksForBlockMarkdown() {
        let renderer = StructuredSessionMarkdownRenderer(cacheLimit: 0)
        let markdown = """
        In `/Users/ck/source/repos/nexus`:

        - `.DS_Store`
        - `.git/`
        - `.gitignore`

        Want a recursive tree too?
        """

        let rendered = renderer.render(markdown)

        #expect(
            String(rendered.characters) == """
            In /Users/ck/source/repos/nexus:

            - .DS_Store
            - .git/
            - .gitignore

            Want a recursive tree too?
            """
        )
    }

    @Test func rendererPreservesMultilineFencedCodeBlocks() {
        let renderer = StructuredSessionMarkdownRenderer(cacheLimit: 0)
        let markdown = """
        Before

        ```swift
        print(1)
        print(2)
        ```

        After
        """

        let rendered = renderer.render(markdown)

        #expect(
            String(rendered.characters) == """
            Before

            print(1)
            print(2)

            After
            """
        )
    }

    @Test func structuredSessionFeedTextSelectionDefaultsMatchPlatformPolicy() {
        #if os(macOS)
        #expect(StructuredSessionFeedTextSelectionPolicy.isEnabled == false)
        #else
        #expect(StructuredSessionFeedTextSelectionPolicy.isEnabled == true)
        #endif
    }
}
