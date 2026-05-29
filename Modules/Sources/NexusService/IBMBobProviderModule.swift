#if os(macOS)
import Foundation
import NexusDomain

struct IBMBobProviderModule: ProviderModule {
    let provider = Provider(id: .ibmBob)

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
        await providerHealthEvaluator.healthSummary(for: .ibmBob, workspace: workspace, remoteContext: remoteContext)
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
        false
    }

    func persistedSessionRelaunchMetadataSource(
        for session: Session,
        storedMetadata: SessionRecordAdapterMetadata?
    ) -> SessionRecordAdapterMetadataLaunchSource {
        guard session.state != .ready else {
            return .stored
        }

        if session.state == .interrupted,
           let linkage = storedMetadata?.ibmBobSessionLinkage {
            return .explicit(
                SessionRecordAdapterMetadata.ibmBob(
                    sessionID: linkage.sessionID,
                    activityItems: linkage.persistedActivityItems,
                    turnInProgress: false
                )
            )
        }

        return .explicit(SessionRecordAdapterMetadata.ibmBob(sessionID: storedMetadata?.ibmBobSessionLinkage?.sessionID))
    }

    func sessionMayRemainReadyWithoutRuntime(
        _ session: Session,
        workspace: Workspace?,
        persistedPrimarySurface: SessionSurface,
        storedMetadata: SessionRecordAdapterMetadata?
    ) -> Bool {
        guard persistedPrimarySurface == .structuredActivityFeed else {
            return false
        }

        return storedMetadata?.ibmBobTurnInProgress != true
    }
}
#endif
