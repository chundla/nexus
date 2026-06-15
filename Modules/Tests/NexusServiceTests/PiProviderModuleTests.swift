#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct PiProviderModuleTests {
        @Test func testProviderModuleUsesSharedFreshOpenAndPersistedRelaunchPlan() async throws {
            let module = TestProviderModule(
                providerID: .claude,
                healthSummaryEvaluator: { _, _, _ in
                    ProviderHealthSummary(
                        state: .available, summary: "Ready", resolvedExecutable: "/tmp/fake-claude",
                        launchability: .launchable)
                }
            )
            let workspace = Workspace(
                id: UUID(),
                name: "Local Claude",
                kind: .local,
                folderPath: "/tmp/local-claude",
                primaryGroupID: UUID()
            )
            let launchedSession = Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .claude,
                name: "Review",
                isDefault: false,
                state: .ready
            )
            let openTracker = FreshOpenActionTracker()

            let openResult = try await module.openFreshSession(
                .launchDefaultSession(workspace: workspace),
                actions: makeFreshOpenSessionActions(
                    tracker: openTracker,
                    providerID: .claude,
                    healthSummary: { _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Ready",
                            resolvedExecutable: "/tmp/fake-claude",
                            launchability: .launchable
                        )
                    }
                )
            )
            let relaunchPlan = module.planPersistedSessionRelaunch(
                ProviderModulePersistedSessionRelaunchRequest(
                    execution: PersistedSessionLaunchExecution(
                        session: launchedSession,
                        workspace: workspace,
                        launchSnapshot: LaunchSnapshot(
                            sessionID: launchedSession.id,
                            workspaceID: workspace.id,
                            providerID: .claude,
                            primarySurface: .terminal,
                            resolvedExecutable: "/tmp/claude",
                            resolvedWorkingDirectory: workspace.folderPath
                        ),
                        mode: .launch(forceFreshRemoteRuntime: false),
                        sessionRecordAdapterMetadataSource: .stored
                    )
                )
            )

            #expect(
                openResult
                    == .launch(
                        ProviderModuleFreshSessionLaunch(
                            primarySurface: .terminal,
                            executable: "/tmp/fake-claude"
                        )
                    ))
            #expect(relaunchPlan == .sharedLaunch)
            #expect(
                openTracker.healthRequests == [
                    .init(workspaceID: workspace.id, providerID: .claude)
                ])
            #expect(
                try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
                    NSError(domain: "PiProviderModuleTests", code: 1),
                    metadata: nil
                ) == false)
        }

        @Test func piProviderModuleOwnsPiLaunchSupportInsteadOfDelegatingToAdapter() {
            let module = PiProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Pi",
                kind: .local,
                folderPath: "/tmp/local-pi",
                primaryGroupID: UUID()
            )

            #expect(module.supportsDefaultSessionLaunch(in: workspace))
            #expect(module.supportsNamedSessions(in: workspace))
        }

        @Test func piProviderModuleHealthUsesProviderHealthFactsInsteadOfAdapter() async {
            let module = PiProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Pi",
                kind: .local,
                folderPath: "/tmp/local-pi",
                primaryGroupID: UUID()
            )
            let providerHealthEvaluator = RecordingPiProviderHealthFacts(
                summary: ProviderHealthSummary(
                    state: .available,
                    summary: "Pi health from evaluator",
                    resolvedExecutable: "/tmp/fake-pi",
                    launchability: .launchable
                )
            )

            let health = await module.providerHealthSummary(
                for: workspace,
                remoteContext: nil,
                providerHealthEvaluator: providerHealthEvaluator
            )

            #expect(health.summary == "Pi health from evaluator")
            #expect(
                providerHealthEvaluator.requests == [
                    .init(providerID: .pi, workspaceID: workspace.id)
                ])
        }

        @Test func piProviderModuleOwnsRemoteHealthSnapshotReusePolicyInsteadOfDelegatingToAdapter() {
            let module = PiProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()

            let shouldReuse = module.reusesRemoteHealthSnapshot(
                ProviderHealthSummary(
                    state: .available,
                    summary: "Pi ready",
                    checkedAt: Date()
                ),
                remoteContext: RemoteWorkspaceHealthContext(
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
            )

            #expect(shouldReuse)
        }

        @Test func piProviderModulePlansRemoteRecoveryAndFreshRemoteRelaunchBehindProviderModuleSeam() {
            let module = PiProviderModule()
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
            let localSession = Session(
                id: UUID(),
                workspaceID: localWorkspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let remoteSession = Session(
                id: UUID(),
                workspaceID: remoteWorkspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            )

            let localPlan = module.planPersistedSessionRelaunch(
                ProviderModulePersistedSessionRelaunchRequest(
                    execution: PersistedSessionLaunchExecution(
                        session: localSession,
                        workspace: localWorkspace,
                        launchSnapshot: LaunchSnapshot(
                            sessionID: localSession.id,
                            workspaceID: localWorkspace.id,
                            providerID: .pi,
                            primarySurface: .structuredActivityFeed,
                            resolvedExecutable: "/tmp/pi",
                            resolvedWorkingDirectory: localWorkspace.folderPath
                        ),
                        mode: .launch(forceFreshRemoteRuntime: false),
                        sessionRecordAdapterMetadataSource: .stored
                    )
                )
            )
            let remoteRecoveryPlan = module.planPersistedSessionRelaunch(
                ProviderModulePersistedSessionRelaunchRequest(
                    execution: PersistedSessionLaunchExecution(
                        session: remoteSession,
                        workspace: remoteWorkspace,
                        launchSnapshot: LaunchSnapshot(
                            sessionID: remoteSession.id,
                            workspaceID: remoteWorkspace.id,
                            providerID: .pi,
                            primarySurface: .structuredActivityFeed,
                            resolvedExecutable: "/tmp/pi",
                            resolvedWorkingDirectory: remoteWorkspace.folderPath
                        ),
                        mode: .recoverRemoteRuntime,
                        sessionRecordAdapterMetadataSource: .stored
                    )
                )
            )
            let remoteFreshPlan = module.planPersistedSessionRelaunch(
                ProviderModulePersistedSessionRelaunchRequest(
                    execution: PersistedSessionLaunchExecution(
                        session: remoteSession,
                        workspace: remoteWorkspace,
                        launchSnapshot: LaunchSnapshot(
                            sessionID: remoteSession.id,
                            workspaceID: remoteWorkspace.id,
                            providerID: .pi,
                            primarySurface: .structuredActivityFeed,
                            resolvedExecutable: "/tmp/pi",
                            resolvedWorkingDirectory: remoteWorkspace.folderPath
                        ),
                        mode: .launch(forceFreshRemoteRuntime: true),
                        sessionRecordAdapterMetadataSource: .stored
                    )
                )
            )

            #expect(localPlan == .sharedLaunch)
            #expect(
                remoteRecoveryPlan
                    == .recoverRemoteRuntime(
                        ProviderModuleFreshRemotePersistedSessionRelaunch(
                            sessionRecordAdapterMetadataSource: .stored,
                            retriesWithoutContinuity: true
                        )
                    ))
            #expect(
                remoteFreshPlan
                    == .launchFreshRemoteRuntime(
                        ProviderModuleFreshRemotePersistedSessionRelaunch(
                            sessionRecordAdapterMetadataSource: .stored,
                            retriesWithoutContinuity: true
                        )
                    ))
        }

        @Test func serviceProviderRegistryRoutesPiThroughPiProviderModule() {
            let registry = ServiceSessionProviderRegistry.providerModules()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Local Workspace",
                kind: .local,
                folderPath: "/tmp/workspace",
                primaryGroupID: UUID()
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
            let checkedSnapshot = ProviderHealthSummary(
                state: .available,
                summary: "reuse me",
                checkedAt: Date()
            )

            let piModule = registry.module(for: .pi)
            let claudeModule = registry.module(for: .claude)

            #expect(piModule.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
            #expect(claudeModule.prelaunchPrimarySurface(in: workspace) == .terminal)
            #expect(piModule.reusesRemoteHealthSnapshot(checkedSnapshot, remoteContext: remoteContext))
            #expect(claudeModule.reusesRemoteHealthSnapshot(checkedSnapshot, remoteContext: remoteContext))
        }

        @Test func serviceProviderRegistryKeepsDedicatedProviderModulesAvailableWithoutAdapterEntries() {
            let registry = ServiceSessionProviderRegistry.providerModules()
            let workspace = Workspace(
                id: UUID(),
                name: "Remote Workspace",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: UUID()
            )

            #expect(registry.module(for: .claude).supportsDefaultSessionLaunch(in: workspace))
            #expect(registry.module(for: .codex).prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
            #expect(registry.module(for: .ibmBob).supportsNamedSessions(in: workspace))
            #expect(registry.module(for: .pi).supportsNamedSessions(in: workspace))
        }

        @Test func piProviderModuleOwnsFreshOpenPlanningForLocalAndRemotePiSessions() async throws {
            let module = PiProviderModule()
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
            let tracker = FreshOpenActionTracker()
            let actions = makeFreshOpenSessionActions(
                tracker: tracker,
                providerID: .pi,
                healthSummary: { workspace in
                    ProviderHealthSummary(
                        state: .available,
                        summary: "Ready",
                        resolvedExecutable: workspace.kind == .remote ? "/tmp/remote-pi" : "/tmp/local-pi",
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
                            executable: "/tmp/local-pi"
                        )
                    ))
            #expect(
                localNamedOpen
                    == .launch(
                        ProviderModuleFreshSessionLaunch(
                            primarySurface: .structuredActivityFeed,
                            executable: "/tmp/local-pi"
                        )
                    ))
            #expect(
                remoteDefaultOpen
                    == .launch(
                        ProviderModuleFreshSessionLaunch(
                            primarySurface: .structuredActivityFeed,
                            executable: "/tmp/remote-pi"
                        )
                    ))
            #expect(
                tracker.healthRequests == [
                    .init(workspaceID: localWorkspace.id, providerID: .pi),
                    .init(workspaceID: localWorkspace.id, providerID: .pi),
                    .init(workspaceID: remoteWorkspace.id, providerID: .pi),
                ])
        }

        @Test func piProviderModuleRetriesFreshRemotePersistedRelaunchWithoutContinuityOnlyForRejectedPiLinkage() throws
        {
            let module = PiProviderModule()
            let linkageMetadata = PiSessionLinkage(
                piSessionID: "pi-session-1",
                sessionFile: "/tmp/pi-session-1.jsonl"
            ).sessionRecordAdapterMetadata

            let invalidPiSessionRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
                NSError(
                    domain: "PiProviderModuleTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Pi session linkage"]
                ),
                metadata: linkageMetadata
            )
            let missingSessionRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
                NSError(
                    domain: "PiProviderModuleTests",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "session not found"]
                ),
                metadata: linkageMetadata
            )
            let unrelatedErrorRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
                NSError(
                    domain: "PiProviderModuleTests",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "permission denied"]
                ),
                metadata: linkageMetadata
            )
            let missingMetadataRetry = try module.shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
                NSError(
                    domain: "PiProviderModuleTests",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Pi session linkage"]
                ),
                metadata: nil
            )

            #expect(invalidPiSessionRetry)
            #expect(missingSessionRetry)
            #expect(unrelatedErrorRetry == false)
            #expect(missingMetadataRetry == false)
        }

        @Test func piProviderModuleDerivesLocalCatalogReadFromSharedCLIProbeFacts() async throws {
            let module = PiProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Pi",
                kind: .local,
                folderPath: "/tmp/local-pi",
                primaryGroupID: UUID()
            )
            let providerHealthEvaluator = RecordingPiHealthFactProvider(
                localProbeResult: .ready(
                    executable: "/tmp/fake-pi",
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
                        summary: "Pi 1.2.3 is available",
                        resolvedExecutable: "/tmp/fake-pi",
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
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
            #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
            #expect(catalogRead.capabilities.createNamedSession.isEnabled)
            #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
        }

        @Test func piProviderModuleDerivesRemoteBlockedCatalogReadFromPrerequisiteFacts() async throws {
            let module = PiProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Pi",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingPiHealthFactProvider(
                localProbeResult: .ready(executable: "/tmp/unused", version: nil, diagnostics: [])
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
                                    "Provider Health for Pi is blocked by Host Validation: SSH authentication failed."
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

        @Test func piProviderModuleDerivesRemoteCatalogReadFromRawPiProbeFacts() async throws {
            let module = PiProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Pi",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingPiHealthFactProvider(
                localProbeResult: .ready(executable: "/tmp/unused", version: nil, diagnostics: []),
                remoteExecutableFacts: .sshLaunchFailed("direct remote probe should stay unused"),
                remoteReadinessResult: .authenticationUncertain("Pi auth readiness could not be confirmed.")
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
                        .pi: RemoteProviderProbeFacts(
                            executable: "/home/tester/.local/bin/pi",
                            version: "1.2.3",
                            resolutionDetail: nil,
                            probeDetail: nil
                        )
                    ]
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
                        summary: "Pi 1.2.3 is available",
                        resolvedExecutable: "/home/tester/.local/bin/pi",
                        version: "1.2.3",
                        launchability: .launchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .info,
                                code: "remoteProbe",
                                message: "Validated remote Pi launch prerequisites on Build Server for /srv/api."
                            ),
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "remoteAuthUncertain",
                                message: "Pi auth readiness could not be confirmed."
                            ),
                        ]
                    ))
            #expect(providerHealthEvaluator.remoteProbeRequests.isEmpty)
            #expect(
                providerHealthEvaluator.remoteReadinessRequests == [
                    .init(workspaceID: workspace.id, hostID: hostID, executable: "/home/tester/.local/bin/pi")
                ])
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
            #expect(catalogRead.capabilities.launchDefaultSession.isEnabled)
            #expect(catalogRead.capabilities.createNamedSession.isEnabled)
            #expect(catalogRead.prelaunchPrimarySurface == .structuredActivityFeed)
        }

        @Test func piProviderModuleClassifiesRemoteRawProbeFactsWithoutSharedRemoteHealthAdapter() async {
            let module = PiProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Remote Pi",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: hostID
            )
            let providerHealthEvaluator = RecordingPiHealthFactProvider(
                localProbeResult: .ready(executable: "/tmp/unused", version: nil, diagnostics: []),
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
                        .pi: RemoteProviderProbeFacts(
                            executable: nil,
                            version: nil,
                            resolutionDetail: "NEXUS_REMOTE_PI_NOT_FOUND",
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
                        summary: "Pi is unavailable on the Remote Workspace",
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "remoteExecutableNotFound",
                                message: "Pi executable was not found in the remote shell environments Nexus checked."
                            )
                        ]
                    ))
            #expect(providerHealthEvaluator.remoteProbeRequests.isEmpty)
            #expect(providerHealthEvaluator.remoteReadinessRequests.isEmpty)
            #expect(providerHealthEvaluator.legacyRequests.isEmpty)
        }

        @Test func piProviderModulePreservesPiCatalogReadBehavior() async {
            let module = PiProviderModule()
            let workspaceID = UUID()
            let hostID = UUID()
            let workspace = Workspace(
                id: workspaceID,
                name: "Local Pi",
                kind: .local,
                folderPath: "/tmp/local-pi",
                primaryGroupID: UUID()
            )
            let providerHealthEvaluator = RecordingPiProviderHealthFacts(
                summary: ProviderHealthSummary(
                    state: .available,
                    summary: "Pi module health",
                    resolvedExecutable: "/tmp/fake-pi",
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

            let health = await module.providerHealthSummary(
                for: workspace,
                remoteContext: nil,
                providerHealthEvaluator: providerHealthEvaluator
            )
            let capabilities = module.providerCapabilities(in: workspace, health: health, defaultSession: nil)

            #expect(health.summary == "Pi module health")
            #expect(
                providerHealthEvaluator.requests == [
                    .init(providerID: .pi, workspaceID: workspace.id)
                ])
            #expect(capabilities.launchDefaultSession.isEnabled)
            #expect(capabilities.createNamedSession.isEnabled)
            #expect(module.prelaunchPrimarySurface(in: workspace) == .structuredActivityFeed)
            #expect(
                module.reusesRemoteHealthSnapshot(
                    ProviderHealthSummary(state: .available, summary: "reuse me", checkedAt: Date()),
                    remoteContext: remoteContext
                ))
        }

        @Test func piProviderModuleChoosesLocalProtocolNativeRuntimeConstructionThroughProviderModuleSeam() async throws
        {
            let module = PiProviderModule()
            let workspace = Workspace(
                id: UUID(),
                name: "Local Pi",
                kind: .local,
                folderPath: "/tmp/local-pi",
                primaryGroupID: UUID()
            )
            let session = Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let tracker = PiRuntimeConstructionTracker()

            let runtime = try await module.constructRuntime(
                for: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/tmp/fake-pi",
                    workingDirectory: workspace.folderPath,
                    remoteHost: nil
                ),
                actions: ProviderModuleRuntimeConstructionActions(
                    makeLocalTerminalRuntime: {
                        Issue.record("Pi should not choose a terminal runtime for local structured Sessions")
                        return StaticPiRuntime()
                    },
                    makeRemoteTerminalRuntime: {
                        Issue.record("Pi should not choose a terminal runtime for local structured Sessions")
                        return StaticPiRuntime()
                    },
                    makeLocalPiRuntime: {
                        tracker.requests.append(.localProtocolNative)
                        return StaticPiRuntime()
                    },
                    makeRemotePiRuntime: {
                        Issue.record("Pi should not choose a remote runtime for local structured Sessions")
                        return StaticPiRuntime()
                    },
                    makeLocalCodexRuntime: { StaticPiRuntime() },
                    makeRemoteCodexRuntime: { StaticPiRuntime() },
                    makeLocalIBMBobRuntime: { StaticPiRuntime() },
                    makeRemoteIBMBobRuntime: { StaticPiRuntime() }
                )
            )

            #expect(tracker.requests == [.localProtocolNative])
            #expect(runtime?.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
        }

        @Test func piProviderModuleChoosesRemoteProtocolNativeRuntimeConstructionThroughProviderModuleSeam()
            async throws
        {
            let module = PiProviderModule()
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")
            let workspace = Workspace(
                id: UUID(),
                name: "Remote Pi",
                kind: .remote,
                folderPath: "/srv/api",
                primaryGroupID: UUID(),
                remoteHostID: host.id
            )
            let session = Session(
                id: UUID(),
                workspaceID: workspace.id,
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let tracker = PiRuntimeConstructionTracker()

            let runtime = try await module.constructRuntime(
                for: session,
                workspace: workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration(
                    executable: "/home/tester/.local/bin/pi",
                    workingDirectory: workspace.folderPath,
                    remoteHost: host,
                    remoteRuntimeIdentifier: "nexus-runtime-1"
                ),
                actions: ProviderModuleRuntimeConstructionActions(
                    makeLocalTerminalRuntime: {
                        Issue.record("Pi should not choose a terminal runtime for remote structured Sessions")
                        return StaticPiRuntime()
                    },
                    makeRemoteTerminalRuntime: {
                        Issue.record("Pi should not choose a terminal runtime for remote structured Sessions")
                        return StaticPiRuntime()
                    },
                    makeLocalPiRuntime: {
                        Issue.record("Pi should not choose a local runtime for remote structured Sessions")
                        return StaticPiRuntime()
                    },
                    makeRemotePiRuntime: {
                        tracker.requests.append(.remoteProtocolNative)
                        return StaticPiRuntime()
                    },
                    makeLocalCodexRuntime: { StaticPiRuntime() },
                    makeRemoteCodexRuntime: { StaticPiRuntime() },
                    makeLocalIBMBobRuntime: { StaticPiRuntime() },
                    makeRemoteIBMBobRuntime: { StaticPiRuntime() }
                )
            )

            #expect(tracker.requests == [.remoteProtocolNative])
            #expect(runtime?.sessionScreen(for: session).primarySurface == .structuredActivityFeed)
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

    private final class FreshOpenActionTracker: @unchecked Sendable {
        struct SessionRequest: Equatable {
            let workspaceID: UUID
            let providerID: ProviderID
        }

        var healthRequests: [SessionRequest] = []
    }

    private final class RecordingPiProviderHealthFacts: @unchecked Sendable, ProviderHealthEvaluating {
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

    private final class RecordingPiHealthFactProvider: @unchecked Sendable, ProviderHealthEvaluating,
        CLIProviderHealthFactProviding, PiProviderHealthFactProviding
    {
        struct RemoteReadinessRequest: Equatable {
            let workspaceID: UUID
            let hostID: UUID
            let executable: String
        }

        let localProbeResult: LocalCLIHealthProbeResult
        let remoteExecutableFacts: RemotePiExecutableProbeResult
        let remoteReadinessResult: RemotePiReadinessProbeResult
        private(set) var localProbeRequests: [UUID] = []
        private(set) var remoteProbeRequests: [UUID] = []
        private(set) var remoteReadinessRequests: [RemoteReadinessRequest] = []
        private(set) var legacyRequests: [UUID] = []

        init(
            localProbeResult: LocalCLIHealthProbeResult,
            remoteExecutableFacts: RemotePiExecutableProbeResult = .sshLaunchFailed("unexpected"),
            remoteReadinessResult: RemotePiReadinessProbeResult = .ready
        ) {
            self.localProbeResult = localProbeResult
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

        func localCLIHealthProbe(commandName: String, providerName: String, workspace: Workspace) async
            -> LocalCLIHealthProbeResult
        {
            localProbeRequests.append(workspace.id)
            return localProbeResult
        }

        func remoteCLIHealthProbe(
            commandName: String, providerName: String, workspace: Workspace, host: NexusDomain.Host
        ) async -> RemoteCLIHealthProbeResult {
            Issue.record("Pi should not use the shared generic remote CLI probe")
            return .sshLaunchFailed("unexpected")
        }

        func remotePiExecutableFacts(workspace: Workspace, host: NexusDomain.Host) async
            -> RemotePiExecutableProbeResult
        {
            remoteProbeRequests.append(workspace.id)
            return remoteExecutableFacts
        }

        func probeRemotePiReadiness(
            workspace: Workspace,
            host: NexusDomain.Host,
            executable: String
        ) async -> RemotePiReadinessProbeResult {
            remoteReadinessRequests.append(.init(workspaceID: workspace.id, hostID: host.id, executable: executable))
            return remoteReadinessResult
        }
    }

    private enum PiRuntimeConstructionRequest: Equatable {
        case localProtocolNative
        case remoteProtocolNative
    }

    private final class PiRuntimeConstructionTracker: @unchecked Sendable {
        var requests: [PiRuntimeConstructionRequest] = []
    }

    private final class StaticPiRuntime: SessionRuntime, @unchecked Sendable {
        var state: Session.State = .ready
        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

        func sessionScreen(for session: Session) -> SessionScreen {
            SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "Pi ready")
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
