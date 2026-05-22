import Foundation

public struct RemoteAccessState: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let activePairing: PairingCeremony?

    public init(isEnabled: Bool, activePairing: PairingCeremony?) {
        self.isEnabled = isEnabled
        self.activePairing = activePairing
    }
}

public struct PairingCeremony: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let code: String
    public let qrPayload: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: UUID, code: String, qrPayload: String, createdAt: Date, expiresAt: Date) {
        self.id = id
        self.code = code
        self.qrPayload = qrPayload
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct PairedDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let pairedAt: Date

    public init(id: UUID, name: String, pairedAt: Date) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
    }
}
