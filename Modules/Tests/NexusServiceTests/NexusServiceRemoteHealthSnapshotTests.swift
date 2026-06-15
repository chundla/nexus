#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct NexusServiceRemoteHealthSnapshotTests {
        @Test func staleUnavailableRemoteCodexProviderHealthRefreshesOnReadAcrossBootstrap() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let firstService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: StubProviderHealthFacts(summariesByProvider: [
                    .codex: ProviderHealthSummary(
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
                    )
                ]),
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator()
            )

            let group = try firstService.createWorkspaceGroup(name: "Remote")
            let host = try firstService.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try firstService.validateHost(hostID: host.id)
            let workspace = try firstService.createRemoteWorkspace(
                name: nil,
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let staleDetail = try firstService.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
            #expect(staleDetail.health.state == .unavailable)
            #expect(staleDetail.health.summary == "Codex is unavailable on the Remote Workspace")

            let secondService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: StubProviderHealthFacts(summariesByProvider: [
                    .codex: ProviderHealthSummary(
                        state: .available,
                        summary: "Codex 1.2.3 is available",
                        resolvedExecutable: "/usr/local/bin/codex",
                        version: "1.2.3",
                        launchability: .launchable
                    )
                ]),
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator()
            )

            let refreshedDetail = try secondService.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

            #expect(refreshedDetail.health.state == .available)
            #expect(refreshedDetail.health.summary == "Codex 1.2.3 is available")
            #expect(refreshedDetail.health.resolvedExecutable == "/usr/local/bin/codex")
        }

        @Test func staleNotCheckedRemoteCodexProviderHealthRefreshesOnReadAcrossBootstrap() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            let firstService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: StubProviderHealthFacts(summariesByProvider: [
                    .codex: ProviderHealthSummary(
                        state: .notChecked,
                        summary: "Remote Codex execution is not implemented yet",
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "remoteExecutionNotImplemented",
                                message:
                                    "Nexus shows Codex on Remote Workspaces, but remote execution for this Provider is not implemented in this milestone."
                            )
                        ]
                    )
                ]),
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator()
            )

            let group = try firstService.createWorkspaceGroup(name: "Remote")
            let host = try firstService.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
            _ = try firstService.validateHost(hostID: host.id)
            let workspace = try firstService.createRemoteWorkspace(
                name: nil,
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: group.id
            )

            let staleOverview = try firstService.getWorkspaceOverview(workspaceID: workspace.id)
            let staleCard = try #require(staleOverview.providerCards.first(where: { $0.provider.id == .codex }))
            #expect(staleCard.health.state == .notChecked)
            #expect(staleCard.health.summary == "Remote Codex execution is not implemented yet")

            let secondService = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: StubProviderHealthFacts(summariesByProvider: [
                    .codex: ProviderHealthSummary(
                        state: .available,
                        summary: "Codex 1.2.3 is available",
                        resolvedExecutable: "/usr/local/bin/codex",
                        version: "1.2.3",
                        launchability: .launchable
                    )
                ]),
                hostValidationEvaluator: AvailableHostValidationEvaluator(),
                workspaceAvailabilityEvaluator: AvailableWorkspaceAvailabilityEvaluator()
            )

            let reusedOverview = try secondService.getWorkspaceOverview(workspaceID: workspace.id)
            let reusedCard = try #require(reusedOverview.providerCards.first(where: { $0.provider.id == .codex }))

            #expect(reusedCard.health.state == .notChecked)
            #expect(reusedCard.health.summary == "Remote Codex execution is not implemented yet")
            #expect(reusedOverview.usesStaleBrowseFacts == false)

            let refreshedOverview = try secondService.refreshWorkspaceOverview(workspaceID: workspace.id)
            let refreshedCard = try #require(refreshedOverview.providerCards.first(where: { $0.provider.id == .codex }))

            #expect(refreshedCard.health.state == .available)
            #expect(refreshedCard.health.summary == "Codex 1.2.3 is available")
            #expect(refreshedCard.health.resolvedExecutable == "/usr/local/bin/codex")
        }
    }

    private struct StubProviderHealthFacts: ProviderHealthEvaluating {
        let summariesByProvider: [ProviderID: ProviderHealthSummary]

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
            summariesByProvider[providerID]
                ?? ProviderHealthSummary(state: .notChecked, summary: "Health checks coming soon")
        }
    }

    private struct AvailableHostValidationEvaluator: HostValidationEvaluating {
        func validate(host: NexusDomain.Host) -> HostValidationResult {
            HostValidationResult(
                state: .available,
                summary: "Host is available",
                diagnostics: [
                    HostValidationDiagnostic(severity: .info, code: "sshTarget", message: "Validated \(host.sshTarget)")
                ]
            )
        }
    }

    private struct AvailableWorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
        func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?)
            -> WorkspaceAvailabilityResult
        {
            WorkspaceAvailabilityResult(
                state: .available,
                summary: "Workspace is available",
                diagnostics: [
                    WorkspaceAvailabilityDiagnostic(
                        severity: .info,
                        code: "remotePath",
                        message: "Validated remote path \(workspace.folderPath) on \(host.name)."
                    )
                ]
            )
        }
    }
#endif
