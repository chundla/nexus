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
