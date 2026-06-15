import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionFeedArtifactPreviewCard: View {
    public let artifact: StructuredSessionFeedArtifactPresentation
    public let actions: StructuredSessionFeedArtifactActionPresentation
    public let onDownload: (() -> Void)?
    public let onOpenOnHost: (() -> Void)?

    public init(
        artifact: StructuredSessionFeedArtifactPresentation,
        actions: StructuredSessionFeedArtifactActionPresentation,
        onDownload: (() -> Void)? = nil,
        onOpenOnHost: (() -> Void)? = nil
    ) {
        self.artifact = artifact
        self.actions = actions
        self.onDownload = onDownload
        self.onOpenOnHost = onOpenOnHost
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.subheadline.weight(.semibold))
                    Text(artifact.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let disabledReason = actions.disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if actions.canDownload {
                    Button("Download", action: { onDownload?() })
                        .buttonStyle(.bordered)
                }
                if actions.canOpenOnHost {
                    Button("Open", action: { onOpenOnHost?() })
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 620, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artifact.title), \(artifact.fileName)")
    }
}