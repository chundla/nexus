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
        case remote
    }
}

public struct Host: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let sshTarget: String
    public let port: Int?

    public init(id: UUID, name: String, sshTarget: String, port: Int? = nil) {
        self.id = id
        self.name = name
        self.sshTarget = sshTarget
        self.port = port
    }
}

public struct HostValidationDiagnostic: Codable, Equatable, Sendable {
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

public struct HostValidationSnapshot: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let state: State
    public let summary: String
    public let checkedAt: Date
    public let diagnostics: [HostValidationDiagnostic]

    public init(
        hostID: UUID,
        state: State,
        summary: String,
        checkedAt: Date,
        diagnostics: [HostValidationDiagnostic] = []
    ) {
        self.hostID = hostID
        self.state = state
        self.summary = summary
        self.checkedAt = checkedAt
        self.diagnostics = diagnostics
    }

    public enum State: String, Codable, Sendable {
        case notChecked
        case available
        case unavailable
        case broken
    }
}

public struct HostDetail: Codable, Equatable, Sendable {
    public let host: Host
    public let latestValidation: HostValidationSnapshot?

    public init(host: Host, latestValidation: HostValidationSnapshot?) {
        self.host = host
        self.latestValidation = latestValidation
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
    public let alternateSessionCount: Int

    public init(
        provider: Provider,
        health: ProviderHealthSummary,
        defaultSession: ProviderDefaultSessionSummary,
        alternateSessionCount: Int = 0
    ) {
        self.provider = provider
        self.health = health
        self.defaultSession = defaultSession
        self.alternateSessionCount = alternateSessionCount
    }

    public var id: ProviderID {
        provider.id
    }
}

public struct ProviderDetail: Codable, Equatable, Sendable {
    public let workspace: Workspace
    public let provider: Provider
    public let health: ProviderHealthSummary
    public let defaultSession: Session?
    public let alternateSessions: [Session]
    public let failedSessions: [Session]

    public init(
        workspace: Workspace,
        provider: Provider,
        health: ProviderHealthSummary,
        defaultSession: Session?,
        alternateSessions: [Session],
        failedSessions: [Session]
    ) {
        self.workspace = workspace
        self.provider = provider
        self.health = health
        self.defaultSession = defaultSession
        self.alternateSessions = alternateSessions
        self.failedSessions = failedSessions
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

public struct NavigationTarget: Codable, Equatable, Hashable, Sendable {
    public let kind: Kind
    public let workspaceID: UUID?
    public let providerID: ProviderID?
    public let sessionID: UUID?

    public init(kind: Kind, workspaceID: UUID? = nil, providerID: ProviderID? = nil, sessionID: UUID? = nil) {
        self.kind = kind
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.sessionID = sessionID
    }

    public static func workspace(_ workspaceID: UUID) -> NavigationTarget {
        NavigationTarget(kind: .workspace, workspaceID: workspaceID)
    }

    public static func provider(workspaceID: UUID, providerID: ProviderID) -> NavigationTarget {
        NavigationTarget(kind: .provider, workspaceID: workspaceID, providerID: providerID)
    }

    public static func session(_ sessionID: UUID) -> NavigationTarget {
        NavigationTarget(kind: .session, sessionID: sessionID)
    }

    public enum Kind: String, Codable, Sendable {
        case workspace
        case provider
        case session
    }
}

public struct NavigationItem: Codable, Equatable, Identifiable, Sendable {
    public let target: NavigationTarget
    public let title: String
    public let subtitle: String
    public let kind: NavigationTarget.Kind

    public init(target: NavigationTarget, title: String, subtitle: String, kind: NavigationTarget.Kind? = nil) {
        self.target = target
        self.title = title
        self.subtitle = subtitle
        self.kind = kind ?? target.kind
    }

    public var id: String {
        switch target.kind {
        case .workspace:
            "workspace:\(target.workspaceID?.uuidString ?? "missing")"
        case .provider:
            "provider:\(target.workspaceID?.uuidString ?? "missing"):\(target.providerID?.rawValue ?? "missing")"
        case .session:
            "session:\(target.sessionID?.uuidString ?? "missing")"
        }
    }
}
