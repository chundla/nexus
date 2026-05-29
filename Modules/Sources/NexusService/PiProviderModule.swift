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
