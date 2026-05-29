#if os(macOS)
import Foundation
import NexusDomain

struct ServiceSessionLifecycleDependencies {
    let workspace: (UUID) throws -> Workspace?
    let sessionRecordStore: any SessionRecordStore
    let providerAdapter: (ProviderID) -> ServiceProviderAdapter
    let remoteWorkspaceHealthContext: (Workspace) throws -> RemoteWorkspaceHealthContext?
    let providerHealthSummary: (ProviderID, Workspace, RemoteWorkspaceHealthContext?) async throws -> ProviderHealthSummary
    let resolveNamedSessionName: (String?, [Session]) -> String
    let launchOrResumePersistedSession: (Session, Workspace) async throws -> Session
    let launchFreshSession: (Session, Workspace, LaunchSnapshot) async throws -> Session
}

final class ServiceSessionLifecycle: SessionLifecycleManaging {
    private let dependencies: ServiceSessionLifecycleDependencies

    init(dependencies: ServiceSessionLifecycleDependencies) {
        self.dependencies = dependencies
    }

    func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        guard let session = try dependencies.sessionRecordStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }
        let workspace = try requiredWorkspace(id: session.workspaceID)
        return try await dependencies.launchOrResumePersistedSession(session, workspace)
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let workspace = try requiredWorkspace(id: workspaceID)
        let adapter = dependencies.providerAdapter(providerID)

        guard adapter.supportsDefaultSessionLaunch(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        if let existingSession = try dependencies.sessionRecordStore.defaultSession(workspaceID: workspaceID, providerID: providerID) {
            return try await dependencies.launchOrResumePersistedSession(existingSession, workspace)
        }

        let health = try await providerHealthSummary(for: providerID, workspace: workspace)
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try dependencies.sessionRecordStore.createDefaultSession(
                workspaceID: workspaceID,
                providerID: providerID,
                state: .failed,
                failureMessage: failureMessage(from: health)
            )
        }

        let session = try dependencies.sessionRecordStore.createDefaultSession(
            workspaceID: workspaceID,
            providerID: providerID,
            state: .ready,
            failureMessage: nil
        )
        return try await launchFreshSession(session, workspace: workspace, adapter: adapter, executable: executable)
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        let workspace = try requiredWorkspace(id: workspaceID)
        let adapter = dependencies.providerAdapter(providerID)

        guard adapter.supportsNamedSessions(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let existingSessions = try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
        let resolvedName = dependencies.resolveNamedSessionName(name, existingSessions)
        let health = try await providerHealthSummary(for: providerID, workspace: workspace)

        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try dependencies.sessionRecordStore.createNamedSession(
                workspaceID: workspaceID,
                providerID: providerID,
                name: resolvedName,
                state: .failed,
                failureMessage: failureMessage(from: health)
            )
        }

        let session = try dependencies.sessionRecordStore.createNamedSession(
            workspaceID: workspaceID,
            providerID: providerID,
            name: resolvedName,
            state: .ready,
            failureMessage: nil
        )
        return try await launchFreshSession(session, workspace: workspace, adapter: adapter, executable: executable)
    }

    private func requiredWorkspace(id workspaceID: UUID) throws -> Workspace {
        guard let workspace = try dependencies.workspace(workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }
        return workspace
    }

    private func providerHealthSummary(for providerID: ProviderID, workspace: Workspace) async throws -> ProviderHealthSummary {
        let remoteContext = try dependencies.remoteWorkspaceHealthContext(workspace)
        return try await dependencies.providerHealthSummary(providerID, workspace, remoteContext)
    }

    private func launchFreshSession(
        _ session: Session,
        workspace: Workspace,
        adapter: ServiceProviderAdapter,
        executable: String
    ) async throws -> Session {
        let launchSnapshot = try dependencies.sessionRecordStore.ensureLaunchSnapshot(
            sessionID: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            primarySurface: adapter.primarySurface(in: workspace),
            resolvedExecutable: executable,
            resolvedWorkingDirectory: workspace.folderPath
        )
        return try await dependencies.launchFreshSession(session, workspace, launchSnapshot)
    }

    private func failureMessage(from health: ProviderHealthSummary) -> String {
        health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
    }
}
#endif
