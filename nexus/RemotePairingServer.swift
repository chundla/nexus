#if os(macOS)
import Foundation
import Network
import NexusDomain
import NexusIPC

nonisolated final class RemotePairingServer: @unchecked Sendable {
    private static let revokedPairingMessage = "Pair this iPhone again to browse this Paired Mac"

    let displayHost: String
    let macName: String

    var endpoint: RemotePairingEndpoint {
        RemotePairingEndpoint(host: displayHost, port: port)
    }

    private let client: any NexusServiceClient
    private let listener: NWListener
    private let queue = DispatchQueue(label: "RemotePairingServer")

    private(set) var port: Int = 0

    init(
        client: any NexusServiceClient,
        displayHost: String = ProcessInfo.processInfo.hostName,
        macName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        listeningPort: Int? = nil
    ) throws {
        self.client = client
        self.displayHost = displayHost
        self.macName = macName
        if let listeningPort {
            guard (1...65_535).contains(listeningPort),
                  let nwPort = NWEndpoint.Port(rawValue: UInt16(listeningPort)) else {
                throw RemotePairingServerError.invalidPort
            }
            self.listener = try NWListener(using: .tcp, on: nwPort)
        } else {
            self.listener = try NWListener(using: .tcp, on: .any)
        }

        let startup = DispatchSemaphore(value: 0)
        let startupState = RemotePairingServerStartupState()

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = Int(self?.listener.port?.rawValue ?? 0)
                startup.signal()
            case .failed(let error):
                startupState.store(error)
                startup.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        startup.wait()

        if let startupError = startupState.error {
            throw startupError
        }
    }

    deinit {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            do {
                if let request = try Self.parseRequest(from: buffer) {
                    Task {
                        await self.respond(to: request, over: connection)
                    }
                    return
                }
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
                return
            }

            if let error {
                send(statusCode: 500, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
                return
            }

            if isComplete {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: "Incomplete request"), over: connection)
                return
            }

            receive(on: connection, accumulated: buffer)
        }
    }

    private func respond(to request: ParsedRequest, over connection: NWConnection) async {
        if request.method == "GET", request.path == "/remote-client/status" {
            do {
                let state = try await client.getRemoteAccessState()
                send(
                    statusCode: 200,
                    body: RemotePairedMacStatus(macName: macName, isRemoteAccessEnabled: state.isEnabled),
                    over: connection
                )
            } catch {
                send(statusCode: 500, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "GET", request.path == "/remote-client/catalog" {
            await respondToAuthorizedRequest(
                operation: .fetchCatalog,
                request: request,
                over: connection
            ) { [self] in
                let workspaceGroups = try await self.client.listWorkspaceGroups()
                let recentNavigation = try await self.client.listRecentNavigation(limit: 10)
                let workspaces = try await self.client.listWorkspaces()
                let workspaceOverviews = try await self.client.getWorkspaceOverviews(workspaceIDs: workspaces.map(\.id))

                return RemoteWorkspaceCatalog(
                    workspaceGroups: workspaceGroups,
                    recentNavigation: recentNavigation,
                    workspaceOverviews: workspaceOverviews
                )
            }
            return
        }

        if request.method == "GET",
           let providerDetailRequest = providerDetailRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .fetchProviderDetail,
                request: request,
                over: connection,
                workspaceID: providerDetailRequest.workspaceID,
                providerID: providerDetailRequest.providerID
            ) { [self] in
                try await self.client.getProviderDetail(
                    workspaceID: providerDetailRequest.workspaceID,
                    providerID: providerDetailRequest.providerID
                )
            }
            return
        }

        if request.method == "POST",
           let defaultSessionLaunchRequest = defaultSessionLaunchRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .launchDefaultSession,
                request: request,
                over: connection,
                workspaceID: defaultSessionLaunchRequest.workspaceID,
                providerID: defaultSessionLaunchRequest.providerID
            ) { [self] in
                try await self.client.launchOrResumeDefaultSession(
                    workspaceID: defaultSessionLaunchRequest.workspaceID,
                    providerID: defaultSessionLaunchRequest.providerID
                )
            }
            return
        }

        if request.method == "POST",
           let namedSessionCreateRequest = namedSessionCreateRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .createNamedSession,
                request: request,
                over: connection,
                workspaceID: namedSessionCreateRequest.workspaceID,
                providerID: namedSessionCreateRequest.providerID
            ) { [self] in
                try await self.client.createNamedSession(
                    workspaceID: namedSessionCreateRequest.workspaceID,
                    providerID: namedSessionCreateRequest.providerID,
                    name: nil
                )
            }
            return
        }

        if request.method == "GET",
           let sessionScreenObservationRequest = sessionScreenObservationRequest(from: request) {
            do {
                try await authorize(request)
                let stream = RemoteSessionScreenStream(connection: connection, queue: queue)
                let observation = try await client.observeSessionScreen(sessionID: sessionScreenObservationRequest.sessionID) { screen in
                    stream.enqueue(screen)
                }
                stream.setOnClose {
                    await observation.cancel()
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .failed, .cancelled:
                        stream.close()
                    default:
                        break
                    }
                }
                stream.start()
            } catch RemotePairingServerError.unauthorized {
                await recordRemoteClientDiagnosticBreadcrumb(
                    kind: .reconnectFailure,
                    operation: .observeSessionScreen,
                    request: request,
                    sessionID: sessionScreenObservationRequest.sessionID,
                    message: Self.revokedPairingMessage
                )
                send(statusCode: 401, body: RemotePairingErrorResponse(message: Self.revokedPairingMessage), over: connection)
            } catch {
                await recordRemoteClientDiagnosticBreadcrumb(
                    kind: .reconnectFailure,
                    operation: .observeSessionScreen,
                    request: request,
                    sessionID: sessionScreenObservationRequest.sessionID,
                    message: error.localizedDescription
                )
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let sessionLaunchRequest = sessionLaunchRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .launchSession,
                request: request,
                over: connection,
                sessionID: sessionLaunchRequest.sessionID
            ) { [self] in
                try await self.client.launchOrResumeSession(sessionID: sessionLaunchRequest.sessionID)
            }
            return
        }

        if request.method == "POST",
           let stopSessionRequest = stopSessionRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .stopSession,
                request: request,
                over: connection,
                sessionID: stopSessionRequest.sessionID
            ) { [self] in
                try await self.client.stopSession(sessionID: stopSessionRequest.sessionID)
            }
            return
        }

        if request.method == "POST",
           let deleteSessionRecordRequest = deleteSessionRecordRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .deleteSessionRecord,
                request: request,
                over: connection,
                sessionID: deleteSessionRecordRequest.sessionID
            ) { [self] in
                try await self.client.deleteSessionRecord(sessionID: deleteSessionRecordRequest.sessionID)
            }
            return
        }

        if request.method == "GET",
           let sessionScreenRequest = sessionScreenRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .fetchSessionScreen,
                request: request,
                over: connection,
                sessionID: sessionScreenRequest.sessionID
            ) { [self] in
                try await self.client.getSessionScreen(sessionID: sessionScreenRequest.sessionID)
            }
            return
        }

        if request.method == "POST",
           let takeControlRequest = takeControlRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .takeSessionControl,
                request: request,
                over: connection,
                sessionID: takeControlRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                let body = try JSONDecoder().decode(RemoteSessionControlRequest.self, from: request.body)
                return try await self.client.takeRemoteSessionControl(
                    sessionID: takeControlRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    columns: body.columns,
                    rows: body.rows
                )
            }
            return
        }

        if request.method == "POST",
           let releaseControlRequest = releaseControlRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .releaseSessionControl,
                request: request,
                over: connection,
                sessionID: releaseControlRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                return try await self.client.releaseRemoteSessionControl(
                    sessionID: releaseControlRequest.sessionID,
                    pairedDeviceID: pairedDeviceID
                )
            }
            return
        }

        if request.method == "POST",
           let sessionInputRequest = sessionInputRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .sendSessionInput,
                request: request,
                over: connection,
                sessionID: sessionInputRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                let body = try JSONDecoder().decode(RemoteSessionInputRequest.self, from: request.body)
                return try await self.client.sendRemoteSessionInput(
                    sessionID: sessionInputRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    prompt: body.prompt
                )
            }
            return
        }

        if request.method == "POST",
           let approvalDecisionRequest = approvalDecisionRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .respondToApprovalRequest,
                request: request,
                over: connection,
                sessionID: approvalDecisionRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                let body = try JSONDecoder().decode(RemoteApprovalRequestDecisionRequest.self, from: request.body)
                return try await self.client.respondToRemoteApprovalRequest(
                    sessionID: approvalDecisionRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    approvalRequestID: approvalDecisionRequest.approvalRequestID,
                    decision: body.decision
                )
            }
            return
        }

        if request.method == "POST",
           let extensionDialogResponseRequest = extensionDialogResponseRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .respondToExtensionDialog,
                request: request,
                over: connection,
                sessionID: extensionDialogResponseRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                let response = try JSONDecoder().decode(SessionExtensionUIDialogResponse.self, from: request.body)
                return try await self.client.respondToRemoteExtensionDialog(
                    sessionID: extensionDialogResponseRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    dialogID: extensionDialogResponseRequest.dialogID,
                    response: response
                )
            }
            return
        }

        if request.method == "POST",
           let sessionTextRequest = sessionTextRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .sendSessionText,
                request: request,
                over: connection,
                sessionID: sessionTextRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                let body = try JSONDecoder().decode(RemoteSessionTextRequest.self, from: request.body)
                return try await self.client.sendRemoteSessionText(
                    sessionID: sessionTextRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    text: body.text
                )
            }
            return
        }

        if request.method == "POST",
           let sessionKeyRequest = sessionKeyRequest(from: request) {
            await respondToAuthorizedRequest(
                operation: .sendSessionInputKey,
                request: request,
                over: connection,
                sessionID: sessionKeyRequest.sessionID
            ) { [self] in
                let pairedDeviceID = try self.pairedDeviceID(from: request)
                let body = try JSONDecoder().decode(RemoteSessionKeyRequest.self, from: request.body)
                return try await self.client.sendRemoteSessionInputKey(
                    sessionID: sessionKeyRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    key: body.key
                )
            }
            return
        }

        guard request.method == "POST", request.path == "/pairings/complete" else {
            send(statusCode: 404, body: RemotePairingErrorResponse(message: "Not found"), over: connection)
            return
        }

        do {
            let pairingRequest = try JSONDecoder().decode(RemotePairingCompletionRequest.self, from: request.body)
            let pairedDevice = try await client.completePairing(pairingCode: pairingRequest.pairingCode, deviceName: pairingRequest.deviceName)
            send(
                statusCode: 200,
                body: RemotePairingCompletionResponse(
                    macName: macName,
                    pairedAt: pairedDevice.pairedAt,
                    pairedDeviceID: pairedDevice.id
                ),
                over: connection
            )
        } catch {
            send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
        }
    }

    private func respondToAuthorizedRequest<Response: Encodable>(
        operation: RemoteClientDiagnosticOperation,
        request: ParsedRequest,
        over connection: NWConnection,
        kind: RemoteClientDiagnosticKind = .actionFailure,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil,
        action: @escaping () async throws -> Response
    ) async {
        do {
            try await authorize(request)
            let response = try await action()
            send(statusCode: 200, body: response, over: connection)
        } catch RemotePairingServerError.unauthorized {
            await recordRemoteClientDiagnosticBreadcrumb(
                kind: kind,
                operation: operation,
                request: request,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID,
                message: Self.revokedPairingMessage
            )
            send(statusCode: 401, body: RemotePairingErrorResponse(message: Self.revokedPairingMessage), over: connection)
        } catch {
            await recordRemoteClientDiagnosticBreadcrumb(
                kind: kind,
                operation: operation,
                request: request,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID,
                message: error.localizedDescription
            )
            send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
        }
    }

    private func recordRemoteClientDiagnosticBreadcrumb(
        kind: RemoteClientDiagnosticKind,
        operation: RemoteClientDiagnosticOperation,
        request: ParsedRequest,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil,
        message: String
    ) async {
        let resolvedContext = await resolveRemoteClientDiagnosticContext(
            workspaceID: workspaceID,
            providerID: providerID,
            sessionID: sessionID
        )
        let breadcrumb = RemoteClientDiagnosticBreadcrumb(
            kind: kind,
            operation: operation,
            message: message,
            pairedMacID: endpoint.displayAddress.lowercased(),
            pairedDeviceID: UUID(uuidString: request.headers["x-nexus-paired-device-id"] ?? ""),
            workspaceID: resolvedContext.workspaceID,
            providerID: resolvedContext.providerID,
            sessionID: sessionID
        )
        try? await client.recordRemoteClientDiagnosticBreadcrumb(breadcrumb)
    }

    private func resolveRemoteClientDiagnosticContext(
        workspaceID: UUID?,
        providerID: ProviderID?,
        sessionID: UUID?
    ) async -> (workspaceID: UUID?, providerID: ProviderID?) {
        guard let sessionID,
              workspaceID == nil || providerID == nil,
              let session = try? await client.getSessionRecord(sessionID: sessionID) else {
            return (workspaceID, providerID)
        }

        return (
            workspaceID ?? session.workspaceID,
            providerID ?? session.providerID
        )
    }

    private func authorize(_ request: ParsedRequest) async throws {
        let pairedDeviceID = try pairedDeviceID(from: request)
        let pairedDevices = try await client.listPairedDevices()
        guard pairedDevices.contains(where: { $0.id == pairedDeviceID }) else {
            throw RemotePairingServerError.unauthorized
        }
    }

    private func pairedDeviceID(from request: ParsedRequest) throws -> UUID {
        guard let rawValue = request.headers["x-nexus-paired-device-id"],
              let pairedDeviceID = UUID(uuidString: rawValue) else {
            throw RemotePairingServerError.unauthorized
        }

        return pairedDeviceID
    }

    private func providerDetailRequest(from request: ParsedRequest) -> ProviderDetailRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 5,
              components[0] == "remote-client",
              components[1] == "workspaces",
              let workspaceID = UUID(uuidString: String(components[2])),
              components[3] == "providers",
              let providerID = ProviderID(rawValue: String(components[4])) else {
            return nil
        }

        return ProviderDetailRequest(workspaceID: workspaceID, providerID: providerID)
    }

    private func defaultSessionLaunchRequest(from request: ParsedRequest) -> ProviderDetailRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 7,
              components[0] == "remote-client",
              components[1] == "workspaces",
              let workspaceID = UUID(uuidString: String(components[2])),
              components[3] == "providers",
              let providerID = ProviderID(rawValue: String(components[4])),
              components[5] == "default-session",
              components[6] == "launch" else {
            return nil
        }

        return ProviderDetailRequest(workspaceID: workspaceID, providerID: providerID)
    }

    private func namedSessionCreateRequest(from request: ParsedRequest) -> ProviderDetailRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 6,
              components[0] == "remote-client",
              components[1] == "workspaces",
              let workspaceID = UUID(uuidString: String(components[2])),
              components[3] == "providers",
              let providerID = ProviderID(rawValue: String(components[4])),
              components[5] == "named-sessions" else {
            return nil
        }

        return ProviderDetailRequest(workspaceID: workspaceID, providerID: providerID)
    }

    private func sessionScreenObservationRequest(from request: ParsedRequest) -> SessionScreenObservationRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "observe" else {
            return nil
        }

        return SessionScreenObservationRequest(sessionID: sessionID)
    }

    private func sessionLaunchRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "launch" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func stopSessionRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "stop" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func deleteSessionRecordRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "delete-record" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func sessionScreenRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "screen" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func takeControlRequest(from request: ParsedRequest) -> SessionScreenControlRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 5,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "controller",
              components[4] == "take" else {
            return nil
        }

        return SessionScreenControlRequest(sessionID: sessionID)
    }

    private func releaseControlRequest(from request: ParsedRequest) -> SessionScreenControlRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 5,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "controller",
              components[4] == "release" else {
            return nil
        }

        return SessionScreenControlRequest(sessionID: sessionID)
    }

    private func sessionInputRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "input" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func approvalDecisionRequest(from request: ParsedRequest) -> SessionApprovalDecisionRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 6,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "approval-requests",
              let approvalRequestID = UUID(uuidString: String(components[4])),
              components[5] == "decision" else {
            return nil
        }

        return SessionApprovalDecisionRequest(sessionID: sessionID, approvalRequestID: approvalRequestID)
    }

    private func extensionDialogResponseRequest(from request: ParsedRequest) -> SessionExtensionDialogResponseRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 6,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "extension-dialogs",
              components[5] == "response" else {
            return nil
        }

        return SessionExtensionDialogResponseRequest(sessionID: sessionID, dialogID: String(components[4]))
    }

    private func sessionTextRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "text" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func sessionKeyRequest(from request: ParsedRequest) -> SessionScreenRequest? {
        let components = request.path.split(separator: "/")
        guard components.count == 4,
              components[0] == "remote-client",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: String(components[2])),
              components[3] == "keys" else {
            return nil
        }

        return SessionScreenRequest(sessionID: sessionID)
    }

    private func send<T: Encodable>(statusCode: Int, body: T, over connection: NWConnection) {
        do {
            let bodyData = try JSONEncoder().encode(body)
            let responseHead = "HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(bodyData.count)\r\n"
                + "Connection: close\r\n"
                + "\r\n"
            var payload = Data(responseHead.utf8)
            payload.append(bodyData)
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private static func parseRequest(from data: Data) throws -> ParsedRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return nil
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw RemotePairingServerError.invalidRequest
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            throw RemotePairingServerError.invalidRequest
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            throw RemotePairingServerError.invalidRequest
        }

        var contentLength = 0
        var headers: [String: String] = [:]
        for headerLine in headerLines.dropFirst() {
            let parts = headerLine.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name.lowercased()] = value

            if name.caseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(value) ?? 0
            }
        }

        let bodyStart = headerRange.upperBound
        let bodyEnd = data.index(bodyStart, offsetBy: contentLength, limitedBy: data.endIndex)
        guard let bodyEnd else {
            return nil
        }

        return ParsedRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: Data(data[bodyStart..<bodyEnd])
        )
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            "OK"
        case 400:
            "Bad Request"
        case 401:
            "Unauthorized"
        case 404:
            "Not Found"
        default:
            "Internal Server Error"
        }
    }
}

