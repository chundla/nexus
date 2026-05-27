import Foundation
import NexusDomain
import NexusIPC

struct RemotePairingEndpoint: Equatable, Sendable {
    let host: String
    let port: Int

    var displayAddress: String {
        "\(host):\(port)"
    }
}

struct RemotePairedMacStatus: Codable, Equatable, Sendable {
    let macName: String
    let isRemoteAccessEnabled: Bool
}

struct PairedMac: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let host: String
    let port: Int
    let pairedAt: Date
    let pairedDeviceID: UUID?

    init(name: String, host: String, port: Int, pairedAt: Date, pairedDeviceID: UUID? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.pairedAt = pairedAt
        self.pairedDeviceID = pairedDeviceID
    }

    var id: String {
        "\(host.lowercased()):\(port)"
    }
}

struct RemoteWorkspaceCatalog: Codable, Equatable, Sendable {
    let workspaceGroups: [WorkspaceGroup]
    let recentNavigation: [NavigationItem]
    let workspaceOverviews: [WorkspaceOverview]
}

struct RemotePairingHTTPClient {
    private final class SessionBox: @unchecked Sendable {
        let session: URLSession

        init(session: URLSession) {
            self.session = session
        }

        deinit {
            session.invalidateAndCancel()
        }
    }

    private let sessionBox: SessionBox

    private var session: URLSession {
        sessionBox.session
    }

    init(session: URLSession? = nil) {
        self.sessionBox = SessionBox(session: session ?? Self.makeDefaultSession())
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }

    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus {
        let request = URLRequest(url: URL(string: "http://\(host):\(port)/remote-client/status")!)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse?.statusCode == 200 else {
            throw Self.decodeRequestFailure(from: data, statusCode: httpResponse?.statusCode ?? 500)
        }

        return try JSONDecoder().decode(RemotePairedMacStatus.self, from: data)
    }

    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac {
        let requestBody = RemotePairingCompletionRequest(pairingCode: pairingCode, deviceName: deviceName)
        var request = URLRequest(url: URL(string: "http://\(host):\(port)/pairings/complete")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse?.statusCode == 200 else {
            throw Self.decodeRequestFailure(from: data, statusCode: httpResponse?.statusCode ?? 500)
        }

        let completion = try JSONDecoder().decode(RemotePairingCompletionResponse.self, from: data)
        return PairedMac(
            name: completion.macName,
            host: host,
            port: port,
            pairedAt: completion.pairedAt,
            pairedDeviceID: completion.pairedDeviceID
        )
    }

    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog {
        let request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/catalog"
        )
        let data = try await send(request)
        return try JSONDecoder().decode(RemoteWorkspaceCatalog.self, from: data)
    }

