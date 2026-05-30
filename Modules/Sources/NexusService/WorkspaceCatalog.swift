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
            let sessions = try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
                .map(reconcileSessionRuntimeState)
            let defaultSession = sessions.first(where: \.isDefault)
            let catalogRead = try await providerModule.readCatalog(
                ProviderModuleCatalogReadRequest(
                    workspace: workspace,
                    remoteContext: remoteContext,
                    defaultSession: defaultSession
                ),
                actions: ProviderModuleCatalogReadActions { [self] in
                    try await self.providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
                }
            )
            providerCards.append(
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: catalogRead.health,
                    capabilities: catalogRead.capabilities,
                    prelaunchPrimarySurface: catalogRead.prelaunchPrimarySurface,
                    defaultSession: catalogRead.defaultSession,
                    alternateSessionCount: sessions.filter { $0.isDefault == false }.count
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
        let defaultSession = sessions.first(where: \.isDefault)
        let catalogRead = try await providerModule.readCatalog(
            ProviderModuleCatalogReadRequest(
                workspace: workspace,
                remoteContext: remoteContext,
                defaultSession: defaultSession
            ),
            actions: ProviderModuleCatalogReadActions { [self] in
                try await self.providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
            }
        )

        return ProviderDetail(
            workspace: workspace,
            provider: Provider(id: providerID),
            health: catalogRead.health,
            capabilities: catalogRead.capabilities,
            prelaunchPrimarySurface: catalogRead.prelaunchPrimarySurface,
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
        providerModule(for: session.providerID).sessionMayRemainReadyWithoutRuntime(
            session,
            workspace: workspace,
            persistedPrimarySurface: try persistedPrimarySurface(for: session, workspace: workspace),
            storedMetadata: try dependencies.sessionRecordStore.sessionRecordAdapterMetadata(sessionID: session.id)
        )
    }

    private func providerModule(for providerID: ProviderID) -> any ProviderModule {
        dependencies.providerModuleRegistry.module(for: providerID)
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

        return providerModule(for: session.providerID).prelaunchPrimarySurface(in: resolvedWorkspace)
    }

    private func interruptedSessionFailureMessage(for session: Session, workspace: Workspace?) throws -> String {
        let primarySurface = try persistedPrimarySurface(for: session, workspace: workspace)
        return providerModule(for: session.providerID).interruptedSessionFailureMessage(
            for: session,
            workspace: workspace,
            persistedPrimarySurface: primarySurface
        )
    }
}
#endif
