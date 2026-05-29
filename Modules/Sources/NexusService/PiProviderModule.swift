#if os(macOS)
import Foundation
import NexusDomain

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
#endif
