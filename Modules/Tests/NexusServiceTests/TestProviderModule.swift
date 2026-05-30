#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService

struct TestProviderModule: ProviderModule {
    let provider: Provider
    private let defaultSessionLaunchSupportEvaluator: (Workspace) -> Bool
    private let namedSessionSupportEvaluator: (Workspace) -> Bool
    private let healthSummaryEvaluator: (Workspace, RemoteWorkspaceHealthContext?, any ProviderHealthEvaluating) async -> ProviderHealthSummary
    private let primarySurfaceEvaluator: (Workspace) -> SessionSurface
    private let initialTranscriptBuilder: (Workspace, NexusDomain.Host?, RemoteRuntimeLaunchMode) -> String
    private let terminationStatusMessageBuilder: (Int32) -> String
    private let remoteRuntimeRecoveryFailureEvaluator: (RemoteRuntimeRecoveryFailureContext) -> (state: Session.State, message: String)
    private let remoteHealthSnapshotReuseEvaluator: (ProviderHealthSummary, RemoteWorkspaceHealthContext?) -> Bool
    private let sharedRemoteProbeFactsSupportEvaluator: (any ProviderHealthEvaluating) -> Bool
    private let interruptedSessionFailureMessageBuilder: (Session, Workspace?, SessionSurface) -> String
    private let runtimeConstructor: ((Session, Workspace, SessionRuntimeLaunchConfiguration, ProviderModuleRuntimeConstructionActions) async throws -> (any SessionRuntime)?)?

    init(
        providerID: ProviderID,
        supportsDefaultSessionLaunch: Bool = true,
        supportsNamedSessions: Bool = true,
        healthSummaryEvaluator: @escaping (Workspace, RemoteWorkspaceHealthContext?, any ProviderHealthEvaluating) async -> ProviderHealthSummary,
        primarySurfaceEvaluator: @escaping (Workspace) -> SessionSurface = { _ in .terminal },
        initialTranscriptBuilder: ((Workspace, NexusDomain.Host?, RemoteRuntimeLaunchMode) -> String)? = nil,
        terminationStatusMessageBuilder: ((Int32) -> String)? = nil,
        remoteRuntimeRecoveryFailureEvaluator: ((RemoteRuntimeRecoveryFailureContext) -> (state: Session.State, message: String))? = nil,
        remoteHealthSnapshotReuseEvaluator: @escaping (ProviderHealthSummary, RemoteWorkspaceHealthContext?) -> Bool = { _, _ in false },
        sharedRemoteProbeFactsSupportEvaluator: @escaping (any ProviderHealthEvaluating) -> Bool = { _ in false },
        interruptedSessionFailureMessageBuilder: ((Session, Workspace?, SessionSurface) -> String)? = nil,
        runtimeConstructor: ((Session, Workspace, SessionRuntimeLaunchConfiguration, ProviderModuleRuntimeConstructionActions) async throws -> (any SessionRuntime)?)? = nil
    ) {
        let provider = Provider(id: providerID)
        self.provider = provider
        self.defaultSessionLaunchSupportEvaluator = { _ in supportsDefaultSessionLaunch }
        self.namedSessionSupportEvaluator = { _ in supportsNamedSessions }
        self.healthSummaryEvaluator = healthSummaryEvaluator
        self.primarySurfaceEvaluator = primarySurfaceEvaluator
        self.initialTranscriptBuilder = initialTranscriptBuilder ?? { workspace, remoteHost, launchMode in
            providerModuleDefaultInitialTranscript(
                provider: provider,
                workspace: workspace,
                remoteHost: remoteHost,
                launchMode: launchMode
            )
        }
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder ?? { status in
            providerModuleDefaultTerminationStatusMessage(provider: provider, status: status)
        }
        self.remoteRuntimeRecoveryFailureEvaluator = remoteRuntimeRecoveryFailureEvaluator ?? { context in
            providerModuleDefaultRemoteRuntimeRecoveryFailure(for: context)
        }
        self.remoteHealthSnapshotReuseEvaluator = remoteHealthSnapshotReuseEvaluator
        self.sharedRemoteProbeFactsSupportEvaluator = sharedRemoteProbeFactsSupportEvaluator
        self.interruptedSessionFailureMessageBuilder = interruptedSessionFailureMessageBuilder ?? { _, _, _ in
            providerModuleDefaultInterruptedSessionFailureMessage()
        }
        self.runtimeConstructor = runtimeConstructor
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
        primarySurfaceEvaluator(workspace)
    }

    func initialTranscript(
        for workspace: Workspace,
        remoteHost: NexusDomain.Host?,
        launchMode: RemoteRuntimeLaunchMode
    ) -> String {
        initialTranscriptBuilder(workspace, remoteHost, launchMode)
    }

    func terminationStatusMessage(for status: Int32) -> String {
        terminationStatusMessageBuilder(status)
    }

    func remoteRuntimeRecoveryFailure(
        for context: RemoteRuntimeRecoveryFailureContext
    ) -> (state: Session.State, message: String) {
        remoteRuntimeRecoveryFailureEvaluator(context)
    }

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        remoteHealthSnapshotReuseEvaluator(snapshot, remoteContext)
    }

    func supportsSharedRemoteProbeFacts(
        with providerHealthEvaluator: any ProviderHealthEvaluating
    ) -> Bool {
        sharedRemoteProbeFactsSupportEvaluator(providerHealthEvaluator)
    }

    func interruptedSessionFailureMessage(
        for session: Session,
        workspace: Workspace?,
        persistedPrimarySurface: SessionSurface
    ) -> String {
        interruptedSessionFailureMessageBuilder(session, workspace, persistedPrimarySurface)
    }

    func constructRuntime(
        for session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration,
        actions: ProviderModuleRuntimeConstructionActions
    ) async throws -> (any SessionRuntime)? {
        try await runtimeConstructor?(session, workspace, launchConfiguration, actions)
    }
}
#endif
