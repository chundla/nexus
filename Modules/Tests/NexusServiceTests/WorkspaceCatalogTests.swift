#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct WorkspaceCatalogTests {
        @Test func providerDetailPersistsCatalogVisibleSessionDegradation() async throws {
            let fixture = try WorkspaceCatalogFixture()
            let session = try fixture.sessionRecordStore.createDefaultSession(
                workspaceID: fixture.workspace.id,
                providerID: .claude,
                state: .ready,
                failureMessage: nil
            )

            let detail = try await fixture.catalog.providerDetail(
                workspaceID: fixture.workspace.id, providerID: .claude)
            let persistedSession = try #require(try fixture.sessionRecordStore.session(id: session.id))

            #expect(detail.defaultSession?.id == session.id)
            #expect(detail.defaultSession?.state == .interrupted)
            #expect(persistedSession.state == .interrupted)
            #expect(
                persistedSession.failureMessage
                    == "Claude Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."
            )
        }

        @Test func workspaceOverviewUsesProviderModuleRegistryForPiCatalogReads() async throws {
            let fixture = try WorkspaceCatalogFixture(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .pi: StubProviderModule(
                            providerID: .pi,
                            health: ProviderHealthSummary(
                                state: .misconfigured,
                                summary: "Pi catalog reads now come from the Provider Module",
                                launchability: .notLaunchable
                            ),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession,
                                    isSupported: false,
                                    isEnabled: false,
                                    disabledReason: "Module-owned launch gating"
                                ),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession,
                                    isSupported: false,
                                    isEnabled: false,
                                    disabledReason: "Module-owned named-session gating"
                                )
                            ),
                            prelaunchPrimarySurface: .terminal
                        )
                    ]
                )
            )

            let overview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)
            let detail = try await fixture.catalog.providerDetail(workspaceID: fixture.workspace.id, providerID: .pi)
            let piCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))

            #expect(piCard.health.summary == "Pi catalog reads now come from the Provider Module")
            #expect(piCard.capabilities.launchDefaultSession.disabledReason == "Module-owned launch gating")
            #expect(piCard.capabilities.createNamedSession.disabledReason == "Module-owned named-session gating")
            #expect(piCard.prelaunchPrimarySurface == .terminal)
            #expect(detail.health == piCard.health)
            #expect(detail.capabilities == piCard.capabilities)
            #expect(detail.prelaunchPrimarySurface == piCard.prelaunchPrimarySurface)
        }

        @Test func workspaceCatalogUsesProviderModuleCatalogReadResultForClaude() async throws {
            let fixture = try WorkspaceCatalogFixture(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .claude: StubProviderModule(
                            providerID: .claude,
                            health: ProviderHealthSummary(
                                state: .misconfigured,
                                summary: "Legacy catalog path should stay unused",
                                launchability: .notLaunchable
                            ),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession,
                                    isSupported: false,
                                    isEnabled: false,
                                    disabledReason: "Legacy launch gating"
                                ),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession,
                                    isSupported: false,
                                    isEnabled: false,
                                    disabledReason: "Legacy named-session gating"
                                )
                            ),
                            prelaunchPrimarySurface: .structuredActivityFeed,
                            catalogReadResult: ProviderModuleCatalogReadResult(
                                health: ProviderHealthSummary(
                                    state: .available,
                                    summary: "Claude catalog result from the Provider Module",
                                    resolvedExecutable: "/tmp/fake-claude",
                                    launchability: .launchable
                                ),
                                capabilities: ProviderCapabilities(
                                    launchDefaultSession: ProviderCapability(
                                        action: .launchDefaultSession,
                                        isSupported: true,
                                        isEnabled: true
                                    ),
                                    createNamedSession: ProviderCapability(
                                        action: .createNamedSession,
                                        isSupported: true,
                                        isEnabled: true
                                    )
                                ),
                                prelaunchPrimarySurface: .terminal,
                                defaultSession: ProviderDefaultSessionSummary(
                                    state: .notCreated,
                                    summary: "Catalog-owned default summary",
                                    actionTitle: "Launch"
                                )
                            )
                        )
                    ]
                )
            )

            let overview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)
            let detail = try await fixture.catalog.providerDetail(
                workspaceID: fixture.workspace.id, providerID: .claude)
            let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

            #expect(claudeCard.health.summary == "Claude catalog result from the Provider Module")
            #expect(claudeCard.capabilities.launchDefaultSession.isEnabled)
            #expect(claudeCard.capabilities.createNamedSession.isEnabled)
            #expect(claudeCard.prelaunchPrimarySurface == .terminal)
            #expect(claudeCard.defaultSession.summary == "Catalog-owned default summary")
            #expect(detail.health == claudeCard.health)
            #expect(detail.capabilities == claudeCard.capabilities)
            #expect(detail.prelaunchPrimarySurface == claudeCard.prelaunchPrimarySurface)
        }

        @Test func providerDetailUsesProviderModuleSurfaceWhenPersistedPiSessionHasNoLaunchSnapshot() async throws {
            let fixture = try WorkspaceCatalogFixture()
            let session = try fixture.sessionRecordStore.createDefaultSession(
                workspaceID: fixture.workspace.id,
                providerID: .pi,
                state: .ready,
                failureMessage: nil
            )

            let detail = try await fixture.catalog.providerDetail(workspaceID: fixture.workspace.id, providerID: .pi)
            let persistedSession = try #require(try fixture.sessionRecordStore.session(id: session.id))

            #expect(detail.defaultSession?.state == .interrupted)
            #expect(persistedSession.state == .interrupted)
            #expect(persistedSession.failureMessage == structuredInterruptedSessionFailureMessage(for: .pi))
        }

        @Test func providerDetailUsesProviderModuleInterruptedFailureCopyWhenRuntimeIsLost() async throws {
            let fixture = try WorkspaceCatalogFixture(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .pi: StubProviderModule(
                            providerID: .pi,
                            health: ProviderHealthSummary(
                                state: .available,
                                summary: "Ready",
                                resolvedExecutable: "/tmp/fake-pi",
                                launchability: .launchable
                            ),
                            capabilities: ProviderCapabilities(
                                launchDefaultSession: ProviderCapability(
                                    action: .launchDefaultSession,
                                    isSupported: true,
                                    isEnabled: true
                                ),
                                createNamedSession: ProviderCapability(
                                    action: .createNamedSession,
                                    isSupported: true,
                                    isEnabled: true
                                )
                            ),
                            prelaunchPrimarySurface: .structuredActivityFeed,
                            interruptedFailureMessage: "Module-owned interrupted copy"
                        )
                    ]
                )
            )
            let session = try fixture.sessionRecordStore.createDefaultSession(
                workspaceID: fixture.workspace.id,
                providerID: .pi,
                state: .ready,
                failureMessage: nil
            )

            let detail = try await fixture.catalog.providerDetail(workspaceID: fixture.workspace.id, providerID: .pi)
            let persistedSession = try #require(try fixture.sessionRecordStore.session(id: session.id))

            #expect(detail.defaultSession?.state == .interrupted)
            #expect(persistedSession.state == .interrupted)
            #expect(persistedSession.failureMessage == "Module-owned interrupted copy")
        }

        @Test func workspaceOverviewsPreserveInputOrder() async throws {
            let fixture = try WorkspaceCatalogFixture()
            let secondWorkspace = try fixture.metadataStore.createLocalWorkspace(
                name: "Second Workspace",
                folderPath: fixture.secondWorkspaceFolder.path(percentEncoded: false),
                primaryGroupID: fixture.group.id
            )

            let overviews = try await fixture.catalog.workspaceOverviews(
                workspaceIDs: [secondWorkspace.id, fixture.workspace.id]
            )

            #expect(overviews.map(\.workspace.id) == [secondWorkspace.id, fixture.workspace.id])
        }

        @Test func workspaceOverviewBoundsProviderCardConcurrencyWhilePreservingProviderOrder() async throws {
            let tracker = ProviderCatalogReadConcurrencyTracker()
            let fixture = try WorkspaceCatalogFixture(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: Dictionary(
                        uniqueKeysWithValues: ProviderID.allCases.map { providerID in
                            (providerID, ConcurrentCatalogReadProviderModule(providerID: providerID, tracker: tracker))
                        })
                )
            )

            let overview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)

            #expect(overview.providerCards.map(\.provider.id) == ProviderID.allCases)
            #expect(await tracker.maximumConcurrentReads() == 2)
        }

        @Test func workspaceOverviewBrowsePreservesStaleProviderSummariesWhileBoundingProviderCardConcurrency()
            async throws
        {
            let now = Date(timeIntervalSince1970: 1_500)
            let tracker = ProviderCatalogReadConcurrencyTracker()
            let fixture = try WorkspaceCatalogFixture(
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: Dictionary(
                        uniqueKeysWithValues: ProviderID.allCases.map { providerID in
                            (providerID, ConcurrentCatalogReadProviderModule(providerID: providerID, tracker: tracker))
                        })
                ),
                currentDate: { now }
            )

            for providerID in ProviderID.allCases {
                _ = try fixture.metadataStore.saveProviderHealth(
                    workspaceID: fixture.workspace.id,
                    providerID: providerID,
                    summary: ProviderHealthSummary(
                        state: .unavailable,
                        summary: "Stale \(providerID.displayName) health",
                        launchability: .notLaunchable
                    ),
                    checkedAt: now.addingTimeInterval(-120)
                )
            }

            let overview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)

            #expect(overview.providerCards.map(\.provider.id) == ProviderID.allCases)
            #expect(
                overview.providerCards.map(\.health.summary)
                    == ProviderID.allCases.map { "Stale \($0.displayName) health" })
            #expect(overview.usesStaleBrowseFacts)
            #expect(await tracker.maximumConcurrentReads() == 2)
        }

        @Test func workspaceOverviewReusesRecentLocalProviderHealthSnapshot() async throws {
            let now = Date(timeIntervalSince1970: 1_000)
            let evaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    ProviderID.claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Fresh Claude health should stay unused",
                        resolvedExecutable: "/tmp/fresh-claude",
                        launchability: .launchable
                    )
                ]
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: evaluator,
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        ProviderID.claude: TestProviderModule(providerID: .claude) {
                            workspace, remoteContext, providerHealthEvaluator in
                            await providerHealthEvaluator.healthSummary(
                                for: .claude, workspace: workspace, remoteContext: remoteContext)
                        }
                    ]
                ),
                currentDate: { now }
            )
            let cached = try fixture.metadataStore.saveProviderHealth(
                workspaceID: fixture.workspace.id,
                providerID: ProviderID.claude,
                summary: ProviderHealthSummary(
                    state: .available,
                    summary: "Cached Claude health",
                    resolvedExecutable: "/tmp/cached-claude",
                    launchability: .launchable
                ),
                checkedAt: now.addingTimeInterval(-10)
            )

            let overview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)
            let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == ProviderID.claude }))

            #expect(claudeCard.health == cached)
            #expect(await evaluator.callCount(for: ProviderID.claude) == 0)
            #expect(overview.usesStaleBrowseFacts == false)
        }

        @Test func workspaceOverviewMarksStaleLocalProviderHealthSnapshotUntilExplicitRefresh() async throws {
            let now = Date(timeIntervalSince1970: 2_000)
            let freshSummary = ProviderHealthSummary(
                state: .available,
                summary: "Fresh Claude health",
                resolvedExecutable: "/tmp/fresh-claude",
                launchability: .launchable
            )
            let evaluator = CountingProviderHealthEvaluator(summariesByProvider: [ProviderID.claude: freshSummary])
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: evaluator,
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        ProviderID.claude: TestProviderModule(providerID: .claude) {
                            workspace, remoteContext, providerHealthEvaluator in
                            await providerHealthEvaluator.healthSummary(
                                for: .claude, workspace: workspace, remoteContext: remoteContext)
                        }
                    ]
                ),
                currentDate: { now }
            )
            let cached = try fixture.metadataStore.saveProviderHealth(
                workspaceID: fixture.workspace.id,
                providerID: ProviderID.claude,
                summary: ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Stale Claude health",
                    launchability: .notLaunchable
                ),
                checkedAt: now.addingTimeInterval(-120)
            )

            let staleOverview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)
            let staleCard = try #require(
                staleOverview.providerCards.first(where: { $0.provider.id == ProviderID.claude }))

            #expect(staleCard.health == cached)
            #expect(staleOverview.usesStaleBrowseFacts)

            let refreshedOverview = try await fixture.catalog.refreshWorkspaceOverview(
                workspaceID: fixture.workspace.id)
            let refreshedCard = try #require(
                refreshedOverview.providerCards.first(where: { $0.provider.id == ProviderID.claude }))
            let persistedSummary = try #require(
                try fixture.metadataStore.providerHealth(
                    workspaceID: fixture.workspace.id, providerID: ProviderID.claude))

            #expect(refreshedCard.health.summary == "Fresh Claude health")
            #expect(refreshedOverview.usesStaleBrowseFacts == false)
            #expect(persistedSummary.summary == "Fresh Claude health")
            #expect(await evaluator.callCount(for: ProviderID.claude) == 1)
        }

        @Test func workspaceOverviewReusesRecentRemoteSnapshotsWithoutRefreshingChecks() async throws {
            let now = Date(timeIntervalSince1970: 3_000)
            let hostValidationEvaluator = CountingHostValidationEvaluator(
                result: HostValidationResult(state: .available, summary: "Fresh Host Validation", diagnostics: [])
            )
            let workspaceAvailabilityEvaluator = CountingWorkspaceAvailabilityEvaluator(
                result: WorkspaceAvailabilityResult(
                    state: .available, summary: "Fresh Workspace Availability", diagnostics: [])
            )
            let providerHealthEvaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    ProviderID.claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Fresh Claude health should stay unused",
                        resolvedExecutable: "/tmp/fresh-claude",
                        launchability: .launchable
                    )
                ]
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: providerHealthEvaluator,
                hostValidationEvaluator: hostValidationEvaluator,
                workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        ProviderID.claude: TestProviderModule(providerID: .claude) {
                            workspace, remoteContext, providerHealthEvaluator in
                            await providerHealthEvaluator.healthSummary(
                                for: .claude, workspace: workspace, remoteContext: remoteContext)
                        }
                    ]
                ),
                currentDate: { now }
            )
            let host = try fixture.metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            let remoteWorkspace = try fixture.metadataStore.createRemoteWorkspace(
                name: "Remote API",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: fixture.group.id
            )
            let cachedHostValidation = try fixture.metadataStore.saveHostValidation(
                hostID: host.id,
                result: HostValidationResult(state: .unavailable, summary: "Cached Host Validation", diagnostics: []),
                checkedAt: now.addingTimeInterval(-10)
            )
            let cachedAvailability = try fixture.metadataStore.saveWorkspaceAvailability(
                workspaceID: remoteWorkspace.id,
                result: WorkspaceAvailabilityResult(
                    state: .blocked, summary: "Cached Workspace Availability", diagnostics: []),
                checkedAt: now.addingTimeInterval(-10)
            )
            let cachedHealth = try fixture.metadataStore.saveProviderHealth(
                workspaceID: remoteWorkspace.id,
                providerID: ProviderID.claude,
                summary: ProviderHealthSummary(
                    state: .blocked,
                    summary: "Cached Claude health",
                    launchability: .notLaunchable
                ),
                checkedAt: now.addingTimeInterval(-10)
            )

            let overview = try await fixture.catalog.workspaceOverview(workspaceID: remoteWorkspace.id)
            let remoteTarget = try #require(overview.remoteTarget)
            let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == ProviderID.claude }))

            #expect(remoteTarget.hostValidation == cachedHostValidation)
            #expect(remoteTarget.workspaceAvailability == cachedAvailability)
            #expect(claudeCard.health == cachedHealth)
            #expect(overview.usesStaleBrowseFacts == false)
            #expect(hostValidationEvaluator.callCount == 0)
            #expect(workspaceAvailabilityEvaluator.callCount == 0)
            #expect(await providerHealthEvaluator.callCount(for: ProviderID.claude) == 0)
        }

        @Test func workspaceOverviewMarksStaleRemoteSnapshotsUntilExplicitRefresh() async throws {
            let now = Date(timeIntervalSince1970: 4_000)
            let hostValidationEvaluator = CountingHostValidationEvaluator(
                result: HostValidationResult(state: .available, summary: "Fresh Host Validation", diagnostics: [])
            )
            let workspaceAvailabilityEvaluator = CountingWorkspaceAvailabilityEvaluator(
                result: WorkspaceAvailabilityResult(
                    state: .available, summary: "Fresh Workspace Availability", diagnostics: [])
            )
            let providerHealthEvaluator = CountingProviderHealthEvaluator(
                summariesByProvider: [
                    ProviderID.claude: ProviderHealthSummary(
                        state: .available,
                        summary: "Fresh Claude health",
                        resolvedExecutable: "/tmp/fresh-claude",
                        launchability: .launchable
                    )
                ]
            )
            let collector = RecordingRemoteWorkspaceProbeCollector(
                result: .collected(
                    RemoteWorkspaceProbeFacts(
                        tmuxAvailable: true,
                        workspacePath: .available,
                        providerFacts: [:]
                    )
                )
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: providerHealthEvaluator,
                hostValidationEvaluator: hostValidationEvaluator,
                workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                remoteWorkspaceProbeCollector: collector,
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        ProviderID.claude: TestProviderModule(providerID: .claude) {
                            workspace, remoteContext, providerHealthEvaluator in
                            await providerHealthEvaluator.healthSummary(
                                for: .claude, workspace: workspace, remoteContext: remoteContext)
                        }
                    ]
                ),
                currentDate: { now }
            )
            let host = try fixture.metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            let remoteWorkspace = try fixture.metadataStore.createRemoteWorkspace(
                name: "Remote API",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: fixture.group.id
            )
            let cachedHostValidation = try fixture.metadataStore.saveHostValidation(
                hostID: host.id,
                result: HostValidationResult(state: .unavailable, summary: "Stale Host Validation", diagnostics: []),
                checkedAt: now.addingTimeInterval(-120)
            )
            let cachedAvailability = try fixture.metadataStore.saveWorkspaceAvailability(
                workspaceID: remoteWorkspace.id,
                result: WorkspaceAvailabilityResult(
                    state: .blocked, summary: "Stale Workspace Availability", diagnostics: []),
                checkedAt: now.addingTimeInterval(-120)
            )
            let cachedHealth = try fixture.metadataStore.saveProviderHealth(
                workspaceID: remoteWorkspace.id,
                providerID: ProviderID.claude,
                summary: ProviderHealthSummary(
                    state: .blocked,
                    summary: "Stale Claude health",
                    launchability: .notLaunchable
                ),
                checkedAt: now.addingTimeInterval(-120)
            )

            let staleOverview = try await fixture.catalog.workspaceOverview(workspaceID: remoteWorkspace.id)
            let staleRemoteTarget = try #require(staleOverview.remoteTarget)
            let staleCard = try #require(
                staleOverview.providerCards.first(where: { $0.provider.id == ProviderID.claude }))

            #expect(staleRemoteTarget.hostValidation == cachedHostValidation)
            #expect(staleRemoteTarget.workspaceAvailability == cachedAvailability)
            #expect(staleCard.health == cachedHealth)
            #expect(staleOverview.usesStaleBrowseFacts)

            let refreshedOverview = try await fixture.catalog.refreshWorkspaceOverview(workspaceID: remoteWorkspace.id)
            let refreshedRemoteTarget = try #require(refreshedOverview.remoteTarget)
            let refreshedCard = try #require(
                refreshedOverview.providerCards.first(where: { $0.provider.id == ProviderID.claude }))

            #expect(refreshedRemoteTarget.hostValidation?.summary == "Host is available")
            #expect(refreshedRemoteTarget.workspaceAvailability.summary == "Workspace is available")
            #expect(refreshedCard.health.summary == "Fresh Claude health")
            #expect(refreshedOverview.usesStaleBrowseFacts == false)
            #expect(collector.callCount == 1)
            #expect(hostValidationEvaluator.callCount == 0)
            #expect(workspaceAvailabilityEvaluator.callCount == 0)
            #expect(await providerHealthEvaluator.callCount(for: ProviderID.claude) == 1)
        }

        @Test func providerDetailUsesSingleRemoteProbePassWhenProviderModuleConsumesSharedProbeFacts() async throws {
            let hostValidationEvaluator = CountingHostValidationEvaluator(
                result: HostValidationResult(state: .available, summary: "Unexpected Host Validation", diagnostics: [])
            )
            let workspaceAvailabilityEvaluator = CountingWorkspaceAvailabilityEvaluator(
                result: WorkspaceAvailabilityResult(
                    state: .available, summary: "Unexpected Workspace Availability", diagnostics: [])
            )
            let collector = RecordingRemoteWorkspaceProbeCollector(
                result: .collected(
                    RemoteWorkspaceProbeFacts(
                        tmuxAvailable: true,
                        workspacePath: .available,
                        providerFacts: [
                            .claude: RemoteProviderProbeFacts(
                                executable: "/opt/tools/claude",
                                version: "1.2.3",
                                resolutionDetail: nil,
                                probeDetail: nil
                            )
                        ]
                    )
                )
            )
            let providerModule = TestProviderModule(
                providerID: .claude,
                healthSummaryEvaluator: { _, remoteContext, _ in
                    guard let probeFact = remoteContext?.probeFacts?.providerFacts[.claude],
                        let executable = probeFact.executable
                    else {
                        return ProviderHealthSummary(state: .notChecked, summary: "Missing probe facts")
                    }

                    return ProviderHealthSummary(
                        state: .available,
                        summary: probeFact.version.map { "Claude \($0) is available" } ?? "Claude is available",
                        resolvedExecutable: executable,
                        version: probeFact.version,
                        launchability: .launchable
                    )
                },
                sharedRemoteProbeFactsSupportEvaluator: { _ in true }
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: AvailableProviderHealthFacts(),
                hostValidationEvaluator: hostValidationEvaluator,
                workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                remoteWorkspaceProbeCollector: collector,
                providerModuleRegistry: ServiceSessionProviderRegistry.providerModules(
                    overrides: [.claude: providerModule]
                )
            )
            let host = try fixture.metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            let remoteWorkspace = try fixture.metadataStore.createRemoteWorkspace(
                name: "Remote API",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: fixture.group.id
            )

            let detail = try await fixture.catalog.providerDetail(workspaceID: remoteWorkspace.id, providerID: .claude)

            #expect(detail.health.summary == "Claude 1.2.3 is available")
            #expect(detail.health.resolvedExecutable == "/opt/tools/claude")
            #expect(collector.callCount == 1)
            #expect(hostValidationEvaluator.callCount == 0)
            #expect(workspaceAvailabilityEvaluator.callCount == 0)
        }

        @Test func refreshWorkspaceOverviewUsesSingleRemoteProbePassForRemoteWorkspaceTarget() async throws {
            let hostValidationEvaluator = CountingHostValidationEvaluator(
                result: HostValidationResult(state: .available, summary: "Unexpected Host Validation", diagnostics: [])
            )
            let workspaceAvailabilityEvaluator = CountingWorkspaceAvailabilityEvaluator(
                result: WorkspaceAvailabilityResult(
                    state: .available, summary: "Unexpected Workspace Availability", diagnostics: [])
            )
            let commandRunner = FailingWorkspaceCatalogCommandRunner()
            let codexReadinessProbe = RecordingWorkspaceCatalogRemoteCodexReadinessProbe()
            let piReadinessProbe = RecordingWorkspaceCatalogRemotePiReadinessProbe()
            let claudeReadinessProbe = RecordingWorkspaceCatalogRemoteClaudeReadinessProbe()
            let providerHealthEvaluator = ProviderHealthFacts(
                commandRunner: commandRunner,
                remoteCodexReadinessProbe: codexReadinessProbe,
                remotePiReadinessProbe: piReadinessProbe,
                remoteClaudeStreamJSONReadinessProbe: claudeReadinessProbe
            )
            let collector = RecordingRemoteWorkspaceProbeCollector(
                result: .collected(
                    RemoteWorkspaceProbeFacts(
                        tmuxAvailable: true,
                        workspacePath: .available,
                        providerFacts: [
                            .claude: RemoteProviderProbeFacts(
                                executable: "/opt/tools/claude",
                                version: "1.2.3",
                                resolutionDetail: nil,
                                probeDetail: nil
                            ),
                            .codex: RemoteProviderProbeFacts(
                                executable: "/opt/tools/codex",
                                version: "0.9.0",
                                resolutionDetail: nil,
                                probeDetail: nil
                            ),
                            .pi: RemoteProviderProbeFacts(
                                executable: "/opt/tools/pi",
                                version: "3.1.4",
                                resolutionDetail: nil,
                                probeDetail: nil
                            ),
                            .ibmBob: RemoteProviderProbeFacts(
                                executable: "/opt/tools/bob",
                                version: "2026.05",
                                resolutionDetail: nil,
                                probeDetail: nil
                            ),
                        ]
                    )
                )
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: providerHealthEvaluator,
                hostValidationEvaluator: hostValidationEvaluator,
                workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                remoteWorkspaceProbeCollector: collector
            )
            let host = try fixture.metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
            let remoteWorkspace = try fixture.metadataStore.createRemoteWorkspace(
                name: "Remote API",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: fixture.group.id
            )

            let overview = try await fixture.catalog.refreshWorkspaceOverview(workspaceID: remoteWorkspace.id)
            let remoteTarget = try #require(overview.remoteTarget)

            #expect(remoteTarget.hostValidation?.summary == "Host is available")
            #expect(remoteTarget.workspaceAvailability.summary == "Workspace is available")
            #expect(
                overview.providerCards.first(where: { $0.provider.id == .claude })?.health.summary
                    == "Claude 1.2.3 is available")
            #expect(
                overview.providerCards.first(where: { $0.provider.id == .codex })?.health.summary
                    == "Codex 0.9.0 is available")
            #expect(
                overview.providerCards.first(where: { $0.provider.id == .pi })?.health.summary
                    == "Pi 3.1.4 is available")
            #expect(
                overview.providerCards.first(where: { $0.provider.id == .ibmBob })?.health.summary
                    == "IBM Bob 2026.05 is available")
            #expect(overview.usesStaleBrowseFacts == false)
            #expect(collector.callCount == 1)
            #expect(hostValidationEvaluator.callCount == 0)
            #expect(workspaceAvailabilityEvaluator.callCount == 0)
            #expect(commandRunner.callCount == 0)
            #expect(
                await codexReadinessProbe.invocations == [
                    WorkspaceCatalogReadinessInvocation(
                        hostID: host.id, executable: "/opt/tools/codex", workingDirectory: "/srv/api")
                ])
            #expect(
                await piReadinessProbe.invocations == [
                    WorkspaceCatalogReadinessInvocation(
                        hostID: host.id, executable: "/opt/tools/pi", workingDirectory: "/srv/api")
                ])
            #expect(
                await claudeReadinessProbe.invocations == [
                    WorkspaceCatalogReadinessInvocation(
                        hostID: host.id, executable: "/opt/tools/claude", workingDirectory: "/srv/api")
                ])
        }

        @Test func refreshWorkspaceOverviewClassifiesRemoteProbeTransportFailureWithoutSeparateChecks() async throws {
            let hostValidationEvaluator = CountingHostValidationEvaluator(
                result: HostValidationResult(state: .available, summary: "Unexpected Host Validation", diagnostics: [])
            )
            let workspaceAvailabilityEvaluator = CountingWorkspaceAvailabilityEvaluator(
                result: WorkspaceAvailabilityResult(
                    state: .available, summary: "Unexpected Workspace Availability", diagnostics: [])
            )
            let commandRunner = FailingWorkspaceCatalogCommandRunner()
            let collector = RecordingRemoteWorkspaceProbeCollector(
                result: .transportFailed("Permission denied (publickey).")
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: ProviderHealthFacts(commandRunner: commandRunner),
                hostValidationEvaluator: hostValidationEvaluator,
                workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                remoteWorkspaceProbeCollector: collector
            )
            let host = try fixture.metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            let remoteWorkspace = try fixture.metadataStore.createRemoteWorkspace(
                name: "Remote API",
                hostID: host.id,
                remotePath: "/srv/missing",
                primaryGroupID: fixture.group.id
            )

            let overview = try await fixture.catalog.refreshWorkspaceOverview(workspaceID: remoteWorkspace.id)
            let remoteTarget = try #require(overview.remoteTarget)
            let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

            #expect(remoteTarget.hostValidation?.state == .broken)
            #expect(remoteTarget.hostValidation?.summary == "Host requires configuration repair")
            #expect(remoteTarget.workspaceAvailability.state == .blocked)
            #expect(
                remoteTarget.workspaceAvailability.summary == "Workspace Availability is blocked by Host Validation")
            #expect(claudeCard.health.state == .blocked)
            #expect(claudeCard.health.summary == "Provider Health is blocked by Host Validation")
            #expect(collector.callCount == 1)
            #expect(hostValidationEvaluator.callCount == 0)
            #expect(workspaceAvailabilityEvaluator.callCount == 0)
            #expect(commandRunner.callCount == 0)
        }

        @Test func refreshWorkspaceOverviewClassifiesRemoteProbeRawFailureWithoutSeparateChecks() async throws {
            let hostValidationEvaluator = CountingHostValidationEvaluator(
                result: HostValidationResult(state: .available, summary: "Unexpected Host Validation", diagnostics: [])
            )
            let workspaceAvailabilityEvaluator = CountingWorkspaceAvailabilityEvaluator(
                result: WorkspaceAvailabilityResult(
                    state: .available, summary: "Unexpected Workspace Availability", diagnostics: [])
            )
            let commandRunner = FailingWorkspaceCatalogCommandRunner()
            let collector = RecordingRemoteWorkspaceProbeCollector(
                result: .rawProbeFailed("Unsupported remote probe protocol: v2")
            )
            let fixture = try WorkspaceCatalogFixture(
                providerHealthEvaluator: ProviderHealthFacts(commandRunner: commandRunner),
                hostValidationEvaluator: hostValidationEvaluator,
                workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                remoteWorkspaceProbeCollector: collector
            )
            let host = try fixture.metadataStore.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            let remoteWorkspace = try fixture.metadataStore.createRemoteWorkspace(
                name: "Remote API",
                hostID: host.id,
                remotePath: "/srv/missing",
                primaryGroupID: fixture.group.id
            )

            let overview = try await fixture.catalog.refreshWorkspaceOverview(workspaceID: remoteWorkspace.id)
            let remoteTarget = try #require(overview.remoteTarget)
            let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

            #expect(remoteTarget.hostValidation?.state == .broken)
            #expect(remoteTarget.hostValidation?.summary == "Host validation failed")
            #expect(remoteTarget.workspaceAvailability.state == .blocked)
            #expect(
                remoteTarget.workspaceAvailability.summary == "Workspace Availability is blocked by Host Validation")
            #expect(claudeCard.health.state == .blocked)
            #expect(claudeCard.health.summary == "Provider Health is blocked by Host Validation")
            #expect(collector.callCount == 1)
            #expect(hostValidationEvaluator.callCount == 0)
            #expect(workspaceAvailabilityEvaluator.callCount == 0)
            #expect(commandRunner.callCount == 0)
        }
    }

    private struct WorkspaceCatalogFixture {
        let metadataStore: NexusMetadataStore
        let sessionRecordStore: any SessionRecordStore
        let catalog: WorkspaceCatalog
        let group: WorkspaceGroup
        let workspace: Workspace
        let secondWorkspaceFolder: URL

        init(
            providerHealthEvaluator: any ProviderHealthEvaluating = AvailableProviderHealthFacts(),
            hostValidationEvaluator: any HostValidationEvaluating = UnusedHostValidationEvaluator(),
            workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating =
                UnusedWorkspaceAvailabilityEvaluator(),
            remoteWorkspaceProbeCollector: any RemoteWorkspaceProbeCollecting = UnusedRemoteWorkspaceProbeCollector(),
            providerModuleRegistry: ProviderModuleRegistry? = nil,
            currentDate: @escaping () -> Date = Date.init
        ) throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WorkspaceCatalogTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            let secondWorkspaceFolder = rootURL.appendingPathComponent("workspace-2", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondWorkspaceFolder, withIntermediateDirectories: true)

            let metadataStore = try NexusMetadataStore(
                storeURL: rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false))
            let sessionRecordStore = MetadataStoreSessionRecordStore(metadataStore: metadataStore)
            let group = try metadataStore.createWorkspaceGroup(name: "Solo Group")
            let workspace = try metadataStore.createLocalWorkspace(
                name: "Local Claude",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            self.metadataStore = metadataStore
            self.sessionRecordStore = sessionRecordStore
            self.group = group
            self.workspace = workspace
            self.secondWorkspaceFolder = secondWorkspaceFolder
            self.catalog = WorkspaceCatalog(
                dependencies: WorkspaceCatalogDependencies(
                    metadataStore: metadataStore,
                    sessionRecordStore: sessionRecordStore,
                    providerHealthEvaluator: providerHealthEvaluator,
                    hostValidationEvaluator: hostValidationEvaluator,
                    workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
                    remoteWorkspaceProbeCollector: remoteWorkspaceProbeCollector,
                    sessionRuntimeManager: InMemorySessionRuntimeManager(),
                    providerModuleRegistry: providerModuleRegistry ?? ServiceSessionProviderRegistry.providerModules(),
                    currentDate: currentDate
                )
            )
        }
    }

    private struct StubProviderModule: ProviderModule {
        let provider: Provider
        let health: ProviderHealthSummary
        let capabilities: ProviderCapabilities
        let prelaunchPrimarySurface: SessionSurface
        let catalogReadResult: ProviderModuleCatalogReadResult?
        let interruptedFailureMessage: String?

        init(
            providerID: ProviderID,
            health: ProviderHealthSummary,
            capabilities: ProviderCapabilities,
            prelaunchPrimarySurface: SessionSurface,
            catalogReadResult: ProviderModuleCatalogReadResult? = nil,
            interruptedFailureMessage: String? = nil
        ) {
            self.provider = Provider(id: providerID)
            self.health = health
            self.capabilities = capabilities
            self.prelaunchPrimarySurface = prelaunchPrimarySurface
            self.catalogReadResult = catalogReadResult
            self.interruptedFailureMessage = interruptedFailureMessage
        }

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
            capabilities.launchDefaultSession.isSupported
        }

        func readCatalog(
            _ request: ProviderModuleCatalogReadRequest,
            actions: ProviderModuleCatalogReadActions
        ) async throws -> ProviderModuleCatalogReadResult {
            catalogReadResult
                ?? ProviderModuleCatalogReadResult(
                    health: health,
                    capabilities: capabilities,
                    prelaunchPrimarySurface: prelaunchPrimarySurface,
                    defaultSession: defaultSessionSummary(for: request.defaultSession)
                )
        }

        func supportsNamedSessions(in workspace: Workspace) -> Bool {
            capabilities.createNamedSession.isSupported
        }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            health
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            capabilities
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            prelaunchPrimarySurface
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func interruptedSessionFailureMessage(
            for session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface
        ) -> String {
            interruptedFailureMessage ?? providerModuleDefaultInterruptedSessionFailureMessage()
        }
    }

    private struct AvailableProviderHealthFacts: ProviderHealthEvaluating {
        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            ProviderID.allCases.map { providerID in
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: summary(for: providerID),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .notCreated,
                        summary: "No default session yet",
                        actionTitle: "Launch"
                    )
                )
            }
        }

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            summary(for: providerID)
        }

        private func summary(for providerID: ProviderID) -> ProviderHealthSummary {
            ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/\(providerID.rawValue)",
                launchability: .launchable
            )
        }
    }

    private struct UnusedHostValidationEvaluator: HostValidationEvaluating {
        func validate(host: NexusDomain.Host) -> HostValidationResult {
            Issue.record("Host validation should not run for local Workspace tests")
            return HostValidationResult(state: .available, summary: "Host is available", diagnostics: [])
        }
    }

    private struct UnusedWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
            Issue.record("Workspace Availability should not run for local Workspace tests")
            return WorkspaceAvailabilityResult(state: .available, summary: "Workspace is available", diagnostics: [])
        }
    }

    private actor CountingProviderHealthEvaluator: ProviderHealthEvaluating {
        let summariesByProvider: [ProviderID: ProviderHealthSummary]
        private var callsByProvider: [ProviderID: Int] = [:]

        init(summariesByProvider: [ProviderID: ProviderHealthSummary]) {
            self.summariesByProvider = summariesByProvider
        }

        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            ProviderID.allCases.map { providerID in
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: ProviderHealthSummary(state: .notChecked, summary: "Unused"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .notCreated,
                        summary: "No default session yet",
                        actionTitle: "Launch"
                    )
                )
            }
        }

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            callsByProvider[providerID, default: 0] += 1
            return summariesByProvider[providerID] ?? ProviderHealthSummary(state: .notChecked, summary: "Unused")
        }

        func callCount(for providerID: ProviderID) -> Int {
            callsByProvider[providerID, default: 0]
        }
    }

    private final class CountingHostValidationEvaluator: HostValidationEvaluating, @unchecked Sendable {
        let result: HostValidationResult
        private(set) var callCount = 0

        init(result: HostValidationResult) {
            self.result = result
        }

        func validate(host: NexusDomain.Host) -> HostValidationResult {
            callCount += 1
            return result
        }
    }

    private final class CountingWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating, @unchecked Sendable {
        let result: WorkspaceAvailabilityResult
        private(set) var callCount = 0

        init(result: WorkspaceAvailabilityResult) {
            self.result = result
        }

        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
            callCount += 1
            return result
        }
    }

    private struct UnusedRemoteWorkspaceProbeCollector: RemoteWorkspaceProbeCollecting {
        func collect(workspace: Workspace, host: NexusDomain.Host) -> RemoteWorkspaceProbeCollection {
            Issue.record("Remote Workspace probe collection should not run for this test")
            return .transportFailed("unused")
        }
    }

    private final class RecordingRemoteWorkspaceProbeCollector: RemoteWorkspaceProbeCollecting, @unchecked Sendable {
        let result: RemoteWorkspaceProbeCollection
        private(set) var callCount = 0

        init(result: RemoteWorkspaceProbeCollection) {
            self.result = result
        }

        func collect(workspace: Workspace, host: NexusDomain.Host) -> RemoteWorkspaceProbeCollection {
            callCount += 1
            return result
        }
    }

    private final class FailingWorkspaceCatalogCommandRunner: ProviderCommandRunning, @unchecked Sendable {
        private(set) var callCount = 0

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            callCount += 1
            throw NSError(
                domain: "WorkspaceCatalogTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected command runner invocation."])
        }
    }

    private struct WorkspaceCatalogReadinessInvocation: Equatable {
        let hostID: UUID
        let executable: String
        let workingDirectory: String
    }

    private actor RecordingWorkspaceCatalogRemoteCodexReadinessProbe: RemoteCodexReadinessProbing {
        private(set) var invocations: [WorkspaceCatalogReadinessInvocation] = []

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemoteCodexReadinessOutcome
        {
            invocations.append(
                WorkspaceCatalogReadinessInvocation(
                    hostID: host.id, executable: executable, workingDirectory: workingDirectory))
            return .ready
        }
    }

    private actor RecordingWorkspaceCatalogRemotePiReadinessProbe: RemotePiReadinessProbing {
        private(set) var invocations: [WorkspaceCatalogReadinessInvocation] = []

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws
            -> RemotePiReadinessOutcome
        {
            invocations.append(
                WorkspaceCatalogReadinessInvocation(
                    hostID: host.id, executable: executable, workingDirectory: workingDirectory))
            return .ready
        }
    }

    private actor RecordingWorkspaceCatalogRemoteClaudeReadinessProbe: RemoteClaudeStreamJSONReadinessProbing {
        private(set) var invocations: [WorkspaceCatalogReadinessInvocation] = []

        func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws {
            invocations.append(
                WorkspaceCatalogReadinessInvocation(
                    hostID: host.id, executable: executable, workingDirectory: workingDirectory))
        }
    }

    private actor ProviderCatalogReadConcurrencyTracker {
        private var activeReads = 0
        private var maxActiveReads = 0

        func beginRead() {
            activeReads += 1
            maxActiveReads = max(maxActiveReads, activeReads)
        }

        func endRead() {
            activeReads -= 1
        }

        func maximumConcurrentReads() -> Int {
            maxActiveReads
        }
    }

    private struct ConcurrentCatalogReadProviderModule: ProviderModule {
        let provider: Provider
        let tracker: ProviderCatalogReadConcurrencyTracker

        init(providerID: ProviderID, tracker: ProviderCatalogReadConcurrencyTracker) {
            self.provider = Provider(id: providerID)
            self.tracker = tracker
        }

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
            true
        }

        func supportsNamedSessions(in workspace: Workspace) -> Bool {
            true
        }

        func readCatalog(
            _ request: ProviderModuleCatalogReadRequest,
            actions: ProviderModuleCatalogReadActions
        ) async throws -> ProviderModuleCatalogReadResult {
            await tracker.beginRead()
            try? await Task.sleep(nanoseconds: 50_000_000)
            await tracker.endRead()

            let health = try await actions.providerHealthSummary()
            return ProviderModuleCatalogReadResult(
                health: health,
                capabilities: providerCapabilities(
                    in: request.workspace,
                    health: health,
                    defaultSession: request.defaultSession
                ),
                prelaunchPrimarySurface: prelaunchPrimarySurface(in: request.workspace),
                defaultSession: defaultSessionSummary(for: request.defaultSession)
            )
        }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/\(provider.id.rawValue)",
                launchability: .launchable
            )
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            ProviderCapabilities(
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession,
                    isSupported: true,
                    isEnabled: true
                ),
                createNamedSession: ProviderCapability(
                    action: .createNamedSession,
                    isSupported: true,
                    isEnabled: true
                )
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            .terminal
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func interruptedSessionFailureMessage(
            for session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface
        ) -> String {
            providerModuleDefaultInterruptedSessionFailureMessage()
        }
    }
#endif
