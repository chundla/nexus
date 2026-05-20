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

public struct ProviderHealthDiagnostic: Codable, Equatable, Sendable {
    public let severity: Severity
    public let code: String
    public let message: String

    public init(severity: Severity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }

    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }
}

public struct ProviderHealthSummary: Codable, Equatable, Sendable {
    public let state: State
    public let summary: String
    public let resolvedExecutable: String?
    public let version: String?
    public let launchability: Launchability
    public let diagnostics: [ProviderHealthDiagnostic]

    public init(
        state: State,
        summary: String,
        resolvedExecutable: String? = nil,
        version: String? = nil,
        launchability: Launchability = .notChecked,
        diagnostics: [ProviderHealthDiagnostic] = []
    ) {
        self.state = state
        self.summary = summary
        self.resolvedExecutable = resolvedExecutable
        self.version = version
        self.launchability = launchability
        self.diagnostics = diagnostics
    }

    public enum State: String, Codable, Sendable {
        case notChecked
        case available
        case unavailable
        case misconfigured
    }

    public enum Launchability: String, Codable, Sendable {
        case notChecked
        case launchable
        case notLaunchable
    }
}

public struct ProviderDefaultSessionSummary: Codable, Equatable, Sendable {
    public let state: State
    public let summary: String
    public let actionTitle: String
    public let sessionID: UUID?

    public init(state: State, summary: String, actionTitle: String, sessionID: UUID? = nil) {
        self.state = state
        self.summary = summary
        self.actionTitle = actionTitle
        self.sessionID = sessionID
    }

    public enum State: String, Codable, Sendable {
        case notCreated
        case ready
        case interrupted
        case exited
        case failed
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
