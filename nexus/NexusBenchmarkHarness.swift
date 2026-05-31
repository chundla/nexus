import Foundation
import NexusDomain
import NexusIPC

enum NexusBenchmarkScenario: String, CaseIterable {
    case macTerminalBusy = "mac-terminal-busy"
    case macStructuredStreaming = "mac-structured-streaming"
    case iphoneTerminalBusy = "iphone-terminal-busy"
    case iphoneStructuredStreaming = "iphone-structured-streaming"

    enum Platform {
        case macOS
        case iOS
    }

    var platform: Platform {
        switch self {
        case .macTerminalBusy, .macStructuredStreaming:
            return .macOS
        case .iphoneTerminalBusy, .iphoneStructuredStreaming:
            return .iOS
        }
    }

    static func macOSScenario(from environment: [String: String]) -> NexusBenchmarkScenario? {
        scenario(from: environment, for: .macOS)
    }

    static func iOSScenario(from environment: [String: String]) -> NexusBenchmarkScenario? {
        scenario(from: environment, for: .iOS)
    }

    private static func scenario(
        from environment: [String: String],
        for platform: Platform
    ) -> NexusBenchmarkScenario? {
        guard let rawValue = environment["NEXUS_BENCHMARK_SCENARIO"],
              let scenario = NexusBenchmarkScenario(rawValue: rawValue),
              scenario.platform == platform else {
            return nil
        }

        return scenario
    }
}

struct NexusBenchmarkFixture {
    let workspaceGroup: WorkspaceGroup
    let workspace: Workspace
    let session: Session
    let frames: [SessionScreen]
    let stepDurationMilliseconds: UInt64

    var initialScreen: SessionScreen {
        frames[0]
    }

    static func make(for scenario: NexusBenchmarkScenario) -> NexusBenchmarkFixture {
        switch scenario {
        case .macStructuredStreaming, .iphoneStructuredStreaming:
            makeStructuredStreamingFixture(for: scenario)
        case .macTerminalBusy, .iphoneTerminalBusy:
            makeTerminalBusyFixture(for: scenario)
        }
    }

