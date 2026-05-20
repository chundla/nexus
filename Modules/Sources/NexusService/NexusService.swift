import Foundation
import NexusDomain
import NexusIPC

public protocol NexusEmbeddedServiceSession: AnyObject {
    var listenerEndpoint: NSXPCListenerEndpoint { get }
    var storeURL: URL { get }
}

public enum NexusEmbeddedServiceBootstrap {
    public static func bootstrap() throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrap()
    }

    public static func bootstrapForTests() throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrapForTests()
    }

    public static func bootstrapForTests(rootURL: URL) throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrapForTests(rootURL: rootURL)
    }
}

public final class NexusService: NSObject, NexusEmbeddedServiceSession {
    nonisolated public let listener: NSXPCListener
    nonisolated public let storeURL: URL

    nonisolated public var listenerEndpoint: NSXPCListenerEndpoint {
        listener.endpoint
    }

    private let metadataStore: NexusMetadataStore

    private init(listener: NSXPCListener, storeURL: URL, metadataStore: NexusMetadataStore) {
        self.listener = listener
        self.storeURL = storeURL
        self.metadataStore = metadataStore
        super.init()
        self.listener.delegate = self
        self.listener.resume()
    }

    nonisolated public static func bootstrap() throws -> NexusService {
        let rootURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Nexus", isDirectory: true)

        return try bootstrap(rootURL: rootURL)
    }

    nonisolated public static func bootstrapForTests() throws -> NexusService {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return try bootstrap(rootURL: rootURL)
    }

    nonisolated public static func bootstrapForTests(rootURL: URL) throws -> NexusService {
        try bootstrap(rootURL: rootURL)
    }

    private nonisolated static func bootstrap(rootURL: URL) throws -> NexusService {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        if FileManager.default.fileExists(atPath: storeURL.path) == false {
            FileManager.default.createFile(atPath: storeURL.path, contents: Data())
        }

        let metadataStore = try NexusMetadataStore(storeURL: storeURL)
        return NexusService(listener: NSXPCListener.anonymous(), storeURL: storeURL, metadataStore: metadataStore)
    }

    nonisolated public func serviceStatus() -> NexusServiceStatus {
        NexusServiceStatus(
            state: .running,
            store: .init(
                kind: .sqlite,
                owner: .backgroundService,
                location: storeURL
            )
        )
    }

    func listWorkspaceGroups() throws -> [WorkspaceGroup] {
        try metadataStore.listWorkspaceGroups()
    }

    func createWorkspaceGroup(name: String) throws -> WorkspaceGroup {
        try metadataStore.createWorkspaceGroup(name: name)
    }

    func listWorkspaces() throws -> [Workspace] {
        try metadataStore.listWorkspaces()
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) throws -> Workspace {
        try metadataStore.createLocalWorkspace(name: name, folderPath: folderPath, primaryGroupID: primaryGroupID)
    }
}

extension NexusService: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: NexusXPCProtocol.self)
        newConnection.exportedObject = NexusXPCBridge(service: self)
        newConnection.resume()
        return true
    }
}

private final class NexusXPCBridge: NSObject, NexusXPCProtocol {
    let service: NexusService

    init(service: NexusService) {
        self.service = service
    }

    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { service.serviceStatus() }, reply: reply)
    }

    func listWorkspaceGroups(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listWorkspaceGroups, reply: reply)
    }

    func createWorkspaceGroup(name: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.createWorkspaceGroup(name: name) }, reply: reply)
    }

    func listWorkspaces(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listWorkspaces, reply: reply)
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                try service.createLocalWorkspace(
                    name: name,
                    folderPath: folderPath,
                    primaryGroupID: try primaryGroupID.map(resolveUUID)
                )
            },
            reply: reply
        )
    }

    private func sendReply<T: Encodable>(with operation: () throws -> T, reply: @escaping (Data?, NSString?) -> Void) {
        do {
            let payload = try JSONEncoder().encode(operation())
            reply(payload, nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    private func resolveUUID(_ rawValue: String) throws -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        return uuid
    }
}
