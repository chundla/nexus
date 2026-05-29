#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct ServiceSessionLifecycleScenariosTests {
    @Test func launchOrResumeDefaultSessionReusesExistingDefaultSessionLane() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let existingSession = try fixture.store.createDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            state: .ready,
            failureMessage: nil
        )
        let lifecycle = fixture.makeLifecycle()

        let resumedSession = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude
        )

        #expect(resumedSession.id == existingSession.id)
        #expect(fixture.tracker.resumedSessions.map { $0.0.id } == [existingSession.id])
        #expect(fixture.tracker.freshLaunches.isEmpty)
    }

    @Test func createNamedSessionCreatesReadyNamedSessionAndLaunchSnapshot() async throws {
        let fixture = try ServiceSessionLifecycleFixture()
        let lifecycle = fixture.makeLifecycle()

        let namedSession = try await lifecycle.createNamedSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude,
            name: "Review"
        )
        let persistedSession = try #require(try fixture.store.session(id: namedSession.id))
        let launch = try #require(fixture.tracker.freshLaunches.first)
        let launchSnapshot = try #require(try fixture.store.launchSnapshot(sessionID: namedSession.id))

        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Review")
        #expect(namedSession.state == .ready)
        #expect(persistedSession == namedSession)
        #expect(fixture.tracker.resumedSessions.isEmpty)
        #expect(launch.session.id == namedSession.id)
        #expect(launch.workspace.id == fixture.workspace.id)
        #expect(launch.launchSnapshot.resolvedExecutable == "/tmp/claude")
        #expect(launchSnapshot.sessionID == namedSession.id)
        #expect(launchSnapshot.primarySurface == .terminal)
        #expect(launchSnapshot.resolvedWorkingDirectory == fixture.workspace.folderPath)
    }

    @Test func failedDefaultLaunchCreatesInspectableFailedSessionRecord() async throws {
        let fixture = try ServiceSessionLifecycleFixture(
            health: ProviderHealthSummary(
                state: .misconfigured,
                summary: "Claude needs login",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "auth-required",
                        message: "Claude needs login"
                    )
                ]
            )
        )
        let lifecycle = fixture.makeLifecycle()

        let failedSession = try await lifecycle.launchOrResumeDefaultSession(
            workspaceID: fixture.workspace.id,
            providerID: .claude
        )
        let persistedSession = try #require(try fixture.store.session(id: failedSession.id))

        #expect(failedSession.isDefault)
        #expect(failedSession.state == .failed)
        #expect(failedSession.failureMessage == "Claude needs login")
        #expect(persistedSession == failedSession)
        #expect(fixture.tracker.resumedSessions.isEmpty)
        #expect(fixture.tracker.freshLaunches.isEmpty)
        #expect(try fixture.store.launchSnapshot(sessionID: failedSession.id) == nil)
    }
}

private struct ServiceSessionLifecycleFixture {
    let rootURL: URL
    let workspace: Workspace
    let store: NexusMetadataStore
    let tracker = SessionLifecycleTracker()
    let health: ProviderHealthSummary

    init(
        health: ProviderHealthSummary = ProviderHealthSummary(
            state: .available,
            summary: "Ready",
            resolvedExecutable: "/tmp/claude",
            launchability: .launchable
        )
    ) throws {
        self.health = health
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        store = try NexusMetadataStore(storeURL: rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false))
        let group = try store.createWorkspaceGroup(name: "Solo Group")
        workspace = try store.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
    }

    func makeLifecycle() -> ServiceSessionLifecycle {
        ServiceSessionLifecycle(
            dependencies: ServiceSessionLifecycleDependencies(
                metadataStore: store,
                providerAdapter: { providerID in
                    ServiceProviderAdapter(
                        providerID: providerID,
                        supportsDefaultSessionLaunch: true,
                        supportsNamedSessions: true,
                        healthSummaryEvaluator: { _, _, _ in health }
                    )
                },
                remoteWorkspaceHealthContext: { _ in Optional<RemoteWorkspaceHealthContext>.none },
                providerHealthSummary: { _, _, _ in health },
                resolveNamedSessionName: { requestedName, _ in requestedName ?? "Session 1" },
                launchOrResumePersistedSession: { session, workspace in
                    tracker.resumedSessions.append((session, workspace))
                    return session
                },
                launchFreshSession: { session, workspace, launchSnapshot in
                    tracker.freshLaunches.append((session, workspace, launchSnapshot))
                    return session
                }
            )
        )
    }
}

private final class SessionLifecycleTracker: @unchecked Sendable {
    var resumedSessions: [(Session, Workspace)] = []
    var freshLaunches: [(session: Session, workspace: Workspace, launchSnapshot: LaunchSnapshot)] = []
}
#endif