    private static func makeStructuredStreamingFixture(for scenario: NexusBenchmarkScenario) -> NexusBenchmarkFixture {
        let workspaceGroup = WorkspaceGroup(id: benchmarkUUID(1), name: "Benchmarks")
        let workspace = Workspace(
            id: benchmarkUUID(2),
            name: "Session Surface Lab",
            kind: .local,
            folderPath: "/tmp/nexus-session-surface-benchmark",
            primaryGroupID: workspaceGroup.id
        )
        let session = Session(
            id: benchmarkUUID(3),
            workspaceID: workspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )

        let activityItems: [SessionActivityItem] = [
            .init(id: benchmarkUUID(10), kind: .status, text: "Connected to the shared structured Session surface."),
            .init(id: benchmarkUUID(11), kind: .message, text: "Review the latest provider-health regressions and propose a compact fix plan.", prompt: SessionPrompt(text: "Review the latest provider-health regressions and propose a compact fix plan.")),
            .init(id: benchmarkUUID(12), kind: .progress, text: "Gathering workspace health snapshots…"),
            .init(id: benchmarkUUID(13), kind: .message, text: "I found three stale provider-health snapshots and one blocked Workspace Availability chain."),
            .init(id: benchmarkUUID(14), kind: .command, text: "rg \"Provider Health\" Modules/Sources/NexusService -n", detailText: "Modules/Sources/NexusService/WorkspaceCatalog.swift:341\nModules/Sources/NexusService/ProviderHealthFacts.swift:205\nModules/Sources/NexusService/ServiceSessionLifecycle.swift:150"),
            .init(id: benchmarkUUID(15), kind: .diff, text: "Drafted a WorkspaceCatalog refresh gate that keeps blocked checks compact.", detailText: "```diff\n- refresh stale workspace overview unconditionally\n+ refresh only when Host Validation is still available\n```"),
            .init(id: benchmarkUUID(16), kind: .message, text: "Next I will verify the remote **Session Surface Support** branch stays aligned with ADR-0029."),
            .init(id: benchmarkUUID(17), kind: .command, text: "swift test --filter WorkspaceCatalogTests/freshRemoteWorkspaceOverview", detailText: "Building for debugging…\n[3/7] Compiling NexusService WorkspaceCatalog.swift\nTest Case 'freshRemoteWorkspaceOverview' passed (0.118 seconds)."),
            .init(id: benchmarkUUID(18), kind: .approvalRequest, text: "Need approval to rewrite the shared refresh path before the final patch lands."),
            .init(id: benchmarkUUID(19), kind: .approvalDecision, text: "Approval granted. Continue with the shared refresh path rewrite."),
            .init(id: benchmarkUUID(20), kind: .progress, text: "Replaying structured activity on the iPhone Remote Client adapter…"),
            .init(id: benchmarkUUID(21), kind: .message, text: "The shared **Session Presentation** now stays in sync on macOS and iPhone without reprojecting the activity list twice."),
            .init(id: benchmarkUUID(22), kind: .command, text: "xcodebuild test -scheme nexus -destination 'platform=macOS'", detailText: "Test Suite 'Selected tests' started…\nTest Suite 'Selected tests' passed.\nExecuted 7 tests, with 0 failures in 1.213 seconds."),
            .init(id: benchmarkUUID(23), kind: .diff, text: "Captured the baseline recipe under docs/performance/live-session-surface-baseline.md.", detailText: "- build Release benchmark target\n- capture Time Profiler\n- capture SwiftUI trace\n- export compact call-tree summary"),
            .init(id: benchmarkUUID(24), kind: .message, text: "Summary: one busy terminal-backed **Session**, one streaming structured **Session**, and matching traces on macOS plus the iPhone **Remote Client**."),
            .init(id: benchmarkUUID(25), kind: .completion, text: "Structured benchmark stream finished.")
        ]

        let request = SessionApprovalRequest(
            id: benchmarkUUID(30),
            title: "Rewrite shared refresh gate?",
            text: "Allow the shared refresh gate rewrite before the baseline capture recipe is published.",
            state: .pending
        )

        let extensionUI = SessionExtensionUIState(
            title: "Benchmark telemetry",
            pendingDialogs: [],
            notifications: [
                .init(id: benchmarkUUID(40), kind: .info, message: "Streaming activity rows into the shared Session Presentation."),
                .init(id: benchmarkUUID(41), kind: .warning, message: "Keep iPhone capture scoped to the structured surface, not pairing chrome.")
            ],
            statuses: [
                .init(key: "render-pass", text: "Render pass: shared structured projection"),
                .init(key: "trace-state", text: "Trace target: Release benchmark harness")
            ],
            widgets: [
                .init(key: "Scope", lines: ["macOS structured surface", "iPhone Remote Client structured surface"], placement: .aboveEditor),
                .init(key: "Trace set", lines: ["Time Profiler", "SwiftUI"], placement: .belowEditor)
            ]
        )

        let frames = (0..<18).map { frameIndex -> SessionScreen in
            let visibleCount = min(activityItems.count, 4 + frameIndex)
            let currentItems = Array(activityItems.prefix(visibleCount))
            let pendingRequests = (8..<10).contains(frameIndex) ? [request] : []
            return SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: scenario.platform == .iOS ? .mac : .mac,
                transcript: currentItems.map(\.text).joined(separator: "\n"),
                activityItems: currentItems,
                approvalRequests: pendingRequests,
                extensionUI: extensionUI,
                slashCommands: [
                    SessionSlashCommand(name: "/trace", description: "Capture a Time Profiler tracer bullet.", source: .builtIn),
                    SessionSlashCommand(name: "/swiftui", description: "Capture the SwiftUI render baseline.", source: .builtIn)
                ],
                isAgentTurnInProgress: frameIndex < 17
            )
        }

