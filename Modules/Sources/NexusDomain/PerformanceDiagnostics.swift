import Foundation

public enum PerformanceDiagnosticOperation: String, Codable, Equatable, Sendable {
    case appStartupBrowse
    case createLocalWorkspace
    case createRemoteWorkspace
    case workspaceOverview
    case providerDetail
    case launchDefaultSession
    case createNamedSession
    case launchSession
    case stopSession
    case deleteSessionRecord
    case validateHost
    case remoteClientAvailability
    case remoteClientCatalog
    case remoteClientProviderDetail
    case remoteClientSessionFocus
    case remoteClientSessionScreen
    case quickSwitchSearch
    case structuredSessionObservation
}

public enum PerformanceDiagnosticOutcome: String, Codable, Equatable, Sendable {
    case success
    case failure
}

public struct PerformanceDiagnosticStep: Codable, Equatable, Sendable {
    public let name: String
    public let elapsedMilliseconds: Int

    public init(name: String, elapsedMilliseconds: Int) {
        self.name = name
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public struct PerformanceDiagnosticRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let operation: PerformanceDiagnosticOperation
    public let outcome: PerformanceDiagnosticOutcome
    public let workspaceID: UUID?
    public let providerID: ProviderID?
    public let sessionID: UUID?
    public let totalElapsedMilliseconds: Int
    public let steps: [PerformanceDiagnosticStep]
    public let metrics: [String: Int]
    public let failureMessage: String?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        operation: PerformanceDiagnosticOperation,
        outcome: PerformanceDiagnosticOutcome,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil,
        totalElapsedMilliseconds: Int,
        steps: [PerformanceDiagnosticStep],
        metrics: [String: Int] = [:],
        failureMessage: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.operation = operation
        self.outcome = outcome
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.sessionID = sessionID
        self.totalElapsedMilliseconds = totalElapsedMilliseconds
        self.steps = steps
        self.metrics = metrics
        self.failureMessage = failureMessage
        self.recordedAt = recordedAt
    }
}
