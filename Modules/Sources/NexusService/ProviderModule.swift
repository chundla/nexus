#if os(macOS)
    import Foundation
    import NexusDomain

    enum ProviderModuleFreshSessionOpenRequest {
        case launchDefaultSession(workspace: Workspace)
        case createNamedSession(workspace: Workspace)

        var workspace: Workspace {
            switch self {
            case .launchDefaultSession(let workspace),
                .createNamedSession(let workspace):
                workspace
            }
        }
    }

    struct ProviderModuleCatalogReadRequest {
        let workspace: Workspace
        let remoteContext: RemoteWorkspaceHealthContext?
        let defaultSession: Session?
    }

    struct ProviderModuleCatalogReadActions {
        let providerHealthSummary: () async throws -> ProviderHealthSummary
    }

    struct ProviderModuleCatalogReadResult: Equatable {
        let health: ProviderHealthSummary
        let capabilities: ProviderCapabilities
        let prelaunchPrimarySurface: SessionSurface
        let defaultSession: ProviderDefaultSessionSummary
    }

    struct ProviderModuleFreshSessionOpenActions {
        let providerHealthSummary: (_ workspace: Workspace) async throws -> ProviderHealthSummary
    }

    struct ProviderModuleFreshSessionLaunch: Equatable {
        let primarySurface: SessionSurface
        let executable: String
    }

    enum ProviderModuleFreshSessionOpenResult: Equatable {
        case launch(ProviderModuleFreshSessionLaunch)
        case failed(String)
    }

    struct ProviderModuleFreshRemotePersistedSessionRelaunch: Equatable {
        let sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource
        let retriesWithoutContinuity: Bool
    }

    enum ProviderModulePersistedSessionRelaunchPlan: Equatable {
        case sharedLaunch
        case recoverRemoteRuntime(ProviderModuleFreshRemotePersistedSessionRelaunch)
        case launchFreshRemoteRuntime(ProviderModuleFreshRemotePersistedSessionRelaunch)
    }

    struct ProviderModulePersistedSessionRelaunchRequest {
        let execution: PersistedSessionLaunchExecution
    }

    struct ProviderModuleReadyWithoutRuntimeBootstrapRequest {
        let session: Session
        let workspace: Workspace
        let persistedPrimarySurface: SessionSurface
        let storedMetadata: SessionRecordAdapterMetadata?
    }

    enum ProviderModuleReadyWithoutRuntimeBootstrapPlan: Equatable {
        case noBootstrap
        case relaunchPersistedSession
    }

    enum ProviderModuleSessionTransitionRequest {
        case openFresh(ProviderModuleFreshSessionOpenRequest, ProviderModuleFreshSessionOpenActions)
        case relaunchPersisted(ProviderModulePersistedSessionRelaunchRequest)
        case bootstrapReadyWithoutRuntime(ProviderModuleReadyWithoutRuntimeBootstrapRequest)
    }

    enum ProviderModuleSessionTransitionPlan: Equatable {
        case openFresh(ProviderModuleFreshSessionOpenResult)
        case relaunchPersisted(ProviderModulePersistedSessionRelaunchPlan)
        case bootstrapReadyWithoutRuntime(ProviderModuleReadyWithoutRuntimeBootstrapPlan)
    }

    struct ProviderModuleRuntimeConstructionActions {
        let makeLocalTerminalRuntime: () throws -> any SessionRuntime
        let makeRemoteTerminalRuntime: () throws -> any SessionRuntime
        let makeLocalPiRuntime: () async throws -> any SessionRuntime
        let makeRemotePiRuntime: () async throws -> any SessionRuntime
        let makeLocalCodexRuntime: () async throws -> any SessionRuntime
        let makeRemoteCodexRuntime: () async throws -> any SessionRuntime
        let makeLocalIBMBobRuntime: () async throws -> any SessionRuntime
        let makeRemoteIBMBobRuntime: () async throws -> any SessionRuntime
    }

    struct ProviderModuleDeleteSessionRecordRequest {
        let session: Session
        let workspace: Workspace
        let host: NexusDomain.Host?
        let sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
    }

    struct ProviderModuleDeleteSessionRecordActions {
        let deleteStoredContinuity: () -> Void
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

        func readCatalog(
            _ request: ProviderModuleCatalogReadRequest,
            actions: ProviderModuleCatalogReadActions
        ) async throws -> ProviderModuleCatalogReadResult

        func defaultSessionSummary(for session: Session?) -> ProviderDefaultSessionSummary

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface

        func initialTranscript(
            for workspace: Workspace,
            remoteHost: NexusDomain.Host?,
            launchMode: RemoteRuntimeLaunchMode
        ) -> String

        func terminationStatusMessage(for status: Int32) -> String

        func remoteRuntimeRecoveryFailure(
            for context: RemoteRuntimeRecoveryFailureContext
        ) -> (state: Session.State, message: String)

        func supportsSharedRemoteProbeFacts(
            with providerHealthEvaluator: any ProviderHealthEvaluating
        ) -> Bool

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool

        func planSessionTransition(
            _ request: ProviderModuleSessionTransitionRequest
        ) async throws -> ProviderModuleSessionTransitionPlan

        func openFreshSession(
            _ request: ProviderModuleFreshSessionOpenRequest,
            actions: ProviderModuleFreshSessionOpenActions
        ) async throws -> ProviderModuleFreshSessionOpenResult

        func planPersistedSessionRelaunch(
            _ request: ProviderModulePersistedSessionRelaunchRequest
        ) -> ProviderModulePersistedSessionRelaunchPlan

        func planReadyWithoutRuntimeBootstrap(
            _ request: ProviderModuleReadyWithoutRuntimeBootstrapRequest
        ) -> ProviderModuleReadyWithoutRuntimeBootstrapPlan

        func persistedSessionRelaunchMetadataSource(
            for session: Session,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> SessionRecordAdapterMetadataLaunchSource

        func sessionMayRemainReadyWithoutRuntime(
            _ session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> Bool

        func interruptedSessionFailureMessage(
            for session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface
        ) -> String

        func shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            _ error: Error,
            metadata: SessionRecordAdapterMetadata?
        ) throws -> Bool

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)?

        func prepareDeleteSessionRecord(
            _ request: ProviderModuleDeleteSessionRecordRequest,
            actions: ProviderModuleDeleteSessionRecordActions
        )
    }

    extension ProviderModule {
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
                prelaunchPrimarySurface: prelaunchPrimarySurface(in: request.workspace),
                defaultSession: defaultSessionSummary(for: request.defaultSession)
            )
        }

        func planSessionTransition(
            _ request: ProviderModuleSessionTransitionRequest
        ) async throws -> ProviderModuleSessionTransitionPlan {
            switch request {
            case .openFresh(let freshRequest, let actions):
                return .openFresh(try await openFreshSession(freshRequest, actions: actions))
            case .relaunchPersisted(let relaunchRequest):
                return .relaunchPersisted(planPersistedSessionRelaunch(relaunchRequest))
            case .bootstrapReadyWithoutRuntime(let bootstrapRequest):
                return .bootstrapReadyWithoutRuntime(planReadyWithoutRuntimeBootstrap(bootstrapRequest))
            }
        }

        func openFreshSession(
            _ request: ProviderModuleFreshSessionOpenRequest,
            actions: ProviderModuleFreshSessionOpenActions
        ) async throws -> ProviderModuleFreshSessionOpenResult {
            try await executeSharedFreshSessionOpen(request, actions: actions)
        }

        func initialTranscript(
            for workspace: Workspace,
            remoteHost: NexusDomain.Host?,
            launchMode: RemoteRuntimeLaunchMode
        ) -> String {
            providerModuleDefaultInitialTranscript(
                provider: provider,
                workspace: workspace,
                remoteHost: remoteHost,
                launchMode: launchMode
            )
        }

        func terminationStatusMessage(for status: Int32) -> String {
            providerModuleDefaultTerminationStatusMessage(provider: provider, status: status)
        }

        func remoteRuntimeRecoveryFailure(
            for context: RemoteRuntimeRecoveryFailureContext
        ) -> (state: Session.State, message: String) {
            providerModuleDefaultRemoteRuntimeRecoveryFailure(for: context)
        }

        func planPersistedSessionRelaunch(
            _ request: ProviderModulePersistedSessionRelaunchRequest
        ) -> ProviderModulePersistedSessionRelaunchPlan {
            .sharedLaunch
        }

        func planReadyWithoutRuntimeBootstrap(
            _ request: ProviderModuleReadyWithoutRuntimeBootstrapRequest
        ) -> ProviderModuleReadyWithoutRuntimeBootstrapPlan {
            sessionMayRemainReadyWithoutRuntime(
                request.session,
                workspace: request.workspace,
                persistedPrimarySurface: request.persistedPrimarySurface,
                storedMetadata: request.storedMetadata
            ) ? .relaunchPersistedSession : .noBootstrap
        }

        func persistedSessionRelaunchMetadataSource(
            for session: Session,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> SessionRecordAdapterMetadataLaunchSource {
            .stored
        }

        func supportsSharedRemoteProbeFacts(
            with providerHealthEvaluator: any ProviderHealthEvaluating
        ) -> Bool {
            false
        }

        func sessionMayRemainReadyWithoutRuntime(
            _ session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> Bool {
            false
        }

        func interruptedSessionFailureMessage(
            for session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface
        ) -> String {
            providerModuleDefaultInterruptedSessionFailureMessage()
        }

        func shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
            _ error: Error,
            metadata: SessionRecordAdapterMetadata?
        ) throws -> Bool {
            false
        }

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)? {
            nil
        }

        func prepareDeleteSessionRecord(
            _ request: ProviderModuleDeleteSessionRecordRequest,
            actions: ProviderModuleDeleteSessionRecordActions
        ) {}

        func executeSharedFreshSessionOpen(
            _ request: ProviderModuleFreshSessionOpenRequest,
            actions: ProviderModuleFreshSessionOpenActions
        ) async throws -> ProviderModuleFreshSessionOpenResult {
            let workspace = request.workspace
            let isSupported =
                switch request {
                case .launchDefaultSession:
                    supportsDefaultSessionLaunch(in: workspace)
                case .createNamedSession:
                    supportsNamedSessions(in: workspace)
                }

            guard isSupported else {
                throw NexusMetadataStoreError.providerNotSupported
            }

            let health = try await actions.providerHealthSummary(workspace)
            guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
                return .failed(providerHealthFailureMessage(from: health))
            }

            return .launch(
                ProviderModuleFreshSessionLaunch(
                    primarySurface: prelaunchPrimarySurface(in: workspace),
                    executable: executable
                )
            )
        }

        func defaultSessionSummary(for session: Session?) -> ProviderDefaultSessionSummary {
            guard let session else {
                return ProviderDefaultSessionSummary(
                    state: .notCreated,
                    summary: "No default session yet",
                    actionTitle: "Launch"
                )
            }

            switch session.state {
            case .ready:
                return ProviderDefaultSessionSummary(
                    state: .ready,
                    summary: "Default session ready",
                    actionTitle: "Resume",
                    sessionID: session.id
                )
            case .interrupted:
                return ProviderDefaultSessionSummary(
                    state: .interrupted,
                    summary: session.failureMessage ?? "Session interrupted after the service restarted",
                    actionTitle: "Relaunch",
                    sessionID: session.id
                )
            case .exited:
                return ProviderDefaultSessionSummary(
                    state: .exited,
                    summary: session.failureMessage ?? "Session exited",
                    actionTitle: "Relaunch",
                    sessionID: session.id
                )
            case .failed:
                return ProviderDefaultSessionSummary(
                    state: .failed,
                    summary: session.failureMessage ?? "Last launch failed",
                    actionTitle: "Relaunch",
                    sessionID: session.id
                )
            }
        }
    }

    struct ProviderModuleRegistry {
        private let modules: [ProviderID: any ProviderModule]
        private let fallbackModuleFactory: (ProviderID) -> any ProviderModule

        init(
            modules: [ProviderID: any ProviderModule] = [:],
            fallbackModuleFactory: @escaping (ProviderID) -> any ProviderModule = {
                UnsupportedProviderModule(providerID: $0)
            }
        ) {
            self.modules = modules
            self.fallbackModuleFactory = fallbackModuleFactory
        }

        func module(for providerID: ProviderID) -> any ProviderModule {
            modules[providerID] ?? fallbackModuleFactory(providerID)
        }
    }

    func makeProviderCapabilities(
        provider: Provider,
        supportsDefaultSessionLaunch: Bool,
        supportsNamedSessions: Bool,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        let canLaunchDefaultSession =
            supportsDefaultSessionLaunch && (defaultSession != nil || health.launchability == .launchable)
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

    func providerCapabilityDisabledReason(
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

    func providerHealthFailureMessage(from health: ProviderHealthSummary) -> String {
        health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
    }

    func providerModuleDefaultInterruptedSessionFailureMessage() -> String {
        "Session interrupted because the background service restarted. Relaunch to create a new live runtime."
    }

    func providerModuleDefaultInitialTranscript(
        provider: Provider,
        workspace: Workspace,
        remoteHost: NexusDomain.Host?,
        launchMode: RemoteRuntimeLaunchMode
    ) -> String {
        if let remoteHost {
            switch launchMode {
            case .launchNew:
                return "Connecting to \(workspace.name) on \(remoteHost.name) with \(provider.displayName)…\n"
            case .attachExisting:
                return "Reconnecting to \(workspace.name) on \(remoteHost.name) with \(provider.displayName)…\n"
            }
        }

        return "Launching \(workspace.name) with \(provider.displayName)…\n"
    }

    func providerModuleDefaultTerminationStatusMessage(provider: Provider, status: Int32) -> String {
        "\n[\(provider.displayName) exited with status \(status)]\n"
    }

    func providerModuleDefaultRemoteRuntimeRecoveryFailure(
        for context: RemoteRuntimeRecoveryFailureContext
    ) -> (state: Session.State, message: String) {
        if context.isMissingRemoteRuntime {
            return (
                state: .failed,
                message:
                    "Known remote runtime '\(context.runtimeIdentifier)' is no longer available on \(context.hostName). Relaunch to create a new remote runtime."
            )
        }

        if context.normalizedDetail.contains("could not resolve hostname")
            || context.normalizedDetail.contains("operation timed out")
            || context.normalizedDetail.contains("connection refused")
            || context.normalizedDetail.contains("no route to host")
            || context.normalizedDetail.contains("connection closed by remote host")
            || context.normalizedDetail.contains("permission denied")
        {
            let suffix = context.detail.isEmpty ? "" : " \(context.detail)"
            return (
                state: .interrupted,
                message:
                    "Could not reach \(context.hostName) to recover remote runtime '\(context.runtimeIdentifier)'.\(suffix)"
            )
        }

        let suffix = context.detail.isEmpty ? "" : " \(context.detail)"
        return (
            state: .interrupted,
            message: "Could not recover remote runtime '\(context.runtimeIdentifier)' on \(context.hostName).\(suffix)"
        )
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
            await providerHealthEvaluator.healthSummary(
                for: provider.id, workspace: workspace, remoteContext: remoteContext)
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

#endif
