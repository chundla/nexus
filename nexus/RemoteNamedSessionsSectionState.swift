import NexusDomain

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

    init(
        providerID: ProviderID,
        providerHealth: ProviderHealthSummary,
        detail: ProviderDetail?,
        errorMessage: String?
    ) {
        canCreateSession = providerID == .claude && providerHealth.launchability == .launchable

        if let detail {
            content = detail.alternateSessions.isEmpty ? .empty : .sessions(detail.alternateSessions)
        } else if errorMessage == nil {
            content = .loading
        } else {
            content = .none
        }

        guard providerID == .claude else {
            createDisabledReason = "This Provider is not supported on iPhone yet."
            return
        }
        guard providerHealth.launchability != .launchable else {
            createDisabledReason = nil
            return
        }
        if detail == nil, errorMessage == nil, providerHealth.launchability == .notChecked {
            createDisabledReason = "Loading Provider detail…"
            return
        }
        createDisabledReason = providerHealth.summary
    }
}
