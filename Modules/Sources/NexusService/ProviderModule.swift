#if os(macOS)
import Foundation
import NexusDomain

enum ProviderModuleOpenSessionRequest {
    case launchOrResumeDefaultSession(workspace: Workspace, providerID: ProviderID)
    case createNamedSession(workspace: Workspace, providerID: ProviderID, name: String?)
    case launchOrResumePersistedSession(Session, workspace: Workspace)

    var providerID: ProviderID {
        switch self {
        case let .launchOrResumeDefaultSession(_, providerID),
             let .createNamedSession(_, providerID, _):
            providerID
        case let .launchOrResumePersistedSession(session, _):
            session.providerID
        }
    }

    var workspace: Workspace {
        switch self {
        case let .launchOrResumeDefaultSession(workspace, _),
             let .createNamedSession(workspace, _, _),
             let .launchOrResumePersistedSession(_, workspace):
            workspace
        }
    }
}

struct ProviderModuleOpenSessionActions {
    let defaultSession: (_ workspaceID: UUID, _ providerID: ProviderID) throws -> Session?
    let listSessions: (_ workspaceID: UUID, _ providerID: ProviderID) throws -> [Session]
    let resolveNamedSessionName: (_ requestedName: String?, _ existingSessions: [Session]) -> String
    let providerHealthSummary: (_ providerID: ProviderID, _ workspace: Workspace) async throws -> ProviderHealthSummary
    let createDefaultSession: (_ workspaceID: UUID, _ providerID: ProviderID, _ state: Session.State, _ failureMessage: String?) throws -> Session
    let createNamedSession: (_ workspaceID: UUID, _ providerID: ProviderID, _ name: String, _ state: Session.State, _ failureMessage: String?) throws -> Session
    let launchFreshSession: (_ session: Session, _ workspace: Workspace, _ primarySurface: SessionSurface, _ executable: String) async throws -> Session
    let launchPersistedSession: (_ session: Session, _ workspace: Workspace) async throws -> Session
}

struct ProviderModulePersistedSessionLaunchActions {
    let executeSharedLaunch: () async throws -> Session
    let attemptRemoteRuntimeRecovery: () async throws -> Session
    let remoteRuntimeRecoveryFailureContext: (Error) throws -> RemoteRuntimeRecoveryFailureContext
    let persistRemoteRecoveryFailure: (RemoteRuntimeRecoveryFailureContext) throws -> Session
    let attemptLaunch: (_ forceFreshRemoteRuntime: Bool, _ sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource) async throws -> Session
    let persistLaunchFailure: (Error) throws -> Session
    let resolvedSessionRecordAdapterMetadata: (SessionRecordAdapterMetadataLaunchSource) throws -> SessionRecordAdapterMetadata?
}

struct ProviderModulePersistedSessionLaunchRequest {
    let execution: PersistedSessionLaunchExecution
    let actions: ProviderModulePersistedSessionLaunchActions
}

protocol ProviderModule {
    var provider: Provider { get }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool

    func supportsNamedSessions(in workspace: Workspace) -> Bool

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool

    func openSession(
        _ request: ProviderModuleOpenSessionRequest,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session

    func launchPersistedSession(
        _ request: ProviderModulePersistedSessionLaunchRequest
    ) async throws -> Session
}

extension ProviderModule {
    func openSession(
        _ request: ProviderModuleOpenSessionRequest,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        try await executeSharedOpenSession(request, actions: actions)
    }

    func launchPersistedSession(
        _ request: ProviderModulePersistedSessionLaunchRequest
    ) async throws -> Session {
        try await request.actions.executeSharedLaunch()
    }

    func executeSharedOpenSession(
        _ request: ProviderModuleOpenSessionRequest,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        switch request {
        case let .launchOrResumeDefaultSession(workspace, providerID):
            return try await launchOrResumeDefaultSession(
                workspaceID: workspace.id,
                providerID: providerID,
                workspace: workspace,
                actions: actions
            )
        case let .createNamedSession(workspace, providerID, name):
            return try await createNamedSession(
                workspaceID: workspace.id,
                providerID: providerID,
                name: name,
                workspace: workspace,
                actions: actions
            )
        case let .launchOrResumePersistedSession(session, workspace):
            return try await launchOrResumePersistedSession(session, workspace: workspace, actions: actions)
        }
    }

