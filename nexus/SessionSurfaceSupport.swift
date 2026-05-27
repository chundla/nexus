import Foundation
import NexusDomain

enum SessionSurfaceClient {
    case mac
    case remoteClient
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