        return NexusBenchmarkFixture(
            workspaceGroup: workspaceGroup,
            workspace: workspace,
            session: session,
            frames: frames,
            stepDurationMilliseconds: 350
        )
    }

    private static func makeTerminalBusyFixture(for scenario: NexusBenchmarkScenario) -> NexusBenchmarkFixture {
        let workspaceGroup = WorkspaceGroup(id: benchmarkUUID(101), name: "Benchmarks")
        let workspace = Workspace(
            id: benchmarkUUID(102),
            name: "Session Surface Lab",
            kind: .local,
            folderPath: "/tmp/nexus-session-surface-benchmark",
            primaryGroupID: workspaceGroup.id
        )
        let session = Session(
            id: benchmarkUUID(103),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )

        let rows = 34
        let columns = 118
        let totalFrames = 48
        let allLines = (0..<(rows + totalFrames + 12)).map { lineIndex in
            terminalLine(frameIndex: lineIndex, columns: columns)
        }

        let frames = (0..<totalFrames).map { frameIndex -> SessionScreen in
            let start = frameIndex
            let end = start + rows
            let visible = Array(allLines[start..<end])
            return SessionScreen(
                session: session,
                primarySurface: .terminal,
                controller: scenario.platform == .iOS ? .mac : .mac,
                transcript: visible.map(\.text).joined(separator: "\n"),
                terminalColumns: columns,
                terminalRows: rows,
                styledVisibleLines: visible,
                cursorRow: rows - 1,
                cursorColumn: min(columns - 1, 28 + (frameIndex % 36)),
                cursorVisible: frameIndex % 2 == 0
            )
        }

        return NexusBenchmarkFixture(
            workspaceGroup: workspaceGroup,
            workspace: workspace,
            session: session,
            frames: frames,
            stepDurationMilliseconds: 140
        )
    }

    private static func terminalLine(frameIndex: Int, columns: Int) -> TerminalLine {
        let timestamp = String(format: "[%02d:%02d:%02d]", 14, (frameIndex / 60) % 60, frameIndex % 60)
        let badge = frameIndex.isMultiple(of: 3) ? "diff" : (frameIndex.isMultiple(of: 2) ? "tool" : "task")
        let command = [
            "claude bash rg SessionScreen --glob '*.swift'",
            "codex build Release benchmark harness",
            "pi stream structured Session Presentation deltas"
        ][frameIndex % 3]
        let detail = [
            "8 matches · 3 files",
            "SwiftUI trace warmup ready",
            "controller remains on this Mac"
        ][frameIndex % 3]

        let rawText = "\(timestamp)  \(badge.uppercased())  \(command)  —  \(detail)"
        let paddedText = rawText.padding(toLength: columns, withPad: " ", startingAt: 0)
        let prefixCount = min(timestamp.count + 2, paddedText.count)
        let badgeEnd = min(prefixCount + badge.count + 4, paddedText.count)
        let detailStart = max(prefixCount, paddedText.count - detail.count - 2)

        let prefix = String(paddedText.prefix(prefixCount))
        let badgeSlice = String(paddedText[paddedText.index(paddedText.startIndex, offsetBy: prefixCount)..<paddedText.index(paddedText.startIndex, offsetBy: badgeEnd)])
        let middleSlice = String(paddedText[paddedText.index(paddedText.startIndex, offsetBy: badgeEnd)..<paddedText.index(paddedText.startIndex, offsetBy: detailStart)])
        let detailSlice = String(paddedText.suffix(paddedText.count - detailStart))

        return TerminalLine(cells: [
            TerminalCell(text: prefix, style: TerminalStyle(foregroundColor: .ansi256(244))),
            TerminalCell(text: badgeSlice, style: TerminalStyle(foregroundColor: .ansi256(frameIndex.isMultiple(of: 2) ? 222 : 153), isBold: true)),
            TerminalCell(text: middleSlice, style: TerminalStyle(foregroundColor: .ansi256(250))),
            TerminalCell(text: detailSlice, style: TerminalStyle(foregroundColor: .ansi256(frameIndex.isMultiple(of: 2) ? 80 : 216), isItalic: true))
        ])
    }

    private static func benchmarkUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private struct BenchmarkUnavailableError: LocalizedError {
    let operation: String

    var errorDescription: String? {
        "The Nexus benchmark harness does not support \(operation)."
    }
}

private struct NexusBenchmarkPlayer {
    let fixture: NexusBenchmarkFixture

    func run(update: @MainActor @escaping (SessionScreen) -> Void) async {
        var frameIndex = 1
        while Task.isCancelled == false {
            try? await Task.sleep(nanoseconds: fixture.stepDurationMilliseconds * 1_000_000)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                update(fixture.frames[frameIndex])
            }
            frameIndex = (frameIndex + 1) % fixture.frames.count
        }
    }
}

#if os(macOS)
import SwiftUI