    private func launchOrResumeDefaultSession(
        workspaceID: UUID,
        providerID: ProviderID,
        workspace: Workspace,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        guard supportsDefaultSessionLaunch(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        if let existingSession = try actions.defaultSession(workspaceID, providerID) {
            return try await actions.launchPersistedSession(existingSession, workspace)
        }

        let health = try await actions.providerHealthSummary(providerID, workspace)
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try actions.createDefaultSession(
                workspaceID,
                providerID,
                .failed,
                providerHealthFailureMessage(from: health)
            )
        }

        let session = try actions.createDefaultSession(workspaceID, providerID, .ready, nil)
        return try await actions.launchFreshSession(
            session,
            workspace,
            prelaunchPrimarySurface(in: workspace),
            executable
        )
    }

    private func createNamedSession(
        workspaceID: UUID,
        providerID: ProviderID,
        name: String?,
        workspace: Workspace,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        guard supportsNamedSessions(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let existingSessions = try actions.listSessions(workspaceID, providerID)
        let resolvedName = actions.resolveNamedSessionName(name, existingSessions)
        let health = try await actions.providerHealthSummary(providerID, workspace)

        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try actions.createNamedSession(
                workspaceID,
                providerID,
                resolvedName,
                .failed,
                providerHealthFailureMessage(from: health)
            )
        }

        let session = try actions.createNamedSession(workspaceID, providerID, resolvedName, .ready, nil)
        return try await actions.launchFreshSession(
            session,
            workspace,
            prelaunchPrimarySurface(in: workspace),
            executable
        )
    }

    private func launchOrResumePersistedSession(
        _ session: Session,
        workspace: Workspace,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        let isSupported = session.isDefault
            ? supportsDefaultSessionLaunch(in: workspace)
            : supportsNamedSessions(in: workspace)
        guard isSupported else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        return try await actions.launchPersistedSession(session, workspace)
    }
}

struct ProviderModuleRegistry {
    private let modules: [ProviderID: any ProviderModule]
    private let fallbackModuleFactory: (ProviderID) -> any ProviderModule

    init(
        modules: [ProviderID: any ProviderModule] = [:],
        fallbackModuleFactory: @escaping (ProviderID) -> any ProviderModule = { UnsupportedProviderModule(providerID: $0) }
    ) {
        self.modules = modules
        self.fallbackModuleFactory = fallbackModuleFactory
    }

    func module(for providerID: ProviderID) -> any ProviderModule {
        modules[providerID] ?? fallbackModuleFactory(providerID)
    }
}

private func makeProviderCapabilities(
    provider: Provider,
    supportsDefaultSessionLaunch: Bool,
    supportsNamedSessions: Bool,
    health: ProviderHealthSummary,
    defaultSession: Session?
) -> ProviderCapabilities {
    let canLaunchDefaultSession = supportsDefaultSessionLaunch && (defaultSession != nil || health.launchability == .launchable)
    let canCreateNamedSession = supportsNamedSessions && health.launchability == .launchable

    return ProviderCapabilities(
        launchDefaultSession: ProviderCapability(
            action: .launchDefaultSession,
            isSupported: supportsDefaultSessionLaunch,
            isEnabled: canLaunchDefaultSession,
            disabledReason: providerCapabilityDisabledReason(
                action: .launchDefaultSession,
                provider: provider,
                isSupported: supportsDefaultSessionLaunch,
                health: health,
                isEnabled: canLaunchDefaultSession
            )
        ),
        createNamedSession: ProviderCapability(
            action: .createNamedSession,
            isSupported: supportsNamedSessions,
            isEnabled: canCreateNamedSession,
            disabledReason: providerCapabilityDisabledReason(
                action: .createNamedSession,
                provider: provider,
                isSupported: supportsNamedSessions,
                health: health,
                isEnabled: canCreateNamedSession
            )
        )
    )
}

private func providerCapabilityDisabledReason(
    action: ProviderCapability.Action,
    provider: Provider,
    isSupported: Bool,
    health: ProviderHealthSummary,
    isEnabled: Bool
) -> String? {
    guard isEnabled == false else {
        return nil
    }

    guard isSupported else {
        switch action {
        case .launchDefaultSession:
            return "\(provider.displayName) cannot launch a Default Session on this Workspace yet."
        case .createNamedSession:
            return "\(provider.displayName) cannot create Named Sessions on this Workspace yet."
        }
    }

    return health.summary
}

private func providerHealthFailureMessage(from health: ProviderHealthSummary) -> String {
    health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
}

private struct UnsupportedProviderModule: ProviderModule {
    let provider: Provider

