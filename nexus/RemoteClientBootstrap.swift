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
    case streamingFeedProfile = "streaming-feed-profile"
}

private enum RemoteClientStreamingFeedProfile {
    nonisolated static let updateIntervalNanoseconds: UInt64 = 200_000_000
    nonisolated private static let seededTurnCount = 28
    nonisolated private static let modelIdentifier = "xai/grok-4.3"
    nonisolated private static let totalTokenLimit = 128_000
    nonisolated private static let draftPrefixFractions: [Double] = [0.18, 0.38, 0.62, 0.85]

    enum Phase: Equatable {
        case drafting(step: Int)
        case finalized
    }

    struct State {
        var turnIndex: Int
        var phase: Phase
        var transcript: String
        var activityItems: [SessionActivityItem]
        var providerEventSequence: Int
    }

    nonisolated static func makeInitialState() -> State {
        var transcriptLines = ["Pi shared Session stream connected"]
        var activityItems = [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        var providerEventSequence = 0

        for turnIndex in 0 ..< seededTurnCount {
            let prompt = userPrompt(for: turnIndex)
            let assistantMessage = finalizedAssistantMessage(for: turnIndex)

            activityItems.append(SessionActivityItem(kind: .message, text: "You: \(prompt)"))
            activityItems.append(SessionActivityItem(
                kind: .progress,
                text: "Planning streaming burst \(turnIndex)",
                detailText: progressDetail(for: turnIndex)
            ))
            activityItems.append(SessionActivityItem(
                kind: .command,
                text: commandTitle(for: turnIndex),
                detailText: commandOutput(for: turnIndex)
            ))
            activityItems.append(SessionActivityItem(kind: .message, text: "Pi: \(assistantMessage)"))

            if turnIndex.isMultiple(of: 4) {
                activityItems.append(SessionActivityItem(kind: .status, text: "Trace marker \(turnIndex) captured"))
            }

            transcriptLines.append("You: \(prompt)")
            transcriptLines.append("Pi: \(assistantMessage)")
            providerEventSequence += 2
        }

        let historyState = State(
            turnIndex: seededTurnCount - 1,
            phase: .finalized,
            transcript: transcriptLines.joined(separator: "\n"),
            activityItems: activityItems,
            providerEventSequence: providerEventSequence
        )
        return startTurn(after: historyState, turnIndex: seededTurnCount)
    }

    nonisolated static func advance(_ state: State) -> State {
        switch state.phase {
        case .drafting(let step):
            if step < draftPrefixFractions.count - 1 {
                var updated = state
                updated.phase = .drafting(step: step + 1)
                updated.providerEventSequence += 1
                return updated
            }

            return finalizeTurn(state)
        case .finalized:
            return startTurn(after: state, turnIndex: state.turnIndex + 1)
        }
    }

    nonisolated static func screen(
        for state: State,
        session: Session,
        controller: SessionController,
        terminalColumns: Int,
        terminalRows: Int
    ) -> SessionScreen {
        let providerFacts = StructuredSessionProviderFacts(
            providerEventCount: max(1, state.providerEventSequence),
            lastProviderEventSequence: max(1, state.providerEventSequence),
            lastProviderEventType: providerEventType(for: state.phase),
            liveAssistantDraftText: liveAssistantDraftText(for: state),
            tokenUsage: tokenUsage(for: state),
            modelIdentifier: modelIdentifier
        )

        let finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic? = if case .finalized = state.phase,
           let assistantItem = state.activityItems.last(where: { $0.kind == .message && $0.text.hasPrefix("Pi: ") }) {
            StructuredSessionFinalOutputDiagnostic(
                trigger: .turnEnd,
                providerEventSequence: max(1, state.providerEventSequence),
                providerRuntimeLatencyMilliseconds: 6 + (state.turnIndex % 5),
                serviceObservationLatencyMilliseconds: 11 + (state.turnIndex % 7),
                expectedActivityItemID: assistantItem.id,
                expectedActivityItemText: assistantItem.text,
                expectedThinkingIndicatorVisible: false
            )
        } else {
            nil
        }

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            controller: controller,
            transcript: state.transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: state.activityItems,
            providerFacts: providerFacts,
            finalOutputDiagnostic: finalOutputDiagnostic,
            isAgentTurnInProgress: isDrafting(state.phase)
        )
    }

    nonisolated private static func startTurn(after state: State, turnIndex: Int) -> State {
        let prompt = userPrompt(for: turnIndex)
        var transcript = state.transcript
        if transcript.isEmpty == false {
            transcript += "\n"
        }
        transcript += "You: \(prompt)"

        return State(
            turnIndex: turnIndex,
            phase: .drafting(step: 0),
            transcript: transcript,
            activityItems: state.activityItems + [
                SessionActivityItem(kind: .message, text: "You: \(prompt)"),
                SessionActivityItem(
                    kind: .progress,
                    text: "Planning streaming burst \(turnIndex)",
                    detailText: progressDetail(for: turnIndex)
                )
            ],
            providerEventSequence: state.providerEventSequence + 1
        )
    }

