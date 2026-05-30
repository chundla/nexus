#if os(macOS)
import Foundation
import NexusDomain

protocol WorkspaceCatalogReading: Sendable {
    func workspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview
    func providerDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail
    func workspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview]
}

private struct LoadedWorkspaceProviderCard {
    let index: Int
    let card: WorkspaceProviderCard
    let performanceSteps: [PerformanceDiagnosticStep]
    let usesStaleBrowseFacts: Bool
}

private enum WorkspaceOverviewLoadMode {
    case browse
    case forceFresh
}

struct WorkspaceCatalogDependencies {
    let metadataStore: NexusMetadataStore
    let sessionRecordStore: any SessionRecordStore
    let providerHealthEvaluator: any ProviderHealthEvaluating
    let hostValidationEvaluator: any HostValidationEvaluating
    let workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating
    let sessionRuntimeManager: any SessionRuntimeManaging
    let providerModuleRegistry: ProviderModuleRegistry
    let recordPerformanceDiagnostic: (PerformanceDiagnosticRecord) throws -> Void
    let currentUptimeNanoseconds: () -> UInt64
    let currentDate: () -> Date

    init(
        metadataStore: NexusMetadataStore,
        sessionRecordStore: any SessionRecordStore,
        providerHealthEvaluator: any ProviderHealthEvaluating,
        hostValidationEvaluator: any HostValidationEvaluating,
        workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating,
        sessionRuntimeManager: any SessionRuntimeManaging,
        providerModuleRegistry: ProviderModuleRegistry,
        recordPerformanceDiagnostic: @escaping (PerformanceDiagnosticRecord) throws -> Void = { _ in },
        currentUptimeNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.metadataStore = metadataStore
        self.sessionRecordStore = sessionRecordStore
        self.providerHealthEvaluator = providerHealthEvaluator
        self.hostValidationEvaluator = hostValidationEvaluator
        self.workspaceAvailabilityEvaluator = workspaceAvailabilityEvaluator
        self.sessionRuntimeManager = sessionRuntimeManager
        self.providerModuleRegistry = providerModuleRegistry
        self.recordPerformanceDiagnostic = recordPerformanceDiagnostic
        self.currentUptimeNanoseconds = currentUptimeNanoseconds
        self.currentDate = currentDate
    }
}

final class WorkspaceCatalog: WorkspaceCatalogReading, @unchecked Sendable {
    private let dependencies: WorkspaceCatalogDependencies

    init(dependencies: WorkspaceCatalogDependencies) {
        self.dependencies = dependencies
    }

