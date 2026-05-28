import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceStructuredSessionCopyTests {
    @Test func structuredInterruptedSessionFailureMessageUsesProviderDisplayName() {
        #expect(structuredInterruptedSessionFailureMessage(for: .pi) == "Pi Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime.")
        #expect(structuredInterruptedSessionFailureMessage(for: .codex) == "Codex Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime.")
    }

    @Test func restartedStructuredNonPiSessionStaysOnStructuredSurface() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        func makeService(sessionRuntimeManager: any SessionRuntimeManaging) throws -> NexusService {
            try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: StructuredCodexProviderHealthEvaluator(),
                sessionRuntimeManager: sessionRuntimeManager,
                providerAdapters: [
                    .codex: ServiceProviderAdapter(
                        providerID: .codex,
                        supportsDefaultSessionLaunch: true,
                        supportsNamedSessions: true,
                        healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                            providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
                        },
                        primarySurfaceEvaluator: { _ in .structuredActivityFeed }
                    )
                ]
            )
        }

        let service = try makeService(
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: StructuredCodexRuntimeLauncher())
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Structured Codex",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let restartedService = try makeService(sessionRuntimeManager: InMemorySessionRuntimeManager())
        let interruptedScreen = try restartedService.getSessionScreen(sessionID: session.id)

        let expectedMessage = "Codex Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."

        #expect(interruptedScreen.primarySurface == .structuredActivityFeed)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.transcript == expectedMessage)
        #expect(interruptedScreen.activityItems.map(\.kind) == [.error])
        #expect(interruptedScreen.activityItems.map(\.text) == [expectedMessage])
    }
}

private struct StructuredCodexProviderHealthEvaluator: ProviderHealthEvaluating {
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
        switch providerID {
        case .codex:
            ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/fake-codex",
                launchability: .launchable
            )
        default:
            ProviderHealthSummary(
                state: .notChecked,
                summary: "Not checked"
            )
        }
    }
}

private struct StructuredCodexRuntimeLauncher: SessionRuntimeLaunching {
    func makeRuntime(
        session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration
    ) async throws -> any SessionRuntime {
        StructuredCodexRuntime()
    }
}

private final class StructuredCodexRuntime: SessionRuntime, @unchecked Sendable {
    var state: Session.State = .ready
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

    func sessionScreen(for session: Session) -> SessionScreen {
        SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
    func stop() throws {}
    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
    func resize(columns: Int, rows: Int) throws {}
}
