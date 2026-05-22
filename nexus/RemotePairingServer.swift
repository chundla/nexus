#if os(macOS)
import Foundation
import Network
import NexusIPC

final class RemotePairingServer {
    let displayHost: String
    let macName: String

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
        guard request.method == "POST", request.path == "/pairings/complete" else {
            send(statusCode: 404, body: RemotePairingErrorResponse(message: "Not found"), over: connection)
            return
        }

        do {
            let pairingRequest = try JSONDecoder().decode(RemotePairingCompletionRequest.self, from: request.body)
            let pairedDevice = try await client.completePairing(pairingCode: pairingRequest.pairingCode, deviceName: pairingRequest.deviceName)
            send(
                statusCode: 200,
                body: RemotePairingCompletionResponse(macName: macName, pairedAt: pairedDevice.pairedAt),
                over: connection
            )
        } catch {
            send(statusCode: 400, body: RemotePairingErrorResponse(message: error.localizedDescription), over: connection)
        }
    }

    private func send<T: Encodable>(statusCode: Int, body: T, over connection: NWConnection) {
        do {
            let bodyData = try JSONEncoder().encode(body)
            let responseHead = """
            HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))\r
            Content-Type: application/json\r
            Content-Length: \(bodyData.count)\r
            Connection: close\r
            \r
            """
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
        for headerLine in headerLines.dropFirst() {
            let parts = headerLine.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            if parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
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
            body: Data(data[bodyStart..<bodyEnd])
        )
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            "OK"
        case 400:
            "Bad Request"
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
    let body: Data
}

private enum RemotePairingServerError: LocalizedError {
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Invalid request"
        }
    }
}
#endif