    func workspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        try await loadWorkspaceOverview(workspaceID: workspaceID, mode: .browse)
    }

    func refreshWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        try await loadWorkspaceOverview(workspaceID: workspaceID, mode: .forceFresh)
    }

    func providerDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        var trace = PerformanceDiagnosticTrace(
            operation: .providerDetail,
            workspaceID: workspaceID,
            providerID: providerID,
            currentUptimeNanoseconds: dependencies.currentUptimeNanoseconds
        )

        do {
            guard let workspace = try trace.measure("loadWorkspace", { try dependencies.metadataStore.workspace(id: workspaceID) }) else {
                throw NexusMetadataStoreError.workspaceNotFound
            }

            let remoteTarget = try trace.measure("loadRemoteTarget", { try remoteWorkspaceTargetOverview(for: workspace) })
            let remoteContext = remoteTarget.map {
                RemoteWorkspaceHealthContext(
                    host: $0.host,
                    hostValidation: $0.hostValidation,
                    workspaceAvailability: $0.workspaceAvailability
                )
            }
            let providerModule = providerModule(for: providerID)
            let sessions = try trace.measure("loadSessions") {
                try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
                    .map(reconcileSessionRuntimeState)
            }
            let defaultSession = sessions.first(where: \.isDefault)
            let catalogRead = try await trace.measure("readProviderCatalog") {
                try await providerModule.readCatalog(
                    ProviderModuleCatalogReadRequest(
                        workspace: workspace,
                        remoteContext: remoteContext,
                        defaultSession: defaultSession
                    ),
                    actions: ProviderModuleCatalogReadActions { [self] in
                        try await self.providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
                    }
                )
            }

            let detail = ProviderDetail(
                workspace: workspace,
                provider: Provider(id: providerID),
                health: catalogRead.health,
                capabilities: catalogRead.capabilities,
                prelaunchPrimarySurface: catalogRead.prelaunchPrimarySurface,
                defaultSession: defaultSession,
                alternateSessions: sessions.filter { $0.isDefault == false && $0.state != .failed },
                failedSessions: sessions.filter { $0.isDefault == false && $0.state == .failed }
            )
            try? dependencies.recordPerformanceDiagnostic(trace.finish(outcome: .success))
            return detail
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

    func workspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview] {
        try await withThrowingTaskGroup(of: (Int, WorkspaceOverview).self, returning: [WorkspaceOverview].self) { group in
            for (index, workspaceID) in workspaceIDs.enumerated() {
                group.addTask { [self] in
                    (index, try await workspaceOverview(workspaceID: workspaceID))
                }
            }

            var orderedOverviews = Array<WorkspaceOverview?>(repeating: nil, count: workspaceIDs.count)
            for try await (index, overview) in group {
                orderedOverviews[index] = overview
            }
            return orderedOverviews.compactMap { $0 }
        }
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

        let availability: WorkspaceAvailabilitySnapshot
        if refreshHostValidation == false,
           let existingAvailability = try dependencies.metadataStore.workspaceAvailability(workspaceID: workspace.id),
           isRecent(existingAvailability.checkedAt) {
            availability = existingAvailability
        } else {
            let availabilityResult = dependencies.workspaceAvailabilityEvaluator.evaluate(
                workspace: workspace,
                host: host,
                hostValidation: hostValidation
            )
            availability = try dependencies.metadataStore.saveWorkspaceAvailability(
                workspaceID: workspace.id,
                result: availabilityResult,
                checkedAt: dependencies.currentDate()
            )
        }
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

        if preferFreshRemoteCheck == false,
           let snapshot = try dependencies.metadataStore.providerHealth(workspaceID: workspace.id, providerID: providerID),
           workspace.kind != .remote,
           isRecent(snapshot.checkedAt) {
            return snapshot
        }

        guard workspace.kind == .remote else {
            return await providerModule.providerHealthSummary(
                for: workspace,
                remoteContext: remoteContext,
                providerHealthEvaluator: dependencies.providerHealthEvaluator
            )
        }

        if preferFreshRemoteCheck == false,
           let snapshot = try dependencies.metadataStore.providerHealth(workspaceID: workspace.id, providerID: providerID),
           isRecent(snapshot.checkedAt),
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

    private func loadWorkspaceOverview(
        workspaceID: UUID,
        mode: WorkspaceOverviewLoadMode
    ) async throws -> WorkspaceOverview {
        var trace = PerformanceDiagnosticTrace(
            operation: .workspaceOverview,
            workspaceID: workspaceID,
            currentUptimeNanoseconds: dependencies.currentUptimeNanoseconds
        )

        do {
            guard let workspace = try trace.measure("loadWorkspace", { try dependencies.metadataStore.workspace(id: workspaceID) }) else {
                throw NexusMetadataStoreError.workspaceNotFound
            }

            let (remoteTarget, usesStaleRemoteFacts) = try trace.measure("loadRemoteTarget") {
                try workspaceOverviewRemoteTargetOverview(for: workspace, mode: mode)
            }
            let remoteContext = remoteTarget.map {
                RemoteWorkspaceHealthContext(
                    host: $0.host,
                    hostValidation: $0.hostValidation,
                    workspaceAvailability: $0.workspaceAvailability
                )
            }

            let (providerCards, usesStaleProviderFacts) = try await workspaceProviderCards(
                workspaceID: workspaceID,
                workspace: workspace,
                remoteContext: remoteContext,
                mode: mode,
                trace: &trace
            )

            let overview = WorkspaceOverview(
                workspace: workspace,
                providerCards: providerCards,
                remoteTarget: remoteTarget,
                usesStaleBrowseFacts: mode == .browse && (usesStaleRemoteFacts || usesStaleProviderFacts)
            )
            try? dependencies.recordPerformanceDiagnostic(trace.finish(outcome: .success))
            return overview
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

    private func workspaceOverviewRemoteTargetOverview(
        for workspace: Workspace,
        mode: WorkspaceOverviewLoadMode
    ) throws -> (RemoteWorkspaceTargetOverview?, Bool) {
        guard workspace.kind == .remote,
              let hostID = workspace.remoteHostID,
              let host = try dependencies.metadataStore.host(id: hostID) else {
            return (nil, false)
        }

        let existingHostValidation = try dependencies.metadataStore.hostValidation(hostID: hostID)
        let hostValidation: HostValidationSnapshot?
        let usesStaleHostValidation: Bool
        switch mode {
        case .browse:
            hostValidation = existingHostValidation
            usesStaleHostValidation = existingHostValidation.map { isRecent($0.checkedAt) == false } ?? false
        case .forceFresh:
            hostValidation = try dependencies.metadataStore.saveHostValidation(
                hostID: hostID,
                result: dependencies.hostValidationEvaluator.validate(host: host),
                checkedAt: dependencies.currentDate()
            )
            usesStaleHostValidation = false
        }

        let availability: WorkspaceAvailabilitySnapshot
        let usesStaleAvailability: Bool
        switch mode {
        case .browse:
            if let existingAvailability = try dependencies.metadataStore.workspaceAvailability(workspaceID: workspace.id) {
                if isRecent(existingAvailability.checkedAt) {
                    availability = existingAvailability
                    usesStaleAvailability = false
                } else {
                    availability = existingAvailability
                    usesStaleAvailability = true
                }
            } else {
                let availabilityResult = dependencies.workspaceAvailabilityEvaluator.evaluate(
                    workspace: workspace,
                    host: host,
                    hostValidation: hostValidation
                )
                availability = try dependencies.metadataStore.saveWorkspaceAvailability(
                    workspaceID: workspace.id,
                    result: availabilityResult,
                    checkedAt: dependencies.currentDate()
                )
                usesStaleAvailability = false
            }
        case .forceFresh:
            let availabilityResult = dependencies.workspaceAvailabilityEvaluator.evaluate(
                workspace: workspace,
                host: host,
                hostValidation: hostValidation
            )
            availability = try dependencies.metadataStore.saveWorkspaceAvailability(
                workspaceID: workspace.id,
                result: availabilityResult,
                checkedAt: dependencies.currentDate()
            )
            usesStaleAvailability = false
        }

        return (
            RemoteWorkspaceTargetOverview(
                host: host,
                hostValidation: hostValidation,
                workspaceAvailability: availability
            ),
            usesStaleHostValidation || usesStaleAvailability
        )
    }

    private func workspaceProviderCards(
        workspaceID: UUID,
        workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        mode: WorkspaceOverviewLoadMode,
        trace: inout PerformanceDiagnosticTrace
    ) async throws -> ([WorkspaceProviderCard], Bool) {
        let providerIDs = Array(ProviderID.allCases)
        let loadedProviderCards = try await withThrowingTaskGroup(of: LoadedWorkspaceProviderCard.self, returning: [LoadedWorkspaceProviderCard].self) { group in
            for (index, providerID) in providerIDs.enumerated() {
                group.addTask { [self] in
                    let providerModule = providerModule(for: providerID)
                    let (sessions, loadSessionsStep) = try measuredStep("loadSessions.\(providerID.rawValue)") {
                        try dependencies.sessionRecordStore.listSessions(workspaceID: workspaceID, providerID: providerID)
                            .map(reconcileSessionRuntimeState)
                    }
                    let defaultSession = sessions.first(where: \.isDefault)
                    let (catalogReadResult, readProviderCatalogStep) = try await measuredStep("readProviderCatalog.\(providerID.rawValue)") {
                        try await self.workspaceOverviewCatalogRead(
                            providerID: providerID,
                            providerModule: providerModule,
                            workspace: workspace,
                            remoteContext: remoteContext,
                            defaultSession: defaultSession,
                            mode: mode
                        )
                    }
                    let (catalogRead, usesStaleBrowseFacts) = catalogReadResult

                    return LoadedWorkspaceProviderCard(
                        index: index,
                        card: WorkspaceProviderCard(
                            provider: Provider(id: providerID),
                            health: catalogRead.health,
                            capabilities: catalogRead.capabilities,
                            prelaunchPrimarySurface: catalogRead.prelaunchPrimarySurface,
                            defaultSession: catalogRead.defaultSession,
                            alternateSessionCount: sessions.filter { $0.isDefault == false }.count
                        ),
                        performanceSteps: [loadSessionsStep, readProviderCatalogStep],
                        usesStaleBrowseFacts: usesStaleBrowseFacts
                    )
                }
            }

            var orderedProviderCards = Array<LoadedWorkspaceProviderCard?>(repeating: nil, count: providerIDs.count)
            for try await loadedProviderCard in group {
                orderedProviderCards[loadedProviderCard.index] = loadedProviderCard
            }
            return orderedProviderCards.compactMap { $0 }
        }

        for loadedProviderCard in loadedProviderCards {
            trace.appendSteps(loadedProviderCard.performanceSteps)
        }
        return (
            loadedProviderCards.map(\.card),
            loadedProviderCards.contains(where: \.usesStaleBrowseFacts)
        )
    }

    private func workspaceOverviewCatalogRead(
        providerID: ProviderID,
        providerModule: any ProviderModule,
        workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        defaultSession: Session?,
        mode: WorkspaceOverviewLoadMode
    ) async throws -> (ProviderModuleCatalogReadResult, Bool) {
        var usesStaleBrowseFacts = false
        let catalogRead = try await providerModule.readCatalog(
            ProviderModuleCatalogReadRequest(
                workspace: workspace,
                remoteContext: remoteContext,
                defaultSession: defaultSession
            ),
            actions: ProviderModuleCatalogReadActions { [self] in
                let health = try await self.workspaceOverviewProviderHealthSummary(
                    for: providerID,
                    workspace: workspace,
                    remoteContext: remoteContext,
                    mode: mode
                )
                usesStaleBrowseFacts = health.usesStaleBrowseFacts
                return health.summary
            }
        )
        return (catalogRead, usesStaleBrowseFacts)
    }

    private func workspaceOverviewProviderHealthSummary(
        for providerID: ProviderID,
        workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        mode: WorkspaceOverviewLoadMode
    ) async throws -> (summary: ProviderHealthSummary, usesStaleBrowseFacts: Bool) {
        switch mode {
        case .browse:
            if let snapshot = try dependencies.metadataStore.providerHealth(workspaceID: workspace.id, providerID: providerID) {
                if isRecent(snapshot.checkedAt) {
                    return (snapshot, false)
                }
                return (snapshot, true)
            }
        case .forceFresh:
            break
        }

        return (try await evaluateAndPersistProviderHealth(for: providerID, workspace: workspace, remoteContext: remoteContext), false)
    }

    private func evaluateAndPersistProviderHealth(
        for providerID: ProviderID,
        workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?
    ) async throws -> ProviderHealthSummary {
        let evaluated = await providerModule(for: providerID).providerHealthSummary(
            for: workspace,
            remoteContext: remoteContext,
            providerHealthEvaluator: dependencies.providerHealthEvaluator
        )
        return try dependencies.metadataStore.saveProviderHealth(
            workspaceID: workspace.id,
            providerID: providerID,
            summary: evaluated,
            checkedAt: dependencies.currentDate()
        )
    }

    private func measuredStep<T>(_ name: String, _ block: () throws -> T) rethrows -> (T, PerformanceDiagnosticStep) {
        let startedAt = dependencies.currentUptimeNanoseconds()
        let value = try block()
        return (
            value,
            PerformanceDiagnosticStep(
                name: name,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        )
    }

    private func measuredStep<T>(_ name: String, _ block: () async throws -> T) async rethrows -> (T, PerformanceDiagnosticStep) {
        let startedAt = dependencies.currentUptimeNanoseconds()
        let value = try await block()
        return (
            value,
            PerformanceDiagnosticStep(
                name: name,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        )
    }

    private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        let current = dependencies.currentUptimeNanoseconds()
        return Int((current >= startedAt ? current - startedAt : 0) / 1_000_000)
    }

    private func providerModule(for providerID: ProviderID) -> any ProviderModule {
        dependencies.providerModuleRegistry.module(for: providerID)
    }

    private func isRecent(_ checkedAt: Date?) -> Bool {
        guard let checkedAt else {
            return false
        }

        return dependencies.currentDate().timeIntervalSince(checkedAt) <= 30
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
