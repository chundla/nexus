import Foundation
import NexusDomain

/// Provider-native structured artifact surfaced as a feed preview card (#243).
public struct StructuredSessionFeedArtifactPresentation: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case piExportedSessionHTML
    }

    public let activityItemID: UUID
    public let kind: Kind
    public let title: String
    public let fileName: String
    public let hostPath: String?

    public var id: UUID { activityItemID }

    public init(
        activityItemID: UUID,
        kind: Kind,
        title: String,
        fileName: String,
        hostPath: String?
    ) {
        self.activityItemID = activityItemID
        self.kind = kind
        self.title = title
        self.fileName = fileName
        self.hostPath = hostPath
    }
}

public struct StructuredSessionFeedArtifactActionPresentation: Equatable, Sendable {
    public let canDownload: Bool
    public let canOpenOnHost: Bool
    public let disabledReason: String?

    public init(canDownload: Bool, canOpenOnHost: Bool, disabledReason: String?) {
        self.canDownload = canDownload
        self.canOpenOnHost = canOpenOnHost
        self.disabledReason = disabledReason
    }
}

private let structuredSessionPiExportedHTMLPrefix = "Exported session HTML"

public func structuredSessionFeedArtifactPresentation(
    for item: SessionActivityItem
) -> StructuredSessionFeedArtifactPresentation? {
    guard item.kind == .status else {
        return nil
    }

    let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix(structuredSessionPiExportedHTMLPrefix) else {
        return nil
    }

    let hostPath = structuredSessionPiExportedHTMLHostPath(from: trimmed)
    let fileName = hostPath.map { ($0 as NSString).lastPathComponent }
        ?? "session.html"

    return StructuredSessionFeedArtifactPresentation(
        activityItemID: item.id,
        kind: .piExportedSessionHTML,
        title: "Session HTML export",
        fileName: fileName,
        hostPath: hostPath
    )
}

public func structuredSessionFeedArtifactActionPresentation(
    for artifact: StructuredSessionFeedArtifactPresentation,
    hasWriterAuthority: Bool,
    usesHostArtifactFetch: Bool
) -> StructuredSessionFeedArtifactActionPresentation {
    if usesHostArtifactFetch {
        guard hasWriterAuthority else {
            return StructuredSessionFeedArtifactActionPresentation(
                canDownload: false,
                canOpenOnHost: false,
                disabledReason: "Take Controller to download artifacts from this iPhone."
            )
        }
        guard artifact.hostPath != nil else {
            return StructuredSessionFeedArtifactActionPresentation(
                canDownload: false,
                canOpenOnHost: false,
                disabledReason: "Export path unavailable for download."
            )
        }
        return StructuredSessionFeedArtifactActionPresentation(
            canDownload: true,
            canOpenOnHost: false,
            disabledReason: nil
        )
    }

    guard artifact.hostPath != nil else {
        return StructuredSessionFeedArtifactActionPresentation(
            canDownload: false,
            canOpenOnHost: false,
            disabledReason: "Export path unavailable."
        )
    }

    return StructuredSessionFeedArtifactActionPresentation(
        canDownload: false,
        canOpenOnHost: true,
        disabledReason: nil
    )
}

private func structuredSessionPiExportedHTMLHostPath(from statusText: String) -> String? {
    guard let range = statusText.range(of: " to ", options: [.caseInsensitive]) else {
        return nil
    }
    let path = String(statusText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
}