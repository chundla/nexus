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
    let recordPerformanceDiagnostic: (PerformanceDiagnosticRecord) throws -> Void
    let currentUptimeNanoseconds: () -> UInt64

    init(
        workspace: @escaping (UUID) throws -> Workspace?,
        sessionRecordStore: any SessionRecordStore,
        providerModule: @escaping (ProviderID) -> any ProviderModule,
        remoteWorkspaceHealthContext: @escaping (Workspace) throws -> RemoteWorkspaceHealthContext?,
        providerHealthSummary: @escaping (ProviderID, Workspace, RemoteWorkspaceHealthContext?) async throws -> ProviderHealthSummary,
        resolveNamedSessionName: @escaping (String?, [Session]) -> String,
        reconcileSessionRuntimeState: @escaping (Session) throws -> Session,
        sessionMayRemainReadyWithoutRuntime: @escaping (Session, Workspace) throws -> Bool,
        hasRuntime: @escaping (Session) -> Bool,
        runtimeState: @escaping (Session) -> Session.State?,
        executePersistedSessionLaunch: @escaping (PersistedSessionLaunchExecution) async throws -> Session,
        launchFreshSession: @escaping (Session, Workspace, LaunchSnapshot) async throws -> Session,
        recordPerformanceDiagnostic: @escaping (PerformanceDiagnosticRecord) throws -> Void = { _ in },
        currentUptimeNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.workspace = workspace
        self.sessionRecordStore = sessionRecordStore
        self.providerModule = providerModule
        self.remoteWorkspaceHealthContext = remoteWorkspaceHealthContext
        self.providerHealthSummary = providerHealthSummary
        self.resolveNamedSessionName = resolveNamedSessionName
        self.reconcileSessionRuntimeState = reconcileSessionRuntimeState
        self.sessionMayRemainReadyWithoutRuntime = sessionMayRemainReadyWithoutRuntime
        self.hasRuntime = hasRuntime
        self.runtimeState = runtimeState
        self.executePersistedSessionLaunch = executePersistedSessionLaunch
        self.launchFreshSession = launchFreshSession
        self.recordPerformanceDiagnostic = recordPerformanceDiagnostic
        self.currentUptimeNanoseconds = currentUptimeNanoseconds
    }
}

final class ServiceSessionLifecycle: SessionLifecycleManaging {
    private let dependencies: ServiceSessionLifecycleDependencies

    init(dependencies: ServiceSessionLifecycleDependencies) {
        self.dependencies = dependencies
    }

    func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        var trace = PerformanceDiagnosticTrace(
            operation: .launchSession,
            sessionID: sessionID,
            currentUptimeNanoseconds: dependencies.currentUptimeNanoseconds
        )

        do {
            guard let session = try trace.measure("loadSession", { try dependencies.sessionRecordStore.session(id: sessionID) }) else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            let workspace = try trace.measure("loadWorkspace") {
                try requiredWorkspace(id: session.workspaceID)
            }
            let launchedSession = try await launchPersistedSession(session, workspace: workspace, trace: &trace)
            try? dependencies.recordPerformanceDiagnostic(trace.finish(outcome: .success))
            return launchedSession
        } catch {
            try? dependencies.recordPerformanceDiagnostic(
                trace.finish(
                    outcome: .failure,
                    failureMessage: String(describing: error)
                )
            )
            throw error
        }
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        var trace = PerformanceDiagnosticTrace(
            operation: .launchDefaultSession,
            workspaceID: workspaceID,
            providerID: providerID,
            currentUptimeNanoseconds: dependencies.currentUptimeNanoseconds
        )

