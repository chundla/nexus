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
    let unsupportedCopy: UnsupportedRemoteSessionSurfaceCopy?
}

func sessionSurfaceSupport(for screen: SessionScreen, on client: SessionSurfaceClient) -> SessionSurfaceSupport {
    switch client {
    case .mac:
        .supported
    case .remoteClient:
        switch screen.primarySurface {
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

    return RemoteSessionSurfacePresentation(
        surfaceSupport: support,
        showsTerminal: support == .supported,
        showsAttachment: isReady && support == .supported,
        showsInput: isReady && support == .supported,
        unsupportedCopy: unsupportedCopy
    )
}
