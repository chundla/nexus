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

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case ibmBob
    case pi

    public var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .ibmBob:
            "IBM Bob"
        case .pi:
            "Pi"
        }
    }
}

public struct Provider: Codable, Equatable, Identifiable, Sendable {
    public let id: ProviderID
    public let displayName: String

    public init(id: ProviderID, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id.displayName
    }
}

public struct ProviderHealthSummary: Codable, Equatable, Sendable {
    public let state: State
    public let summary: String

    public init(state: State, summary: String) {
        self.state = state
        self.summary = summary
    }

    public enum State: String, Codable, Sendable {
        case notChecked
    }
}

public struct ProviderDefaultSessionSummary: Codable, Equatable, Sendable {
    public let state: State
    public let summary: String
    public let actionTitle: String

    public init(state: State, summary: String, actionTitle: String) {
        self.state = state
        self.summary = summary
        self.actionTitle = actionTitle
    }

    public enum State: String, Codable, Sendable {
        case notCreated
    }
}

public struct WorkspaceProviderCard: Codable, Equatable, Identifiable, Sendable {
    public let provider: Provider
    public let health: ProviderHealthSummary
    public let defaultSession: ProviderDefaultSessionSummary

    public init(provider: Provider, health: ProviderHealthSummary, defaultSession: ProviderDefaultSessionSummary) {
        self.provider = provider
        self.health = health
        self.defaultSession = defaultSession
    }

    public var id: ProviderID {
        provider.id
    }
}

public struct WorkspaceOverview: Codable, Equatable, Sendable {
    public let workspace: Workspace
    public let providerCards: [WorkspaceProviderCard]

    public init(workspace: Workspace, providerCards: [WorkspaceProviderCard]) {
        self.workspace = workspace
        self.providerCards = providerCards
    }
}
