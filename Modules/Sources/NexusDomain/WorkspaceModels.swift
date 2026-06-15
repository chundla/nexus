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
    public let remoteHostID: UUID?

    public init(id: UUID, name: String, kind: Kind, folderPath: String, primaryGroupID: UUID, remoteHostID: UUID? = nil)
    {
        self.id = id
        self.name = name
        self.kind = kind
        self.folderPath = folderPath
        self.primaryGroupID = primaryGroupID
        self.remoteHostID = remoteHostID
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

public struct WorkspaceAvailabilityDiagnostic: Codable, Equatable, Sendable {
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

public struct WorkspaceAvailabilitySnapshot: Codable, Equatable, Sendable {
    public let workspaceID: UUID
    public let state: State
    public let summary: String
    public let checkedAt: Date
    public let diagnostics: [WorkspaceAvailabilityDiagnostic]

    public init(
        workspaceID: UUID,
        state: State,
        summary: String,
        checkedAt: Date,
        diagnostics: [WorkspaceAvailabilityDiagnostic] = []
    ) {
        self.workspaceID = workspaceID
        self.state = state
        self.summary = summary
        self.checkedAt = checkedAt
        self.diagnostics = diagnostics
    }

    public enum State: String, Codable, Sendable {
        case available
        case unavailable
        case broken
        case blocked
    }
}

public struct RemoteWorkspaceTargetOverview: Codable, Equatable, Sendable {
    public let host: Host
    public let hostValidation: HostValidationSnapshot?
    public let workspaceAvailability: WorkspaceAvailabilitySnapshot

    public init(
        host: Host, hostValidation: HostValidationSnapshot?, workspaceAvailability: WorkspaceAvailabilitySnapshot
    ) {
        self.host = host
        self.hostValidation = hostValidation
        self.workspaceAvailability = workspaceAvailability
    }
}

public enum ProviderID: String, Codable, CaseIterable, Hashable, Sendable {
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
    public let checkedAt: Date?
    public let diagnostics: [ProviderHealthDiagnostic]

    public init(
        state: State,
        summary: String,
        resolvedExecutable: String? = nil,
        version: String? = nil,
        launchability: Launchability = .notChecked,
        checkedAt: Date? = nil,
        diagnostics: [ProviderHealthDiagnostic] = []
    ) {
        self.state = state
        self.summary = summary
        self.resolvedExecutable = resolvedExecutable
        self.version = version
        self.launchability = launchability
        self.checkedAt = checkedAt
        self.diagnostics = diagnostics
    }

    public enum State: String, Codable, Sendable {
        case notChecked
        case available
        case unavailable
        case misconfigured
        case blocked
    }

    public enum Launchability: String, Codable, Sendable {
        case notChecked
        case launchable
        case notLaunchable
    }
}

public struct ProviderCapability: Codable, Equatable, Sendable {
    public let action: Action
    public let isSupported: Bool
    public let isEnabled: Bool
    public let disabledReason: String?

    public init(action: Action, isSupported: Bool, isEnabled: Bool, disabledReason: String? = nil) {
        self.action = action
        self.isSupported = isSupported
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }

    public enum Action: String, Codable, Sendable {
        case launchDefaultSession
        case createNamedSession
    }
}

public struct ProviderCapabilities: Codable, Equatable, Sendable {
    public let launchDefaultSession: ProviderCapability
    public let createNamedSession: ProviderCapability

    public init(
        launchDefaultSession: ProviderCapability = ProviderCapability(
            action: .launchDefaultSession, isSupported: false, isEnabled: false),
        createNamedSession: ProviderCapability = ProviderCapability(
            action: .createNamedSession, isSupported: false, isEnabled: false)
    ) {
        self.launchDefaultSession = launchDefaultSession
        self.createNamedSession = createNamedSession
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
    public let capabilities: ProviderCapabilities
    public let prelaunchPrimarySurface: SessionSurface
    public let defaultSession: ProviderDefaultSessionSummary
    public let alternateSessionCount: Int

    public init(
        provider: Provider,
        health: ProviderHealthSummary,
        capabilities: ProviderCapabilities = ProviderCapabilities(),
        prelaunchPrimarySurface: SessionSurface = .terminal,
        defaultSession: ProviderDefaultSessionSummary,
        alternateSessionCount: Int = 0
    ) {
        self.provider = provider
        self.health = health
        self.capabilities = capabilities
        self.prelaunchPrimarySurface = prelaunchPrimarySurface
        self.defaultSession = defaultSession
        self.alternateSessionCount = alternateSessionCount
    }

    public var id: ProviderID {
        provider.id
    }

    public var namedSessionSummary: String? {
        guard alternateSessionCount > 0 else { return nil }
        return "\(alternateSessionCount) named session\(alternateSessionCount == 1 ? "" : "s")"
    }
}

public struct ProviderDetail: Codable, Equatable, Sendable {
    public let workspace: Workspace
    public let provider: Provider
    public let health: ProviderHealthSummary
    public let capabilities: ProviderCapabilities
    public let prelaunchPrimarySurface: SessionSurface
    public let defaultSession: Session?
    public let alternateSessions: [Session]
    public let failedSessions: [Session]

    public init(
        workspace: Workspace,
        provider: Provider,
        health: ProviderHealthSummary,
        capabilities: ProviderCapabilities = ProviderCapabilities(),
        prelaunchPrimarySurface: SessionSurface = .terminal,
        defaultSession: Session?,
        alternateSessions: [Session],
        failedSessions: [Session]
    ) {
        self.workspace = workspace
        self.provider = provider
        self.health = health
        self.capabilities = capabilities
        self.prelaunchPrimarySurface = prelaunchPrimarySurface
        self.defaultSession = defaultSession
        self.alternateSessions = alternateSessions
        self.failedSessions = failedSessions
    }
}

public struct WorkspaceOverview: Codable, Equatable, Sendable {
    public let workspace: Workspace
    public let providerCards: [WorkspaceProviderCard]
    public let remoteTarget: RemoteWorkspaceTargetOverview?
    public let usesStaleBrowseFacts: Bool

    public init(
        workspace: Workspace,
        providerCards: [WorkspaceProviderCard],
        remoteTarget: RemoteWorkspaceTargetOverview? = nil,
        usesStaleBrowseFacts: Bool = false
    ) {
        self.workspace = workspace
        self.providerCards = providerCards
        self.remoteTarget = remoteTarget
        self.usesStaleBrowseFacts = usesStaleBrowseFacts
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

public enum RemoteClientDiagnosticKind: String, Codable, Equatable, Sendable {
    case reconnectFailure
    case actionFailure
}

public enum RemoteClientDiagnosticOperation: String, Codable, Equatable, Sendable {
    case fetchCatalog
    case fetchProviderDetail
    case launchDefaultSession
    case createNamedSession
    case launchSession
    case stopSession
    case deleteSessionRecord
    case fetchSessionScreen
    case observeSessionScreen
    case takeSessionControl
    case releaseSessionControl
    case sendSessionInput
    case respondToApprovalRequest
    case respondToExtensionDialog
    case sendSessionText
    case sendSessionInputKey
}

public struct RemoteClientDiagnosticBreadcrumb: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: RemoteClientDiagnosticKind
    public let operation: RemoteClientDiagnosticOperation
    public let message: String
    public let pairedMacID: String?
    public let pairedDeviceID: UUID?
    public let workspaceID: UUID?
    public let providerID: ProviderID?
    public let sessionID: UUID?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        kind: RemoteClientDiagnosticKind,
        operation: RemoteClientDiagnosticOperation,
        message: String,
        pairedMacID: String? = nil,
        pairedDeviceID: UUID? = nil,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.operation = operation
        self.message = message
        self.pairedMacID = pairedMacID
        self.pairedDeviceID = pairedDeviceID
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.sessionID = sessionID
        self.recordedAt = recordedAt
    }
}
