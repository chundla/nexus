import Foundation
import Testing
@testable import nexus

@MainActor
struct RemoteClientProfilingFixtureTests {
    @Test func bootstrapSeedsActivePairedMacAndWorkspaceCatalogForInvalidationProfiling() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "invalidation-baseline"
        ])

        let pairedMac = try #require(model.activePairedMac)
        #expect(pairedMac.name == "Profiling Mac")

        await model.refreshPairedMacAvailability()
        #expect(model.availability(for: pairedMac) == .available)

        await model.refreshActivePairedMacCatalog()
        let presentation = try #require(model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil as UUID?))

        #expect(presentation.workspaceOverviews.map { $0.workspace.name } == [
            "Baseline API",
            "Baseline iPhone"
        ])
    }

    @Test func bootstrapStreamsFocusedSessionUpdatesForInvalidationProfiling() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "invalidation-baseline"
        ])

        await model.refreshActivePairedMacCatalog()
        let session = try await model.launchOrResumeDefaultSession(
            workspaceID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerID: .pi
        )

        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0 ..< 20 where model.focusedSessionScreen == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let initialScreen = try #require(model.focusedSessionScreen)
        #expect(initialScreen.transcript.contains("Pi shared Session stream connected"))

        for _ in 0 ..< 30 where model.focusedSessionScreen?.transcript == initialScreen.transcript {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let updatedScreen = try #require(model.focusedSessionScreen)
        #expect(updatedScreen.session.id == session.id)
        #expect(updatedScreen.transcript.contains("Fixture update 1"))
        #expect(model.focusedSessionWorkspaceLocation == "Build Server • /srv/baseline-api")
    }
}
