import Foundation

public struct WorkspaceGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: Kind
    public let folderPath: String
    public let primaryGroupID: UUID

    public init(id: UUID, name: String, kind: Kind, folderPath: String, primaryGroupID: UUID) {
        self.id = id
        self.name = name
        self.kind = kind
        self.folderPath = folderPath
        self.primaryGroupID = primaryGroupID
    }

    public enum Kind: String, Codable, Sendable {
        case local
    }
}
