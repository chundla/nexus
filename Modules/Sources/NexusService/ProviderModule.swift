#if os(macOS)
import Foundation
import NexusDomain

enum ProviderModuleFreshSessionOpenRequest {
    case launchDefaultSession(workspace: Workspace)
    case createNamedSession(workspace: Workspace)

    var workspace: Workspace {
        switch self {
        case let .launchDefaultSession(workspace),
             let .createNamedSession(workspace):
            workspace
        }
    }
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

    func openFreshSession(
        _ request: ProviderModuleFreshSessionOpenRequest,
        actions: ProviderModuleFreshSessionOpenActions
    ) async throws -> ProviderModuleFreshSessionOpenResult

    func planPersistedSessionRelaunch(
        _ request: ProviderModulePersistedSessionRelaunchRequest
    ) -> ProviderModulePersistedSessionRelaunchPlan

    func shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
        _ error: Error,
        metadata: SessionRecordAdapterMetadata?
    ) throws -> Bool
}

extension ProviderModule {
    func openFreshSession(
        _ request: ProviderModuleFreshSessionOpenRequest,
        actions: ProviderModuleFreshSessionOpenActions
    ) async throws -> ProviderModuleFreshSessionOpenResult {
        try await executeSharedFreshSessionOpen(request, actions: actions)
    }

    func planPersistedSessionRelaunch(
        _ request: ProviderModulePersistedSessionRelaunchRequest
    ) -> ProviderModulePersistedSessionRelaunchPlan {
        .sharedLaunch
    }

    func shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
        _ error: Error,
        metadata: SessionRecordAdapterMetadata?
    ) throws -> Bool {
        false
    }

    func executeSharedFreshSessionOpen(
        _ request: ProviderModuleFreshSessionOpenRequest,
        actions: ProviderModuleFreshSessionOpenActions
    ) async throws -> ProviderModuleFreshSessionOpenResult {
        let workspace = request.workspace
        let isSupported = switch request {
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

func makeProviderCapabilities(
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
