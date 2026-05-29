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
}
#endif
