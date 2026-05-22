import Foundation
import NexusDomain

@objc public protocol NexusSessionScreenObserverXPCProtocol {
    func sessionScreenDidUpdate(observationID: String, payload: Data)
}

public struct SessionScreenObservationStart: Codable, Sendable {
    public let observationID: UUID
    public let screen: SessionScreen

    public init(observationID: UUID, screen: SessionScreen) {
        self.observationID = observationID
        self.screen = screen
    }
}

public protocol SessionScreenObservation: Sendable {
    func cancel() async
}

@objc public protocol NexusXPCProtocol {
    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void)
    func listWorkspaceGroups(_ reply: @escaping (Data?, NSString?) -> Void)
    func createWorkspaceGroup(name: String, reply: @escaping (Data?, NSString?) -> Void)
    func listWorkspaces(_ reply: @escaping (Data?, NSString?) -> Void)
    func listHosts(_ reply: @escaping (Data?, NSString?) -> Void)
    func getHostDetail(hostID: String, reply: @escaping (Data?, NSString?) -> Void)
    func createHost(name: String, sshTarget: String, port: NSNumber?, reply: @escaping (Data?, NSString?) -> Void)
    func updateHost(hostID: String, name: String, sshTarget: String, port: NSNumber?, reply: @escaping (Data?, NSString?) -> Void)
    func validateHost(hostID: String, reply: @escaping (Data?, NSString?) -> Void)
    func deleteHost(hostID: String, reply: @escaping (Data?, NSString?) -> Void)
    func listRecentNavigation(limit: Int, reply: @escaping (Data?, NSString?) -> Void)
    func recordNavigation(targetPayload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func searchNavigation(query: String, reply: @escaping (Data?, NSString?) -> Void)
    func getWorkspaceOverview(workspaceID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getProviderDetail(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void)
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void)
    func createRemoteWorkspace(name: String?, hostID: String, remotePath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void)
    func launchOrResumeDefaultSession(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void)
    func launchOrResumeSession(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func createNamedSession(workspaceID: String, providerID: String, name: String?, reply: @escaping (Data?, NSString?) -> Void)
    func stopSession(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func deleteSessionRecord(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func observeSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func cancelSessionScreenObservation(observationID: String, reply: @escaping (Data?, NSString?) -> Void)
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
    func listHosts() async throws -> [NexusDomain.Host]
    func getHostDetail(hostID: UUID) async throws -> NexusDomain.HostDetail
    func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host
    func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host
    func validateHost(hostID: UUID) async throws -> HostValidationSnapshot
    func deleteHost(hostID: UUID) async throws -> Bool
    func listRecentNavigation(limit: Int) async throws -> [NavigationItem]
    func recordNavigation(target: NavigationTarget) async throws
    func searchNavigation(query: String) async throws -> [NavigationItem]
    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview
    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace
    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace
    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session
    func launchOrResumeSession(sessionID: UUID) async throws -> Session
    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session
    func stopSession(sessionID: UUID) async throws -> Session
    func deleteSessionRecord(sessionID: UUID) async throws -> Bool
    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen
    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation
    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen
    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen
}

public typealias NexusServiceStatusClient = NexusServiceClient

public final class NexusIPCClient: NexusServiceClient, @unchecked Sendable {
    private let connection: NSXPCConnection
    private let sessionScreenObserverBridge: NexusSessionScreenObserverBridge

    private init(connection: NSXPCConnection) {
        self.connection = connection
        self.sessionScreenObserverBridge = NexusSessionScreenObserverBridge()
        self.connection.remoteObjectInterface = NSXPCInterface(with: NexusXPCProtocol.self)
        self.connection.exportedInterface = NSXPCInterface(with: NexusSessionScreenObserverXPCProtocol.self)
        self.connection.exportedObject = sessionScreenObserverBridge
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

    nonisolated public func listHosts() async throws -> [NexusDomain.Host] {
        try await requestDecodable { proxy, reply in
            proxy.listHosts(reply)
        }
    }

    nonisolated public func getHostDetail(hostID: UUID) async throws -> NexusDomain.HostDetail {
        try await requestDecodable { proxy, reply in
            proxy.getHostDetail(hostID: hostID.uuidString, reply: reply)
        }
    }

    nonisolated public func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        try await requestDecodable { proxy, reply in
            proxy.createHost(name: name, sshTarget: sshTarget, port: port.map(NSNumber.init(value:)), reply: reply)
        }
    }

    nonisolated public func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        try await requestDecodable { proxy, reply in
            proxy.updateHost(
                hostID: hostID.uuidString,
                name: name,
                sshTarget: sshTarget,
                port: port.map(NSNumber.init(value:)),
                reply: reply
            )
        }
    }

    nonisolated public func validateHost(hostID: UUID) async throws -> HostValidationSnapshot {
        try await requestDecodable { proxy, reply in
            proxy.validateHost(hostID: hostID.uuidString, reply: reply)
        }
    }

    nonisolated public func deleteHost(hostID: UUID) async throws -> Bool {
        try await requestDecodable { proxy, reply in
            proxy.deleteHost(hostID: hostID.uuidString, reply: reply)
        }
    }

    nonisolated public func listRecentNavigation(limit: Int = 10) async throws -> [NavigationItem] {
        try await requestDecodable { proxy, reply in
            proxy.listRecentNavigation(limit: limit, reply: reply)
        }
    }

    nonisolated public func recordNavigation(target: NavigationTarget) async throws {
        let payload = try JSONEncoder().encode(target)
        let _: Bool = try await requestDecodable { proxy, reply in
            proxy.recordNavigation(targetPayload: payload, reply: reply)
        }
    }

    nonisolated public func searchNavigation(query: String) async throws -> [NavigationItem] {
        try await requestDecodable { proxy, reply in
            proxy.searchNavigation(query: query, reply: reply)
        }
    }

    nonisolated public func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        try await requestDecodable { proxy, reply in
            proxy.getWorkspaceOverview(workspaceID: workspaceID.uuidString, reply: reply)
        }
    }

    nonisolated public func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        try await requestDecodable { proxy, reply in
            proxy.getProviderDetail(
                workspaceID: workspaceID.uuidString,
                providerID: providerID.rawValue,
                reply: reply
            )
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

    nonisolated public func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace {
        try await requestDecodable { proxy, reply in
            proxy.createRemoteWorkspace(
                name: name,
                hostID: hostID.uuidString,
                remotePath: remotePath,
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

    nonisolated public func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        try await requestDecodable { proxy, reply in
            proxy.launchOrResumeSession(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        try await requestDecodable { proxy, reply in
            proxy.createNamedSession(
                workspaceID: workspaceID.uuidString,
                providerID: providerID.rawValue,
                name: name,
                reply: reply
            )
        }
    }

    nonisolated public func stopSession(sessionID: UUID) async throws -> Session {
        try await requestDecodable { proxy, reply in
            proxy.stopSession(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func deleteSessionRecord(sessionID: UUID) async throws -> Bool {
        try await requestDecodable { proxy, reply in
            proxy.deleteSessionRecord(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.getSessionScreen(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func observeSessionScreen(
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void
    ) async throws -> any SessionScreenObservation {
        let start: SessionScreenObservationStart = try await requestDecodable { proxy, reply in
            proxy.observeSessionScreen(sessionID: sessionID.uuidString, reply: reply)
        }

        sessionScreenObserverBridge.registerHandler(onUpdate, for: start.observationID)
        onUpdate(start.screen)

        let latestScreen = try await getSessionScreen(sessionID: sessionID)
        if latestScreen != start.screen {
            onUpdate(latestScreen)
        }

        return NexusSessionScreenObservationHandle(observationID: start.observationID, observerBridge: sessionScreenObserverBridge) { [weak self] observationID in
            guard let self else {
                return
            }

            let _: Bool = (try? await self.requestDecodable { proxy, reply in
                proxy.cancelSessionScreenObservation(observationID: observationID.uuidString, reply: reply)
            }) ?? false
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

private final class NexusSessionScreenObserverBridge: NSObject, NexusSessionScreenObserverXPCProtocol {
    private let lock = NSLock()
    private var handlers: [UUID: @Sendable (SessionScreen) -> Void] = [:]

    func registerHandler(_ handler: @escaping @Sendable (SessionScreen) -> Void, for observationID: UUID) {
        lock.lock()
        handlers[observationID] = handler
        lock.unlock()
    }

    func removeHandler(for observationID: UUID) {
        lock.lock()
        handlers.removeValue(forKey: observationID)
        lock.unlock()
    }

    func sessionScreenDidUpdate(observationID: String, payload: Data) {
        guard let observationID = UUID(uuidString: observationID) else {
            return
        }

        let handler: (@Sendable (SessionScreen) -> Void)?
        lock.lock()
        handler = handlers[observationID]
        lock.unlock()

        guard let handler else {
            return
        }

        do {
            let screen = try JSONDecoder().decode(SessionScreen.self, from: payload)
            handler(screen)
        } catch {
            return
        }
    }
}

private final class NexusSessionScreenObservationHandle: SessionScreenObservation, @unchecked Sendable {
    private let observationID: UUID
    private let observerBridge: NexusSessionScreenObserverBridge
    private let cancelRemote: @Sendable (UUID) async -> Void
    private let cancellationState = ObservationCancellationState()

    init(
        observationID: UUID,
        observerBridge: NexusSessionScreenObserverBridge,
        cancelRemote: @escaping @Sendable (UUID) async -> Void
    ) {
        self.observationID = observationID
        self.observerBridge = observerBridge
        self.cancelRemote = cancelRemote
    }

    func cancel() async {
        guard await cancellationState.beginCancellation() else {
            return
        }

        observerBridge.removeHandler(for: observationID)
        await cancelRemote(observationID)
    }

    deinit {
        observerBridge.removeHandler(for: observationID)
    }
}

private actor ObservationCancellationState {
    private var isCancelled = false

    func beginCancellation() -> Bool {
        guard isCancelled == false else {
            return false
        }

        isCancelled = true
        return true
    }
}