nonisolated private final class RemotePairingServerStartupState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    func store(_ error: Error) {
        lock.lock()
        storedError = error
        lock.unlock()
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

nonisolated private final class RemoteSessionScreenStream: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var didStart = false
    private var isClosed = false
    private var pendingScreens: [SessionScreen] = []
    private var onClose: (@Sendable () async -> Void)?

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func enqueue(_ screen: SessionScreen) {
        queue.async { [weak self] in
            guard let self, self.isClosed == false else {
                return
            }

            if self.didStart {
                self.sendEvent(screen)
            } else {
                self.pendingScreens.append(screen)
            }
        }
    }

    func setOnClose(_ onClose: @escaping @Sendable () async -> Void) {
        queue.async { [weak self] in
            self?.onClose = onClose
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.isClosed == false else {
                return
            }

            self.didStart = true
            self.sendHeaders()

            let pendingScreens = self.pendingScreens
            self.pendingScreens.removeAll()
            for screen in pendingScreens {
                self.sendEvent(screen)
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self, self.isClosed == false else {
                return
            }

            self.isClosed = true
            let onClose = self.onClose
            self.onClose = nil
            self.connection.cancel()
            if let onClose {
                Task {
                    await onClose()
                }
            }
        }
    }

    private func sendHeaders() {
        let responseHead = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Transfer-Encoding: chunked\r\n"
            + "Connection: keep-alive\r\n"
            + "\r\n"
        connection.send(content: Data(responseHead.utf8), completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.close()
            }
        })
    }

    private func sendEvent(_ screen: SessionScreen) {
        guard let bodyData = try? JSONEncoder().encode(screen),
              let body = String(data: bodyData, encoding: .utf8) else {
            return
        }

        let payload = Data("data: \(body)\r\n\r\n".utf8)
        let chunkPrefix = Data("\(String(payload.count, radix: 16))\r\n".utf8)
        let chunkSuffix = Data("\r\n".utf8)
        var chunk = Data()
        chunk.append(chunkPrefix)
        chunk.append(payload)
        chunk.append(chunkSuffix)
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.close()
            }
        })
    }
}

private struct ParsedRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private struct ProviderDetailRequest {
    let workspaceID: UUID
    let providerID: ProviderID
}

private struct SessionScreenObservationRequest {
    let sessionID: UUID
}

private struct SessionScreenRequest {
    let sessionID: UUID
}

private struct SessionScreenControlRequest {
    let sessionID: UUID
}

private struct SessionApprovalDecisionRequest {
    let sessionID: UUID
    let approvalRequestID: UUID
}

private struct SessionExtensionDialogResponseRequest {
    let sessionID: UUID
    let dialogID: String
}

private enum RemotePairingServerError: LocalizedError {
    case invalidRequest
    case invalidPort
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Invalid request"
        case .invalidPort:
            "Invalid port"
        case .unauthorized:
            "Unauthorized"
        }
    }
}
#endif
