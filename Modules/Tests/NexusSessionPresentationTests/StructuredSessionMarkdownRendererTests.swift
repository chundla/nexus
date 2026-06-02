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
}
