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

    init() throws {
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
                providerAdapters: ServiceSessionProviderRegistry.providerAdapters()
            )
        )
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
