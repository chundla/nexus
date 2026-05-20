import Foundation

public struct Session: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let workspaceID: UUID
    public let providerID: ProviderID
    public let isDefault: Bool
    public let state: State
    public let failureMessage: String?

    public init(
        id: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        isDefault: Bool,
        state: State,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.isDefault = isDefault
        self.state = state
        self.failureMessage = failureMessage
    }

    public enum State: String, Codable, Sendable {
        case ready
        case failed
    }
}
