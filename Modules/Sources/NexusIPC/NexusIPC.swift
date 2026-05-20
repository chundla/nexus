import Foundation
import NexusDomain

@objc public protocol NexusXPCProtocol {
    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void)
    func listWorkspaceGroups(_ reply: @escaping (Data?, NSString?) -> Void)
    func createWorkspaceGroup(name: String, reply: @escaping (Data?, NSString?) -> Void)
    func listWorkspaces(_ reply: @escaping (Data?, NSString?) -> Void)
    func getWorkspaceOverview(workspaceID: String, reply: @escaping (Data?, NSString?) -> Void)
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void)
    func launchOrResumeDefaultSession(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionInput(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionText(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionInputKey(sessionID: String, key: String, reply: @escaping (Data?, NSString?) -> Void)
    func resizeSession(sessionID: String, columns: Int, rows: Int, reply: @escaping (Data?, NSString?) -> Void)
}

public protocol NexusServiceClient {
    func getServiceStatus() async throws -> NexusServiceStatus
    func listWorkspaceGroups() async throws -> [WorkspaceGroup]
    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup
    func listWorkspaces() async throws -> [Workspace]
    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace
    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session
    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen
    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen
    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen
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

    nonisolated public func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        try await requestDecodable { proxy, reply in
            proxy.getWorkspaceOverview(workspaceID: workspaceID.uuidString, reply: reply)
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

    nonisolated public func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        try await requestDecodable { proxy, reply in
            proxy.launchOrResumeDefaultSession(
                workspaceID: workspaceID.uuidString,
                providerID: providerID.rawValue,
                reply: reply
            )
        }
    }

    nonisolated public func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.getSessionScreen(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendSessionInput(sessionID: sessionID.uuidString, text: text, reply: reply)
        }
    }

    nonisolated public func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendSessionText(sessionID: sessionID.uuidString, text: text, reply: reply)
        }
    }

    nonisolated public func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendSessionInputKey(sessionID: sessionID.uuidString, key: key.rawValue, reply: reply)
        }
    }

    nonisolated public func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.resizeSession(sessionID: sessionID.uuidString, columns: columns, rows: rows, reply: reply)
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