        do {
            let workspace = try trace.measure("loadWorkspace") {
                try requiredWorkspace(id: workspaceID)
            }
            if let existingSession = try trace.measure("loadDefaultSession", {
                try dependencies.sessionRecordStore.defaultSession(workspaceID: workspaceID, providerID: providerID)
            }) {
                let launchedSession = try await launchPersistedSession(existingSession, workspace: workspace, trace: &trace)
                try? dependencies.recordPerformanceDiagnostic(trace.finish(outcome: .success))
                return launchedSession
            }

            let launchedSession = try await openFreshSession(
                providerID: providerID,
                request: .launchDefaultSession(workspace: workspace),
                trace: &trace,
                createSessionStepName: "createDefaultSession",
                createSession: { [sessionRecordStore = dependencies.sessionRecordStore] state, failureMessage in
                    try sessionRecordStore.createDefaultSession(
                        workspaceID: workspaceID,
                        providerID: providerID,
                        state: state,
                        failureMessage: failureMessage
                    )
                }
            )
            try? dependencies.recordPerformanceDiagnostic(trace.finish(outcome: .success))
            return launchedSession
        } catch {
            try? dependencies.recordPerformanceDiagnostic(
                trace.finish(
                    outcome: .failure,
                    failureMessage: String(describing: error)
                )
            )
            throw error
        }
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        var trace = PerformanceDiagnosticTrace(
            operation: .createNamedSession,
            workspaceID: workspaceID,
            providerID: providerID,
            currentUptimeNanoseconds: dependencies.currentUptimeNanoseconds
        )