    nonisolated private static func finalizeTurn(_ state: State) -> State {
        let assistantMessage = finalizedAssistantMessage(for: state.turnIndex)
        var transcript = state.transcript
        if transcript.isEmpty == false {
            transcript += "\n"
        }
        transcript += "Pi: \(assistantMessage)"

        return State(
            turnIndex: state.turnIndex,
            phase: .finalized,
            transcript: transcript,
            activityItems: state.activityItems + [
                SessionActivityItem(
                    kind: .command,
                    text: commandTitle(for: state.turnIndex),
                    detailText: commandOutput(for: state.turnIndex)
                ),
                SessionActivityItem(kind: .message, text: "Pi: \(assistantMessage)")
            ],
            providerEventSequence: state.providerEventSequence + 1
        )
    }

    nonisolated private static func providerEventType(for phase: Phase) -> String {
        switch phase {
        case .drafting:
            "message_update"
        case .finalized:
            "turn_end"
        }
    }

    nonisolated private static func liveAssistantDraftText(for state: State) -> String? {
        guard case .drafting(let step) = state.phase else {
            return nil
        }

        let fragments = draftFragments(for: state.turnIndex)
        return fragments[min(step, fragments.count - 1)]
    }

    nonisolated private static func tokenUsage(for state: State) -> StructuredSessionProviderTokenUsage {
        let draftStep = if case .drafting(let step) = state.phase { step } else { draftPrefixFractions.count }
        let usedTokens = min(
            totalTokenLimit - 1,
            34_000 + (state.turnIndex * 913) + (draftStep * 271)
        )
        let percent = Int((Double(usedTokens) / Double(totalTokenLimit)) * 100.0)
        return StructuredSessionProviderTokenUsage(
            usedTokens: usedTokens,
            totalTokens: totalTokenLimit,
            percent: percent
        )
    }

    nonisolated private static func draftFragments(for turnIndex: Int) -> [String] {
        let message = finalizedAssistantMessage(for: turnIndex)
        return draftPrefixFractions.map { fraction in
            prefixedDraftText(message, fraction: fraction)
        }
    }

    nonisolated private static func prefixedDraftText(_ text: String, fraction: Double) -> String {
        guard text.isEmpty == false else {
            return text
        }

        let characterCount = max(1, min(text.count, Int(Double(text.count) * fraction)))
        let endIndex = text.index(text.startIndex, offsetBy: characterCount)
        return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func userPrompt(for turnIndex: Int) -> String {
        "Profile the structured feed burst \(turnIndex)"
    }

    nonisolated private static func finalizedAssistantMessage(for turnIndex: Int) -> String {
        """
        ### Streaming burst \(turnIndex)
        - keep the scroll anchor near the live tail
        - preserve finalized assistant output without clipping
        - collapse only the streaming draft preview when the text grows

        ```swift
        let burst = \(turnIndex)
        let visibleRows = \(92 + (turnIndex % 11))
        let profile = \"structured-feed\"
        ```

        This deterministic fixture alternates compact and multi-line command output so Instruments can sample stable layout pressure while the live draft keeps changing height.
        """
    }

    nonisolated private static func progressDetail(for turnIndex: Int) -> String {
        """
        preloadedRows=\(92 + turnIndex)
        liveDraftPhase=\(turnIndex % draftPrefixFractions.count)
        feedMode=streaming-feed-profile
        """
    }

    nonisolated private static func commandTitle(for turnIndex: Int) -> String {
        if turnIndex.isMultiple(of: 2) {
            return "swift test --filter StructuredFeedBurst\(turnIndex)"
        }

        return "git diff --stat -- StreamingBurst\(turnIndex).swift"
    }

    nonisolated private static func commandOutput(for turnIndex: Int) -> String {
        if turnIndex.isMultiple(of: 2) {
            return """
            Test Suite 'StructuredFeedBurst\(turnIndex)' started
            Test Case '-[StructuredFeedBurst\(turnIndex) testTailAppend]' passed (0.04 seconds)
            Executed 1 test, with 0 failures in 0.04 seconds
            """
        }

        return (0 ..< 14).map { index in
            "StreamingBurst\(turnIndex).swift | \(index + 1) insertions | chunk \(index)"
        }.joined(separator: "\n")
    }

    nonisolated private static func isDrafting(_ phase: Phase) -> Bool {
        if case .drafting = phase {
            return true
        }
        return false
    }
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
        private var streamingFeedProfileState: RemoteClientStreamingFeedProfile.State?

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

            switch mode {
            case .streamingFeedProfile:
                let state = RemoteClientStreamingFeedProfile.makeInitialState()
                streamingFeedProfileState = state
                latestScreen = RemoteClientStreamingFeedProfile.screen(
                    for: state,
                    session: session,
                    controller: .mac,
                    terminalColumns: 80,
                    terminalRows: 24
                )
            case .thinkingDiagnosis:
                latestScreen = SessionScreen(
                    session: session,
                    primarySurface: .structuredActivityFeed,
                    controller: .mac,
                    transcript: "Pi shared Session stream connected\nPi: thinking step 0",
                    activityItems: [
                        SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                        SessionActivityItem(kind: .message, text: "Pi: thinking step 0")
                    ],
                    isAgentTurnInProgress: true
                )
            case .invalidationBaseline:
                latestScreen = SessionScreen(
                    session: session,
                    primarySurface: .structuredActivityFeed,
                    controller: .mac,
                    transcript: "Pi shared Session stream connected",
                    activityItems: [
                        SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                        SessionActivityItem(kind: .message, text: "Pi: Profiling fixture ready")
                    ],
                    isAgentTurnInProgress: false
                )
            }
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
                controller: latestScreen.controller,
                transcript: latestScreen.transcript,
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows,
                activityItems: latestScreen.activityItems + [SessionActivityItem(kind: .status, text: "Fixture Session stopped")],
                approvalRequests: latestScreen.approvalRequests,
                extensionUI: latestScreen.extensionUI,
                slashCommands: latestScreen.slashCommands,
                providerEvents: latestScreen.providerEvents,
                providerFacts: latestScreen.providerFacts,
                finalOutputDiagnostic: latestScreen.finalOutputDiagnostic,
                isAgentTurnInProgress: false
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
            rebuildLatestScreen(
                controller: .pairedDevice(pairedMac.pairedDeviceID!),
                terminalColumns: columns,
                terminalRows: rows
            )
        }

