#if os(macOS)
import Foundation
import NexusDomain

enum FocusedSessionSurface: Equatable {
    case terminal
    case structuredActivityFeed
}

enum StructuredSessionActivityEmphasis: Equatable {
    case neutral
    case accent
    case critical
    case success
}

struct StructuredSessionActivityRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let systemImage: String
    let text: String
    let emphasis: StructuredSessionActivityEmphasis
}

func focusedSessionSurface(for screen: SessionScreen) -> FocusedSessionSurface {
    switch screen.primarySurface {
    case .terminal:
        .terminal
    case .structuredActivityFeed:
        .structuredActivityFeed
    }
}

func structuredSessionActivityRows(for screen: SessionScreen) -> [StructuredSessionActivityRow] {
    screen.activityItems.map { item in
        StructuredSessionActivityRow(
            id: item.id,
            title: structuredSessionActivityTitle(for: item.kind),
            systemImage: structuredSessionActivitySystemImage(for: item.kind),
            text: item.text,
            emphasis: structuredSessionActivityEmphasis(for: item.kind)
        )
    }
}

private func structuredSessionActivityTitle(for kind: SessionActivityItem.Kind) -> String {
    switch kind {
    case .status:
        "Status"
    case .message:
        "Message"
    case .approvalRequest:
        "Approval Request"
    case .approvalDecision:
        "Approval Decision"
    case .progress:
        "Progress"
    case .command:
        "Command"
    case .diff:
        "Diff"
    case .error:
        "Error"
    case .completion:
        "Completion"
    }
}

private func structuredSessionActivitySystemImage(for kind: SessionActivityItem.Kind) -> String {
    switch kind {
    case .status:
        "dot.radiowaves.left.and.right"
    case .message:
        "message"
    case .approvalRequest:
        "hand.raised"
    case .approvalDecision:
        "checkmark.shield"
    case .progress:
        "hourglass"
    case .command:
        "terminal"
    case .diff:
        "square.and.pencil"
    case .error:
        "exclamationmark.triangle"
    case .completion:
        "checkmark.circle"
    }
}

private func structuredSessionActivityEmphasis(for kind: SessionActivityItem.Kind) -> StructuredSessionActivityEmphasis {
    switch kind {
    case .status, .command:
        .neutral
    case .message, .approvalRequest, .progress, .diff:
        .accent
    case .approvalDecision:
        .success
    case .error:
        .critical
    case .completion:
        .success
    }
}
#endif
