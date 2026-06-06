#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import Testing

struct NexusServiceStructuredSessionObserverPriorityTests {
    @Test func structuredSessionObserverReceivesFinalOutputBeforeRuntimeMetadataPersistenceFinishes() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let saveCoordinator = BlockingMetadataSaveCoordinator()
        var blockingStore: BlockingMetadataSaveSessionRecordStore?
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: ObservationPriorityRuntimeLauncher()),
            sessionRecordStoreFactory: { metadataStore in
                let store = BlockingMetadataSaveSessionRecordStore(
                    base: MetadataStoreSessionRecordStore(metadataStore: metadataStore),
                    coordinator: saveCoordinator
                )
                blockingStore = store
                return store
            },
            providerModuleRegistry: ServiceSessionProviderRegistry.providerModules(
                overrides: [
                    .pi: TestProviderModule(
                        providerID: .pi,
                        healthSummaryEvaluator: { _, _, _ in
                            ProviderHealthSummary(
                                state: .available,
                                summary: "Ready",
                                resolvedExecutable: "/tmp/pi",
                                launchability: .launchable
                            )
                        },
                        primarySurfaceEvaluator: { _ in .structuredActivityFeed }
                    )
                ]
            )
        )
        _ = try #require(blockingStore)

        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let sink = SessionScreenSink()
        let accumulatorBox = ObservationAccumulatorBox()
        let start = try service.observeSessionScreen(observationID: UUID(), sessionID: session.id) { update in
            guard let accumulator = accumulatorBox.value,
                  let screen = try? accumulator.apply(update) else {
                return
            }
            Task {
                await sink.record(screen)
            }
        }
        accumulatorBox.value = SessionScreenObservationAccumulator(start: start)

        saveCoordinator.armForNextSave()

        let sendTask = Task {
            try await service.sendSessionInput(sessionID: session.id, text: "finish")
        }

        await saveCoordinator.waitUntilSaveStarts()

        let observedScreen = await sink.nextScreen(timeoutNanoseconds: 200_000_000)
        #expect(observedScreen?.activityItems.last?.text == "Pi: done")
        #expect(observedScreen?.isAgentTurnInProgress == false)

        saveCoordinator.resumeSave()

        let responseScreen = try await sendTask.value
        #expect(responseScreen.activityItems.last?.text == "Pi: done")
        await saveCoordinator.waitUntilSaveCompletes()
    }
}

private final class BlockingMetadataSaveSessionRecordStore: SessionRecordStore {
    private let base: any SessionRecordStore
    private let coordinator: BlockingMetadataSaveCoordinator

    init(base: any SessionRecordStore, coordinator: BlockingMetadataSaveCoordinator) {
        self.base = base
        self.coordinator = coordinator
    }

    func defaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session? {
        try base.defaultSession(workspaceID: workspaceID, providerID: providerID)
    }

    func listSessions(workspaceID: UUID, providerID: ProviderID) throws -> [Session] {
        try base.listSessions(workspaceID: workspaceID, providerID: providerID)
    }

    func listAllSessions() throws -> [Session] {
        try base.listAllSessions()
    }

    func session(id: UUID) throws -> Session? {
        try base.session(id: id)
    }

    func createDefaultSession(
        workspaceID: UUID,
        providerID: ProviderID,
        state: Session.State,
        failureMessage: String?
    ) throws -> Session {
        try base.createDefaultSession(
            workspaceID: workspaceID,
            providerID: providerID,
            state: state,
            failureMessage: failureMessage
        )
    }

    func createNamedSession(
        workspaceID: UUID,
        providerID: ProviderID,
        name: String,
        state: Session.State,
        failureMessage: String?
    ) throws -> Session {
        try base.createNamedSession(
            workspaceID: workspaceID,
            providerID: providerID,
            name: name,
            state: state,
            failureMessage: failureMessage
        )
    }

    func updateSession(id: UUID, state: Session.State, failureMessage: String?) throws -> Session {
        try base.updateSession(id: id, state: state, failureMessage: failureMessage)
    }

    func updateSessionName(id: UUID, name: String?) throws -> Session {
        try base.updateSessionName(id: id, name: name)
    }

    func deleteSessionRecord(id: UUID) throws -> Bool {
        try base.deleteSessionRecord(id: id)
    }

    func launchSnapshot(sessionID: UUID) throws -> LaunchSnapshot? {
        try base.launchSnapshot(sessionID: sessionID)
    }

    func ensureLaunchSnapshot(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        primarySurface: SessionSurface,
        resolvedExecutable: String,
        resolvedWorkingDirectory: String
    ) throws -> LaunchSnapshot {
        try base.ensureLaunchSnapshot(
            sessionID: sessionID,
            workspaceID: workspaceID,
            providerID: providerID,
            primarySurface: primarySurface,
            resolvedExecutable: resolvedExecutable,
            resolvedWorkingDirectory: resolvedWorkingDirectory
        )
    }

