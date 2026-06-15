#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC

extension NexusAppModel {
    static func bootstrap(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> NexusAppModel {
        if let mode = NexusAppFixtureMode(rawValue: environment[NexusAppFixture.environmentKey] ?? "") {
            return NexusAppFixture.makeModel(mode: mode)
        }

        return try live(listeningPort: appBootstrapListeningPort(environment: environment))
    }
}

private enum NexusAppFixtureMode: String {
    case structuredFeedProfile = "structured-feed-profile"
}

private enum NexusAppFixture {
    static let environmentKey = "NEXUS_MAC_PROFILE_FIXTURE"

    static func makeModel(mode: NexusAppFixtureMode) -> NexusAppModel {
        let workspaceGroup = WorkspaceGroup(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "Profiling Fixtures"
        )
        let host = NexusDomain.Host(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "Fixture Host",
            sshTarget: "fixture-host",
            port: 22
        )
        let workspace = Workspace(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            name: "Structured Feed Fixture",
            kind: .remote,
            folderPath: "/srv/structured-feed-profile",
            primaryGroupID: workspaceGroup.id,
            remoteHostID: host.id
        )
        let provider = Provider(id: .pi)
        let session = Session(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            workspaceID: workspace.id,
            providerID: provider.id,
            isDefault: true,
            state: .ready
        )

        return NexusAppModel(
            client: FixtureServiceClient(
                workspaceGroup: workspaceGroup,
                host: host,
                workspace: workspace,
                provider: provider,
                session: session,
                mode: mode
            ),
            bootstrapInitialSelection: .session(session.id)
        )
    }

    private actor FixtureServiceClient: NexusServiceClient {
        private let workspaceGroup: WorkspaceGroup
        private let host: NexusDomain.Host
        private let workspace: Workspace
        private let provider: Provider
        private let session: Session
        private let mode: NexusAppFixtureMode
        private let providerCapabilities: ProviderCapabilities
        private let workspaceOverview: WorkspaceOverview
        private let providerDetail: ProviderDetail
        private let serviceStatus: NexusServiceStatus
        private let remoteAccessState = RemoteAccessState(isEnabled: false, activePairing: nil)
        private var latestScreen: SessionScreen
        private var streamingState: StructuredFeedProfilingFixture.State

        init(
            workspaceGroup: WorkspaceGroup,
            host: NexusDomain.Host,
            workspace: Workspace,
            provider: Provider,
            session: Session,
            mode: NexusAppFixtureMode
        ) {
            self.workspaceGroup = workspaceGroup
            self.host = host
            self.workspace = workspace
            self.provider = provider
            self.session = session
            self.mode = mode
            providerCapabilities = ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            )

            let remoteTarget = RemoteWorkspaceTargetOverview(
                host: host,
                hostValidation: HostValidationSnapshot(
                    hostID: host.id,
                    state: .available,
                    summary: "Fixture host ready",
                    checkedAt: Date(timeIntervalSince1970: 600)
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspace.id,
                    state: .available,
                    summary: "Fixture workspace available",
                    checkedAt: Date(timeIntervalSince1970: 600)
                )
            )
            workspaceOverview = WorkspaceOverview(
                workspace: workspace,
                providerCards: [
                    WorkspaceProviderCard(
                        provider: provider,
                        health: ProviderHealthSummary(
                            state: .available,
                            summary: "Pi fixture ready",
                            resolvedExecutable: "/usr/bin/pi-fixture",
                            version: "fixture",
                            launchability: .launchable,
                            checkedAt: Date(timeIntervalSince1970: 600)
                        ),
                        capabilities: providerCapabilities,
                        prelaunchPrimarySurface: .structuredActivityFeed,
                        defaultSession: ProviderDefaultSessionSummary(
                            state: .ready,
                            summary: "Profiling Session ready",
                            actionTitle: "Open conversation",
                            sessionID: session.id
                        )
                    )
                ],
                remoteTarget: remoteTarget
            )
            providerDetail = ProviderDetail(
                workspace: workspace,
                provider: provider,
                health: ProviderHealthSummary(
                    state: .available,
                    summary: "Pi fixture ready",
                    resolvedExecutable: "/usr/bin/pi-fixture",
                    version: "fixture",
                    launchability: .launchable,
                    checkedAt: Date(timeIntervalSince1970: 600)
                ),
                capabilities: providerCapabilities,
                prelaunchPrimarySurface: .structuredActivityFeed,
                defaultSession: session,
                alternateSessions: [],
                failedSessions: []
            )
            serviceStatus = NexusServiceStatus(
                state: .running,
                store: .init(
                    kind: .sqlite,
                    owner: .backgroundService,
                    location: URL(fileURLWithPath: "/tmp/nexus-fixture.sqlite")
                )
            )

            switch mode {
            case .structuredFeedProfile:
                let initialState = StructuredFeedProfilingFixture.makeInitialState()
                streamingState = initialState
                latestScreen = StructuredFeedProfilingFixture.screen(for: initialState, session: session)
            }
        }

