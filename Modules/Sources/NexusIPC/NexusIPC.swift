import Foundation
import NexusDomain

@objc public protocol NexusXPCProtocol {
    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void)
    func listWorkspaceGroups(_ reply: @escaping (Data?, NSString?) -> Void)
    func createWorkspaceGroup(name: String, reply: @escaping (Data?, NSString?) -> Void)
    func listWorkspaces(_ reply: @escaping (Data?, NSString?) -> Void)
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void)
}

public protocol NexusServiceClient {
    func getServiceStatus() async throws -> NexusServiceStatus
    func listWorkspaceGroups() async throws -> [WorkspaceGroup]
    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup
    func listWorkspaces() async throws -> [Workspace]
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace
}

public typealias NexusServiceStatusClient = NexusServiceClient

public final class NexusIPCClient: NexusServiceClient {
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
        try await requestDecodable { proxy, reply in
            proxy.getServiceStatus(reply)
        }
    }

    nonisolated public func listWorkspaceGroups() async throws -> [WorkspaceGroup] {
        try await requestDecodable { proxy, reply in
            proxy.listWorkspaceGroups(reply)
        }
    }

    nonisolated public func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        try await requestDecodable { proxy, reply in
            proxy.createWorkspaceGroup(name: name, reply: reply)
        }
    }

    nonisolated public func listWorkspaces() async throws -> [Workspace] {
        try await requestDecodable { proxy, reply in
            proxy.listWorkspaces(reply)
        }
    }

    nonisolated public func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        try await requestDecodable { proxy, reply in
            proxy.createLocalWorkspace(
                name: name,
                folderPath: folderPath,
                primaryGroupID: primaryGroupID?.uuidString,
                reply: reply
            )
        }
    }

    private nonisolated func requestDecodable<T: Decodable & Sendable>(
        _ send: @escaping (NexusXPCProtocol, @escaping (Data?, NSString?) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? NexusXPCProtocol else {
                continuation.resume(throwing: CocoaError(.coderInvalidValue))
                return
            }

            send(proxy) { data, errorMessage in
                if let errorMessage {
                    continuation.resume(
                        throwing: NSError(
                            domain: "NexusIPC",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: errorMessage]
                        )
                    )
                    return
                }

                guard let data else {
                    continuation.resume(throwing: CocoaError(.coderValueNotFound))
                    return
                }

                do {
                    continuation.resume(returning: try JSONDecoder().decode(T.self, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
