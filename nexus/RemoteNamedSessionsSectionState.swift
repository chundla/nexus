import Foundation
import NexusDomain

struct RemoteDefaultSessionSectionState: Equatable {
    let session: Session?
    let canDeleteSessionRecord: Bool

    init(detail: ProviderDetail?) {
        session = detail?.defaultSession
        canDeleteSessionRecord = detail?.defaultSession.map { $0.isDefault && remoteSessionRecordCanBeDeleted($0, workspace: detail?.workspace) } ?? false
    }
}

struct RemoteNamedSessionsSectionState: Equatable {
    enum Content: Equatable {
        case loading
        case empty
        case sessions([Session])
        case none
    }

    let content: Content
    let canCreateSession: Bool
    let createDisabledReason: String?
    let deletableSessionIDs: Set<UUID>

    init(
        capabilities: ProviderCapabilities,
        detail: ProviderDetail?,
        errorMessage: String?
    ) {
        let createCapability = detail?.capabilities.createNamedSession ?? capabilities.createNamedSession
        canCreateSession = createCapability.isEnabled

        if let detail {
            content = detail.alternateSessions.isEmpty ? .empty : .sessions(detail.alternateSessions)
            deletableSessionIDs = Set(
                detail.alternateSessions
                    .filter { $0.isDefault == false && remoteSessionRecordCanBeDeleted($0, workspace: detail.workspace) }
                    .map(\.id)
            )
        } else if errorMessage == nil {
            content = .loading
            deletableSessionIDs = []
        } else {
            content = .none
            deletableSessionIDs = []
        }

        if canCreateSession {
            createDisabledReason = nil
        } else if let disabledReason = createCapability.disabledReason {
            createDisabledReason = disabledReason
        } else if detail == nil, errorMessage == nil {
            createDisabledReason = "Loading Provider detail…"
        } else {
            createDisabledReason = nil
        }
    }
}

private func remoteSessionRecordCanBeDeleted(_ session: Session, workspace: Workspace?) -> Bool {
    if session.state != .ready {
        return true
    }

    return session.providerID == .ibmBob && workspace?.kind == .local
}