    func updateLaunchSnapshotPrimarySurface(sessionID: UUID, primarySurface: SessionSurface) throws {
        try base.updateLaunchSnapshotPrimarySurface(sessionID: sessionID, primarySurface: primarySurface)
    }

    func sessionRecordAdapterMetadata(sessionID: UUID) throws -> SessionRecordAdapterMetadata? {
        try base.sessionRecordAdapterMetadata(sessionID: sessionID)
    }

    func saveSessionRecordAdapterMetadata(sessionID: UUID, metadata: SessionRecordAdapterMetadata) throws {
        guard coordinator.shouldBlockCurrentSave() else {
            try base.saveSessionRecordAdapterMetadata(sessionID: sessionID, metadata: metadata)
            return
        }

        coordinator.saveDidStart()
        coordinator.waitUntilResumed()
        try base.saveSessionRecordAdapterMetadata(sessionID: sessionID, metadata: metadata)
        coordinator.saveDidComplete()
    }

    func deleteSessionRecordAdapterMetadata(sessionID: UUID) throws {
        try base.deleteSessionRecordAdapterMetadata(sessionID: sessionID)
    }

    func updateSessionTerminalSize(id: UUID, columns: Int, rows: Int) throws {
        try base.updateSessionTerminalSize(id: id, columns: columns, rows: rows)
    }

    func sessionTerminalSize(id: UUID) throws -> (columns: Int, rows: Int) {
        try base.sessionTerminalSize(id: id)
    }

    func remoteRuntimeGeneration(sessionID: UUID) throws -> Int {
        try base.remoteRuntimeGeneration(sessionID: sessionID)
    }

    func advanceRemoteRuntimeGeneration(sessionID: UUID) throws -> Int {
        try base.advanceRemoteRuntimeGeneration(sessionID: sessionID)
    }
}

private final class BlockingMetadataSaveCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let saveStartedSemaphore = DispatchSemaphore(value: 0)
    private let saveCompletedSemaphore = DispatchSemaphore(value: 0)
    private let resumeSemaphore = DispatchSemaphore(value: 0)
    private var shouldBlockNextSave = false

    func armForNextSave() {
        lock.lock()
        shouldBlockNextSave = true
        lock.unlock()
    }

    func shouldBlockCurrentSave() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard shouldBlockNextSave else {
            return false
        }
        shouldBlockNextSave = false
        return true
    }

    func saveDidStart() {
        saveStartedSemaphore.signal()
    }

    func waitUntilSaveStarts() async {
        await wait(for: saveStartedSemaphore)
    }

    func resumeSave() {
        resumeSemaphore.signal()
    }

    func waitUntilResumed() {
        resumeSemaphore.wait()
    }

    func saveDidComplete() {
        saveCompletedSemaphore.signal()
    }

    func waitUntilSaveCompletes() async {
        await wait(for: saveCompletedSemaphore)
    }

    private func wait(for semaphore: DispatchSemaphore) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                semaphore.wait()
                continuation.resume()
            }
        }
    }
}

private final class ObservationPriorityRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        _ = session
        _ = workspace
        _ = launchConfiguration
        return ObservationPriorityRuntime()
    }
}

private final class ObservationPriorityRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    let sessionRecordAdapterMetadata = PiSessionLinkage(
        piSessionID: "pi-session-1",
        sessionFile: "/tmp/pi-session-1.json"
    ).sessionRecordAdapterMetadata

    private let lock = NSLock()
    private let statusItem = SessionActivityItem(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        kind: .status,
        text: "Pi thinking"
    )
    private let finalMessage = SessionActivityItem(
        id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        kind: .message,
        text: "Pi: done"
    )
    private var hasFinalOutput = false
    private var changeHandler: (@Sendable () -> Void)?

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let hasFinalOutput = self.hasFinalOutput
        lock.unlock()

        let activityItems = if hasFinalOutput {
            [statusItem, finalMessage]
        } else {
            [statusItem]
        }

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: hasFinalOutput ? "Pi: done" : "",
            activityItems: activityItems,
            isAgentTurnInProgress: hasFinalOutput == false
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func stop() throws {}

    func sendInput(_ text: String) throws {
        lock.lock()
        if text == "finish" {
            hasFinalOutput = true
        }
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }

    func sendText(_ text: String) throws {
        _ = text
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {
        _ = key
        _ = applicationCursorMode
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {
        _ = approvalRequestID
        _ = decision
    }

    func resize(columns: Int, rows: Int) throws {
        _ = columns
        _ = rows
    }
}

private final class ObservationAccumulatorBox: @unchecked Sendable {
    var value: SessionScreenObservationAccumulator?
}

private actor SessionScreenSink {
    private var screens: [SessionScreen] = []

    func record(_ screen: SessionScreen) {
        screens.append(screen)
    }

    func nextScreen(timeoutNanoseconds: UInt64) async -> SessionScreen? {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let screen = screens.first {
                screens.removeFirst()
                return screen
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }
}
#endif
