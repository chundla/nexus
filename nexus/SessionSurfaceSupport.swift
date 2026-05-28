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
    let showsAttachment: Bool
    let showsInput: Bool
    let relaunchIsEnabled: Bool
    let relaunchDisabledReason: String?
    let unsupportedCopy: UnsupportedRemoteSessionSurfaceCopy?
}

struct RemoteProviderActionState: Equatable {
    let isEnabled: Bool
    let disabledReason: String?

    init(capability: ProviderCapability, provider: Provider, prelaunchPrimarySurface: SessionSurface) {
        if capability.isEnabled == false {
            self.init(isEnabled: false, disabledReason: capability.disabledReason)
            return
        }

        if sessionSurfaceSupport(for: prelaunchPrimarySurface, on: .remoteClient) == .unsupported {
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

func sessionSurfaceSupport(for screen: SessionScreen, on client: SessionSurfaceClient) -> SessionSurfaceSupport {
    sessionSurfaceSupport(for: screen.primarySurface, on: client)
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

func remoteSessionSurfacePresentation(for screen: SessionScreen, isReady: Bool) -> RemoteSessionSurfacePresentation {
    let support = sessionSurfaceSupport(for: screen, on: .remoteClient)
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

    return RemoteSessionSurfacePresentation(
        surfaceSupport: support,
        showsTerminal: support == .supported,
        showsAttachment: isReady && support == .supported,
        showsInput: isReady && support == .supported,
        relaunchIsEnabled: relaunchIsEnabled,
        relaunchDisabledReason: relaunchDisabledReason,
        unsupportedCopy: unsupportedCopy
    )
}
