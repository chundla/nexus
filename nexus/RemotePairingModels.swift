import Foundation

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

    var id: String {
        "\(host.lowercased()):\(port)"
    }
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
        return PairedMac(name: completion.macName, host: host, port: port, pairedAt: completion.pairedAt)
    }
}

enum RemotePairingHTTPError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            message
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
}

struct RemotePairingErrorResponse: Codable, Sendable {
    let message: String
}
