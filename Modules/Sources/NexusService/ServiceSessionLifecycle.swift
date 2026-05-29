#if os(macOS)
import Foundation
import NexusDomain

enum PersistedSessionLaunchMode {
    case recoverRemoteRuntime
    case launch(forceFreshRemoteRuntime: Bool)
}

struct PersistedSessionLaunchExecution {
    let session: Session
    let workspace: Workspace
    let launchSnapshot: LaunchSnapshot
    let mode: PersistedSessionLaunchMode
    let sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource
}

struct ServiceSessionLifecycleDependencies {
    let workspace: (UUID) throws -> Workspace?
    let sessionRecordStore: any SessionRecordStore
    let providerAdapter: (ProviderID) -> ServiceProviderAdapter
    let providerModule: (ProviderID) -> any ProviderModule
    let remoteWorkspaceHealthContext: (Workspace) throws -> RemoteWorkspaceHealthContext?
    let providerHealthSummary: (ProviderID, Workspace, RemoteWorkspaceHealthContext?) async throws -> ProviderHealthSummary
    let resolveNamedSessionName: (String?, [Session]) -> String
    let reconcileSessionRuntimeState: (Session) throws -> Session
    let sessionMayRemainReadyWithoutRuntime: (Session, Workspace) throws -> Bool
    let hasRuntime: (Session) -> Bool
    let runtimeState: (Session) -> Session.State?
    let executePersistedSessionLaunch: (PersistedSessionLaunchExecution) async throws -> Session
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
        return try await openSession(.launchOrResumePersistedSession(session, workspace: workspace))
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        let workspace = try requiredWorkspace(id: workspaceID)
        return try await openSession(.launchOrResumeDefaultSession(workspace: workspace, providerID: providerID))
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        let workspace = try requiredWorkspace(id: workspaceID)
        return try await openSession(.createNamedSession(workspace: workspace, providerID: providerID, name: name))
    }

    private func openSession(_ request: ProviderModuleOpenSessionRequest) async throws -> Session {
        let fallback = { [self] in
            try await self.openSessionWithoutProviderModule(request)
        }

        if let session = try await dependencies.providerModule(request.providerID).openSession(
            request,
            openFallback: fallback
        ) {
            return session
        }

        return try await fallback()
    }

    private func openSessionWithoutProviderModule(_ request: ProviderModuleOpenSessionRequest) async throws -> Session {
        switch request {
        case let .launchOrResumeDefaultSession(workspace, providerID):
            return try await launchOrResumeDefaultSessionWithoutProviderModule(
                workspaceID: workspace.id,
                providerID: providerID,
                workspace: workspace
            )
        case let .createNamedSession(workspace, providerID, name):
            return try await createNamedSessionWithoutProviderModule(
                workspaceID: workspace.id,
                providerID: providerID,
                name: name,
                workspace: workspace
            )
        case let .launchOrResumePersistedSession(session, workspace):
            return try await launchPersistedSession(session, workspace: workspace)
        }
    }

    private func launchOrResumeDefaultSessionWithoutProviderModule(
        workspaceID: UUID,
        providerID: ProviderID,
        workspace: Workspace
    ) async throws -> Session {
        let adapter = dependencies.providerAdapter(providerID)

        guard adapter.supportsDefaultSessionLaunch(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        if let existingSession = try dependencies.sessionRecordStore.defaultSession(workspaceID: workspaceID, providerID: providerID) {
            return try await launchPersistedSession(existingSession, workspace: workspace)
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

    private func createNamedSessionWithoutProviderModule(
        workspaceID: UUID,
        providerID: ProviderID,
        name: String?,
        workspace: Workspace
    ) async throws -> Session {
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

    private func launchPersistedSession(_ session: Session, workspace: Workspace) async throws -> Session {
        let adapter = dependencies.providerAdapter(session.providerID)
        let isSupported = session.isDefault
            ? adapter.supportsDefaultSessionLaunch(in: workspace)
            : adapter.supportsNamedSessions(in: workspace)
        guard isSupported else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let reconciledSession = try dependencies.reconcileSessionRuntimeState(session)
        let metadataSource = try relaunchSessionRecordAdapterMetadataSource(for: reconciledSession)

        if let launchSnapshot = try dependencies.sessionRecordStore.launchSnapshot(sessionID: reconciledSession.id) {
            let readySession = try readySessionForLaunch(from: reconciledSession)
            let mode: PersistedSessionLaunchMode = if shouldAttemptRemoteRuntimeRecovery(for: reconciledSession, workspace: workspace) {
                .recoverRemoteRuntime
            } else {
                .launch(forceFreshRemoteRuntime: shouldCreateFreshRemoteRuntime(for: reconciledSession, workspace: workspace))
            }

            return try await dependencies.executePersistedSessionLaunch(
                PersistedSessionLaunchExecution(
                    session: readySession,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot,
                    mode: mode,
                    sessionRecordAdapterMetadataSource: metadataSource
                )
            )
        }

        let health = try await providerHealthSummary(for: reconciledSession.providerID, workspace: workspace)
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try dependencies.sessionRecordStore.updateSession(
                id: reconciledSession.id,
                state: .failed,
                failureMessage: failureMessage(from: health)
            )
        }

        let readySession = try readySessionForLaunch(from: reconciledSession)
        let launchSnapshot = try dependencies.sessionRecordStore.ensureLaunchSnapshot(
            sessionID: readySession.id,
            workspaceID: readySession.workspaceID,
            providerID: readySession.providerID,
            primarySurface: adapter.primarySurface(in: workspace),
            resolvedExecutable: executable,
            resolvedWorkingDirectory: workspace.folderPath
        )
        return try await dependencies.executePersistedSessionLaunch(
            PersistedSessionLaunchExecution(
                session: readySession,
                workspace: workspace,
                launchSnapshot: launchSnapshot,
                mode: .launch(forceFreshRemoteRuntime: shouldCreateFreshRemoteRuntime(for: reconciledSession, workspace: workspace)),
                sessionRecordAdapterMetadataSource: metadataSource
            )
        )
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

    private func readySessionForLaunch(from session: Session) throws -> Session {
        if session.state == .ready, session.failureMessage == nil {
            return session
        }

        return try dependencies.sessionRecordStore.updateSession(id: session.id, state: .ready, failureMessage: nil)
    }

    private func relaunchSessionRecordAdapterMetadataSource(for session: Session) throws -> SessionRecordAdapterMetadataLaunchSource {
        guard session.providerID == .ibmBob,
              session.state != .ready else {
            return .stored
        }

        let storedMetadata = try dependencies.sessionRecordStore.sessionRecordAdapterMetadata(sessionID: session.id)
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

        let storedSessionID = storedMetadata?.ibmBobSessionLinkage?.sessionID
        return .explicit(SessionRecordAdapterMetadata.ibmBob(sessionID: storedSessionID))
    }

    private func shouldAttemptRemoteRuntimeRecovery(for session: Session, workspace: Workspace) -> Bool {
        guard workspace.kind == .remote else {
            return false
        }

        if (try? dependencies.sessionMayRemainReadyWithoutRuntime(session, workspace)) == true {
            return false
        }

        let runtimeState = dependencies.runtimeState(session)
        if dependencies.hasRuntime(session), runtimeState != .interrupted {
            return false
        }

        switch session.state {
        case .ready, .interrupted:
            return true
        case .exited, .failed:
            return false
        }
    }

    private func shouldCreateFreshRemoteRuntime(for session: Session, workspace: Workspace) -> Bool {
        guard workspace.kind == .remote else {
            return false
        }

        guard shouldAttemptRemoteRuntimeRecovery(for: session, workspace: workspace) == false else {
            return false
        }

        return dependencies.runtimeState(session) != .ready
    }

    private func failureMessage(from health: ProviderHealthSummary) -> String {
        health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
    }
}
#endif
