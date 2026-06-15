import Foundation
import NexusDomain
import NexusIPC

nonisolated struct RemotePairingEndpoint: Equatable, Sendable {
    let host: String
    let port: Int

    var displayAddress: String {
        "\(host):\(port)"
    }
}

nonisolated struct RemotePairedMacStatus: Codable, Equatable, Sendable {
    let macName: String
    let isRemoteAccessEnabled: Bool
}

nonisolated struct PairedMac: Codable, Equatable, Identifiable, Sendable {
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

nonisolated struct RemoteWorkspaceCatalog: Codable, Equatable, Sendable {
    let workspaceGroups: [WorkspaceGroup]
    let recentNavigation: [NavigationItem]
    let workspaceOverviews: [WorkspaceOverview]
}

nonisolated struct RemotePairingHTTPClient {
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
            path:
                "/remote-client/workspaces/\(workspaceID.uuidString)/providers/\(providerID.rawValue)/default-session/launch"
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

    func fetchStructuredSessionHistoryPage(
        for pairedMac: PairedMac,
        sessionID: UUID,
        pageSize: Int,
        before cursor: StructuredSessionHistoryCursor?
    ) async throws -> StructuredSessionHistoryPage {
        var components = URLComponents()
        components.path = "/remote-client/sessions/\(sessionID.uuidString)/structured-history"
        components.queryItems = [URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let cursor {
            components.queryItems?.append(
                URLQueryItem(name: "activityItemOffset", value: String(cursor.activityItemOffset)))
            components.queryItems?.append(
                URLQueryItem(name: "providerEventOffset", value: String(cursor.providerEventOffset)))
        }
        let request = try authenticatedRequest(for: pairedMac, path: components.string ?? components.path)
        let data = try await send(request)
        return try JSONDecoder().decode(StructuredSessionHistoryPage.self, from: data)
    }

    func fetchStructuredSessionArtifactFile(
        for pairedMac: PairedMac,
        sessionID: UUID,
        hostPath: String
    ) async throws -> StructuredSessionArtifactFile {
        var components = URLComponents()
        components.path = "/remote-client/sessions/\(sessionID.uuidString)/artifact"
        components.queryItems = [URLQueryItem(name: "hostPath", value: hostPath)]
        let request = try authenticatedRequest(for: pairedMac, path: components.string ?? components.path)
        let data = try await send(request)
        return try JSONDecoder().decode(StructuredSessionArtifactFile.self, from: data)
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

    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws
        -> SessionScreen
    {
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

    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        try await sendSessionInput(for: pairedMac, sessionID: sessionID, prompt: SessionPrompt(text: text))
    }

    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, prompt: SessionPrompt) async throws
        -> SessionScreen
    {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/input"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RemoteSessionInputRequest(prompt: prompt))
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func respondToApprovalRequest(
        for pairedMac: PairedMac,
        sessionID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        var request = try authenticatedRequest(
            for: pairedMac,
            path:
                "/remote-client/sessions/\(sessionID.uuidString)/approval-requests/\(approvalRequestID.uuidString)/decision"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RemoteApprovalRequestDecisionRequest(decision: decision))
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
    }

    func respondToExtensionDialog(
        for pairedMac: PairedMac,
        sessionID: UUID,
        dialogID: String,
        response: SessionExtensionUIDialogResponse
    ) async throws -> SessionScreen {
        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/extension-dialogs/\(dialogID)/response"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(response)
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

    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws
        -> SessionScreen
    {
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
        let initialSnapshot = try await fetchSessionScreenObservationSnapshot(for: pairedMac, sessionID: sessionID)
        let accumulator = SessionScreenObservationAccumulator(snapshot: initialSnapshot)
        onUpdate(initialSnapshot.screen)

        var request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/observe"
        )
        if let structuredRevision = initialSnapshot.structuredSnapshot?.revision {
            request.setValue(String(structuredRevision), forHTTPHeaderField: "X-Nexus-Structured-Revision")
        }

        let session = self.session
        let task = Task.detached(priority: nil) { [self] in
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

                for try await byte in bytes {
                    if Task.isCancelled {
                        return
                    }

                    eventBuffer.append(byte)
                    while let eventLines = Self.dequeueObservedEventLines(from: &eventBuffer) {
                        try await Self.emitObservedUpdate(
                            from: eventLines,
                            accumulator: accumulator,
                            snapshotFetcher: {
                                try await self.fetchSessionScreenObservationSnapshot(
                                    for: pairedMac, sessionID: sessionID)
                            },
                            onUpdate: onUpdate
                        )
                    }
                }

                if let eventLines = Self.dequeueTrailingObservedEventLines(from: eventBuffer) {
                    try await Self.emitObservedUpdate(
                        from: eventLines,
                        accumulator: accumulator,
                        snapshotFetcher: {
                            try await self.fetchSessionScreenObservationSnapshot(for: pairedMac, sessionID: sessionID)
                        },
                        onUpdate: onUpdate
                    )
                }

                if Task.isCancelled == false {
                    onDisconnect(RemotePairingHTTPObservationError.connectionClosed)
                }
            } catch {
                if Task.isCancelled == false {
                    onDisconnect(error)
                }
            }
        }

        return RemoteSessionScreenHTTPObservation(task: task)
    }

    private func fetchSessionScreenObservationSnapshot(
        for pairedMac: PairedMac,
        sessionID: UUID
    ) async throws -> SessionScreenObservationSnapshotResponse {
        let request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/observe-start"
        )
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreenObservationSnapshotResponse.self, from: data)
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

    private nonisolated static func emitObservedUpdate(
        from eventLines: [String],
        accumulator: SessionScreenObservationAccumulator,
        snapshotFetcher: @escaping @Sendable () async throws -> SessionScreenObservationSnapshotResponse,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void
    ) async throws {
        guard eventLines.isEmpty == false else {
            return
        }

        let payload = eventLines.joined(separator: "\n")
        let update = try JSONDecoder().decode(SessionScreenObservationUpdate.self, from: Data(payload.utf8))

        do {
            if let screen = try accumulator.apply(update) {
                onUpdate(screen)
            }
        } catch is SessionScreenObservationGapError {
            let latestSnapshot = try await snapshotFetcher()
            onUpdate(accumulator.replace(with: latestSnapshot))
        }
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
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let lines =
            text
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("data:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return lines.isEmpty ? nil : lines
    }

    private nonisolated static func decodeRequestFailure(from data: Data, statusCode: Int) -> RemotePairingHTTPError {
        let message =
            ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
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

nonisolated enum RemotePairingHTTPError: LocalizedError, Equatable {
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

nonisolated struct RemotePairingCompletionRequest: Codable, Sendable {
    let pairingCode: String
    let deviceName: String
}

nonisolated struct RemotePairingCompletionResponse: Codable, Sendable {
    let macName: String
    let pairedAt: Date
    let pairedDeviceID: UUID
}

nonisolated struct RemoteSessionControlRequest: Codable, Sendable {
    let columns: Int
    let rows: Int
}

nonisolated struct RemoteSessionInputRequest: Codable, Sendable {
    let prompt: SessionPrompt

    init(text: String) {
        self.prompt = SessionPrompt(text: text)
    }

    init(prompt: SessionPrompt) {
        self.prompt = prompt
    }
}

nonisolated struct RemoteSessionTextRequest: Codable, Sendable {
    let text: String
}

nonisolated struct RemoteApprovalRequestDecisionRequest: Codable, Sendable {
    let decision: ApprovalRequestDecision
}

nonisolated struct RemoteSessionKeyRequest: Codable, Sendable {
    let key: SessionInputKey
}

nonisolated struct RemotePairingErrorResponse: Codable, Sendable {
    let message: String
}
