import SwiftUI

/// Reasoning / Final answer feed markdown: inline images when `![alt](url)` is present (#242).
@available(macOS 12.0, iOS 15.0, *)
@MainActor
@ViewBuilder
public func structuredSessionFeedMarkdownContentView(
    markdown: String,
    font: Font,
    color: Color,
    renderer: StructuredSessionMarkdownRenderer = .shared
) -> some View {
    if structuredSessionFeedMarkdownShowsInlineImagePreviews(in: markdown) {
        StructuredSessionFeedMarkdownBodySegmentsView(
            markdown: markdown,
            font: font,
            color: color,
            renderer: renderer
        )
    } else {
        StructuredSessionMarkdownText(
            markdown: markdown,
            font: font,
            color: color,
            renderer: renderer
        )
    }
}

public func structuredSessionFeedMarkdownShowsInlineImagePreviews(in markdown: String) -> Bool {
    structuredSessionFeedMarkdownImageReferences(in: markdown).isEmpty == false
}

@available(macOS 12.0, iOS 15.0, *)
@MainActor
@ViewBuilder
func structuredSessionFeedFinalAnswerMarkdownView(
    markdown: String,
    font: Font,
    color: Color,
    prefersPlainTextUntilIdle: Bool,
    allowsInlineMarkdownHydration: Bool,
    renderer: StructuredSessionMarkdownRenderer = .shared
) -> some View {
    if structuredSessionFeedMarkdownShowsInlineImagePreviews(in: markdown) {
        StructuredSessionFeedMarkdownBodySegmentsView(
            markdown: markdown,
            font: font,
            color: color,
            renderer: renderer
        )
    } else {
        StructuredSessionIdleGatedAssistantFeedMarkdownText(
            markdown: markdown,
            font: font,
            color: color,
            prefersPlainTextUntilIdle: prefersPlainTextUntilIdle,
            allowsInlineMarkdownHydration: allowsInlineMarkdownHydration,
            renderer: renderer
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionFeedMarkdownBodySegmentsView: View {
    private let segments: [StructuredSessionFeedMarkdownBodySegment]
    private let font: Font
    private let color: Color
    private let renderer: StructuredSessionMarkdownRenderer

    public init(
        markdown: String,
        font: Font,
        color: Color,
        renderer: StructuredSessionMarkdownRenderer = .shared
    ) {
        self.segments = structuredSessionFeedMarkdownBodySegments(in: markdown)
        self.font = font
        self.color = color
        self.renderer = renderer
    }

    public var body: some View {
        let imageRefs = segments.compactMap { segment -> StructuredSessionFeedMarkdownImageReference? in
            guard case .image(let ref) = segment else { return nil }
            return ref
        }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if text.isEmpty == false {
                        Text(renderer.render(text))
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .image(let ref):
                    if imageRefs.count > 1 {
                        EmptyView()
                    } else {
                        StructuredSessionFeedInlineImagePreview(reference: ref)
                    }
                }
            }
            if imageRefs.count > 1 {
                StructuredSessionFeedMarkdownImageCarousel(references: imageRefs)
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct StructuredSessionFeedInlineImagePreview: View {
    let reference: StructuredSessionFeedMarkdownImageReference
    @State private var isExpanded = false

    var body: some View {
        Group {
            if let url = structuredSessionFeedResolvedImageURL(for: reference) {
                Button {
                    isExpanded = true
                } label: {
                    StructuredSessionFeedLazyRemoteImage(url: url, altText: reference.altText)
                        .frame(maxWidth: 420, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isExpanded) {
                    StructuredSessionFeedExpandedImageSheet(url: url, altText: reference.altText)
                }
            } else {
                StructuredSessionFeedUnsupportedImagePlaceholder(altText: reference.altText)
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct StructuredSessionFeedMarkdownImageCarousel: View {
    let references: [StructuredSessionFeedMarkdownImageReference]
    @State private var selection = 0
    @State private var expandedReference: StructuredSessionFeedMarkdownImageReference?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabView(selection: $selection) {
                ForEach(Array(references.enumerated()), id: \.offset) { index, ref in
                    Group {
                        if let url = structuredSessionFeedResolvedImageURL(for: ref) {
                            Button {
                                expandedReference = ref
                            } label: {
                                StructuredSessionFeedLazyRemoteImage(url: url, altText: ref.altText)
                            }
                            .buttonStyle(.plain)
                        } else {
                            StructuredSessionFeedUnsupportedImagePlaceholder(altText: ref.altText)
                        }
                    }
                    .tag(index)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            #else
            .tabViewStyle(.automatic)
            #endif

            if references.count > 1 {
                Text("\(selection + 1) of \(references.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $expandedReference) { ref in
            if let url = structuredSessionFeedResolvedImageURL(for: ref) {
                StructuredSessionFeedExpandedImageSheet(url: url, altText: ref.altText)
            }
        }
    }
}

extension StructuredSessionFeedMarkdownImageReference: Identifiable {
    public var id: String { "\(altText)|\(urlString)" }
}

@available(macOS 12.0, iOS 15.0, *)
struct StructuredSessionFeedLazyRemoteImage: View {
    let url: URL
    let altText: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.06))
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                StructuredSessionFeedUnsupportedImagePlaceholder(altText: altText)
            @unknown default:
                EmptyView()
            }
        }
        .accessibilityLabel(altText.isEmpty ? "Image" : altText)
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct StructuredSessionFeedExpandedImageSheet: View {
    let url: URL
    let altText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if #available(macOS 13.0, iOS 16.0, *) {
                NavigationStack {
                    expandedImageScrollContent
                }
            } else {
                NavigationView {
                    expandedImageScrollContent
                }
            }
        }
    }

    private var expandedImageScrollContent: some View {
        ScrollView {
            StructuredSessionFeedLazyRemoteImage(url: url, altText: altText)
                .padding()
        }
        .navigationTitle(altText.isEmpty ? "Image" : altText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct StructuredSessionFeedUnsupportedImagePlaceholder: View {
    let altText: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.title2)
            Text(altText.isEmpty ? "Image unavailable" : altText)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func structuredSessionFeedResolvedImageURL(
    for reference: StructuredSessionFeedMarkdownImageReference
) -> URL? {
    guard let url = URL(string: reference.urlString) else {
        return nil
    }
    guard StructuredSessionFeedRemoteClientImageURLPolicy.allows(url) else {
        return nil
    }
    return url
}