    func fetchProviderDetail(
        for pairedMac: PairedMac,
        workspaceID: UUID,
        providerID: ProviderID
    ) async throws -> ProviderDetail {
        let request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/workspaces/\(workspaceID.uuidString)/providers/\(providerID.rawValue)"
        )
        let data = try await send(request)
        return try JSONDecoder().decode(ProviderDetail.self, from: data)
    }

    func launchOrResumeDefaultSession(
        for pairedMac: PairedMac,
        workspaceID: UUID,
        providerID: ProviderID
    ) async throws -> Session {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/workspaces/\(workspaceID.uuidString)/providers/\(providerID.rawValue)/default-session/launch"
        )
        request.httpMethod = "POST"
        let data = try await send(request)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func createNamedSession(
        for pairedMac: PairedMac,
        workspaceID: UUID,
        providerID: ProviderID
    ) async throws -> Session {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/workspaces/\(workspaceID.uuidString)/providers/\(providerID.rawValue)/named-sessions"
        )
        request.httpMethod = "POST"
        let data = try await send(request)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        let request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/screen"
        )
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func launchOrResumeSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/launch"
        )
        request.httpMethod = "POST"
        let data = try await send(request)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func stopSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/stop"
        )
        request.httpMethod = "POST"
        let data = try await send(request)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func deleteSessionRecord(for pairedMac: PairedMac, sessionID: UUID) async throws -> Bool {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/delete-record"
        )
        request.httpMethod = "POST"
        let data = try await send(request)
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/controller/take"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RemoteSessionControlRequest(columns: columns, rows: rows))
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/controller/release"
        )
        request.httpMethod = "POST"
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/text"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RemoteSessionTextRequest(text: text))
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/keys"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RemoteSessionKeyRequest(key: key))
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func observeSessionScreen(
        for pairedMac: PairedMac,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void,
        onDisconnect: @escaping @Sendable (any Error) -> Void
    ) async throws -> any SessionScreenObservation {
        let request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/observe"
        )
        let session = self.session
        let startup = ObservationStartupSignal()
        let task = Task.detached(priority: nil) {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RemotePairingHTTPObservationError.invalidResponse
                }

                guard httpResponse.statusCode == 200 else {
                    var responseBody = Data()
                    for try await byte in bytes {
                        responseBody.append(byte)
                    }
                    throw Self.decodeRequestFailure(from: responseBody, statusCode: httpResponse.statusCode)
                }

                var eventBuffer = Data()
                var didDeliverInitialScreen = false

                for try await byte in bytes {
                    if Task.isCancelled {
                        return
                    }

                    eventBuffer.append(byte)
                    while let eventLines = Self.dequeueObservedEventLines(from: &eventBuffer) {
                        try Self.emitObservedScreen(from: eventLines, onUpdate: onUpdate)
                        if didDeliverInitialScreen == false {
                            didDeliverInitialScreen = true
                            await startup.succeed()
                        }
                    }
                }

                if let eventLines = Self.dequeueTrailingObservedEventLines(from: eventBuffer) {
                    try Self.emitObservedScreen(from: eventLines, onUpdate: onUpdate)
                    if didDeliverInitialScreen == false {
                        didDeliverInitialScreen = true
                        await startup.succeed()
                    }
                }

                if didDeliverInitialScreen == false {
                    await startup.fail(RemotePairingHTTPObservationError.connectionClosed)
                }

                if Task.isCancelled == false {
                    onDisconnect(RemotePairingHTTPObservationError.connectionClosed)
                }
            } catch is CancellationError {
                await startup.fail(CancellationError())
            } catch {
                await startup.fail(error)
                if Task.isCancelled == false {
                    onDisconnect(error)
                }
            }
        }

        try await startup.wait()
        return RemoteSessionScreenHTTPObservation(task: task)
    }

    private func authenticatedRequest(for pairedMac: PairedMac, path: String) throws -> URLRequest {
        guard let pairedDeviceID = pairedMac.pairedDeviceID else {
            throw RemotePairingHTTPError.missingPairedDeviceIdentity
        }

        var request = URLRequest(url: URL(string: "http://\(pairedMac.host):\(pairedMac.port)\(path)")!)
        request.setValue(pairedDeviceID.uuidString, forHTTPHeaderField: "X-Nexus-Paired-Device-ID")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse?.statusCode == 200 else {
            throw Self.decodeRequestFailure(from: data, statusCode: httpResponse?.statusCode ?? 500)
        }

        return data
    }

    private nonisolated static func emitObservedScreen(
        from eventLines: [String],
        onUpdate: @escaping @Sendable (SessionScreen) -> Void
    ) throws {
        guard eventLines.isEmpty == false else {
            return
        }

        let payload = eventLines.joined(separator: "\n")
        let screen = try JSONDecoder().decode(SessionScreen.self, from: Data(payload.utf8))
        onUpdate(screen)
    }

    private nonisolated static func dequeueObservedEventLines(from buffer: inout Data) -> [String]? {
        guard let separatorRange = buffer.range(of: Data("\r\n\r\n".utf8)) ?? buffer.range(of: Data("\n\n".utf8)) else {
            return nil
        }

        let eventData = buffer[..<separatorRange.lowerBound]
        buffer.removeSubrange(..<separatorRange.upperBound)
        return observedEventLines(from: Data(eventData))
    }

    private nonisolated static func dequeueTrailingObservedEventLines(from buffer: Data) -> [String]? {
        observedEventLines(from: buffer)
    }

    private nonisolated static func observedEventLines(from data: Data) -> [String]? {
        guard data.isEmpty == false,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = text
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("data:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return lines.isEmpty ? nil : lines
    }

    private nonisolated static func decodeRequestFailure(from data: Data, statusCode: Int) -> RemotePairingHTTPError {
        let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
            ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)

        if statusCode == 401 {
            return .pairingRevoked(message)
        }

        return .requestFailed(message)
    }
}

private final class RemoteSessionScreenHTTPObservation: SessionScreenObservation, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() async {
        task.cancel()
        _ = await task.result
    }
}

private actor ObservationStartupSignal {
    private var result: Result<Void, Error>?
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        if let result {
            return try result.get()
        }

        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func succeed() {
        complete(with: .success(()))
    }

    func fail(_ error: Error) {
        complete(with: .failure(error))
    }

    private func complete(with result: Result<Void, Error>) {
        guard self.result == nil else {
            return
        }

        self.result = result
        let continuations = self.continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }
}

enum RemotePairingHTTPError: LocalizedError, Equatable {
    case requestFailed(String)
    case pairingRevoked(String)
    case missingPairedDeviceIdentity

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message), .pairingRevoked(let message):
            message
        case .missingPairedDeviceIdentity:
            "Pair this Mac again to browse its Workspace catalog"
        }
    }
}

private enum RemotePairingHTTPObservationError: LocalizedError {
    case connectionClosed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionClosed:
            "The connection to this Paired Mac was lost."
        case .invalidResponse:
            "The Paired Mac returned an invalid response."
        }
    }
}

struct RemotePairingCompletionRequest: Codable, Sendable {
    let pairingCode: String
    let deviceName: String
}

struct RemotePairingCompletionResponse: Codable, Sendable {
    let macName: String
    let pairedAt: Date
    let pairedDeviceID: UUID
}

struct RemoteSessionControlRequest: Codable, Sendable {
    let columns: Int
    let rows: Int
}

struct RemoteSessionTextRequest: Codable, Sendable {
    let text: String
}

struct RemoteSessionKeyRequest: Codable, Sendable {
    let key: SessionInputKey
}

struct RemotePairingErrorResponse: Codable, Sendable {
    let message: String
}
