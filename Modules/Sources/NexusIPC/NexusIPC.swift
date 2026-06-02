#if os(macOS)
import Foundation
import NexusDomain

@objc public protocol NexusSessionScreenObserverXPCProtocol {
    func sessionScreenDidUpdate(observationID: String, payload: Data)
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
    func recordRemoteClientDiagnosticBreadcrumb(payload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func listPerformanceDiagnostics(limit: Int, reply: @escaping (Data?, NSString?) -> Void)
    func getRemoteAccessState(_ reply: @escaping (Data?, NSString?) -> Void)
    func setRemoteAccessEnabled(isEnabled: Bool, reply: @escaping (Data?, NSString?) -> Void)
    func startPairing(_ reply: @escaping (Data?, NSString?) -> Void)
    func completePairing(pairingCode: String, deviceName: String, reply: @escaping (Data?, NSString?) -> Void)
    func listPairedDevices(_ reply: @escaping (Data?, NSString?) -> Void)
    func revokePairedDevice(deviceID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getWorkspaceOverview(workspaceID: String, reply: @escaping (Data?, NSString?) -> Void)
    func refreshWorkspaceOverview(workspaceID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getWorkspaceOverviews(workspaceIDsPayload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func getProviderDetail(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void)
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void)
    func createRemoteWorkspace(name: String?, hostID: String, remotePath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void)
    func launchOrResumeDefaultSession(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void)
    func launchOrResumeSession(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func createNamedSession(workspaceID: String, providerID: String, name: String?, reply: @escaping (Data?, NSString?) -> Void)
    func stopSession(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func deleteSessionRecord(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getSessionRecord(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func getSessionScreenObservationSnapshot(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func observeSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void)
    func cancelSessionScreenObservation(observationID: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionInput(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionPrompt(sessionID: String, promptPayload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionText(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendSessionInputKey(sessionID: String, key: String, reply: @escaping (Data?, NSString?) -> Void)
    func respondToApprovalRequest(sessionID: String, approvalRequestID: String, decision: String, reply: @escaping (Data?, NSString?) -> Void)
    func respondToExtensionDialog(sessionID: String, dialogID: String, responsePayload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func resizeSession(sessionID: String, columns: Int, rows: Int, reply: @escaping (Data?, NSString?) -> Void)
    func takeRemoteSessionControl(sessionID: String, pairedDeviceID: String, columns: Int, rows: Int, reply: @escaping (Data?, NSString?) -> Void)
    func releaseRemoteSessionControl(sessionID: String, pairedDeviceID: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendRemoteSessionInput(sessionID: String, pairedDeviceID: String, text: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendRemoteSessionPrompt(sessionID: String, pairedDeviceID: String, promptPayload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func respondToRemoteApprovalRequest(sessionID: String, pairedDeviceID: String, approvalRequestID: String, decision: String, reply: @escaping (Data?, NSString?) -> Void)
    func respondToRemoteExtensionDialog(sessionID: String, pairedDeviceID: String, dialogID: String, responsePayload: Data, reply: @escaping (Data?, NSString?) -> Void)
    func sendRemoteSessionText(sessionID: String, pairedDeviceID: String, text: String, reply: @escaping (Data?, NSString?) -> Void)
    func sendRemoteSessionInputKey(sessionID: String, pairedDeviceID: String, key: String, reply: @escaping (Data?, NSString?) -> Void)
}

public protocol NexusServiceClient: Sendable {
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
    func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) async throws
    func listPerformanceDiagnostics(limit: Int) async throws -> [PerformanceDiagnosticRecord]
    func getRemoteAccessState() async throws -> RemoteAccessState
    func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState
    func startPairing() async throws -> PairingCeremony
    func completePairing(pairingCode: String, deviceName: String) async throws -> PairedDevice
    func listPairedDevices() async throws -> [PairedDevice]
    func revokePairedDevice(deviceID: UUID) async throws -> Bool
    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview
    func refreshWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview
    func getWorkspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview]
    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail
    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace
    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace
    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session
    func launchOrResumeSession(sessionID: UUID) async throws -> Session
    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session
    func stopSession(sessionID: UUID) async throws -> Session
    func deleteSessionRecord(sessionID: UUID) async throws -> Bool
    func getSessionRecord(sessionID: UUID) async throws -> Session
    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen
    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation
    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen
    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen
    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen
    func respondToApprovalRequest(sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen
    func respondToExtensionDialog(sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen
    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen
    func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen
    func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) async throws -> SessionScreen
    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen
    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws -> SessionScreen
    func respondToRemoteApprovalRequest(sessionID: UUID, pairedDeviceID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen
    func respondToRemoteExtensionDialog(sessionID: UUID, pairedDeviceID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen
    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen
    func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen
}

public extension NexusServiceClient {
    func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        if prompt.images.isEmpty == false {
            throw NSError(
                domain: "NexusIPC",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This client does not support image-bearing Session prompts."]
            )
        }
        return try await sendSessionInput(sessionID: sessionID, text: prompt.text)
    }

    func respondToExtensionDialog(sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen {
        _ = sessionID
        _ = dialogID
        _ = response
        throw NSError(
            domain: "NexusIPC",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "This client does not support Extension UI dialogs."]
        )
    }

    func respondToRemoteExtensionDialog(
        sessionID: UUID,
        pairedDeviceID: UUID,
        dialogID: String,
        response: SessionExtensionUIDialogResponse
    ) async throws -> SessionScreen {
        _ = sessionID
        _ = pairedDeviceID
        _ = dialogID
        _ = response
        throw NSError(
            domain: "NexusIPC",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "This client does not support remote Extension UI dialogs."]
        )
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        if prompt.images.isEmpty == false {
            throw NSError(
                domain: "NexusIPC",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This client does not support image-bearing remote Session prompts."]
            )
        }
        return try await sendRemoteSessionInput(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: prompt.text)
    }
}

public typealias NexusServiceStatusClient = NexusServiceClient

public protocol SessionScreenObservationEventClient: NexusServiceClient {
    func getSessionScreenObservationSnapshot(sessionID: UUID) async throws -> SessionScreenObservationSnapshotResponse
    func observeSessionScreenUpdateEvents(
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreenObservationUpdate) -> Void
    ) async throws -> any SessionScreenObservation
}

public final class NexusIPCClient: NexusServiceClient, SessionScreenObservationEventClient, @unchecked Sendable {
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

    deinit {
        connection.invalidate()
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

    nonisolated public func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) async throws {
        let payload = try JSONEncoder().encode(breadcrumb)
        let _: Bool = try await requestDecodable { proxy, reply in
            proxy.recordRemoteClientDiagnosticBreadcrumb(payload: payload, reply: reply)
        }
    }

    nonisolated public func listPerformanceDiagnostics(limit: Int = 10) async throws -> [PerformanceDiagnosticRecord] {
        try await requestDecodable { proxy, reply in
            proxy.listPerformanceDiagnostics(limit: limit, reply: reply)
        }
    }

    nonisolated public func getRemoteAccessState() async throws -> RemoteAccessState {
        try await requestDecodable { proxy, reply in
            proxy.getRemoteAccessState(reply)
        }
    }

    nonisolated public func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState {
        try await requestDecodable { proxy, reply in
            proxy.setRemoteAccessEnabled(isEnabled: isEnabled, reply: reply)
        }
    }

    nonisolated public func startPairing() async throws -> PairingCeremony {
        try await requestDecodable { proxy, reply in
            proxy.startPairing(reply)
        }
    }

    nonisolated public func completePairing(pairingCode: String, deviceName: String) async throws -> PairedDevice {
        try await requestDecodable { proxy, reply in
            proxy.completePairing(pairingCode: pairingCode, deviceName: deviceName, reply: reply)
        }
    }

    nonisolated public func listPairedDevices() async throws -> [PairedDevice] {
        try await requestDecodable { proxy, reply in
            proxy.listPairedDevices(reply)
        }
    }

    nonisolated public func revokePairedDevice(deviceID: UUID) async throws -> Bool {
        try await requestDecodable { proxy, reply in
            proxy.revokePairedDevice(deviceID: deviceID.uuidString, reply: reply)
        }
    }

    nonisolated public func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        try await requestDecodable { proxy, reply in
            proxy.getWorkspaceOverview(workspaceID: workspaceID.uuidString, reply: reply)
        }
    }

    nonisolated public func refreshWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        try await requestDecodable { proxy, reply in
            proxy.refreshWorkspaceOverview(workspaceID: workspaceID.uuidString, reply: reply)
        }
    }

    nonisolated public func getWorkspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview] {
        let payload = try JSONEncoder().encode(workspaceIDs)
        return try await requestDecodable { proxy, reply in
            proxy.getWorkspaceOverviews(workspaceIDsPayload: payload, reply: reply)
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

    nonisolated public func getSessionRecord(sessionID: UUID) async throws -> Session {
        try await requestDecodable { proxy, reply in
            proxy.getSessionRecord(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.getSessionScreen(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func getSessionScreenObservationSnapshot(
        sessionID: UUID
    ) async throws -> SessionScreenObservationSnapshotResponse {
        try await requestDecodable { proxy, reply in
            proxy.getSessionScreenObservationSnapshot(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    nonisolated public func observeSessionScreenUpdateEvents(
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreenObservationUpdate) -> Void
    ) async throws -> any SessionScreenObservation {
        let start = try await startSessionScreenObservation(sessionID: sessionID)
        sessionScreenObserverBridge.registerHandler(onUpdate, for: start.observationID)

        let latestSnapshot = try await getSessionScreenObservationSnapshot(sessionID: sessionID)
        if let startStructuredRevision = start.structuredSnapshot?.revision,
           let latestStructuredRevision = latestSnapshot.structuredSnapshot?.revision,
           latestStructuredRevision != startStructuredRevision {
            onUpdate(.structuredGap(currentRevision: latestStructuredRevision))
        } else if latestSnapshot.screen != start.screen {
            onUpdate(.screen(latestSnapshot.screen))
        }

        return makeObservationHandle(observationID: start.observationID)
    }

    nonisolated public func observeSessionScreen(
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void
    ) async throws -> any SessionScreenObservation {
        let start = try await startSessionScreenObservation(sessionID: sessionID)
        let accumulator = SessionScreenObservationAccumulator(start: start)
        sessionScreenObserverBridge.registerHandler({ [weak self] update in
            do {
                if let screen = try accumulator.apply(update) {
                    onUpdate(screen)
                }
            } catch is SessionScreenObservationGapError {
                guard let self else {
                    return
                }

                Task {
                    guard let latestSnapshot = try? await self.getSessionScreenObservationSnapshot(sessionID: sessionID) else {
                        return
                    }
                    onUpdate(accumulator.replace(with: latestSnapshot))
                }
            } catch {
                return
            }
        }, for: start.observationID)
        onUpdate(start.screen)

        let latestSnapshot = try await getSessionScreenObservationSnapshot(sessionID: sessionID)
        if latestSnapshot.screen != accumulator.currentScreen {
            onUpdate(accumulator.replace(with: latestSnapshot))
        }

        return makeObservationHandle(observationID: start.observationID)
    }

    nonisolated public func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendSessionInput(sessionID: sessionID.uuidString, text: text, reply: reply)
        }
    }

    nonisolated public func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        let payload = try JSONEncoder().encode(prompt)
        return try await requestDecodable { proxy, reply in
            proxy.sendSessionPrompt(sessionID: sessionID.uuidString, promptPayload: payload, reply: reply)
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

    nonisolated public func respondToApprovalRequest(
        sessionID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.respondToApprovalRequest(
                sessionID: sessionID.uuidString,
                approvalRequestID: approvalRequestID.uuidString,
                decision: decision.rawValue,
                reply: reply
            )
        }
    }

    nonisolated public func respondToExtensionDialog(
        sessionID: UUID,
        dialogID: String,
        response: SessionExtensionUIDialogResponse
    ) async throws -> SessionScreen {
        let payload = try JSONEncoder().encode(response)
        return try await requestDecodable { proxy, reply in
            proxy.respondToExtensionDialog(
                sessionID: sessionID.uuidString,
                dialogID: dialogID,
                responsePayload: payload,
                reply: reply
            )
        }
    }

    nonisolated public func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.resizeSession(sessionID: sessionID.uuidString, columns: columns, rows: rows, reply: reply)
        }
    }

    nonisolated public func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.takeRemoteSessionControl(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                columns: columns,
                rows: rows,
                reply: reply
            )
        }
    }

    nonisolated public func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.releaseRemoteSessionControl(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                reply: reply
            )
        }
    }

    nonisolated public func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendRemoteSessionInput(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                text: text,
                reply: reply
            )
        }
    }

    nonisolated public func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        let payload = try JSONEncoder().encode(prompt)
        return try await requestDecodable { proxy, reply in
            proxy.sendRemoteSessionPrompt(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                promptPayload: payload,
                reply: reply
            )
        }
    }

    nonisolated public func respondToRemoteApprovalRequest(
        sessionID: UUID,
        pairedDeviceID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.respondToRemoteApprovalRequest(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                approvalRequestID: approvalRequestID.uuidString,
                decision: decision.rawValue,
                reply: reply
            )
        }
    }

    nonisolated public func respondToRemoteExtensionDialog(
        sessionID: UUID,
        pairedDeviceID: UUID,
        dialogID: String,
        response: SessionExtensionUIDialogResponse
    ) async throws -> SessionScreen {
        let payload = try JSONEncoder().encode(response)
        return try await requestDecodable { proxy, reply in
            proxy.respondToRemoteExtensionDialog(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                dialogID: dialogID,
                responsePayload: payload,
                reply: reply
            )
        }
    }

    nonisolated public func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendRemoteSessionText(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                text: text,
                reply: reply
            )
        }
    }

    nonisolated public func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        try await requestDecodable { proxy, reply in
            proxy.sendRemoteSessionInputKey(
                sessionID: sessionID.uuidString,
                pairedDeviceID: pairedDeviceID.uuidString,
                key: key.rawValue,
                reply: reply
            )
        }
    }

    private nonisolated func startSessionScreenObservation(
        sessionID: UUID
    ) async throws -> SessionScreenObservationStart {
        try await requestDecodable { proxy, reply in
            proxy.observeSessionScreen(sessionID: sessionID.uuidString, reply: reply)
        }
    }

    private nonisolated func makeObservationHandle(
        observationID: UUID
    ) -> NexusSessionScreenObservationHandle {
        NexusSessionScreenObservationHandle(
            observationID: observationID,
            observerBridge: sessionScreenObserverBridge
        ) { [weak self] observationID in
            guard let self else {
                return
            }

            let _: Bool = (try? await self.requestDecodable { proxy, reply in
                proxy.cancelSessionScreenObservation(observationID: observationID.uuidString, reply: reply)
            }) ?? false
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

final class NexusSessionScreenObserverBridge: NSObject, NexusSessionScreenObserverXPCProtocol, @unchecked Sendable {
    private final class HandlerRegistration: @unchecked Sendable {
        let queue: DispatchQueue
        let handler: @Sendable (SessionScreenObservationUpdate) -> Void

        init(observationID: UUID, handler: @escaping @Sendable (SessionScreenObservationUpdate) -> Void) {
            self.queue = DispatchQueue(label: "NexusSessionScreenObserverBridge.\(observationID.uuidString)")
            self.handler = handler
        }

        func deliver(_ payload: Data) {
            queue.async { [handler] in
                guard let update = try? JSONDecoder().decode(SessionScreenObservationUpdate.self, from: payload) else {
                    return
                }
                handler(update)
            }
        }
    }

    private let lock = NSLock()
    private var handlers: [UUID: HandlerRegistration] = [:]

    func registerHandler(_ handler: @escaping @Sendable (SessionScreenObservationUpdate) -> Void, for observationID: UUID) {
        lock.lock()
        handlers[observationID] = HandlerRegistration(observationID: observationID, handler: handler)
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

        let registration: HandlerRegistration?
        lock.lock()
        registration = handlers[observationID]
        lock.unlock()

        registration?.deliver(payload)
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
#else
import Foundation
import NexusDomain

public protocol SessionScreenObservation: Sendable {
    func cancel() async
}

public protocol NexusServiceClient: Sendable {}

public typealias NexusServiceStatusClient = NexusServiceClient

@available(iOS, unavailable, message: "Nexus IPC is only available on macOS")
public final class NexusIPCClient: @unchecked Sendable {}
#endif