private struct BenchmarkNexusServiceClient: NexusServiceClient {
    private func unsupported(_ operation: String) -> BenchmarkUnavailableError {
        BenchmarkUnavailableError(operation: operation)
    }

    func getServiceStatus() async throws -> NexusServiceStatus {
        throw unsupported(#function)
    }

    func listWorkspaceGroups() async throws -> [WorkspaceGroup] {
        throw unsupported(#function)
    }

    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        throw unsupported(#function)
    }

    func listWorkspaces() async throws -> [Workspace] {
        throw unsupported(#function)
    }

    func listHosts() async throws -> [NexusDomain.Host] {
        throw unsupported(#function)
    }

    func getHostDetail(hostID: UUID) async throws -> NexusDomain.HostDetail {
        throw unsupported(#function)
    }

    func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        throw unsupported(#function)
    }

    func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        throw unsupported(#function)
    }

    func validateHost(hostID: UUID) async throws -> HostValidationSnapshot {
        throw unsupported(#function)
    }

    func deleteHost(hostID: UUID) async throws -> Bool {
        throw unsupported(#function)
    }

    func listRecentNavigation(limit: Int) async throws -> [NavigationItem] {
        throw unsupported(#function)
    }

    func recordNavigation(target: NavigationTarget) async throws {
        throw unsupported(#function)
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        throw unsupported(#function)
    }

    func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) async throws {
        throw unsupported(#function)
    }

    func listPerformanceDiagnostics(limit: Int) async throws -> [PerformanceDiagnosticRecord] {
        throw unsupported(#function)
    }

    func getRemoteAccessState() async throws -> RemoteAccessState {
        throw unsupported(#function)
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState {
        throw unsupported(#function)
    }

    func startPairing() async throws -> PairingCeremony {
        throw unsupported(#function)
    }

    func completePairing(pairingCode: String, deviceName: String) async throws -> PairedDevice {
        throw unsupported(#function)
    }

    func listPairedDevices() async throws -> [PairedDevice] {
        throw unsupported(#function)
    }

    func revokePairedDevice(deviceID: UUID) async throws -> Bool {
        throw unsupported(#function)
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        throw unsupported(#function)
    }

    func refreshWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        throw unsupported(#function)
    }

    func getWorkspaceOverviews(workspaceIDs: [UUID]) async throws -> [WorkspaceOverview] {
        throw unsupported(#function)
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        throw unsupported(#function)
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        throw unsupported(#function)
    }

    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace {
        throw unsupported(#function)
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        throw unsupported(#function)
    }

    func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        throw unsupported(#function)
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        throw unsupported(#function)
    }

    func stopSession(sessionID: UUID) async throws -> Session {
        throw unsupported(#function)
    }

    func deleteSessionRecord(sessionID: UUID) async throws -> Bool {
        throw unsupported(#function)
    }

    func getSessionRecord(sessionID: UUID) async throws -> Session {
        throw unsupported(#function)
    }

    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation {
        throw unsupported(#function)
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func respondToApprovalRequest(sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func respondToExtensionDialog(sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func respondToRemoteApprovalRequest(sessionID: UUID, pairedDeviceID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func respondToRemoteExtensionDialog(sessionID: UUID, pairedDeviceID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        throw unsupported(#function)
    }
}

extension NexusAppModel {
    static func placeholderBenchmarkModel() -> NexusAppModel {
        NexusAppModel(client: BenchmarkNexusServiceClient())
    }

    static func benchmark(fixture: NexusBenchmarkFixture) -> NexusAppModel {
        let model = placeholderBenchmarkModel()
        model.workspaceGroups = [fixture.workspaceGroup]
        model.workspaces = [fixture.workspace]
        model.focusedSessionScreen = fixture.initialScreen
        return model
    }
}

struct NexusMacBenchmarkHostView: View {
    private let fixture: NexusBenchmarkFixture
    @State private var appModel: NexusAppModel
    private let player: NexusBenchmarkPlayer

    init(scenario: NexusBenchmarkScenario) {
        let fixture = NexusBenchmarkFixture.make(for: scenario)
        self.fixture = fixture
        self.player = NexusBenchmarkPlayer(fixture: fixture)
        _appModel = State(initialValue: NexusAppModel.benchmark(fixture: fixture))
    }

    var body: some View {
        ContentView(
            appModel: appModel,
            forcedSessionID: fixture.session.id,
            showsSidebar: false,
            autoRefresh: false,
            allowsInteractions: false
        )
        .task {
            await player.run { frame in
                appModel.focusedSessionScreen = frame
            }
        }
    }
}
#endif

#if os(iOS)
import SwiftUI

private struct BenchmarkPairedMacStore: PairedMacStore {
    func loadPairedMacs() -> [PairedMac] { [] }
    func savePairedMacs(_ pairedMacs: [PairedMac]) throws {}
    func loadActivePairedMacID() -> PairedMac.ID? { nil }
    func saveActivePairedMacID(_ activePairedMacID: PairedMac.ID?) {}
}

private struct BenchmarkRemotePairingClient: RemotePairingClient {
    private func unsupported(_ operation: String) -> BenchmarkUnavailableError {
        BenchmarkUnavailableError(operation: operation)
    }

    func fetchStatus(host: String, port: Int) async throws -> RemotePairedMacStatus {
        throw unsupported(#function)
    }

    func completePairing(host: String, port: Int, pairingCode: String, deviceName: String) async throws -> PairedMac {
        throw unsupported(#function)
    }

    func fetchCatalog(for pairedMac: PairedMac) async throws -> RemoteWorkspaceCatalog {
        throw unsupported(#function)
    }

    func fetchProviderDetail(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        throw unsupported(#function)
    }

    func launchOrResumeDefaultSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        throw unsupported(#function)
    }

    func createNamedSession(for pairedMac: PairedMac, workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        throw unsupported(#function)
    }

    func launchOrResumeSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
        throw unsupported(#function)
    }

    func stopSession(for pairedMac: PairedMac, sessionID: UUID) async throws -> Session {
        throw unsupported(#function)
    }

    func deleteSessionRecord(for pairedMac: PairedMac, sessionID: UUID) async throws -> Bool {
        throw unsupported(#function)
    }

    func fetchSessionScreen(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func takeSessionControl(for pairedMac: PairedMac, sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func releaseSessionControl(for pairedMac: PairedMac, sessionID: UUID) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionInput(for pairedMac: PairedMac, sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func respondToApprovalRequest(for pairedMac: PairedMac, sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func respondToExtensionDialog(for pairedMac: PairedMac, sessionID: UUID, dialogID: String, response: SessionExtensionUIDialogResponse) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionText(for pairedMac: PairedMac, sessionID: UUID, text: String) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func sendSessionInputKey(for pairedMac: PairedMac, sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        throw unsupported(#function)
    }

    func observeSessionScreen(
        for pairedMac: PairedMac,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void,
        onDisconnect: @escaping @Sendable (any Error) -> Void
    ) async throws -> any SessionScreenObservation {
        throw unsupported(#function)
    }
}

extension RemoteClientPairingModel {
    static func benchmark(fixture: NexusBenchmarkFixture) -> RemoteClientPairingModel {
        let model = RemoteClientPairingModel(client: BenchmarkRemotePairingClient(), store: BenchmarkPairedMacStore())
        let pairedMac = PairedMac(name: "Benchmark Mac", host: "127.0.0.1", port: 9234, pairedAt: .distantPast)
        model.pairedMacs = [pairedMac]
        model.activePairedMacID = pairedMac.id
        model.pairedMacAvailability[pairedMac.id] = .available
        model.focusedSessionID = fixture.session.id
        model.focusedSessionScreen = fixture.initialScreen
        model.focusedSessionIsStale = false
        model.focusedSessionErrorMessage = nil
        return model
    }
}

struct NexusRemoteBenchmarkHostView: View {
    private let fixture: NexusBenchmarkFixture
    @State private var model: RemoteClientPairingModel
    private let player: NexusBenchmarkPlayer

    init(scenario: NexusBenchmarkScenario) {
        let fixture = NexusBenchmarkFixture.make(for: scenario)
        self.fixture = fixture
        self.player = NexusBenchmarkPlayer(fixture: fixture)
        _model = State(initialValue: RemoteClientPairingModel.benchmark(fixture: fixture))
    }

    var body: some View {
        NavigationStack {
            RemoteSessionScreenView(model: model, session: fixture.session, benchmarkMode: true)
        }
        .task {
            await player.run { frame in
                model.focusedSessionScreen = frame
            }
        }
    }
}
#endif