        do {
            let workspace = try trace.measure("loadWorkspace") {
                try requiredWorkspace(id: workspaceID)
            }
            let existingSessions = try trace.measure("loadSessions") {
                try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
            }
            let resolvedName = trace.measure("resolveNamedSessionName") {
                dependencies.resolveNamedSessionName(name, existingSessions)
            }

            let launchedSession = try await openFreshSession(
                providerID: providerID,
                request: .createNamedSession(workspace: workspace),
                trace: &trace,
                createSessionStepName: "createNamedSession",
                createSession: { [sessionRecordStore = dependencies.sessionRecordStore] state, failureMessage in
                    try sessionRecordStore.createNamedSession(
                        workspaceID: workspaceID,
                        providerID: providerID,
                        name: resolvedName,
                        state: state,
                        failureMessage: failureMessage
                    )
                }
            )
            try? dependencies.recordPerformanceDiagnostic(trace.finish(outcome: .success))
            return launchedSession
        } catch {
            try? dependencies.recordPerformanceDiagnostic(
                trace.finish(
                    outcome: .failure,
                    failureMessage: String(describing: error)
                )
            )
            throw error
        }
    }

    private func openFreshSession(
        providerID: ProviderID,
        request: ProviderModuleFreshSessionOpenRequest,
        trace: inout PerformanceDiagnosticTrace,
        createSessionStepName: String,
        createSession: (Session.State, String?) throws -> Session
    ) async throws -> Session {
        let transitionPlan = try await trace.measure("planFreshSessionOpen") {
            try await dependencies.providerModule(providerID).planSessionTransition(
                .openFresh(
                    request,
                    ProviderModuleFreshSessionOpenActions(
                        providerHealthSummary: { [self] workspace in
                            try await self.providerHealthSummary(for: providerID, workspace: workspace)
                        }
                    )
                )
            )
        }
        guard case let .openFresh(openResult) = transitionPlan else {
            fatalError("Fresh Session open must produce an openFresh transition plan.")
        }

        switch openResult {
        case let .failed(message):
            return try trace.measure(createSessionStepName) {
                try createSession(.failed, message)
            }
        case let .launch(launch):
            let session = try trace.measure(createSessionStepName) {
                try createSession(.ready, nil)
            }
            return try await launchFreshSession(
                session,
                workspace: request.workspace,
                primarySurface: launch.primarySurface,
                executable: launch.executable,
                trace: &trace
            )
        }
    }

    private func launchPersistedSession(
        _ session: Session,
        workspace: Workspace,
        trace: inout PerformanceDiagnosticTrace
    ) async throws -> Session {
        let providerModule = dependencies.providerModule(session.providerID)
        let isSupported = session.isDefault
            ? providerModule.supportsDefaultSessionLaunch(in: workspace)
            : providerModule.supportsNamedSessions(in: workspace)
        guard isSupported else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let reconciledSession = try trace.measure("reconcileSession") {
            try dependencies.reconcileSessionRuntimeState(session)
        }
        let metadataSource = try trace.measure("resolveRelaunchMetadataSource") {
            try relaunchSessionRecordAdapterMetadataSource(for: reconciledSession)
        }

        if let launchSnapshot = try trace.measure("loadLaunchSnapshot", {
            try dependencies.sessionRecordStore.launchSnapshot(sessionID: reconciledSession.id)
        }) {
            let readySession = try trace.measure("prepareReadySession") {
                try readySessionForLaunch(from: reconciledSession)
            }
            let mode: PersistedSessionLaunchMode = if shouldAttemptRemoteRuntimeRecovery(for: reconciledSession, workspace: workspace) {
                .recoverRemoteRuntime
            } else {
                .launch(forceFreshRemoteRuntime: shouldCreateFreshRemoteRuntime(for: reconciledSession, workspace: workspace))
            }

            return try await trace.measure(performanceStepName(for: mode)) {
                try await dependencies.executePersistedSessionLaunch(
                    PersistedSessionLaunchExecution(
                        session: readySession,
                        workspace: workspace,
                        launchSnapshot: launchSnapshot,
                        mode: mode,
                        sessionRecordAdapterMetadataSource: metadataSource
                    )
                )
            }
        }

        let health = try await trace.measure("providerHealthSummary") {
            try await providerHealthSummary(for: reconciledSession.providerID, workspace: workspace)
        }
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            return try trace.measure("markSessionFailed") {
                try dependencies.sessionRecordStore.updateSession(
                    id: reconciledSession.id,
                    state: .failed,
                    failureMessage: failureMessage(from: health)
                )
            }
        }

        let readySession = try trace.measure("prepareReadySession") {
            try readySessionForLaunch(from: reconciledSession)
        }
        let mode: PersistedSessionLaunchMode = .launch(
            forceFreshRemoteRuntime: shouldCreateFreshRemoteRuntime(for: reconciledSession, workspace: workspace)
        )
        let launchSnapshot = try trace.measure("ensureLaunchSnapshot") {
            try dependencies.sessionRecordStore.ensureLaunchSnapshot(
                sessionID: readySession.id,
                workspaceID: readySession.workspaceID,
                providerID: readySession.providerID,
                primarySurface: providerModule.prelaunchPrimarySurface(in: workspace),
                resolvedExecutable: executable,
                resolvedWorkingDirectory: workspace.folderPath
            )
        }
        return try await trace.measure(performanceStepName(for: mode)) {
            try await dependencies.executePersistedSessionLaunch(
                PersistedSessionLaunchExecution(
                    session: readySession,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot,
                    mode: mode,
                    sessionRecordAdapterMetadataSource: metadataSource
                )
            )
        }
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
        primarySurface: SessionSurface,
        executable: String,
        trace: inout PerformanceDiagnosticTrace
    ) async throws -> Session {
        let launchSnapshot = try trace.measure("ensureLaunchSnapshot") {
            try dependencies.sessionRecordStore.ensureLaunchSnapshot(
                sessionID: session.id,
                workspaceID: session.workspaceID,
                providerID: session.providerID,
                primarySurface: primarySurface,
                resolvedExecutable: executable,
                resolvedWorkingDirectory: workspace.folderPath
            )
        }
        return try await trace.measure("launchFreshSession") {
            try await dependencies.launchFreshSession(session, workspace, launchSnapshot)
        }
    }

    private func readySessionForLaunch(from session: Session) throws -> Session {
        if session.state == .ready, session.failureMessage == nil {
            return session
        }

        return try dependencies.sessionRecordStore.updateSession(id: session.id, state: .ready, failureMessage: nil)
    }

    private func relaunchSessionRecordAdapterMetadataSource(for session: Session) throws -> SessionRecordAdapterMetadataLaunchSource {
        dependencies.providerModule(session.providerID).persistedSessionRelaunchMetadataSource(
            for: session,
            storedMetadata: try dependencies.sessionRecordStore.sessionRecordAdapterMetadata(sessionID: session.id)
        )
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

    private func performanceStepName(for mode: PersistedSessionLaunchMode) -> String {
        switch mode {
        case .recoverRemoteRuntime:
            "executePersistedLaunch.recoverRemoteRuntime"
        case let .launch(forceFreshRemoteRuntime):
            forceFreshRemoteRuntime
                ? "executePersistedLaunch.launchFreshRemoteRuntime"
                : "executePersistedLaunch.relaunch"
        }
    }

    private func failureMessage(from health: ProviderHealthSummary) -> String {
        health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
    }
}
#endif