        func getServiceStatus() async throws -> NexusServiceStatus { serviceStatus }
        func listWorkspaceGroups() async throws -> [WorkspaceGroup] { [workspaceGroup] }
        func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup { try unsupported() }
        func listWorkspaces() async throws -> [Workspace] { [workspace] }
        func listHosts() async throws -> [NexusDomain.Host] { [host] }
        func getHostDetail(hostID: UUID) async throws -> NexusDomain.HostDetail {
            HostDetail(
                host: host,
                latestValidation: HostValidationSnapshot(
                    hostID: host.id,
                    state: .available,
                    summary: "Fixture host ready",
                    checkedAt: Date(timeIntervalSince1970: 600)
                )
            )
        }
        func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host { try unsupported() }
        func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host { try unsupported() }
        func validateHost(hostID: UUID) async throws -> HostValidationSnapshot {
            HostValidationSnapshot(hostID: host.id, state: .available, summary: "Fixture host ready", checkedAt: Date(timeIntervalSince1970: 600))
        }
        func deleteHost(hostID: UUID) async throws -> Bool { try unsupported() }
        func listRecentNavigation(limit: Int) async throws -> [NavigationItem] {
            [
                NavigationItem(target: .session(session.id), title: "Structured Feed Profile", subtitle: workspace.folderPath),
                NavigationItem(target: .workspace(workspace.id), title: workspace.name, subtitle: workspace.folderPath)
            ]
        }
        func recordNavigation(target: NavigationTarget) async throws {}
        func searchNavigation(query: String) async throws -> [NavigationItem] {
            try await listRecentNavigation(limit: 10)
        }
        func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) async throws {}
        func listPerformanceDiagnostics(limit: Int) async throws -> [PerformanceDiagnosticRecord] { [] }
        func getRemoteAccessState() async throws -> RemoteAccessState { remoteAccessState }
        func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState { remoteAccessState }
        func startPairing() async throws -> PairingCeremony { try unsupported() }
        func completePairing(pairingCode: String, deviceName: String) async throws -> PairedDevice { try unsupported() }
        func listPairedDevices() async throws -> [PairedDevice] { [] }
        func revokePairedDevice(deviceID: UUID) async throws -> Bool { try unsupported() }
        func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview { workspaceOverview }
        func refreshWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview { workspaceOverview }
        func getWorkspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview] { [workspaceOverview] }
        func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail { providerDetail }
        func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace { try unsupported() }
        func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace { try unsupported() }
        func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session { session }
        func launchOrResumeSession(sessionID: UUID) async throws -> Session { session }
        func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session { try unsupported() }
        func stopSession(sessionID: UUID) async throws -> Session { session }
        func deleteSessionRecord(sessionID: UUID) async throws -> Bool { try unsupported() }
        func getSessionRecord(sessionID: UUID) async throws -> Session { session }
        func getSessionScreen(sessionID: UUID) async throws -> SessionScreen { latestScreen }
        func getStructuredSessionHistoryPage(
            sessionID: UUID,
            pageSize: Int,
            before cursor: StructuredSessionHistoryCursor?
        ) async throws -> StructuredSessionHistoryPage {
            StructuredSessionHistoryPage(sessionID: session.id, activityItems: [], providerEvents: [], nextCursor: nil)
        }

        func getStructuredSessionArtifactFile(sessionID: UUID, hostPath: String) async throws -> StructuredSessionArtifactFile {
            try unsupported()
        }

        func getStructuredSessionArtifactFile(
            sessionID: UUID,
            hostPath: String,
            requestingPairedDeviceID: UUID?
        ) async throws -> StructuredSessionArtifactFile {
            try unsupported()
        }

        func observeSessionScreen(
            sessionID: UUID,
            onUpdate: @escaping @Sendable (SessionScreen) -> Void
        ) async throws -> any SessionScreenObservation {
            let task = Task {
                onUpdate(self.latestScreen)

                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: StructuredFeedProfilingFixture.updateIntervalNanoseconds)
                    guard Task.isCancelled == false else {
                        break
                    }

                    let updated = self.advanceObservedScreen()
                    onUpdate(updated)
                }
            }

            return FixtureSessionScreenObservation {
                task.cancel()
            }
        }

        func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
            let updated = appendPromptRoundTrip(text: text)
            latestScreen = updated
            return updated
        }

        func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
            try await sendSessionInput(sessionID: sessionID, text: prompt.text)
        }

        func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
            latestScreen
        }

        func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
            latestScreen
        }

        func respondToApprovalRequest(sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
            latestScreen
        }

        func respondToExtensionDialog(sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen {
            latestScreen
        }

        func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
            latestScreen = StructuredFeedProfilingFixture.screen(
                for: streamingState,
                session: session,
                controller: latestScreen.controller,
                terminalColumns: columns,
                terminalRows: rows
            )
            return latestScreen
        }

        func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen { try unsupported() }
        func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) async throws -> SessionScreen { try unsupported() }
        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen { try unsupported() }
        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws -> SessionScreen { try unsupported() }
        func respondToRemoteApprovalRequest(sessionID: UUID, pairedDeviceID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen { try unsupported() }
        func respondToRemoteExtensionDialog(sessionID: UUID, pairedDeviceID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen { try unsupported() }
        func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen { try unsupported() }
        func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen { try unsupported() }

        private func advanceObservedScreen() -> SessionScreen {
            streamingState = StructuredFeedProfilingFixture.advance(streamingState)
            latestScreen = StructuredFeedProfilingFixture.screen(
                for: streamingState,
                session: session,
                controller: latestScreen.controller,
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows
            )
            return latestScreen
        }

        private func appendPromptRoundTrip(text: String) -> SessionScreen {
            let userItem = SessionActivityItem(kind: .message, text: "You: \(text)")
            let assistantItem = SessionActivityItem(kind: .message, text: "Pi: Fixture reply for: \(text)")
            return SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .mac,
                transcript: latestScreen.transcript + "\nYou: \(text)\nPi: Fixture reply for: \(text)",
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows,
                activityItems: latestScreen.activityItems + [userItem, assistantItem],
                providerFacts: StructuredSessionProviderFacts(
                    providerEventCount: latestScreen.providerFacts.providerEventCount + 1,
                    lastProviderEventSequence: (latestScreen.providerFacts.lastProviderEventSequence ?? 0) + 1,
                    lastProviderEventType: "turn_end",
                    tokenUsage: latestScreen.providerFacts.tokenUsage,
                    modelIdentifier: latestScreen.providerFacts.modelIdentifier
                ),
                finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic(
                    trigger: .turnEnd,
                    providerEventSequence: (latestScreen.providerFacts.lastProviderEventSequence ?? 0) + 1,
                    providerRuntimeLatencyMilliseconds: 4,
                    serviceObservationLatencyMilliseconds: 9,
                    expectedActivityItemID: assistantItem.id,
                    expectedActivityItemText: assistantItem.text,
                    expectedThinkingIndicatorVisible: false
                ),
                isAgentTurnInProgress: false
            )
        }

        private func unsupported<T>() throws -> T {
            throw NSError(
                domain: "NexusAppFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This macOS profiling fixture only supports deterministic structured feed profiling flows."]
            )
        }
    }

    private final class FixtureSessionScreenObservation: SessionScreenObservation, @unchecked Sendable {
        private let cancelHandler: @Sendable () -> Void

        init(cancelHandler: @escaping @Sendable () -> Void) {
            self.cancelHandler = cancelHandler
        }

        func cancel() async {
            cancelHandler()
        }
    }
}
#endif
