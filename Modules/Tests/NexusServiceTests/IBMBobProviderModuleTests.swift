#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct IBMBobProviderModuleTests {
    @Test func serviceProviderRegistryRoutesIBMBobThroughIBMBobProviderModule() {
        let registry = ServiceSessionProviderRegistry.providerModules(
            providerAdapters: [
                .ibmBob: ServiceProviderAdapter(
                    providerID: .ibmBob,
                    supportsDefaultSessionLaunch: false,
                    supportsNamedSessions: false,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(state: .misconfigured, summary: "Adapter health should stay behind the seam")
                    },
                    primarySurfaceEvaluator: { _ in .terminal }
                )
            ]
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Remote IBM Bob",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: UUID()
        )

        let module = registry.module(for: .ibmBob)

        #expect(module.supportsDefaultSessionLaunch(in: workspace))
        #expect(module.supportsNamedSessions(in: workspace))
        #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
    }

    @Test func ibmBobProviderModuleRelaunchesInterruptedSessionsWithExplicitIdleContinuity() {
        let module = IBMBobProviderModule()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .interrupted
        )
        let storedActivityItems = [
            SessionActivityItem(kind: .message, text: "You: ship it"),
            SessionActivityItem(kind: .message, text: "Done")
        ]

        let storedMetadata = SessionRecordAdapterMetadata.ibmBob(
            sessionID: "bob-session-123",
            activityItems: storedActivityItems,
            turnInProgress: true
        )

        let source = module.persistedSessionRelaunchMetadataSource(
            for: session,
            storedMetadata: storedMetadata
        )

        guard case let .explicit(metadata) = source else {
            Issue.record("Expected explicit IBM Bob continuity for interrupted relaunch")
            return
        }

        #expect(metadata?.ibmBobSessionLinkage?.sessionID == "bob-session-123")
        #expect(metadata?.ibmBobSessionLinkage?.persistedActivityItems == storedActivityItems)
        #expect(metadata?.ibmBobSessionLinkage?.turnInProgress == false)
    }

    @Test func ibmBobProviderModuleKeepsIdleStructuredSessionsReadyWithoutRuntime() {
        let module = IBMBobProviderModule()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )

        let mayRemainReady = module.sessionMayRemainReadyWithoutRuntime(
            session,
            workspace: nil,
            persistedPrimarySurface: .structuredActivityFeed,
            storedMetadata: SessionRecordAdapterMetadata.ibmBob(
                sessionID: "bob-session-123",
                activityItems: [SessionActivityItem(kind: .message, text: "Done")],
                turnInProgress: false
            )
        )

        #expect(mayRemainReady)
    }
}
#endif
