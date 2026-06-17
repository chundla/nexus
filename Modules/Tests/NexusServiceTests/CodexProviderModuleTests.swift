#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct CodexProviderModuleTests {
        @Test func serviceProviderRegistryRoutesCodexThroughCodexProviderModule() {
            let registry = ServiceSessionProviderRegistry.providerModules()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let remoteContext = RemoteWorkspaceHealthContext(
                host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
                hostValidation: HostValidationSnapshot(
                    hostID: hostID,
                    state: .available,
                    summary: "Host is available",
                    checkedAt: Date()
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspaceID,
                    state: .available,
                    summary: "Workspace is available",
                    checkedAt: Date()
                )
            )

            let module = registry.module(for: .codex)

            #expect(module.supportsDefaultSessionLaunch(in: workspace))
            #expect(module.supportsNamedSessions(in: workspace))
            #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
            #expect(
                module.reusesRemoteHealthSnapshot(
                    ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
                    remoteContext: remoteContext
                ))
        }

        @Test func codexProviderModuleHealthUsesProviderHealthFactsInsteadOfAdapter() async {
            let module = CodexProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Codex",
                kind: .local,
                folderPath: "/tmp/local-codex",
                primaryGroupID: UUID()
            )
            let providerHealthEvaluator = RecordingCodexProviderHealthFacts(
                summary: ProviderHealthSummary(
                    state: .available,
                    summary: "Codex health from evaluator",
                    resolvedExecutable: "/tmp/fake-codex",
                    launchability: .launchable
                )
            )

            let health = await module.providerHealthSummary(
                for: workspace,
                remoteContext: nil,
                providerHealthEvaluator: providerHealthEvaluator
            )

            #expect(health.summary == "Codex health from evaluator")
            #expect(
                providerHealthEvaluator.requests == [
                    .init(providerID: .codex, workspaceID: workspace.id)
                ])
        }

        @Test func codexProviderModuleOwnsFreshOpenPlanningForLocalAndRemoteCodexSessions() async throws {
            let module = CodexProviderModule()
            let localWorkspace = Workspace(
                id: UUID(),
                name: "Local Codex",
                kind: .local,
                folderPath: "/tmp/local-codex",
                primaryGroupID: UUID()
            )
            let remoteWorkspace = Workspace(
                id: UUID(),
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: UUID()
            )
            let tracker = FreshOpenActionTracker()
            let actions = makeFreshOpenSessionActions(
                tracker: tracker,
                providerID: .codex,
                healthSummary: { workspace in
                    ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: workspace.kind == .remote ? "/tmp/remote-codex" : "/tmp/local-codex",
                        launchability: .launchable
                    )
                }
            )

            let localDefaultOpen = try await module.openFreshSession(
                .launchDefaultSession(workspace: localWorkspace),
                actions: actions
            )
            let localNamedOpen = try await module.openFreshSession(
                .createNamedSession(workspace: localWorkspace),
                actions: actions
            )
            let remoteDefaultOpen = try await module.openFreshSession(
                .launchDefaultSession(workspace: remoteWorkspace),
                actions: actions
            )

            #expect(
                localDefaultOpen
                    == .launch(
                        ProviderModuleFreshSessionLaunch(
                            primarySurface: .structuredActivityFeed,
                            executable: "/tmp/local-codex"
                        )
                    ))
            #expect(
                localNamedOpen
                    == .launch(
                        ProviderModuleFreshSessionLaunch(
                            primarySurface: .structuredActivityFeed,
                            executable: "/tmp/local-codex"
                        )
                    ))
            #expect(
                remoteDefaultOpen
                    == .launch(
                        ProviderModuleFreshSessionLaunch(
                            primarySurface: .structuredActivityFeed,
                            executable: "/tmp/remote-codex"
                        )
                    ))
            #expect(
                tracker.healthRequests == [
                    .init(workspaceID: localWorkspace.id, providerID: .codex),
                    .init(workspaceID: localWorkspace.id, providerID: .codex),
                    .init(workspaceID: remoteWorkspace.id, providerID: .codex),
                ])
        }

        @Test func codexProviderModuleDerivesLocalCatalogReadFromRawCodexExecutableFacts() async throws {
            let module = CodexProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Codex",
                kind: .local,
                folderPath: "/tmp/local-codex",
                primaryGroupID: UUID()
            )
            let providerHealthEvaluator = RecordingCodexHealthFactProvider(
                localExecutableFacts: resolvedLocalCodexExecutableFacts(
                    executable: "/tmp/fake-codex",
                    version: "1.2.3",
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .warning,
                            code: "versionUnavailable",
                            message: "Version came from the shared probe"
                        )
                    ]
                )
            )

            let catalogRead = try await module.readCatalog(
                ProviderModuleCatalogReadRequest(
                    workspace: workspace,
                    remoteContext: nil,
                    defaultSession: nil
                ),
                actions: ProviderModuleCatalogReadActions(
                    providerHealthSummary: {
                        await module.providerHealthSummary(
                            for: workspace,
                            remoteContext: nil,
                            providerHealthEvaluator: providerHealthEvaluator
                        )
                    }
                )
            )

            #expect(
                catalogRead.health
                    == ProviderHealthSummary(
                        state: .available,
                        summary: "Codex 1.2.3 is available",
                        resolvedExecutable: "/tmp/fake-codex",
                        version: "1.2.3",
                        launchability: .launchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "versionUnavailable",
                                message: "Version came from the shared probe"
                            )
                        ]
                    ))
            #expect(providerHealthEvaluator.localProbeRequests == [workspace.id])
            #expect(
                providerHealthEvaluator.localReadinessRequests == [
                    .init(workspaceID: workspace.id, executable: "/tmp/fake-codex")
                ])
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
            #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
            #expect(catalogRead.capabilities.createNamedSession.isEnabled)
            #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
        }

        @Test func codexProviderModuleDerivesRemoteBlockedCatalogReadFromPrerequisiteFacts() async throws {
            let module = CodexProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingCodexHealthFactProvider(
                localExecutableFacts: resolvedLocalCodexExecutableFacts(
                    executable: "/tmp/unused",
                    version: nil
                )
            )
            let remoteContext = RemoteWorkspaceHealthContext(
                host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
                hostValidation: HostValidationSnapshot(
                    hostID: hostID,
                    state: .unavailable,
                    summary: "SSH authentication failed",
                    checkedAt: Date()
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspaceID,
                    state: .available,
                    summary: "Workspace is available",
                    checkedAt: Date()
                )
            )

            let catalogRead = try await module.readCatalog(
                ProviderModuleCatalogReadRequest(
                    workspace: workspace,
                    remoteContext: remoteContext,
                    defaultSession: nil
                ),
                actions: ProviderModuleCatalogReadActions(
                    providerHealthSummary: {
                        await module.providerHealthSummary(
                            for: workspace,
                            remoteContext: remoteContext,
                            providerHealthEvaluator: providerHealthEvaluator
                        )
                    }
                )
            )

            #expect(
                catalogRead.health
                    == ProviderHealthSummary(
                        state: .blocked,
                        summary: "Provider Health is blocked by Host Validation",
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "hostValidationBlocked",
                                message:
                                    "Provider Health for Codex is blocked by Host Validation: SSH authentication failed."
                            )
                        ]
                    ))
            #expect(providerHealthEvaluator.remoteProbeRequests.isEmpty)
            #expect(providerHealthEvaluator.remoteReadinessRequests.isEmpty)
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
            #expect(catalogRead.capabilities.launchDefaultSession.isEnabled == false)
            #expect(
                catalogRead.capabilities.launchDefaultSession.disabledReason
                    == "Provider Health is blocked by Host Validation")
            #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
        }

        @Test func codexProviderModuleDerivesRemoteCatalogReadFromRawCodexProbeFacts() async throws {
            let module = CodexProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingCodexHealthFactProvider(
                localExecutableFacts: resolvedLocalCodexExecutableFacts(
                    executable: "/tmp/unused",
                    version: nil
                ),
                remoteExecutableFacts: .facts(
                    RemoteProviderProbeFacts(
                        executable: "/home/tester/.local/bin/codex",
                        version: "1.2.3",
                        resolutionDetail: nil,
                        probeDetail: nil
                    )
                ),
                remoteReadinessResult: .authenticationUncertain("Codex auth readiness could not be confirmed.")
            )
            let remoteContext = RemoteWorkspaceHealthContext(
                host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
                hostValidation: HostValidationSnapshot(
                    hostID: hostID,
                    state: .available,
                    summary: "Host is available",
                    checkedAt: Date()
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspaceID,
                    state: .available,
                    summary: "Workspace is available",
                    checkedAt: Date()
                )
            )

            let catalogRead = try await module.readCatalog(
                ProviderModuleCatalogReadRequest(
                    workspace: workspace,
                    remoteContext: remoteContext,
                    defaultSession: nil
                ),
                actions: ProviderModuleCatalogReadActions(
                    providerHealthSummary: {
                        await module.providerHealthSummary(
                            for: workspace,
                            remoteContext: remoteContext,
                            providerHealthEvaluator: providerHealthEvaluator
                        )
                    }
                )
            )

            #expect(
                catalogRead.health
                    == ProviderHealthSummary(
                        state: .available,
                        summary: "Codex 1.2.3 is available",
                        resolvedExecutable: "/home/tester/.local/bin/codex",
                        version: "1.2.3",
                        launchability: .launchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .info,
                                code: "remoteProbe",
                                message: "Validated remote Codex launch prerequisites on Build Server for /srv/api."
                            ),
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "remoteAuthUncertain",
                                message: "Codex auth readiness could not be confirmed."
                            ),
                        ]
                    ))
            #expect(providerHealthEvaluator.remoteProbeRequests == [workspace.id])
            #expect(
                providerHealthEvaluator.remoteReadinessRequests == [
                    .init(workspaceID: workspace.id, hostID: hostID, executable: "/home/tester/.local/bin/codex")
                ])
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
            #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
            #expect(catalogRead.capabilities.createNamedSession.isEnabled)
            #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
        }

        @Test func codexProviderModuleClassifiesRemoteRawProbeFactsWithoutSharedRemoteHealthAdapter() async {
            let module = CodexProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingCodexHealthFactProvider(
                localExecutableFacts: resolvedLocalCodexExecutableFacts(
                    executable: "/tmp/unused",
                    version: nil
                ),
                remoteExecutableFacts: .sshLaunchFailed("direct remote probe should stay unused")
            )
            let remoteContext = RemoteWorkspaceHealthContext(
                host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
                hostValidation: HostValidationSnapshot(
                    hostID: hostID,
                    state: .available,
                    summary: "Host is available",
                    checkedAt: Date()
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspaceID,
                    state: .available,
                    summary: "Workspace is available",
                    checkedAt: Date()
                ),
                probeFacts: RemoteWorkspaceProbeFacts(
                    tmuxAvailable: true,
                    workspacePath: .available,
                    providerFacts: [
                        .codex: RemoteProviderProbeFacts(
                            executable: nil,
                            version: nil,
                            resolutionDetail: "NEXUS_REMOTE_CODEX_NOT_FOUND",
                            probeDetail: nil
                        )
                    ]
                )
            )

            let health = await module.providerHealthSummary(
                for: workspace,
                remoteContext: remoteContext,
                providerHealthEvaluator: providerHealthEvaluator
            )

            #expect(
                health
                    == ProviderHealthSummary(
                        state: .unavailable,
                        summary: "Codex is unavailable on the Remote Workspace",
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "remoteExecutableNotFound",
                                message:
                                    "Codex executable was not found in the remote shell environments Nexus checked."
                            )
                        ]
                    ))
            #expect(providerHealthEvaluator.remoteProbeRequests.isEmpty)
            #expect(providerHealthEvaluator.remoteReadinessRequests.isEmpty)
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
        }

        @Test func codexProviderModulePreservesCodexCatalogReadBehavior() async throws {
            let module = CodexProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingCodexProviderHealthFacts(
                summary: ProviderHealthSummary(
                    state: .available,
                    summary: "Codex module health",
                    resolvedExecutable: "/tmp/fake-codex",
                    launchability: .launchable
                )
            )
            let remoteContext = RemoteWorkspaceHealthContext(
                host: NexusDomain.Host(id: hostID, name: "Build Server", sshTarget: "build-box"),
                hostValidation: HostValidationSnapshot(
                    hostID: hostID,
                    state: .available,
                    summary: "Host is available",
                    checkedAt: Date()
                ),
                workspaceAvailability: WorkspaceAvailabilitySnapshot(
                    workspaceID: workspaceID,
                    state: .available,
                    summary: "Workspace is available",
                    checkedAt: Date()
                )
            )

            let catalogRead = try await module.readCatalog(
                ProviderModuleCatalogReadRequest(
                    workspace: workspace,
                    remoteContext: remoteContext,
                    defaultSession: nil
                ),
                actions: ProviderModuleCatalogReadActions(
                    providerHealthSummary: {
                        await module.providerHealthSummary(
                            for: workspace,
                            remoteContext: remoteContext,
                            providerHealthEvaluator: providerHealthEvaluator
                        )
                    }
                )
            )

            #expect(catalogRead.health.summary == "Codex module health")
            #expect(
                providerHealthEvaluator.requests == [
                    .init(providerID: .codex, workspaceID: workspace.id)
                ])
            #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
            #expect(catalogRead.capabilities.createNamedSession.isEnabled)
            #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
            #expect(
                module.reusesRemoteHealthSnapshot(
                    ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
                    remoteContext: remoteContext
                ))
        }

        @Test func codexProviderModuleKeepsSharedPersistedRelaunchPlan() {
            let module = CodexProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: UUID()
            )
            let session = Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .codex,
                isDefault: true,
                state: .ready
            )
            let execution = PersistedSessionLaunchExecution(
                session: session,
                workspace: workspace,
                launchSnapshot: LaunchSnapshot(
                    sessionID: session.id,
                    workspaceID: workspace.id,
                    providerID: .codex,
                    primarySurface: .structuredActivityFeed,
                    resolvedExecutable: "/tmp/codex",
                    resolvedWorkingDirectory: workspace.folderPath
                ),
                mode: .recoverRemoteRuntime,
                sessionRecordAdapterMetadataSource: .stored
            )

            #expect(
                module.planPersistedSessionRelaunch(.init(execution: execution))
                    == .recoverRemoteRuntime(
                        ProviderModuleFreshRemotePersistedSessionRelaunch(
                            sessionRecordAdapterMetadataSource: .stored,
                            retriesWithoutContinuity: true
                        )
                    )
            )
        }

        @Test func codexProviderModuleChoosesLocalProtocolNativeRuntimeConstructionThroughProviderModuleSeam()
            async throws
        {
            let module = CodexProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Codex",
                kind: .local,
                folderPath: "/tmp/local-codex",
                primaryGroupID: UUID()
            )
            let session = Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .codex,
                isDefault: true,
                state: .ready
            )
            let tracker = CodexRuntimeConstructionTracker()

            let runtime = try await module.constructRuntime(
                for: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/tmp/fake-codex",
                    workingDirectory: workspace.folderPath,
                    remoteHost: nil
                ),
                actions: ProviderModuleRuntimeConstructionActions(
                    makeLocalTerminalRuntime: {
                        Issue.record("Codex should not choose a terminal runtime for local structured Sessions")
                        return StaticCodexRuntime()
                    },
                    makeRemoteTerminalRuntime: {
                        Issue.record("Codex should not choose a terminal runtime for local structured Sessions")
                        return StaticCodexRuntime()
                    },
                    makeLocalPiRuntime: { StaticCodexRuntime() },
                    makeRemotePiRuntime: { StaticCodexRuntime() },
                    makeLocalCodexRuntime: {
                        tracker.requests.append(.localProtocolNative)
                        return StaticCodexRuntime()
                    },
                    makeRemoteCodexRuntime: {
                        Issue.record("Codex should not choose a remote runtime for local structured Sessions")
                        return StaticCodexRuntime()
                    },
                    makeLocalIBMBobRuntime: { StaticCodexRuntime() },
                    makeRemoteIBMBobRuntime: { StaticCodexRuntime() }
                )
            )

            #expect(tracker.requests == [.localProtocolNative])
            #expect(runtime?.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
        }

        @Test func codexProviderModuleChoosesRemoteProtocolNativeRuntimeConstructionThroughProviderModuleSeam()
            async throws
        {
            let module = CodexProviderModule()
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")
            let workspace = Workspace(
                id: UUID(),
                name: "Remote Codex",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: host.id
            )
            let session = Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .codex,
                isDefault: true,
                state: .ready
            )
            let tracker = CodexRuntimeConstructionTracker()

            let runtime = try await module.constructRuntime(
                for: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/home/tester/.local/bin/codex",
                    workingDirectory: workspace.folderPath,
                    remoteHost: host,
                    remoteRuntimeIdentifier: "nexus-runtime-1"
                ),
                actions: ProviderModuleRuntimeConstructionActions(
                    makeLocalTerminalRuntime: {
                        Issue.record("Codex should not choose a terminal runtime for remote structured Sessions")
                        return StaticCodexRuntime()
                    },
                    makeRemoteTerminalRuntime: {
                        Issue.record("Codex should not choose a terminal runtime for remote structured Sessions")
                        return StaticCodexRuntime()
                    },
                    makeLocalPiRuntime: { StaticCodexRuntime() },
                    makeRemotePiRuntime: { StaticCodexRuntime() },
                    makeLocalCodexRuntime: {
                        Issue.record("Codex should not choose a local runtime for remote structured Sessions")
                        return StaticCodexRuntime()
                    },
                    makeRemoteCodexRuntime: {
                        tracker.requests.append(.remoteProtocolNative)
                        return StaticCodexRuntime()
                    },
                    makeLocalIBMBobRuntime: { StaticCodexRuntime() },
                    makeRemoteIBMBobRuntime: { StaticCodexRuntime() }
                )
            )

            #expect(tracker.requests == [.remoteProtocolNative])
            #expect(runtime?.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
        }

        @Test func persistedCodexRelaunchUsesProviderModuleSessionTransitionPlan() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexProviderModuleTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let initialService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ReadyCodexProviderHealthFacts(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingStaticCodexRuntimeLauncher())
            )
            let group = try initialService.createWorkspaceGroup(name: "Solo Group")
            let workspace = try initialService.createLocalWorkspace(
                name: "Local Codex",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try initialService.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)

            let tracker = CodexProviderModuleSessionTransitionTracker()
            let relaunchedService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ReadyCodexProviderHealthFacts(),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: RecordingStaticCodexRuntimeLauncher()),
                providerModuleRegistry: ProviderModuleRegistry(
                    modules: [
                        .codex: TrackingCodexSessionTransitionProviderModule(tracker: tracker)
                    ]
                )
            )

            _ = try relaunchedService.launchOrResumeSession(sessionID: session.id)

            #expect(
                tracker.requests == [
                    .relaunchPersisted(sessionID: session.id)
                ])
        }
    }

    private func makeFreshOpenSessionActions(
        tracker: FreshOpenActionTracker,
        providerID: ProviderID,
        healthSummary: @escaping (Workspace) -> ProviderHealthSummary
    ) -> ProviderModuleFreshSessionOpenActions {
        ProviderModuleFreshSessionOpenActions(
            providerHealthSummary: { workspace in
                tracker.healthRequests.append(.init(workspaceID: workspace.id, providerID: providerID))
                return healthSummary(workspace)
            }
        )
    }

    private func resolvedLocalCodexExecutableFacts(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic] = []
    ) -> LocalCodexExecutableFacts {
        LocalCodexExecutableFacts(
            resolution: ProviderExecutableResolution(
                resolvedExecutable: executable,
                searchedDirectories: [],
                homeDirectories: [],
                pathEnvironment: nil
            ),
            version: version,
            diagnostics: diagnostics
        )
    }

    private final class FreshOpenActionTracker: @unchecked Sendable {
        struct SessionRequest: Equatable {
            let workspaceID: UUID
            let providerID: ProviderID
        }

        var healthRequests: [SessionRequest] = []
    }

    private final class RecordingCodexProviderHealthFacts: @unchecked Sendable, ProviderHealthEvaluating {
        struct Request: Equatable {
            let providerID: ProviderID
            let workspaceID: UUID
        }

        let summary: ProviderHealthSummary
        private(set) var requests: [Request] = []

        init(summary: ProviderHealthSummary) {
            self.summary = summary
        }

        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            []
        }

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            requests.append(.init(providerID: providerID, workspaceID: workspace.id))
            return summary
        }
    }

    private final class RecordingCodexHealthFactProvider: @unchecked Sendable, ProviderHealthEvaluating,
        CodexProviderHealthFactProviding
    {
        struct LocalReadinessRequest: Equatable {
            let workspaceID: UUID
            let executable: String
        }

        struct RemoteReadinessRequest: Equatable {
            let workspaceID: UUID
            let hostID: UUID
            let executable: String
        }

        let localExecutableFacts: LocalCodexExecutableFacts
        let localReadinessResult: LocalCodexReadinessProbeResult
        let remoteExecutableFacts: RemoteCodexExecutableProbeResult
        let remoteReadinessResult: RemoteCodexReadinessProbeResult
        private(set) var localProbeRequests: [UUID] = []
        private(set) var localReadinessRequests: [LocalReadinessRequest] = []
        private(set) var remoteProbeRequests: [UUID] = []
        private(set) var remoteReadinessRequests: [RemoteReadinessRequest] = []
        private(set) var legacyRequests: [UUID] = []

        init(
            localExecutableFacts: LocalCodexExecutableFacts,
            localReadinessResult: LocalCodexReadinessProbeResult = .ready,
            remoteExecutableFacts: RemoteCodexExecutableProbeResult = .sshLaunchFailed("unexpected"),
            remoteReadinessResult: RemoteCodexReadinessProbeResult = .ready
        ) {
            self.localExecutableFacts = localExecutableFacts
            self.localReadinessResult = localReadinessResult
            self.remoteExecutableFacts = remoteExecutableFacts
            self.remoteReadinessResult = remoteReadinessResult
        }

        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            []
        }

        func healthSummary(
            for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?
        ) async -> ProviderHealthSummary {
            legacyRequests.append(workspace.id)
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "legacy evaluator path should stay unused",
                launchability: .notLaunchable
            )
        }

        func localCodexExecutableFacts(workspace: Workspace) async -> LocalCodexExecutableFacts {
            localProbeRequests.append(workspace.id)
            return localExecutableFacts
        }

        func probeLocalCodexReadiness(workspace: Workspace, executable: String) async -> LocalCodexReadinessProbeResult
        {
            localReadinessRequests.append(.init(workspaceID: workspace.id, executable: executable))
            return localReadinessResult
        }

        func remoteCodexExecutableFacts(workspace: Workspace, host: NexusDomain.Host) async
            -> RemoteCodexExecutableProbeResult
        {
            remoteProbeRequests.append(workspace.id)
            return remoteExecutableFacts
        }

        func probeRemoteCodexReadiness(
            workspace: Workspace,
            host: NexusDomain.Host,
            executable: String
        ) async -> RemoteCodexReadinessProbeResult {
            remoteReadinessRequests.append(.init(workspaceID: workspace.id, hostID: host.id, executable: executable))
            return remoteReadinessResult
        }
    }

    private enum CodexRuntimeConstructionRequest: Equatable {
        case localProtocolNative
        case remoteProtocolNative
    }

    private final class CodexRuntimeConstructionTracker: @unchecked Sendable {
        var requests: [CodexRuntimeConstructionRequest] = []
    }

    private enum CodexProviderModuleSessionTransitionRequestExpectation: Equatable {
        case openFresh
        case relaunchPersisted(sessionID: UUID)
        case bootstrapReadyWithoutRuntime(sessionID: UUID)

        init(request: ProviderModuleSessionTransitionRequest) {
            switch request {
            case .openFresh:
                self = .openFresh
            case .relaunchPersisted(let relaunchRequest):
                self = .relaunchPersisted(sessionID: relaunchRequest.execution.session.id)
            case .bootstrapReadyWithoutRuntime(let bootstrapRequest):
                self = .bootstrapReadyWithoutRuntime(sessionID: bootstrapRequest.session.id)
            }
        }
    }

    private final class CodexProviderModuleSessionTransitionTracker: @unchecked Sendable {
        var requests: [CodexProviderModuleSessionTransitionRequestExpectation] = []
    }

    private struct TrackingCodexSessionTransitionProviderModule: ProviderModule {
        let provider = Provider(id: .codex)
        let tracker: CodexProviderModuleSessionTransitionTracker

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool { true }
        func supportsNamedSessions(in workspace: Workspace) -> Bool { true }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            await providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            makeProviderCapabilities(
                provider: provider,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                health: health,
                defaultSession: defaultSession
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            .structuredActivityFeed
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func planSessionTransition(
            _ request: ProviderModuleSessionTransitionRequest
        ) async throws -> ProviderModuleSessionTransitionPlan {
            tracker.requests.append(.init(request: request))
            switch request {
            case .openFresh:
                Issue.record("Persisted relaunch test should not open a fresh Session")
                return .openFresh(.failed("unexpected"))
            case .relaunchPersisted:
                return .relaunchPersisted(.sharedLaunch)
            case .bootstrapReadyWithoutRuntime(let bootstrapRequest):
                return .bootstrapReadyWithoutRuntime(planReadyWithoutRuntimeBootstrap(bootstrapRequest))
            }
        }

        func planPersistedSessionRelaunch(
            _ request: ProviderModulePersistedSessionRelaunchRequest
        ) -> ProviderModulePersistedSessionRelaunchPlan {
            Issue.record("Persisted relaunch should route through planSessionTransition")
            return .sharedLaunch
        }
    }

    private struct ReadyCodexProviderHealthFacts: ProviderHealthEvaluating {
        func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async
            -> [WorkspaceProviderCard]
        {
            ProviderID.allCases.map { providerID in
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
                        launchability: .launchable
                    ),
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
            ProviderHealthSummary(
                state: .available,
                summary: "Ready",
                resolvedExecutable: "/tmp/fake-\(providerID.rawValue)",
                launchability: .launchable
            )
        }
    }

    private final class RecordingStaticCodexRuntimeLauncher: SessionRuntimeLaunching, @unchecked Sendable {
        func makeRuntime(
            session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration
        ) async throws -> any SessionRuntime {
            StaticCodexRuntime()
        }
    }

    private final class StaticCodexRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .ready
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "Codex ready")
        }

        func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
        func stop() throws {}
        func sendInput(_ text: String) throws {}
        func sendText(_ text: String) throws {}
        func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
        func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
        func resize(columns: Int, rows: Int) throws {}
    }
#endif
