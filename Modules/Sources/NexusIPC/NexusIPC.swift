import Foundation
import NexusDomain

@objc public protocol NexusXPCProtocol {
    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void)
}

public protocol NexusServiceStatusClient {
    func getServiceStatus() async throws -> NexusServiceStatus
}

public final class NexusIPCClient: NexusServiceStatusClient {
    nonisolated private let connection: NSXPCConnection

    private init(connection: NSXPCConnection) {
        self.connection = connection
        self.connection.remoteObjectInterface = NSXPCInterface(with: NexusXPCProtocol.self)
        self.connection.resume()
    }

    nonisolated public static func connect(to endpoint: NSXPCListenerEndpoint) throws -> NexusIPCClient {
        NexusIPCClient(connection: NSXPCConnection(listenerEndpoint: endpoint))
    }

    nonisolated public func getServiceStatus() async throws -> NexusServiceStatus {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? NexusXPCProtocol else {
                continuation.resume(throwing: CocoaError(.coderInvalidValue))
                return
            }

            proxy.getServiceStatus { data, errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: NSError(domain: "NexusIPC", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                    return
                }

                guard let data else {
                    continuation.resume(throwing: CocoaError(.coderValueNotFound))
                    return
                }

                do {
                    continuation.resume(returning: try JSONDecoder().decode(NexusServiceStatus.self, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
