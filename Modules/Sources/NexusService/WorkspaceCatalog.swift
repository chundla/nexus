#if os(macOS)
import Foundation
import NexusDomain

protocol WorkspaceCatalogReading: Sendable {
    func workspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview
    func providerDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail
    func workspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview]
}

struct WorkspaceCatalogDependencies {
    let metadataStore: NexusMetadataStore
    let sessionRecordStore: any SessionRecordStore
    let providerHealthEvaluator: any ProviderHealthEvaluating
    let hostValidationEvaluator: any HostValidationEvaluating
    let workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating
    let sessionRuntimeManager: any SessionRuntimeManaging
    let providerAdapters: [ProviderID: ServiceProviderAdapter]
    let providerModuleRegistry: ProviderModuleRegistry
}

final class WorkspaceCatalog: WorkspaceCatalogReading, @unchecked Sendable {
    private let dependencies: WorkspaceCatalogDependencies

    init(dependencies: WorkspaceCatalogDependencies) {
        self.dependencies = dependencies
    }

    func workspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        guard let workspace = try dependencies.metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        let remoteTarget = try remoteWorkspaceTargetOverview(for: workspace)
        let remoteContext = remoteTarget.map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }

        var providerCards: [WorkspaceProviderCard] = []
        for providerID in ProviderID.allCases {
            let providerModule = providerModule(for: providerID)
            let health = try await providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
            let defaultSession = try dependencies.sessionRecordStore.defaultSession(workspaceID: workspaceID, providerID: providerID)
            providerCards.append(
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: health,
                    capabilities: providerModule.providerCapabilities(in: workspace, health: health, defaultSession: defaultSession),
                    prelaunchPrimarySurface: providerModule.prelaunchPrimarySurface(in: workspace),
                    defaultSession: try defaultSessionSummary(for: workspace, providerID: providerID),
                    alternateSessionCount: try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
                        .filter { $0.isDefault == false }
                        .count
                )
            )
        }

        return WorkspaceOverview(workspace: workspace, providerCards: providerCards, remoteTarget: remoteTarget)
    }

    func providerDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        guard let workspace = try dependencies.metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        let remoteTarget = try remoteWorkspaceTargetOverview(for: workspace)
        let remoteContext = remoteTarget.map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }
        let providerModule = providerModule(for: providerID)
        let sessions = try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
            .map(reconcileSessionRuntimeState)
        let health = try await providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
        let defaultSession = sessions.first(where: \.isDefault)

        return ProviderDetail(
            workspace: workspace,
            provider: Provider(id: providerID),
            health: health,
            capabilities: providerModule.providerCapabilities(in: workspace, health: health, defaultSession: defaultSession),
            prelaunchPrimarySurface: providerModule.prelaunchPrimarySurface(in: workspace),
            defaultSession: defaultSession,
            alternateSessions: sessions.filter { $0.isDefault == false && $0.state != .failed },
            failedSessions: sessions.filter { $0.isDefault == false && $0.state == .failed }
        )
    }

    func workspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview] {
        var overviews: [WorkspaceOverview] = []
        overviews.reserveCapacity(workspaceIDs.count)
        for workspaceID in workspaceIDs {
            overviews.append(try await workspaceOverview(workspaceID: workspaceID))
        }
        return overviews
    }

    func remoteWorkspaceHealthContext(
        for workspace: Workspace,
        refreshHostValidation: Bool = false
    ) throws -> RemoteWorkspaceHealthContext? {
        try remoteWorkspaceTargetOverview(for: workspace, refreshHostValidation: refreshHostValidation).map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }
    }

    func remoteWorkspaceTargetOverview(
        for workspace: Workspace,
        refreshHostValidation: Bool = false
    ) throws -> RemoteWorkspaceTargetOverview? {
        guard workspace.kind == .remote,
              let hostID = workspace.remoteHostID,
              let host = try dependencies.metadataStore.host(id: hostID) else {
            return nil
        }

        let existingHostValidation = try dependencies.metadataStore.hostValidation(hostID: hostID)
        let hostValidation: HostValidationSnapshot?
        if refreshHostValidation {
            hostValidation = try dependencies.metadataStore.saveHostValidation(
                hostID: hostID,
                result: dependencies.hostValidationEvaluator.validate(host: host),
                checkedAt: Date()
            )
        } else {
            hostValidation = existingHostValidation
        }

        let availabilityResult = dependencies.workspaceAvailabilityEvaluator.evaluate(
            workspace: workspace,
            host: host,
            hostValidation: hostValidation
        )
        let availability = try dependencies.metadataStore.saveWorkspaceAvailability(
            workspaceID: workspace.id,
            result: availabilityResult,
            checkedAt: Date()
        )
        return RemoteWorkspaceTargetOverview(
            host: host,
            hostValidation: hostValidation,
            workspaceAvailability: availability
        )
    }

    func providerHealthSummary(
        for providerID: ProviderID,
        workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        preferFreshRemoteCheck: Bool = false
    ) async throws -> ProviderHealthSummary {
        let providerModule = providerModule(for: providerID)

        guard workspace.kind == .remote else {
            return await providerModule.providerHealthSummary(
                for: workspace,
                remoteContext: remoteContext,
                providerHealthEvaluator: dependencies.providerHealthEvaluator
            )
        }

        if preferFreshRemoteCheck == false,
           let snapshot = try dependencies.metadataStore.providerHealth(workspaceID: workspace.id, providerID: providerID),
           providerModule.reusesRemoteHealthSnapshot(snapshot, remoteContext: remoteContext) {
            return snapshot
        }

        let evaluated = await providerModule.providerHealthSummary(
            for: workspace,
            remoteContext: remoteContext,
            providerHealthEvaluator: dependencies.providerHealthEvaluator
        )
        return try dependencies.metadataStore.saveProviderHealth(
            workspaceID: workspace.id,
            providerID: providerID,
            summary: evaluated,
            checkedAt: Date()
        )
    }

    func reconcileSessionRuntimeState(_ session: Session) throws -> Session {
        guard session.state == .ready else {
            return session
        }

        if let runtimeState = dependencies.sessionRuntimeManager.runtimeState(for: session) {
            guard runtimeState != .ready else {
                return session
            }

            return try updatedSessionForRuntimeState(session, runtimeState: runtimeState)
        }

        guard dependencies.sessionRuntimeManager.hasRuntime(for: session) == false else {
            return session
        }

        let workspace = try dependencies.metadataStore.workspace(id: session.workspaceID)
        if try sessionMayRemainReadyWithoutRuntime(session, workspace: workspace) {
            return session
        }

        return try dependencies.sessionRecordStore.updateSession(
            id: session.id,
            state: .interrupted,
            failureMessage: try interruptedSessionFailureMessage(for: session, workspace: workspace)
        )
    }

    func sessionMayRemainReadyWithoutRuntime(_ session: Session, workspace: Workspace?) throws -> Bool {
        guard try stopRequiresActiveIBMBobTurn(session, workspace: workspace) else {
            return false
        }

        return try dependencies.sessionRecordStore.sessionRecordAdapterMetadata(sessionID: session.id)?.ibmBobTurnInProgress != true
    }

    private func providerAdapter(for providerID: ProviderID) -> ServiceProviderAdapter {
        dependencies.providerAdapters[providerID] ?? ServiceProviderAdapter(
            providerID: providerID,
            supportsDefaultSessionLaunch: false,
            supportsNamedSessions: false,
            healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                await providerHealthEvaluator.healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
            }
        )
    }

    private func providerModule(for providerID: ProviderID) -> any ProviderModule {
        dependencies.providerModuleRegistry.module(for: providerID)
    }

    private func defaultSessionSummary(for workspace: Workspace, providerID: ProviderID) throws -> ProviderDefaultSessionSummary {
        guard let session = try dependencies.sessionRecordStore.defaultSession(workspaceID: workspace.id, providerID: providerID) else {
            return ProviderDefaultSessionSummary(
                state: .notCreated,
                summary: "No default session yet",
                actionTitle: "Launch"
            )
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)

        switch resolvedSession.state {
        case .ready:
            return ProviderDefaultSessionSummary(
                state: .ready,
                summary: "Default session ready",
                actionTitle: "Resume",
                sessionID: resolvedSession.id
            )
        case .interrupted:
            return ProviderDefaultSessionSummary(
                state: .interrupted,
                summary: resolvedSession.failureMessage ?? "Session interrupted after the service restarted",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        case .exited:
            return ProviderDefaultSessionSummary(
                state: .exited,
                summary: resolvedSession.failureMessage ?? "Session exited",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        case .failed:
            return ProviderDefaultSessionSummary(
                state: .failed,
                summary: resolvedSession.failureMessage ?? "Last launch failed",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        }
    }

    private func updatedSessionForRuntimeState(_ session: Session, runtimeState: Session.State) throws -> Session {
        switch runtimeState {
        case .ready:
            return session
        case .failed:
            return try dependencies.sessionRecordStore.updateSession(
                id: session.id,
                state: .failed,
                failureMessage: runtimeFailureMessage(for: session) ?? "Session failed"
            )
        case .interrupted:
            let runtimeTranscript = try? dependencies.sessionRuntimeManager.sessionScreen(for: session).transcript
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackFailureMessage = try interruptedSessionFailureMessage(
                for: session,
                workspace: dependencies.metadataStore.workspace(id: session.workspaceID)
            )
            let failureMessage = runtimeTranscript.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackFailureMessage
            return try dependencies.sessionRecordStore.updateSession(
                id: session.id,
                state: .interrupted,
                failureMessage: failureMessage
            )
        case .exited:
            return try dependencies.sessionRecordStore.updateSession(
                id: session.id,
                state: .exited,
                failureMessage: "Session exited. Relaunch to start a new live runtime."
            )
        }
    }

    private func runtimeFailureMessage(for session: Session) -> String? {
        guard let screen = try? dependencies.sessionRuntimeManager.sessionScreen(for: session) else {
            return nil
        }

        if let errorText = screen.activityItems.last(where: { $0.kind == .error })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
           errorText.isEmpty == false {
            return errorText
        }

        let transcript = screen.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private func persistedPrimarySurface(for session: Session, workspace: Workspace? = nil) throws -> SessionSurface {
        if let launchSnapshot = try dependencies.sessionRecordStore.launchSnapshot(sessionID: session.id) {
            return launchSnapshot.primarySurface
        }

        let resolvedWorkspace = if let workspace {
            workspace
        } else {
            try dependencies.metadataStore.workspace(id: session.workspaceID)
        }
        guard let resolvedWorkspace else {
            return .terminal
        }

        return providerAdapter(for: session.providerID).primarySurface(in: resolvedWorkspace)
    }

    private func stopRequiresActiveIBMBobTurn(_ session: Session, workspace: Workspace? = nil) throws -> Bool {
        let resolvedWorkspace = if let workspace {
            workspace
        } else {
            try dependencies.metadataStore.workspace(id: session.workspaceID)
        }

        guard session.providerID == .ibmBob else {
            return false
        }

        return try persistedPrimarySurface(for: session, workspace: resolvedWorkspace) == .structuredActivityFeed
    }

    private func interruptedSessionFailureMessage(for session: Session, workspace: Workspace?) throws -> String {
        if try persistedPrimarySurface(for: session, workspace: workspace) == .structuredActivityFeed,
           session.providerID == .ibmBob || workspace?.kind == .local {
            return structuredInterruptedSessionFailureMessage(for: session.providerID)
        }

        return "Session interrupted because the background service restarted. Relaunch to create a new live runtime."
    }
}
#endif
