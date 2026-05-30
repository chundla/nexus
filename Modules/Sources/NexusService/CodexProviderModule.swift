#if os(macOS)
import Foundation
import NexusDomain

struct CodexProviderModule: ProviderModule {
    let provider = Provider(id: .codex)

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
        await providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
    }

    func readCatalog(
        _ request: ProviderModuleCatalogReadRequest,
        actions: ProviderModuleCatalogReadActions
    ) async throws -> ProviderModuleCatalogReadResult {
        let health = try await actions.providerHealthSummary()
        return ProviderModuleCatalogReadResult(
            health: health,
            capabilities: providerCapabilities(
                in: request.workspace,
                health: health,
                defaultSession: request.defaultSession
            ),
            prelaunchPrimarySurface: prelaunchPrimarySurface(in: request.workspace)
        )
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

    func planSessionTransition(
        _ request: ProviderModuleSessionTransitionRequest
    ) async throws -> ProviderModuleSessionTransitionPlan {
        switch request {
        case let .openFresh(freshRequest, actions):
            return .openFresh(try await executeSharedFreshSessionOpen(freshRequest, actions: actions))
        case let .relaunchPersisted(relaunchRequest):
            return .relaunchPersisted(planPersistedSessionRelaunch(relaunchRequest))
        }
    }

    func constructRuntime(
        for session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration,
        actions: ProviderModuleRuntimeConstructionActions
    ) async throws -> (any SessionRuntime)? {
        if workspace.kind == .remote {
            return try await actions.makeRemoteProtocolNativeRuntime()
        }

        return try await actions.makeLocalProtocolNativeRuntime()
    }
}
#endif
