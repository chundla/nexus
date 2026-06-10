import Foundation
@testable import NexusSessionPresentation
import Testing

@MainActor
private final class StructuredSessionMarkdownHydrationDeliveryCounter {
    var count = 0
}

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

    @Test func structuredSessionFeedTextSelectionIsDisabledForScrollPerformance() {
        #expect(StructuredSessionFeedTextSelectionPolicy.isEnabled == false)
    }

    @Test func structuredSessionMarkdownDisplayedContentDefersParseUntilAppearOnMacOS() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )
        let markdown = "**bold**"

        let beforeAppear = structuredSessionMarkdownDisplayedContent(
            markdown: markdown,
            renderer: renderer,
            defersParseUntilAppear: true,
            hasAppeared: false
        )
        #expect(beforeAppear == .plain(markdown))
        #expect(parseCallCount == 0)

        _ = structuredSessionMarkdownDisplayedContent(
            markdown: markdown,
            renderer: renderer,
            defersParseUntilAppear: true,
            hasAppeared: true
        )
        #expect(parseCallCount == 1)
    }

    @Test func structuredSessionMarkdownDisplayedContentDoesNotDeferPlainText() {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString(text.uppercased())
            }
        )

        let displayed = structuredSessionMarkdownDisplayedContent(
            markdown: "plain status",
            renderer: renderer,
            defersParseUntilAppear: true,
            hasAppeared: false
        )
        #expect(displayed == .plain("plain status"))
        #expect(parseCallCount == 0)
    }

    @Test func structuredSessionMarkdownRowHydrationSchedulerDefersParseOffMainThread() async {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 4,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )
        let markdown = "**bold**"

        StructuredSessionMarkdownRowHydrationScheduler.scheduleHydration(
            markdown: markdown,
            renderer: renderer
        ) { _ in }

        #expect(parseCallCount == 0)

        await Task.yield()
        await StructuredSessionMarkdownRowHydrationScheduler.drainForTesting()

        #expect(parseCallCount == 1)
    }

    @Test @MainActor func structuredSessionMarkdownRowHydrationSchedulerDeliversAllScheduledRows() async {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 8,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )
        let deliveryCounter = StructuredSessionMarkdownHydrationDeliveryCounter()

        for index in 0 ..< 4 {
            StructuredSessionMarkdownRowHydrationScheduler.scheduleHydration(
                markdown: "**item \(index)**",
                renderer: renderer
            ) { _ in
                deliveryCounter.count += 1
            }
        }

        await Task.yield()
        await StructuredSessionMarkdownRowHydrationScheduler.drainForTesting()

        #expect(parseCallCount == 4)
        #expect(deliveryCounter.count == 4)
        let flushCount = await StructuredSessionMarkdownRowHydrationScheduler.deliveryFlushCountForTesting()
        #expect(flushCount >= 1)
        #expect(flushCount < 4)
    }

    @Test @MainActor func structuredSessionMarkdownRowHydrationSchedulerCapsMainActorDeliveriesPerFlush() async {
        var parseCallCount = 0
        let renderer = StructuredSessionMarkdownRenderer(
            cacheLimit: 16,
            parser: { text in
                parseCallCount += 1
                return AttributedString("rendered: \(text)")
            }
        )
        let deliveryCounter = StructuredSessionMarkdownHydrationDeliveryCounter()
        let jobCount = 12

        for index in 0 ..< jobCount {
            StructuredSessionMarkdownRowHydrationScheduler.scheduleHydration(
                markdown: "**cap \(index)**",
                renderer: renderer
            ) { _ in
                deliveryCounter.count += 1
            }
        }

        await Task.yield()
        await StructuredSessionMarkdownRowHydrationScheduler.drainForTesting()

        #expect(parseCallCount == jobCount)
        #expect(deliveryCounter.count == jobCount)
        let flushCount = await StructuredSessionMarkdownRowHydrationScheduler.deliveryFlushCountForTesting()
        #if os(macOS)
        #expect(flushCount >= 2)
        #expect(flushCount < jobCount)
        #else
        #expect(flushCount == 1)
        #endif
    }
}
