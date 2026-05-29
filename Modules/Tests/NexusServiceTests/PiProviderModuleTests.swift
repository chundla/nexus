#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct PiProviderModuleTests {
    @Test func piProviderModuleOwnsLocalOpenSessionSeamButLeavesRemoteOpenToSharedFallback() async throws {
        let module = PiProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(state: .available, summary: "Ready", resolvedExecutable: "/tmp/fake-pi", launchability: .launchable)
                }
            )
        )
        let localWorkspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )
        let remoteWorkspace = Workspace(
            id: UUID(),
            name: "Remote Pi",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )
        let fallbackCounter = FallbackCounter()
        let fallbackSession = Session(
            id: UUID(),
            workspaceID: localWorkspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )

        let localOpen = try await module.openSession(
            .launchOrResumeDefaultSession(workspace: localWorkspace, providerID: .pi),
            openFallback: {
                fallbackCounter.value += 1
                return fallbackSession
            }
        )
        let remoteOpen = try await module.openSession(
            .launchOrResumeDefaultSession(workspace: remoteWorkspace, providerID: .pi),
            openFallback: {
                fallbackCounter.value += 1
                return fallbackSession
            }
        )

        #expect(localOpen == fallbackSession)
        #expect(remoteOpen == nil)
        #expect(fallbackCounter.value == 1)
    }

    @Test func piProviderModulePreservesPiCatalogReadBehavior() async {
        let module = PiProviderModule(
            adapter: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(
                        state: .available,
                        summary: "Pi module health",
                        resolvedExecutable: "/tmp/fake-pi",
                        launchability: .launchable
                    )
                },
                primarySurfaceEvaluator: { _ in .terminal },
                shouldReuseRemoteHealthSnapshot: { snapshot, _ in
                    snapshot.summary == "reuse me"
                }
            )
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Local Pi",
            kind: .local,
            folderPath: "/tmp/local-pi",
            primaryGroupID: UUID()
        )

        let health = await module.providerHealthSummary(
            for: workspace,
            remoteContext: nil,
            providerHealthEvaluator: UnusedPiProviderHealthEvaluator()
        )
        let capabilities = module.providerCapabilities(in: workspace, health: health, defaultSession: nil)

        #expect(health.summary == "Pi module health")
        #expect(capabilities.launchDefaultSession.isEnabled)
        #expect(capabilities.createNamedSession.isEnabled)
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
        #expect(module.reusesRemoteHealthSnapshot(ProviderHealthSummary(state: .available, summary: "reuse me"), remoteContext: nil))
    }
}

private final class FallbackCounter: @unchecked Sendable {
    var value = 0
}

private struct UnusedPiProviderHealthEvaluator: ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
        Issue.record("PiProviderModule should use its adapter-owned health summary evaluator in direct module tests")
        return []
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
        Issue.record("PiProviderModule should use its adapter-owned health summary evaluator in direct module tests")
        return ProviderHealthSummary(state: .notChecked, summary: "unused")
    }
}
#endif