        func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
            rebuildLatestScreen(
                controller: .mac,
                terminalColumns: latestScreen.terminalColumns,
                terminalRows: latestScreen.terminalRows
            )
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
            _ = onDisconnect

            let updateIntervalNanoseconds = mode == .streamingFeedProfile
                ? RemoteClientStreamingFeedProfile.updateIntervalNanoseconds
                : 750_000_000
            let task = Task {
                onUpdate(self.latestScreen)

                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: updateIntervalNanoseconds)
                    guard Task.isCancelled == false else {
                        break
                    }

                    let updatedScreen = self.advanceObservedScreen()
                    onUpdate(updatedScreen)
                }
            }

            return FixtureSessionScreenObservation {
                task.cancel()
            }
        }

        private func advanceObservedScreen() -> SessionScreen {
            if let state = streamingFeedProfileState {
                let updatedState = RemoteClientStreamingFeedProfile.advance(state)
                streamingFeedProfileState = updatedState
                latestScreen = RemoteClientStreamingFeedProfile.screen(
                    for: updatedState,
                    session: session,
                    controller: latestScreen.controller,
                    terminalColumns: latestScreen.terminalColumns,
                    terminalRows: latestScreen.terminalRows
                )
                return latestScreen
            }

            return appendAutoUpdate()
        }

        private func rebuildLatestScreen(
            controller: SessionController,
            terminalColumns: Int,
            terminalRows: Int
        ) -> SessionScreen {
            if let state = streamingFeedProfileState {
                latestScreen = RemoteClientStreamingFeedProfile.screen(
                    for: state,
                    session: latestScreen.session,
                    controller: controller,
                    terminalColumns: terminalColumns,
                    terminalRows: terminalRows
                )
                return latestScreen
            }

            latestScreen = SessionScreen(
                session: latestScreen.session,
                primarySurface: latestScreen.primarySurface,
                controller: controller,
                transcript: latestScreen.transcript,
                terminalColumns: terminalColumns,
                terminalRows: terminalRows,
                activityItems: latestScreen.activityItems,
                approvalRequests: latestScreen.approvalRequests,
                extensionUI: latestScreen.extensionUI,
                slashCommands: latestScreen.slashCommands,
                providerEvents: latestScreen.providerEvents,
                providerFacts: latestScreen.providerFacts,
                finalOutputDiagnostic: latestScreen.finalOutputDiagnostic,
                isAgentTurnInProgress: latestScreen.isAgentTurnInProgress
            )
            return latestScreen
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
                slashCommands: latestScreen.slashCommands,
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
                slashCommands: latestScreen.slashCommands,
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
