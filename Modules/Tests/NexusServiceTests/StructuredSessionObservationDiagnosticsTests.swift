#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import Testing

struct StructuredSessionObservationDiagnosticsTests {
    @Test func structuredObservationSnapshotIsListedInRecentPerformanceDiagnostics() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: StructuredObservationDiagnosticProviderHealthFacts(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StructuredObservationDiagnosticRuntimeLauncher())
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        _ = try service.getSessionScreenObservationSnapshot(sessionID: session.id)

        let diagnostics = try service.listPerformanceDiagnostics(limit: 10)
        let record = try #require(diagnostics.filter {
            $0.operation == .structuredSessionObservation && $0.metrics["snapshotBuildCount"] == 1
        }.first)

        #expect(record.workspaceID == workspace.id)
        #expect(record.providerID == .pi)
        #expect(record.sessionID == session.id)
        #expect(record.steps.contains(where: { $0.name == "buildStructuredSnapshot" }))
        #expect(record.metrics["activityItemCount"] == 1)
        #expect(record.metrics["approvalRequestCount"] == 0)
        #expect(record.metrics["providerEventCount"] == 0)
    }

    @Test func structuredObservationDeltaIsListedInRecentPerformanceDiagnostics() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: StructuredObservationDiagnosticProviderHealthFacts(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StructuredObservationDiagnosticRuntimeLauncher())
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        _ = try service.getSessionScreenObservationSnapshot(sessionID: session.id)
        _ = try await service.sendSessionInput(sessionID: session.id, text: "deploy")

        let diagnostics = try service.listPerformanceDiagnostics(limit: 10)
        let record = try #require(diagnostics.filter {
            $0.operation == .structuredSessionObservation && $0.metrics["deltaBuildCount"] == 1
        }.first)

        #expect(record.workspaceID == workspace.id)
        #expect(record.providerID == .pi)
        #expect(record.sessionID == session.id)
        #expect(record.steps.contains(where: { $0.name == "buildStructuredDelta" }))
        #expect(record.metrics["changeCount"] == 3)
        #expect(record.metrics["activityItemCount"] == 3)
        #expect(record.metrics["approvalRequestCount"] == 1)
    }

    @Test func structuredObservationDeltaDiagnosticCountsFullReplaceFallbacks() throws {
        let recorder = PerformanceDiagnosticRecorder()
        let store = StructuredSessionObservationStore(recordPerformanceDiagnostic: recorder.record)
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)

        _ = store.snapshotResponse(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [SessionActivityItem(kind: .status, text: "Pi ready")]
            )
        )
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [SessionActivityItem(kind: .message, text: "Different item")]
            )
        )

        let record = try #require(recorder.records.filter {
            $0.metrics["deltaBuildCount"] == 1
        }.first)

        #expect(record.steps.contains(where: { $0.name == "buildStructuredDelta" }))
        #expect(record.metrics["fullReplaceFallbackCount"] == 1)
        #expect(record.metrics["fullReplaceActivityItemsCount"] == 1)
        #expect(record.metrics["fullReplaceProviderEventsCount"] == 0)
    }

    @Test func structuredObservationDeltaUsesTailActivityReplacementWhenSharedPrefixStaysStable() throws {
        let recorder = PerformanceDiagnosticRecorder()
        let store = StructuredSessionObservationStore(recordPerformanceDiagnostic: recorder.record)
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let statusItem = SessionActivityItem(id: UUID(), kind: .status, text: "Pi ready")
        let progressItem = SessionActivityItem(id: UUID(), kind: .progress, text: "Streaming 50%")
        let updatedProgressItem = SessionActivityItem(id: progressItem.id, kind: .progress, text: "Streaming 100%")
        let completionItem = SessionActivityItem(kind: .completion, text: "Done")

        _ = store.snapshotResponse(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [statusItem, progressItem]
            )
        )
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [statusItem, updatedProgressItem, completionItem]
            )
        )

        let updates = store.updates(for: session.id, after: 0)
        #expect(updates == [
            .structuredDelta(
                StructuredSessionObservationDelta(
                    baseRevision: 0,
                    revision: 1,
                    changes: [
                        .replaceActivityItemRange(startIndex: 1, items: [updatedProgressItem, completionItem])
                    ]
                )
            )
        ])

        let record = try #require(recorder.records.filter {
            $0.metrics["deltaBuildCount"] == 1
        }.first)

        #expect(record.metrics["activityItemRangeReplaceCount"] == 1)
        #expect(record.metrics["fullReplaceFallbackCount"] == 0)
    }

    @Test func structuredObservationGapDiagnosticIsRecordedWhenRevisionHistoryFallsBehind() throws {
        let recorder = PerformanceDiagnosticRecorder()
        let store = StructuredSessionObservationStore(maxRetainedDeltas: 1, recordPerformanceDiagnostic: recorder.record)
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let statusItem = SessionActivityItem(id: UUID(), kind: .status, text: "Pi ready")
        let firstMessage = SessionActivityItem(id: UUID(), kind: .message, text: "First")
        let secondMessage = SessionActivityItem(id: UUID(), kind: .message, text: "Second")

        _ = store.snapshotResponse(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [statusItem]
            )
        )
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "first",
                activityItems: [statusItem, firstMessage]
            )
        )
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "second",
                activityItems: [statusItem, firstMessage, secondMessage]
            )
        )

        let updates = store.updates(for: session.id, after: 0)
        #expect(updates == [.structuredGap(currentRevision: 2)])

        let record = try #require(recorder.records.filter {
            $0.metrics["gapFallbackCount"] == 1
        }.first)

        #expect(record.steps.contains(where: { $0.name == "resolveStructuredGap" }))
        #expect(record.metrics["requestedRevision"] == 0)
        #expect(record.metrics["currentRevision"] == 2)
        #expect(record.metrics["retainedDeltaCount"] == 1)
    }

    @Test func structuredObservationDeltaRecordsFinalOutputLatencyMetrics() throws {
        let recorder = PerformanceDiagnosticRecorder()
        let uptime = StructuredObservationDiagnosticUptimeClock()
        let store = StructuredSessionObservationStore(
            recordPerformanceDiagnostic: recorder.record,
            currentDate: { Date(timeIntervalSince1970: 123) },
            currentUptimeNanoseconds: uptime.now
        )
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let statusItem = SessionActivityItem(id: UUID(), kind: .status, text: "Pi ready")
        let finalMessage = SessionActivityItem(id: UUID(), kind: .message, text: "Pi: done")

        uptime.value = 100_000_000
        _ = store.snapshotResponse(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "",
                activityItems: [statusItem]
            )
        )

        uptime.value = 200_000_000
        store.recordChange(
            for: SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: "Pi: done",
                activityItems: [statusItem, finalMessage],
                finalOutputDiagnostic: StructuredSessionFinalOutputDiagnostic(
                    trigger: .turnEnd,
                    providerEventSequence: 9,
                    providerRuntimeLatencyMilliseconds: 4,
                    expectedActivityItemID: finalMessage.id,
                    expectedActivityItemText: finalMessage.text,
                    expectedThinkingIndicatorVisible: false,
                    serviceObservationAnchorUptimeNanoseconds: 190_000_000
                )
            )
        )

        let matchingRecords = recorder.records.filter {
            $0.metrics["deltaBuildCount"] == 1 && $0.metrics["finalOutputLatencyCount"] == 1
        }
        let record = try #require(matchingRecords.first)

        #expect(record.metrics["finalOutputProviderRuntimeMilliseconds"] == 4)
        #expect(record.metrics["finalOutputServiceObservationMilliseconds"] == 10)
        #expect(record.metrics["finalOutputTriggerTurnEndCount"] == 1)
        #expect(record.metrics["finalOutputTriggerTextDeltaCount"] == 0)
        #expect(record.metrics["finalOutputProviderEventSequence"] == 9)
    }
}

