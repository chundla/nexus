#if os(macOS)
import Foundation
import NexusDomain
import NexusIPC
@testable import NexusService
import NexusSessionPresentation
import Testing

struct StructuredSessionThinkingStallDiagnosisTests {
    @Test func macOSStructuredObservationFixtureAttributesStuckThinkingToObservationLayer() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ThinkingObservationDiagnosticProviderHealthFacts(),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: ThinkingObservationDiagnosticRuntimeLauncher())
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Pi",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try await service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let previousSnapshot = try service.getSessionScreenObservationSnapshot(sessionID: session.id)
        let previousService = StructuredSessionObservationProgressSample(
            screen: previousSnapshot.screen,
            structuredRevision: previousSnapshot.structuredSnapshot?.revision
        )
        let previousClientPresentation = StructuredSessionPresentationProgressSample(
            presentation: try #require(FocusedStructuredSessionPresenter().presentation(for: previousSnapshot.screen))
        )

        _ = try await service.sendSessionInput(sessionID: session.id, text: "advance")

        let currentSnapshot = try service.getSessionScreenObservationSnapshot(sessionID: session.id)
        let currentService = StructuredSessionObservationProgressSample(
            screen: currentSnapshot.screen,
            structuredRevision: currentSnapshot.structuredSnapshot?.revision
        )

        let attribution = structuredSessionThinkingStallAttribution(
            previousService: previousService,
            currentService: currentService,
            previousClientObservation: previousService,
            currentClientObservation: previousService,
            previousClientPresentation: previousClientPresentation,
            currentClientPresentation: previousClientPresentation
        )

        #expect(currentService.isAgentTurnInProgress)
        #expect(currentService.activityItemCount > previousService.activityItemCount)
        #expect(attribution.layer == .observation)
    }
}

private struct ThinkingObservationDiagnosticProviderHealthFacts: ProviderHealthEvaluating {
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

private final class ThinkingObservationDiagnosticRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        _ = session
        _ = workspace
        _ = launchConfiguration
        return ThinkingObservationDiagnosticRuntime()
    }
}

private final class ThinkingObservationDiagnosticRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    private let lock = NSLock()
    private var step = 0
    private var changeHandler: (@Sendable () -> Void)?

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let step = self.step
        lock.unlock()

        let statusItem = SessionActivityItem(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            kind: .status,
            text: "Thinking turn active"
        )
        let progressItems = (0...step).map { step in
            SessionActivityItem(kind: .message, text: "Pi: thinking step \(step)")
        }

        return SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: progressItems.map(\.text).joined(separator: "\n"),
            activityItems: [statusItem] + progressItems,
            isAgentTurnInProgress: true
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
        if text == "advance" {
            step += 1
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
