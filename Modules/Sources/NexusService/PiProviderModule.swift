#if os(macOS)
import Foundation
import NexusDomain

struct PiProviderModule: ProviderModule {
    let provider = Provider(id: .pi)

    init() {}

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        true
    }

    func supportsNamedSessions(in workspace: Workspace) -> Bool {
        true
    }

    func providerHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await providerHealthEvaluator.healthSummary(for: .pi, workspace: workspace, remoteContext: remoteContext)
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
        shouldReuseRemoteCLIHealthSnapshot(snapshot, remoteContext: remoteContext)
    }

    func planPersistedSessionRelaunch(
        _ request: ProviderModulePersistedSessionRelaunchRequest
    ) -> ProviderModulePersistedSessionRelaunchPlan {
        guard request.execution.workspace.kind == .remote else {
            return .sharedLaunch
        }

        let freshRemoteRelaunch = ProviderModuleFreshRemotePersistedSessionRelaunch(
            sessionRecordAdapterMetadataSource: request.execution.sessionRecordAdapterMetadataSource,
            retriesWithoutContinuity: true
        )

        switch request.execution.mode {
        case .recoverRemoteRuntime:
            return .recoverRemoteRuntime(freshRemoteRelaunch)
        case let .launch(forceFreshRemoteRuntime):
            return forceFreshRemoteRuntime
                ? .launchFreshRemoteRuntime(freshRemoteRelaunch)
                : .sharedLaunch
        }
    }

    func shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
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
