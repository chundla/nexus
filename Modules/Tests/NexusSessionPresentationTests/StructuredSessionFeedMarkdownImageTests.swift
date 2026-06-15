import Foundation
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionFeedMarkdownImageTests {
    @Test func feedMarkdownImageReferencesExtractSingleInlineImage() {
        let markdown = "Before ![diagram](https://example.com/a.png) after"

        let refs = structuredSessionFeedMarkdownImageReferences(in: markdown)

        #expect(refs.count == 1)
        #expect(refs[0].altText == "diagram")
        #expect(refs[0].urlString == "https://example.com/a.png")
    }

    @Test func feedMarkdownImageReferencesIgnoreImagesInsideFencedCode() {
        let markdown = """
        ```text
        ![not an image](https://example.com/skip.png)
        ```
        """

        let refs = structuredSessionFeedMarkdownImageReferences(in: markdown)

        #expect(refs.isEmpty)
    }

    @Test func feedMarkdownBodySegmentsInterleaveTextAndImages() {
        let markdown = "One ![a](https://a.test/1.png)\nTwo ![b](https://b.test/2.png)"

        let segments = structuredSessionFeedMarkdownBodySegments(in: markdown)

        #expect(segments.count == 4)
        #expect(segments[0] == .text("One "))
        #expect(segments[1] == .image(.init(altText: "a", urlString: "https://a.test/1.png")))
        #expect(segments[2] == .text("\nTwo "))
        #expect(segments[3] == .image(.init(altText: "b", urlString: "https://b.test/2.png")))
    }

    @Test func feedMarkdownShowsInlineImagePreviewsWhenImageSyntaxPresent() {
        #expect(structuredSessionFeedMarkdownShowsInlineImagePreviews(in: "![x](https://a.test/x.png)"))
        #expect(structuredSessionFeedMarkdownShowsInlineImagePreviews(in: "plain text") == false)
    }

    @Test func remoteClientImageURLPolicyAllowsHTTPSAndRejectsOpaqueSchemes() {
        let https = URL(string: "https://cdn.example.com/x.png")!
        let http = URL(string: "http://127.0.0.1/x.png")!
        let file = URL(string: "file:///tmp/x.png")!
        let data = URL(string: "data:image/png;base64,abc")!

        #expect(StructuredSessionFeedRemoteClientImageURLPolicy.allows(https))
        #expect(StructuredSessionFeedRemoteClientImageURLPolicy.allows(http))
        #expect(StructuredSessionFeedRemoteClientImageURLPolicy.allows(file) == false)
        #expect(StructuredSessionFeedRemoteClientImageURLPolicy.allows(data) == false)
    }
}