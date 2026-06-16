#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService

    struct ServicePerformanceBaselineFixtures {
        struct WorkspaceCatalogFixture {
            let service: NexusService
            let workspace: Workspace
        }

        struct SessionFixture {
            let service: NexusService
            let workspace: Workspace
            let session: Session?
        }

        static func makeWorkspaceCatalogFixture() throws -> WorkspaceCatalogFixture {
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
                        PerformanceBaselineStubProviderModule(providerID: providerID)
                    }
                )
            )
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Workspace",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            return WorkspaceCatalogFixture(service: service, workspace: workspace)
        }

        static func makeIBMBobSessionFixture() throws -> SessionFixture {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: PerformanceBaselineIBMBobProviderHealthFacts(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(
                    launcher: ProcessSessionRuntimeLauncher(
                        ibmBobTransportFactory: { _, _, _ in
                            PerformanceBaselineIBMBobSyncTransport()
                        }
                    )
                )
            )
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Bob",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            return SessionFixture(service: service, workspace: workspace, session: nil)
        }

        static func makeStructuredSessionFixture() throws -> SessionFixture {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: PerformanceBaselineStructuredProviderHealthFacts(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(
                    launcher: PerformanceBaselineStructuredRuntimeLauncher())
            )
            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Pi",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
            return SessionFixture(service: service, workspace: workspace, session: session)
        }

        static func latestDiagnostic(
            in service: NexusService,
            matching: (PerformanceDiagnosticRecord) -> Bool
        ) throws -> PerformanceDiagnosticRecord? {
            try service.listPerformanceDiagnostics(limit: 20).first(where: matching)
        }
    }

    private struct PerformanceBaselineStubProviderModule: ProviderModule {
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

    private struct PerformanceBaselineIBMBobProviderHealthFacts: ProviderHealthEvaluating {
        private let executableResolver = PerformanceBaselineIBMBobExecutableResolver(executables: [
            "bob": "/tmp/fake-bob"
        ])
        private let commandRunner = PerformanceBaselineIBMBobCommandRunner(results: [
            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(
                stdout: "3.4.5\n"),
            .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(
                stdout: "[]\n"),
        ])
        private let localShellCommandBuilder = LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])

        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
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

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            if providerID == .ibmBob {
                return await ProviderHealthFacts(
                    executableResolver: executableResolver,
                    commandRunner: commandRunner,
                    localShellCommandBuilder: localShellCommandBuilder
                ).healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
            }
            return ProviderHealthSummary(state: .notChecked, summary: "Health checks coming soon")
        }
    }

    private struct PerformanceBaselineIBMBobExecutableResolver: ProviderExecutableResolving {
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

    private struct PerformanceBaselineIBMBobCommandRunner: ProviderCommandRunning {
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
                    domain: "PerformanceBaselineIBMBobCommandRunner",
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

    private struct PerformanceBaselineStructuredProviderHealthFacts: ProviderHealthEvaluating {
        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
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

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
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

    private final class PerformanceBaselineStructuredRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            _ = session
            _ = workspace
            _ = launchConfiguration
            return PerformanceBaselineStructuredRuntime()
        }
    }

    private final class PerformanceBaselineStructuredRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .ready
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        private let lock = NSLock()
        private var hasPendingApproval = false
        private var approvalRequest = SessionApprovalRequest(title: "Deploy?", text: "Deploy?", state: .pending)
        private var changeHandler: (@Sendable () -> Void)?

        func sessionScreen(for session: Session) -> SessionScreen {
            lock.lock()
            let hasPendingApproval = self.hasPendingApproval
            let approvalRequest = self.approvalRequest
            lock.unlock()

            var activityItems = [SessionActivityItem(kind: .status, text: "Pi ready")]
            var approvalRequests: [SessionApprovalRequest] = []
            var transcript = ""

            if hasPendingApproval {
                transcript = "> deploy"
                activityItems.append(SessionActivityItem(kind: .message, text: "You: deploy"))
                activityItems.append(SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy?"))
                approvalRequests = [approvalRequest]
            }

            return SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                transcript: transcript,
                activityItems: activityItems,
                approvalRequests: approvalRequests
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
            if text == "deploy" {
                hasPendingApproval = true
                approvalRequest = SessionApprovalRequest(
                    id: approvalRequest.id, title: "Deploy?", text: "Deploy?", state: .pending)
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

    private final class PerformanceBaselineIBMBobSyncTransport: IBMBobTransporting, @unchecked Sendable {
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var stderrLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (Int32) -> Void)?

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stderrLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {
            terminationHandler?(0)
        }

        func terminate() throws {}
    }

    struct PerformanceBaselineReport {
        static func render(flow: String, record: PerformanceDiagnosticRecord) -> String {
            let steps = record.steps
                .map { "\($0.name)=\($0.elapsedMilliseconds)ms" }
                .joined(separator: ", ")
            let metrics =
                record.metrics.isEmpty
                ? "none"
                : record.metrics
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")

            return
                "[Baseline] \(flow): operation=\(record.operation.rawValue) total=\(record.totalElapsedMilliseconds)ms steps=[\(steps)] metrics=[\(metrics)]"
        }
    }
#endif