    init(providerID: ProviderID) {
        self.provider = Provider(id: providerID)
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        false
    }

    func supportsNamedSessions(in workspace: Workspace) -> Bool {
        false
    }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: provider.id, workspace: workspace, remoteContext: remoteContext)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        makeProviderCapabilities(
            provider: provider,
            supportsDefaultSessionLaunch: supportsDefaultSessionLaunch(in: workspace),
            supportsNamedSessions: supportsNamedSessions(in: workspace),
            health: health,
            defaultSession: defaultSession
        )
    }

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
        .terminal
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        false
    }
}

struct PiProviderModule: ProviderModule {
    let provider = Provider(id: .pi)

    private let healthSummaryEvaluator: (Workspace, RemoteWorkspaceHealthContext?, any ProviderHealthEvaluating) async -> ProviderHealthSummary
    private let defaultSessionLaunchSupportEvaluator: (Workspace) -> Bool
    private let namedSessionSupportEvaluator: (Workspace) -> Bool
    private let remoteHealthSnapshotReuseEvaluator: (ProviderHealthSummary, RemoteWorkspaceHealthContext?) -> Bool

    init(adapter: ServiceProviderAdapter) {
        self.healthSummaryEvaluator = { workspace, remoteContext, providerHealthEvaluator in
            await adapter.healthSummary(
                for: workspace,
                remoteContext: remoteContext,
                providerHealthEvaluator: providerHealthEvaluator
            )
        }
        self.defaultSessionLaunchSupportEvaluator = { workspace in
            adapter.supportsDefaultSessionLaunch(in: workspace)
        }
        self.namedSessionSupportEvaluator = { workspace in
            adapter.supportsNamedSessions(in: workspace)
        }
        self.remoteHealthSnapshotReuseEvaluator = { snapshot, remoteContext in
            adapter.shouldReuseRemoteHealthSnapshot(snapshot, remoteContext)
        }
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        defaultSessionLaunchSupportEvaluator(workspace)
    }

