import Foundation
import NexusDomain
import NexusIPC

extension RemoteClientPairingModel {
    static func bootstrap(environment: [String: String] = ProcessInfo.processInfo.environment) -> RemoteClientPairingModel {
        if let mode = RemoteClientFixtureMode(rawValue: environment[RemoteClientFixture.environmentKey] ?? "") {
            return RemoteClientFixture.makeModel(mode: mode)
        }

        return RemoteClientPairingModel(
            client: RemotePairingHTTPClient(),
            store: UserDefaultsPairedMacStore()
        )
    }
}

private enum RemoteClientFixtureMode: String {
    case invalidationBaseline = "invalidation-baseline"
    case thinkingDiagnosis = "thinking-diagnosis"
}

private enum RemoteClientFixture {
    static let environmentKey = "NEXUS_REMOTE_CLIENT_FIXTURE"

    static func makeModel(mode: RemoteClientFixtureMode) -> RemoteClientPairingModel {
        let pairedMac = PairedMac(
            name: "Profiling Mac",
            host: "profiling.local",
            port: 9234,
            pairedAt: Date(timeIntervalSince1970: 600),
            pairedDeviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let store = InMemoryPairedMacStore(pairedMacs: [pairedMac], activePairedMacID: pairedMac.id)
        return RemoteClientPairingModel(
            client: RemoteClientProfilingFixtureClient(pairedMac: pairedMac, mode: mode),
            store: store
        )
    }

    private final class InMemoryPairedMacStore: PairedMacStore {
        private var pairedMacs: [PairedMac]
        private var activePairedMacID: PairedMac.ID?

        init(pairedMacs: [PairedMac], activePairedMacID: PairedMac.ID?) {
            self.pairedMacs = pairedMacs
            self.activePairedMacID = activePairedMacID
        }

        func loadPairedMacs() -> [PairedMac] {
            pairedMacs
        }

        func savePairedMacs(_ pairedMacs: [PairedMac]) throws {
            self.pairedMacs = pairedMacs
        }

        func loadActivePairedMacID() -> PairedMac.ID? {
            activePairedMacID
        }

        func saveActivePairedMacID(_ activePairedMacID: PairedMac.ID?) {
            self.activePairedMacID = activePairedMacID
        }
    }

    private actor RemoteClientProfilingFixtureClient: RemotePairingClient {
        private let pairedMac: PairedMac
        private let mode: RemoteClientFixtureMode
        private let workspaceGroup: WorkspaceGroup
        private let remoteHost: NexusDomain.Host
        private let apiWorkspace: Workspace
        private let phoneWorkspace: Workspace
        private let provider: Provider
        private let session: Session
        private let providerCapabilities: ProviderCapabilities
        private let catalog: RemoteWorkspaceCatalog
        private let providerDetail: ProviderDetail
        private var latestScreen: SessionScreen
        private var autoUpdateCount = 0

        init(pairedMac: PairedMac, mode: RemoteClientFixtureMode) {
            self.pairedMac = pairedMac
            self.mode = mode
            workspaceGroup = WorkspaceGroup(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "Baseline Work"
            )
            remoteHost = NexusDomain.Host(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "Build Server",
                sshTarget: "build-server",
                port: 22
            )
            apiWorkspace = Workspace(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "Baseline API",
                kind: .remote,
                folderPath: "/srv/baseline-api",
                primaryGroupID: workspaceGroup.id,
                remoteHostID: remoteHost.id
            )
            phoneWorkspace = Workspace(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                name: "Baseline iPhone",
                kind: .local,
                folderPath: "/tmp/baseline-iphone",
                primaryGroupID: workspaceGroup.id
            )
            provider = Provider(id: .pi)
            session = Session(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                workspaceID: apiWorkspace.id,
                providerID: provider.id,
                isDefault: true,
                state: .ready
            )
            providerCapabilities = ProviderCapabilities(
                launchDefaultSession: ProviderCapability(action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            )

            let remoteTarget = RemoteWorkspaceTargetOverview(
                host: remoteHost,
                hostValidation: HostValidationSnapshot(
                    hostID: remoteHost.id,
                    state: .available,
                    summary: "SSH ready",
                    checkedAt: Date(timeIntervalSince1970: 600)
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: apiWorkspace.id,
                    state: .available,
                    summary: "Available",
                    checkedAt: Date(timeIntervalSince1970: 600)
                )
            )

            let providerCard = WorkspaceProviderCard(
                provider: provider,
                health: ProviderHealthSummary(state: .available, summary: "Pi available"),
                capabilities: providerCapabilities,
                prelaunchPrimarySurface: .structuredActivityFeed,
                defaultSession: ProviderDefaultSessionSummary(
                    state: .ready,
                    summary: "Default Session ready",
                    actionTitle: "Open conversation",
                    sessionID: session.id
                )
            )

            catalog = RemoteWorkspaceCatalog(
                workspaceGroups: [workspaceGroup],
                recentNavigation: [
                    NavigationItem(target: .workspace(apiWorkspace.id), title: apiWorkspace.name, subtitle: apiWorkspace.folderPath),
                    NavigationItem(target: .workspace(phoneWorkspace.id), title: phoneWorkspace.name, subtitle: phoneWorkspace.folderPath)
                ],
                workspaceOverviews: [
                    WorkspaceOverview(workspace: apiWorkspace, providerCards: [providerCard], remoteTarget: remoteTarget),
                    WorkspaceOverview(workspace: phoneWorkspace, providerCards: [providerCard])
                ]
            )

            providerDetail = ProviderDetail(
                workspace: apiWorkspace,
                provider: provider,
                health: ProviderHealthSummary(state: .available, summary: "Pi available"),
                capabilities: providerCapabilities,
                prelaunchPrimarySurface: .structuredActivityFeed,
                defaultSession: session,
                alternateSessions: [],
                failedSessions: []
            )

            let isThinkingFixture = mode == .thinkingDiagnosis
            let initialMessage = isThinkingFixture
                ? "Pi: thinking step 0"
                : "Pi: Profiling fixture ready"
            latestScreen = SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .mac,
                transcript: isThinkingFixture
                    ? "Pi shared Session stream connected\n\(initialMessage)"
                    : "Pi shared Session stream connected",
                activityItems: [
                    SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                    SessionActivityItem(kind: .message, text: initialMessage)
                ],
                isAgentTurnInProgress: isThinkingFixture
            )
        }

        func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus {
            RemotePairedMacStatus(macName: pairedMac.name, isRemoteAccessEnabled: true)
        }

        func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac {
            pairedMac
        }

        func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog {
            catalog
        }

        func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
            providerDetail
        }

        func launchOrResumeDefaultSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
            session
        }

