import MarkdownUI
import SwiftUI

/// Dedicated full assistant response reader for structured Session feed rows (#226).
@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionAssistantFullResponseReader: View {
    private let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    public var body: some View {
        ScrollView {
            Markdown(markdown)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    ScrollView(.horizontal, showsIndicators: true) {
                        configuration.label
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}