    func supportsNamedSessions(in workspace: Workspace) -> Bool {
        namedSessionSupportEvaluator(workspace)
    }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await healthSummaryEvaluator(workspace, remoteContext, providerHealthEvaluator)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        makeProviderCapabilities(
            provider: provider,
            supportsDefaultSessionLaunch: supportsDefaultSessionLaunch(in: workspace),
            supportsNamedSessions: supportsNamedSessions(in: workspace),
            health: health,
            defaultSession: defaultSession
        )
    }

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
        .structuredActivityFeed
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        remoteHealthSnapshotReuseEvaluator(snapshot, remoteContext)
    }

    func openSession(
        _ request: ProviderModuleOpenSessionRequest,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        switch request {
        case let .launchOrResumeDefaultSession(workspace, providerID):
            return try await launchOrResumeDefaultSession(
                workspaceID: workspace.id,
                providerID: providerID,
                workspace: workspace,
                actions: actions
            )
        case let .createNamedSession(workspace, providerID, name):
            return try await createNamedSession(
                workspaceID: workspace.id,
                providerID: providerID,
                name: name,
                workspace: workspace,
                actions: actions
            )
        case let .launchOrResumePersistedSession(session, workspace):
            return try await launchOrResumePersistedSession(session, workspace: workspace, actions: actions)
        }
    }

    func launchPersistedSession(
        _ request: ProviderModulePersistedSessionLaunchRequest
    ) async throws -> Session {
        guard request.execution.workspace.kind == .remote else {
            return try await request.actions.executeSharedLaunch()
        }

        switch request.execution.mode {
        case .recoverRemoteRuntime:
            return try await recoverRemotePersistedSession(request)
        case let .launch(forceFreshRemoteRuntime):
            guard forceFreshRemoteRuntime else {
                return try await request.actions.executeSharedLaunch()
            }

            return try await launchFreshRemotePersistedSession(
                request,
                sessionRecordAdapterMetadataSource: request.execution.sessionRecordAdapterMetadataSource
            )
        }
    }

    private func launchOrResumeDefaultSession(
        workspaceID: UUID,
        providerID: ProviderID,
        workspace: Workspace,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        guard supportsDefaultSessionLaunch(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        if let existingSession = try actions.defaultSession(workspaceID, providerID) {
            return try await actions.launchPersistedSession(existingSession, workspace)
        }

        let health = try await actions.providerHealthSummary(providerID, workspace)
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try actions.createDefaultSession(
                workspaceID,
                providerID,
                .failed,
                providerHealthFailureMessage(from: health)
            )
        }

        let session = try actions.createDefaultSession(workspaceID, providerID, .ready, nil)
        return try await actions.launchFreshSession(
            session,
            workspace,
            prelaunchPrimarySurface(in: workspace),
            executable
        )
    }

    private func createNamedSession(
        workspaceID: UUID,
        providerID: ProviderID,
        name: String?,
        workspace: Workspace,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        guard supportsNamedSessions(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let existingSessions = try actions.listSessions(workspaceID, providerID)
        let resolvedName = actions.resolveNamedSessionName(name, existingSessions)
        let health = try await actions.providerHealthSummary(providerID, workspace)

        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try actions.createNamedSession(
                workspaceID,
                providerID,
                resolvedName,
                .failed,
                providerHealthFailureMessage(from: health)
            )
        }

        let session = try actions.createNamedSession(workspaceID, providerID, resolvedName, .ready, nil)
        return try await actions.launchFreshSession(
            session,
            workspace,
            prelaunchPrimarySurface(in: workspace),
            executable
        )
    }

    private func launchOrResumePersistedSession(
        _ session: Session,
        workspace: Workspace,
        actions: ProviderModuleOpenSessionActions
    ) async throws -> Session {
        let isSupported = session.isDefault
            ? supportsDefaultSessionLaunch(in: workspace)
            : supportsNamedSessions(in: workspace)
        guard isSupported else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        return try await actions.launchPersistedSession(session, workspace)
    }

    private func recoverRemotePersistedSession(
        _ request: ProviderModulePersistedSessionLaunchRequest
    ) async throws -> Session {
        do {
            return try await request.actions.attemptRemoteRuntimeRecovery()
        } catch {
            let failureContext = try request.actions.remoteRuntimeRecoveryFailureContext(error)
            if failureContext.isMissingRemoteRuntime {
                return try await launchFreshRemotePersistedSession(
                    request,
                    sessionRecordAdapterMetadataSource: request.execution.sessionRecordAdapterMetadataSource
                )
            }

            return try request.actions.persistRemoteRecoveryFailure(failureContext)
        }
    }

    private func launchFreshRemotePersistedSession(
        _ request: ProviderModulePersistedSessionLaunchRequest,
        sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource
    ) async throws -> Session {
        do {
            return try await request.actions.attemptLaunch(true, sessionRecordAdapterMetadataSource)
        } catch {
            if try shouldRetryFreshRemotePersistedPiLaunchWithoutContinuity(
                error,
                metadata: request.actions.resolvedSessionRecordAdapterMetadata(sessionRecordAdapterMetadataSource)
            ) {
                return try await launchFreshRemotePersistedSession(
                    request,
                    sessionRecordAdapterMetadataSource: .explicit(nil)
                )
            }

            return try request.actions.persistLaunchFailure(error)
        }
    }

    private func shouldRetryFreshRemotePersistedPiLaunchWithoutContinuity(
        _ error: Error,
        metadata: SessionRecordAdapterMetadata?
    ) throws -> Bool {
        guard metadata?.piSessionLinkage != nil else {
            return false
        }

        let normalized = error.localizedDescription.lowercased()
        return normalized.contains("invalid pi session")
            || normalized.contains("invalid session")
            || normalized.contains("session not found")
    }
}

extension ServiceProviderAdapter: ProviderModule {
    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await healthSummary(for: workspace, remoteContext: remoteContext, providerHealthEvaluator: providerHealthEvaluator)
    }

    func providerCapabilities(
        in workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        makeProviderCapabilities(
            provider: provider,
            supportsDefaultSessionLaunch: supportsDefaultSessionLaunch(in: workspace),
            supportsNamedSessions: supportsNamedSessions(in: workspace),
            health: health,
            defaultSession: defaultSession
        )
    }

    func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
        primarySurface(in: workspace)
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        shouldReuseRemoteHealthSnapshot(snapshot, remoteContext)
    }
}
#endif
