import Foundation
import NexusDomain

enum SessionSurfaceClient {
    case mac
    case remoteClient
}

struct UnsupportedRemoteSessionSurfaceCopy: Equatable {
    let title: String
    let summary: String
    let recovery: String
}

struct RemoteSessionSurfacePresentation: Equatable {
    let surfaceSupport: SessionSurfaceSupport
    let showsTerminal: Bool
    let showsStructuredActivity: Bool
    let showsAttachment: Bool
    let showsInput: Bool
    let relaunchIsEnabled: Bool
    let relaunchDisabledReason: String?
    let unsupportedCopy: UnsupportedRemoteSessionSurfaceCopy?
}

struct RemoteProviderActionState: Equatable {
    let isEnabled: Bool
    let disabledReason: String?

    init(
        capability: ProviderCapability,
        provider: Provider,
        prelaunchPrimarySurface: SessionSurface,
        workspaceKind: Workspace.Kind? = nil
    ) {
        if capability.isEnabled == false {
            self.init(isEnabled: false, disabledReason: capability.disabledReason)
            return
        }

        if remoteClientSupportsProviderAction(
            capability.action,
            providerID: provider.id,
            prelaunchPrimarySurface: prelaunchPrimarySurface,
            workspaceKind: workspaceKind
        ) == false {
            let disabledReason: String
            switch capability.action {
            case .launchDefaultSession:
                disabledReason = "Open this Workspace on the paired Mac to launch \(provider.displayName) because this iPhone cannot operate its primary Session surface yet."
            case .createNamedSession:
                disabledReason = "Open this Workspace on the paired Mac to create a \(provider.displayName) Named Session because this iPhone cannot operate its primary Session surface yet."
            }
            self.init(isEnabled: false, disabledReason: disabledReason)
            return
        }

        self.init(isEnabled: true, disabledReason: nil)
    }

    init(isEnabled: Bool, disabledReason: String?) {
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

func sessionSurfaceSupport(
    for screen: SessionScreen,
    on client: SessionSurfaceClient,
    workspaceKind: Workspace.Kind? = nil
) -> SessionSurfaceSupport {
    switch client {
    case .mac:
        .supported
    case .remoteClient:
        switch screen.primarySurface {
        case .terminal:
            .supported
        case .structuredActivityFeed:
            structuredRemoteClientSessionSurfaceSupport(
                providerID: screen.session.providerID,
                workspaceKind: workspaceKind
            )
        }
    }
}

func sessionSurfaceSupport(for primarySurface: SessionSurface, on client: SessionSurfaceClient) -> SessionSurfaceSupport {
    switch client {
    case .mac:
        .supported
    case .remoteClient:
        switch primarySurface {
        case .terminal:
            .supported
        case .structuredActivityFeed:
            .unsupported
        }
    }
}

func remoteSessionSurfacePresentation(
    for screen: SessionScreen,
    isReady: Bool,
    workspaceKind: Workspace.Kind? = nil
) -> RemoteSessionSurfacePresentation {
    let support = sessionSurfaceSupport(for: screen, on: .remoteClient, workspaceKind: workspaceKind)
    let unsupportedCopy: UnsupportedRemoteSessionSurfaceCopy?

    if support == .unsupported {
        unsupportedCopy = UnsupportedRemoteSessionSurfaceCopy(
            title: "Unsupported Session Surface",
            summary: "This iPhone can inspect this \(screen.session.providerID.displayName) Session, but it cannot present or operate its primary Session surface yet.",
            recovery: "Open this Session on the paired Mac to use its primary Session surface."
        )
    } else {
        unsupportedCopy = nil
    }

    let relaunchIsEnabled: Bool
    let relaunchDisabledReason: String?

    if isReady || support == .supported {
        relaunchIsEnabled = true
        relaunchDisabledReason = nil
    } else {
        relaunchIsEnabled = false
        relaunchDisabledReason = "Open this Session on the paired Mac to relaunch it because this iPhone cannot operate its primary Session surface yet."
    }

    let showsTerminal = support == .supported && screen.primarySurface == .terminal
    let showsStructuredActivity = support == .supported && screen.primarySurface == .structuredActivityFeed

    return RemoteSessionSurfacePresentation(
        surfaceSupport: support,
        showsTerminal: showsTerminal,
        showsStructuredActivity: showsStructuredActivity,
        showsAttachment: isReady && support == .supported,
        showsInput: isReady && showsTerminal,
        relaunchIsEnabled: relaunchIsEnabled,
        relaunchDisabledReason: relaunchDisabledReason,
        unsupportedCopy: unsupportedCopy
    )
}

private func remoteClientSupportsProviderAction(
    _ action: ProviderCapability.Action,
    providerID: ProviderID,
    prelaunchPrimarySurface: SessionSurface,
    workspaceKind: Workspace.Kind?
) -> Bool {
    switch prelaunchPrimarySurface {
    case .terminal:
        true
    case .structuredActivityFeed:
        switch action {
        case .launchDefaultSession:
            structuredRemoteClientSessionSurfaceSupport(
                providerID: providerID,
                workspaceKind: workspaceKind
            ) == .supported
        case .createNamedSession:
            structuredRemoteClientSessionSurfaceSupport(
                providerID: providerID,
                workspaceKind: workspaceKind
            ) == .supported
        }
    }
}

private func structuredRemoteClientSessionSurfaceSupport(
    providerID: ProviderID,
    workspaceKind: Workspace.Kind?
) -> SessionSurfaceSupport {
    switch providerID {
    case .codex:
        .supported
    case .pi:
        workspaceKind == .local ? .supported : .unsupported
    case .claude, .ibmBob:
        .unsupported
    }
}
