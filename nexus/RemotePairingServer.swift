#if os(macOS)
import Foundation
import Network
import NexusDomain
import NexusIPC

final class RemotePairingServer {
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
        macName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    ) throws {
        self.client = client
        self.displayHost = displayHost
        self.macName = macName
        self.listener = try NWListener(using: .tcp, on: .any)

        let startup = DispatchSemaphore(value: 0)
        var startupError: Error?

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = Int(self?.listener.port?.rawValue ?? 0)
                startup.signal()
            case .failed(let error):
                startupError = error
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

        if let startupError {
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
            do {
                try await authorize(request)

                let workspaceGroups = try await client.listWorkspaceGroups()
                let recentNavigation = try await client.listRecentNavigation(limit: 10)
                let workspaces = try await client.listWorkspaces()
                var workspaceOverviews: [WorkspaceOverview] = []
                for workspace in workspaces {
                    workspaceOverviews.append(try await client.getWorkspaceOverview(workspaceID: workspace.id))
                }

                send(
                    statusCode: 200,
                    body: RemoteWorkspaceCatalog(
                        workspaceGroups: workspaceGroups,
                        recentNavigation: recentNavigation,
                        workspaceOverviews: workspaceOverviews
                    ),
                    over: connection
                )
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "GET",
           let providerDetailRequest = providerDetailRequest(from: request) {
            do {
                try await authorize(request)
                let detail = try await client.getProviderDetail(
                    workspaceID: providerDetailRequest.workspaceID,
                    providerID: providerDetailRequest.providerID
                )
                send(statusCode: 200, body: detail, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let defaultSessionLaunchRequest = defaultSessionLaunchRequest(from: request) {
            do {
                try await authorize(request)
                let session = try await client.launchOrResumeDefaultSession(
                    workspaceID: defaultSessionLaunchRequest.workspaceID,
                    providerID: defaultSessionLaunchRequest.providerID
                )
                send(statusCode: 200, body: session, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let namedSessionCreateRequest = namedSessionCreateRequest(from: request) {
            do {
                try await authorize(request)
                let session = try await client.createNamedSession(
                    workspaceID: namedSessionCreateRequest.workspaceID,
                    providerID: namedSessionCreateRequest.providerID,
                    name: nil
                )
                send(statusCode: 200, body: session, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
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
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let sessionLaunchRequest = sessionLaunchRequest(from: request) {
            do {
                try await authorize(request)
                let session = try await client.launchOrResumeSession(sessionID: sessionLaunchRequest.sessionID)
                send(statusCode: 200, body: session, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let stopSessionRequest = stopSessionRequest(from: request) {
            do {
                try await authorize(request)
                let session = try await client.stopSession(sessionID: stopSessionRequest.sessionID)
                send(statusCode: 200, body: session, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let deleteSessionRecordRequest = deleteSessionRecordRequest(from: request) {
            do {
                try await authorize(request)
                let deleted = try await client.deleteSessionRecord(sessionID: deleteSessionRecordRequest.sessionID)
                send(statusCode: 200, body: deleted, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "GET",
           let sessionScreenRequest = sessionScreenRequest(from: request) {
            do {
                try await authorize(request)
                let screen = try await client.getSessionScreen(sessionID: sessionScreenRequest.sessionID)
                send(statusCode: 200, body: screen, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let takeControlRequest = takeControlRequest(from: request) {
            do {
                let pairedDeviceID = try pairedDeviceID(from: request)
                try await authorize(request)
                let body = try JSONDecoder().decode(RemoteSessionControlRequest.self, from: request.body)
                let screen = try await client.takeRemoteSessionControl(
                    sessionID: takeControlRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    columns: body.columns,
                    rows: body.rows
                )
                send(statusCode: 200, body: screen, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let releaseControlRequest = releaseControlRequest(from: request) {
            do {
                let pairedDeviceID = try pairedDeviceID(from: request)
                try await authorize(request)
                let screen = try await client.releaseRemoteSessionControl(
                    sessionID: releaseControlRequest.sessionID,
                    pairedDeviceID: pairedDeviceID
                )
                send(statusCode: 200, body: screen, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let sessionTextRequest = sessionTextRequest(from: request) {
            do {
                let pairedDeviceID = try pairedDeviceID(from: request)
                try await authorize(request)
                let body = try JSONDecoder().decode(RemoteSessionTextRequest.self, from: request.body)
                let screen = try await client.sendRemoteSessionText(
                    sessionID: sessionTextRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    text: body.text
                )
                send(statusCode: 200, body: screen, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
            }
            return
        }

        if request.method == "POST",
           let sessionKeyRequest = sessionKeyRequest(from: request) {
            do {
                let pairedDeviceID = try pairedDeviceID(from: request)
                try await authorize(request)
                let body = try JSONDecoder().decode(RemoteSessionKeyRequest.self, from: request.body)
                let screen = try await client.sendRemoteSessionInputKey(
                    sessionID: sessionKeyRequest.sessionID,
                    pairedDeviceID: pairedDeviceID,
                    key: body.key
                )
                send(statusCode: 200, body: screen, over: connection)
            } catch RemotePairingServerError.unauthorized {
                send(statusCode: 401, body: RemotePairingErrorResponse(message: "Pair this iPhone again to browse this Paired Mac"), over: connection)
            } catch {
                send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
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

private final class RemoteSessionScreenStream: @unchecked Sendable {
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

        let payload = Data("data: \(body)\n\n".utf8)
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
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

private enum RemotePairingServerError: LocalizedError {
    case invalidRequest
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Invalid request"
        case .unauthorized:
            "Unauthorized"
        }
    }
}
#endif
