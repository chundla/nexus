#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct NexusServicePerformanceDiagnosticsTests {
        @Test func workspaceOverviewIsListedInRecentPerformanceDiagnostics() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(),
                providerModuleRegistry: ProviderModuleRegistry(
                    fallbackModuleFactory: { providerID in
                        PerformanceDiagnosticStubProviderModule(providerID: providerID)
                    }
                )
            )
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Workspace",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            _ = try service.getWorkspaceOverview(workspaceID: workspace.id)
            let diagnostics = try service.listPerformanceDiagnostics(limit: 10)
            let record = try #require(diagnostics.first)

            #expect(record.operation == .workspaceOverview)
            #expect(record.workspaceID == workspace.id)
            #expect(record.providerID == nil)
            #expect(record.sessionID == nil)
            #expect(record.steps.contains(where: { $0.name == "loadWorkspace" }))
            #expect(record.steps.contains(where: { $0.name == "readProviderCatalog.claude" }))
            #expect(record.steps.contains(where: { $0.name == "readProviderCatalog.pi" }))
        }

        @Test func providerDetailIsListedInRecentPerformanceDiagnostics() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(),
                providerModuleRegistry: ProviderModuleRegistry(
                    fallbackModuleFactory: { providerID in
                        PerformanceDiagnosticStubProviderModule(providerID: providerID)
                    }
                )
            )
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Workspace",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            _ = try service.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
            let diagnostics = try service.listPerformanceDiagnostics(limit: 10)
            let record = try #require(diagnostics.first)

            #expect(record.operation == .providerDetail)
            #expect(record.workspaceID == workspace.id)
            #expect(record.providerID == .claude)
            #expect(record.sessionID == nil)
            #expect(record.steps.contains(where: { $0.name == "loadWorkspace" }))
            #expect(record.steps.contains(where: { $0.name == "loadSessions" }))
            #expect(record.steps.contains(where: { $0.name == "readProviderCatalog" }))
        }

        @Test func defaultSessionLaunchIsListedInRecentPerformanceDiagnostics() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try makePerformanceDiagnosticIBMBobService(rootURL: rootURL)
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Bob",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )

            _ = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
            let diagnostics = try service.listPerformanceDiagnostics(limit: 10)
            let record = try #require(diagnostics.first)

            #expect(record.operation == .launchDefaultSession)
            #expect(record.workspaceID == workspace.id)
            #expect(record.providerID == .ibmBob)
            #expect(record.steps.contains(where: { $0.name == "loadWorkspace" }))
            #expect(record.steps.contains(where: { $0.name == "loadDefaultSession" }))
            #expect(record.steps.contains(where: { $0.name == "planFreshSessionOpen" }))
            #expect(record.steps.contains(where: { $0.name == "createDefaultSession" }))
            #expect(record.steps.contains(where: { $0.name == "ensureLaunchSnapshot" }))
            #expect(record.steps.contains(where: { $0.name == "launchFreshSession" }))
        }
    }

    private func makePerformanceDiagnosticIBMBobService(rootURL: URL) throws -> NexusService {
        try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthFacts(
                executableResolver: PerformanceDiagnosticIBMBobExecutableResolver(executables: ["bob": "/tmp/fake-bob"]
                ),
                commandRunner: PerformanceDiagnosticIBMBobCommandRunner(results: [
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(
                        stdout: "3.4.5\n"),
                    .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                        stdout: "[]\n"),
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            )
        )
    }

    private struct PerformanceDiagnosticIBMBobExecutableResolver: ProviderExecutableResolving {
        let executables: [String: String]

        func resolveExecutable(named command: String) -> ProviderExecutableResolution {
            ProviderExecutableResolution(
                resolvedExecutable: executables[command],
                searchedDirectories: ["/tmp/bin"],
                homeDirectories: ["/tmp/home"],
                pathEnvironment: "/tmp/bin"
            )
        }
    }

    private struct PerformanceDiagnosticIBMBobCommandRunner: ProviderCommandRunning {
        struct Invocation: Hashable {
            let executable: String
            let arguments: [String]
        }

        enum StubbedResult {
            case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
        }

        let results: [Invocation: StubbedResult]

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
                throw NSError(
                    domain: "PerformanceDiagnosticIBMBobCommandRunner",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"]
                )
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private struct PerformanceDiagnosticStubProviderModule: ProviderModule {
        let provider: Provider

        init(providerID: ProviderID) {
            self.provider = Provider(id: providerID)
        }

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
        func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

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

        func readCatalog(
            _ request: ProviderModuleCatalogReadRequest,
            actions: ProviderModuleCatalogReadActions
        ) async throws -> ProviderModuleCatalogReadResult {
            ProviderModuleCatalogReadResult(
                health: ProviderHealthSummary(
                    state: .available,
                    summary: "Ready",
                    resolvedExecutable: "/tmp/\(provider.id.rawValue)",
                    launchability: .launchable
                ),
                capabilities: ProviderCapabilities(
                    launchDefaultSession: ProviderCapability(
                        action: .launchDefaultSession, isSupported: true, isEnabled: true),
                    createNamedSession: ProviderCapability(
                        action: .createNamedSession, isSupported: true, isEnabled: true)
                ),
                prelaunchPrimarySurface: .terminal,
                defaultSession: ProviderDefaultSessionSummary(
                    state: .notCreated,
                    summary: "No default session yet",
                    actionTitle: "Launch"
                )
            )
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            ProviderCapabilities(
                launchDefaultSession: ProviderCapability(
                    action: .launchDefaultSession, isSupported: true, isEnabled: true),
                createNamedSession: ProviderCapability(action: .createNamedSession, isSupported: true, isEnabled: true)
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface { .terminal }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool { false }
    }
#endif
