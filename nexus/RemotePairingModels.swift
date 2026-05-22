import Foundation
import NexusDomain

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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus {
        let request = URLRequest(url: URL(string: "http://\(host):\(port)/remote-client/status")!)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse?.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(RemotePairingErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 500)
            throw RemotePairingHTTPError.requestFailed(message)
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
            let message = (try? JSONDecoder().decode(RemotePairingErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 500)
            throw RemotePairingHTTPError.requestFailed(message)
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

    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        let request = try authenticatedRequest(
            for: pairedMac,
            path: "/remote-client/sessions/\(sessionID.uuidString)/screen"
        )
        let data = try await send(request)
        return try JSONDecoder().decode(SessionScreen.self, from: data)
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
            let message = (try? JSONDecoder().decode(RemotePairingErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 500)
            throw RemotePairingHTTPError.requestFailed(message)
        }

        return data
    }
}

enum RemotePairingHTTPError: LocalizedError {
    case requestFailed(String)
    case missingPairedDeviceIdentity

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            message
        case .missingPairedDeviceIdentity:
            "Pair this Mac again to browse its Workspace catalog"
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

struct RemotePairingErrorResponse: Codable, Sendable {
    let message: String
}