        func createNamedSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
            Session(
                id: UUID(),
                workspaceID: workspaceID,
                providerID: providerID,
                name: "Fixture Side Chat",
                isDefault: false,
                state: .ready
            )
        }

        func launchOrResumeSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
            session
        }

        func stopSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
            let stoppedSession = Session(
                id: session.id,
                workspaceID: session.workspaceID,
                providerID: session.providerID,
                isDefault: session.isDefault,
                state: .exited
            )
            latestScreen = SessionScreen(
                session: stoppedSession,
                primarySurface: .structuredActivityFeed,
                controller: .mac,
                transcript: latestScreen.transcript,
                activityItems: latestScreen.activityItems + [SessionActivityItem(kind: .status, text: "Fixture Session stopped")]
            )
            return stoppedSession
        }

        func deleteSessionRecord(for pairedMac: PairedMac, sessionID: UUID) async throws -> Bool {
            true
        }

        func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
            latestScreen
        }

        func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
            latestScreen = SessionScreen(
                session: latestScreen.session,
                primarySurface: latestScreen.primarySurface,
                controller: .pairedDevice(pairedMac.pairedDeviceID!),
                transcript: latestScreen.transcript,
                terminalColumns: columns,
                terminalRows: rows,
                activityItems: latestScreen.activityItems,
                approvalRequests: latestScreen.approvalRequests,
                extensionUI: latestScreen.extensionUI,
                providerEvents: latestScreen.providerEvents,
                providerFacts: latestScreen.providerFacts,
                isAgentTurnInProgress: latestScreen.isAgentTurnInProgress
            )
            return latestScreen
        }

        func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
            latestScreen = SessionScreen(
                session: latestScreen.session,
                primarySurface: latestScreen.primarySurface,
                controller: .mac,
                transcript: latestScreen.transcript,
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows,
                activityItems: latestScreen.activityItems,
                approvalRequests: latestScreen.approvalRequests,
                extensionUI: latestScreen.extensionUI,
                providerEvents: latestScreen.providerEvents,
                providerFacts: latestScreen.providerFacts,
                isAgentTurnInProgress: latestScreen.isAgentTurnInProgress
            )
            return latestScreen
        }

        func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
            latestScreen = appendedScreen(userLine: text, agentLine: "Fixture reply for: \(text)")
            return latestScreen
        }

        func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
            latestScreen = appendedScreen(userLine: prompt.text, agentLine: "Fixture reply for: \(prompt.text)")
            return latestScreen
        }

        func respondToApprovalRequest(for pairedMac: PairedMac, sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
            latestScreen
        }

        func respondToExtensionDialog(for pairedMac: PairedMac, sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen {
            latestScreen
        }

        func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
            try await sendSessionInput(for: pairedMac, sessionID: sessionID, text: text)
        }

        func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
            latestScreen
        }

        func observeSessionScreen(
            for pairedMac: PairedMac,
            sessionID: UUID,
            onUpdate: @escaping @Sendable (SessionScreen) -> Void,
            onDisconnect: @escaping @Sendable (any Error) -> Void
        ) async throws -> any SessionScreenObservation {
            let task = Task {
                onUpdate(self.latestScreen)

                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    guard Task.isCancelled == false else {
                        break
                    }

                    let updatedScreen = self.appendAutoUpdate()
                    onUpdate(updatedScreen)
                }
            }

            return FixtureSessionScreenObservation {
                task.cancel()
            }
        }

        private func appendAutoUpdate() -> SessionScreen {
            autoUpdateCount += 1
            let line = mode == .thinkingDiagnosis
                ? "Pi: thinking step \(autoUpdateCount)"
                : "Pi: Fixture update \(autoUpdateCount)"
            latestScreen = SessionScreen(
                session: latestScreen.session,
                primarySurface: latestScreen.primarySurface,
                controller: latestScreen.controller,
                transcript: latestScreen.transcript + "\n" + line,
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows,
                activityItems: latestScreen.activityItems + [SessionActivityItem(kind: .message, text: line)],
                approvalRequests: latestScreen.approvalRequests,
                extensionUI: latestScreen.extensionUI,
                providerEvents: latestScreen.providerEvents,
                providerFacts: latestScreen.providerFacts,
                isAgentTurnInProgress: mode == .thinkingDiagnosis
            )
            return latestScreen
        }

        private func appendedScreen(userLine: String, agentLine: String) -> SessionScreen {
            let appendedTranscript = latestScreen.transcript + "\nYou: \(userLine)\nPi: \(agentLine)"
            let userItem = SessionActivityItem(kind: .message, text: "You: \(userLine)")
            let agentItem = SessionActivityItem(kind: .message, text: "Pi: \(agentLine)")
            latestScreen = SessionScreen(
                session: latestScreen.session,
                primarySurface: latestScreen.primarySurface,
                controller: latestScreen.controller,
                transcript: appendedTranscript,
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows,
                activityItems: latestScreen.activityItems + [userItem, agentItem],
                approvalRequests: latestScreen.approvalRequests,
                extensionUI: latestScreen.extensionUI,
                providerEvents: latestScreen.providerEvents,
                providerFacts: latestScreen.providerFacts,
                finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic(
                    trigger: .turnEnd,
                    providerEventSequence: latestScreen.providerFacts.lastProviderEventSequence ?? latestScreen.providerEvents.last?.sequence ?? latestScreen.activityItems.count + 1,
                    providerRuntimeLatencyMilliseconds: 4,
                    serviceObservationLatencyMilliseconds: 10,
                    expectedActivityItemID: agentItem.id,
                    expectedActivityItemText: agentItem.text,
                    expectedThinkingIndicatorVisible: false
                ),
                isAgentTurnInProgress: false
            )
            return latestScreen
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