private struct StructuredObservationDiagnosticProviderHealthFacts: ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        ProviderID.allCases.map { providerID in
            WorkspaceProviderCard(
                provider: Provider(id: providerID),
                health: healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext),
                defaultSession: ProviderDefaultSessionSummary(
                    state: .notCreated,
                    summary: "No default session yet",
                    actionTitle: "Launch"
                )
            )
        }
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        _ = workspace
        _ = remoteContext
        if providerID == .pi {
            return ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/pi",
                launchability: .launchable
            )
        }
        return ProviderHealthSummary(state: .notChecked, summary: "Health checks coming soon")
    }
}

private final class PerformanceDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [PerformanceDiagnosticRecord] = []

    func record(_ record: PerformanceDiagnosticRecord) {
        lock.lock()
        records.append(record)
        lock.unlock()
    }
}

private final class StructuredObservationDiagnosticUptimeClock: @unchecked Sendable {
    var value: UInt64 = 0

    func now() -> UInt64 {
        value
    }
}

private final class StructuredObservationDiagnosticRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        _ = session
        _ = workspace
        _ = launchConfiguration
        return StructuredObservationDiagnosticRuntime()
    }
}

private final class StructuredObservationDiagnosticRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let lock = NSLock()
    private var hasPendingApproval = false
    private var approvalRequest = SessionApprovalRequest(title: "Deploy?", text: "Deploy?", state: .pending)
    private var changeHandler: (@Sendable () -> Void)?

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let hasPendingApproval = self.hasPendingApproval
        let approvalRequest = self.approvalRequest
        lock.unlock()

        var activityItems = [SessionActivityItem(kind: .status, text: "Pi ready")]
        var approvalRequests: [SessionApprovalRequest] = []
        var transcript = ""

        if hasPendingApproval {
            transcript = "> deploy"
            activityItems.append(SessionActivityItem(kind: .message, text: "You: deploy"))
            activityItems.append(SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy?"))
            approvalRequests = [approvalRequest]
        }

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: transcript,
            activityItems: activityItems,
            approvalRequests: approvalRequests
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
        if text == "deploy" {
            hasPendingApproval = true
            approvalRequest = SessionApprovalRequest(id: approvalRequest.id, title: "Deploy?", text: "Deploy?", state: .pending)
        }
        let changeHandler = self.changeHandler
        lock.unlock()
        changeHandler?()
    }

    func sendText(_ text: String) throws { _ = text }
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
#endif
