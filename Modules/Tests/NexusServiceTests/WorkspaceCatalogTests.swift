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

        let detail = try await fixture.catalog.providerDetail(workspaceID: fixture.workspace.id, providerID: .claude)
        let persistedSession = try #require(try fixture.sessionRecordStore.session(id: session.id))

        #expect(detail.defaultSession?.id == session.id)
        #expect(detail.defaultSession?.state == .interrupted)
        #expect(persistedSession.state == .interrupted)
        #expect(persistedSession.failureMessage == "Session interrupted because the background service restarted. Relaunch to create a new live runtime.")
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
                            prelaunchPrimarySurface: .terminal
                        )
                    )
                ]
            )
        )

        let overview = try await fixture.catalog.workspaceOverview(workspaceID: fixture.workspace.id)
        let detail = try await fixture.catalog.providerDetail(workspaceID: fixture.workspace.id, providerID: .claude)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(claudeCard.health.summary == "Claude catalog result from the Provider Module")
        #expect(claudeCard.capabilities.launchDefaultSession.isEnabled)
        #expect(claudeCard.capabilities.createNamedSession.isEnabled)
        #expect(claudeCard.prelaunchPrimarySurface == .terminal)
        #expect(detail.health == claudeCard.health)
        #expect(detail.capabilities == claudeCard.capabilities)
        #expect(detail.prelaunchPrimarySurface == claudeCard.prelaunchPrimarySurface)
    }

    @Test func providerDetailUsesProviderModuleSurfaceWhenPersistedPiSessionHasNoLaunchSnapshot() async throws {
        let fixture = try WorkspaceCatalogFixture(
            providerAdapters: ServiceSessionProviderRegistry.providerAdapters(overrides: [
                .pi: ServiceProviderAdapter(
                    providerID: .pi,
                    supportsDefaultSessionLaunch: false,
                    supportsNamedSessions: false,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Ready",
                            resolvedExecutable: "/tmp/fake-pi",
                            launchability: .launchable
                        )
                    },
                    primarySurfaceEvaluator: { _ in .terminal }
                )
            ])
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
        #expect(persistedSession.failureMessage == structuredInterruptedSessionFailureMessage(for: .pi))
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
}

private struct WorkspaceCatalogFixture {
    let metadataStore: NexusMetadataStore
    let sessionRecordStore: any SessionRecordStore
    let catalog: WorkspaceCatalog
    let group: WorkspaceGroup
    let workspace: Workspace
    let secondWorkspaceFolder: URL

    init(
        providerModuleRegistry: ProviderModuleRegistry? = nil,
        providerAdapters: [ProviderID: ServiceProviderAdapter]? = nil
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceCatalogTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        let secondWorkspaceFolder = rootURL.appendingPathComponent("workspace-2", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondWorkspaceFolder, withIntermediateDirectories: true)

        let metadataStore = try NexusMetadataStore(storeURL: rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false))
        let sessionRecordStore = MetadataStoreSessionRecordStore(metadataStore: metadataStore)
        let group = try metadataStore.createWorkspaceGroup(name: "Solo Group")
        let workspace = try metadataStore.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let providerAdapters = providerAdapters ?? ServiceSessionProviderRegistry.providerAdapters()
        self.metadataStore = metadataStore
        self.sessionRecordStore = sessionRecordStore
        self.group = group
        self.workspace = workspace
        self.secondWorkspaceFolder = secondWorkspaceFolder
        self.catalog = WorkspaceCatalog(
            dependencies: WorkspaceCatalogDependencies(
                metadataStore: metadataStore,
                sessionRecordStore: sessionRecordStore,
                providerHealthEvaluator: AvailableProviderHealthEvaluator(),
                hostValidationEvaluator: UnusedHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: UnusedWorkspaceAvailabilityEvaluator(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(),
                providerModuleRegistry: providerModuleRegistry ?? ServiceSessionProviderRegistry.providerModules(providerAdapters: providerAdapters)
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

    init(
        providerID: ProviderID,
        health: ProviderHealthSummary,
        capabilities: ProviderCapabilities,
        prelaunchPrimarySurface: SessionSurface,
        catalogReadResult: ProviderModuleCatalogReadResult? = nil
    ) {
        self.provider = Provider(id: providerID)
        self.health = health
        self.capabilities = capabilities
        self.prelaunchPrimarySurface = prelaunchPrimarySurface
        self.catalogReadResult = catalogReadResult
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        capabilities.launchDefaultSession.isSupported
    }

    func readCatalog(
        _ request: ProviderModuleCatalogReadRequest,
        actions: ProviderModuleCatalogReadActions
    ) async throws -> ProviderModuleCatalogReadResult {
        catalogReadResult ?? ProviderModuleCatalogReadResult(
            health: health,
            capabilities: capabilities,
            prelaunchPrimarySurface: prelaunchPrimarySurface
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
}

private struct AvailableProviderHealthEvaluator: ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard] {
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

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary {
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
    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult {
        Issue.record("Workspace Availability should not run for local Workspace tests")
        return WorkspaceAvailabilityResult(state: .available, summary: "Workspace is available", diagnostics: [])
    }
}
#endif
