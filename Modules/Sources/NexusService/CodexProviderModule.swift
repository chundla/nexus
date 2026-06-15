#if os(macOS)
    import Foundation
    import NexusDomain

    struct CodexProviderModule: ProviderModule {
        let provider = Provider(id: .codex)

        init() {}

        func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
            true
        }

        func supportsNamedSessions(in workspace: Workspace) -> Bool {
            true
        }

        func providerHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            providerHealthEvaluator: any ProviderHealthEvaluating
        ) async -> ProviderHealthSummary {
            guard let healthFacts = providerHealthEvaluator as? any CodexProviderHealthFactProviding else {
                return await providerHealthEvaluator.healthSummary(
                    for: .codex, workspace: workspace, remoteContext: remoteContext)
            }

            if workspace.kind == .remote {
                return await remoteProviderHealthSummary(
                    for: workspace,
                    remoteContext: remoteContext,
                    healthFacts: healthFacts
                )
            }

            return await localProviderHealthSummary(for: workspace, healthFacts: healthFacts)
        }

        func providerCapabilities(
            in workspace: Workspace,
            health: ProviderHealthSummary,
            defaultSession: Session?
        ) -> ProviderCapabilities {
            makeProviderCapabilities(
                provider: provider,
                supportsDefaultSessionLaunch: supportsDefaultSessionLaunch(in: workspace),
                supportsNamedSessions: supportsNamedSessions(in: workspace),
                health: health,
                defaultSession: defaultSession
            )
        }

        func prelaunchPrimarySurface(in workspace: Workspace) -> SessionSurface {
            .structuredActivityFeed
        }

        func supportsSharedRemoteProbeFacts(
            with providerHealthEvaluator: any ProviderHealthEvaluating
        ) -> Bool {
            providerHealthEvaluator is any CodexProviderHealthFactProviding
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            shouldReuseRemoteCLIHealthSnapshot(snapshot, remoteContext: remoteContext)
        }

        func interruptedSessionFailureMessage(
            for session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface
        ) -> String {
            guard workspace?.kind == .local,
                persistedPrimarySurface == .structuredActivityFeed
            else {
                return providerModuleDefaultInterruptedSessionFailureMessage()
            }

            return structuredInterruptedSessionFailureMessage(for: provider.id)
        }

        func constructRuntime(
            for session: Session,
            workspace: Workspace,
            launchConfiguration: SessionRuntimeLaunchConfiguration,
            actions: ProviderModuleRuntimeConstructionActions
        ) async throws -> (any SessionRuntime)? {
            if workspace.kind == .remote {
                return try await actions.makeRemoteCodexRuntime()
            }

            return try await actions.makeLocalCodexRuntime()
        }
    }

    extension CodexProviderModule {
        fileprivate func localProviderHealthSummary(
            for workspace: Workspace,
            healthFacts: any CodexProviderHealthFactProviding
        ) async -> ProviderHealthSummary {
            let executableFacts = await healthFacts.localCodexExecutableFacts(workspace: workspace)
            guard let executable = executableFacts.executable else {
                let resolution = executableFacts.resolution
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Codex executable was not found",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "executableNotFound",
                            message: "Codex executable was not found in the service search paths."
                        ),
                        ProviderHealthDiagnostic(
                            severity: .info,
                            code: "searchedDirectories",
                            message: "Searched directories: \(resolution.searchedDirectories.joined(separator: ", "))"
                        ),
                        ProviderHealthDiagnostic(
                            severity: .info,
                            code: "homeDirectories",
                            message: "Resolved home directories: \(resolution.homeDirectories.joined(separator: ", "))"
                        ),
                        ProviderHealthDiagnostic(
                            severity: .info,
                            code: "pathEnvironment",
                            message: "PATH: \(resolution.pathEnvironment ?? "<unset>")"
                        ),
                    ]
                )
            }

            switch await healthFacts.probeLocalCodexReadiness(workspace: workspace, executable: executable) {
            case .failed(let detail):
                return ProviderHealthSummary(
                    state: .misconfigured,
                    summary: "Codex is installed but failed the protocol-native readiness probe",
                    resolvedExecutable: executable,
                    version: executableFacts.version,
                    launchability: .notLaunchable,
                    diagnostics: executableFacts.diagnostics + [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "launchProbeFailed",
                            message: detail
                        )
                    ]
                )
            case .ready:
                return ProviderHealthSummary(
                    state: .available,
                    summary: executableFacts.version.map { "Codex \($0) is available" } ?? "Codex is available",
                    resolvedExecutable: executable,
                    version: executableFacts.version,
                    launchability: .launchable,
                    diagnostics: executableFacts.diagnostics
                )
            }
        }

        fileprivate func remoteProviderHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            healthFacts: any CodexProviderHealthFactProviding
        ) async -> ProviderHealthSummary {
            if let hostValidation = remoteContext?.hostValidation {
                if hostValidation.state != .available {
                    return ProviderHealthSummary(
                        state: .blocked,
                        summary: "Provider Health is blocked by Host Validation",
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "hostValidationBlocked",
                                message:
                                    "Provider Health for Codex is blocked by Host Validation: \(hostValidation.summary)."
                            )
                        ]
                    )
                }
            } else {
                return ProviderHealthSummary(
                    state: .blocked,
                    summary: "Provider Health is blocked by Host Validation",
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .warning,
                            code: "hostValidationBlocked",
                            message: "Provider Health for Codex is blocked until Host Validation runs."
                        )
                    ]
                )
            }

            if let workspaceAvailability = remoteContext?.workspaceAvailability {
                if workspaceAvailability.state != .available {
                    return ProviderHealthSummary(
                        state: .blocked,
                        summary: "Provider Health is blocked by Workspace Availability",
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .warning,
                                code: "workspaceAvailabilityBlocked",
                                message:
                                    "Provider Health for Codex is blocked by Workspace Availability: \(workspaceAvailability.summary)."
                            )
                        ]
                    )
                }
            } else {
                return ProviderHealthSummary(
                    state: .blocked,
                    summary: "Provider Health is blocked by Workspace Availability",
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .warning,
                            code: "workspaceAvailabilityBlocked",
                            message: "Provider Health for Codex is blocked until Workspace Availability is checked."
                        )
                    ]
                )
            }

            guard let host = remoteContext?.host else {
                return ProviderHealthSummary(
                    state: .blocked,
                    summary: "Provider Health is blocked by Workspace Availability",
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .warning,
                            code: "workspaceAvailabilityBlocked",
                            message: "Provider Health for Codex is blocked until Workspace Availability is checked."
                        )
                    ]
                )
            }

            let probeFact: RemoteProviderProbeFacts
            if let sharedProbeFact = remoteContext?.probeFacts?.providerFacts[.codex] {
                probeFact = sharedProbeFact
            } else {
                switch await healthFacts.remoteCodexExecutableFacts(workspace: workspace, host: host) {
                case .sshLaunchFailed(let message):
                    return ProviderHealthSummary(
                        state: .unavailable,
                        summary: "Remote Codex health check failed before the SSH probe completed",
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "sshLaunchFailed",
                                message: message
                            )
                        ]
                    )
                case .facts(let facts):
                    probeFact = facts
                }
            }

            if let detail = probeFact.resolutionDetail ?? probeFact.probeDetail {
                let classification = classifyRemoteProbeFailure(detail: detail)
                return ProviderHealthSummary(
                    state: classification.state,
                    summary: classification.summary,
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: classification.code,
                            message: classification.message ?? (detail.isEmpty ? classification.summary : detail)
                        )
                    ]
                )
            }

            guard let executable = probeFact.executable else {
                return ProviderHealthSummary(
                    state: .misconfigured,
                    summary: "Codex executable resolution returned no executable path",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "remoteExecutableResolutionFailed",
                            message: "The remote Codex executable resolution probe did not return an executable path."
                        )
                    ]
                )
            }

            var diagnostics = [
                ProviderHealthDiagnostic(
                    severity: .info,
                    code: "remoteProbe",
                    message: "Validated remote Codex launch prerequisites on \(host.name) for \(workspace.folderPath)."
                )
            ]

            switch await healthFacts.probeRemoteCodexReadiness(workspace: workspace, host: host, executable: executable)
            {
            case .failed(let detail):
                return ProviderHealthSummary(
                    state: .misconfigured,
                    summary: "Codex is installed but failed the remote protocol-native readiness probe",
                    resolvedExecutable: executable,
                    version: probeFact.version,
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "remoteLaunchProbeFailed",
                            message: detail
                        )
                    ]
                )
            case .authenticationRequired(let message):
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Codex requires authentication on the Remote Workspace",
                    resolvedExecutable: executable,
                    version: probeFact.version,
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "remoteAuthRequired",
                            message: message
                        )
                    ]
                )
            case .authenticationUncertain(let message):
                if let message, message.isEmpty == false {
                    diagnostics.append(
                        ProviderHealthDiagnostic(
                            severity: .warning,
                            code: "remoteAuthUncertain",
                            message: message
                        )
                    )
                }
                return ProviderHealthSummary(
                    state: .available,
                    summary: probeFact.version.map { "Codex \($0) is available" } ?? "Codex is available",
                    resolvedExecutable: executable,
                    version: probeFact.version,
                    launchability: .launchable,
                    diagnostics: diagnostics
                )
            case .ready:
                return ProviderHealthSummary(
                    state: .available,
                    summary: probeFact.version.map { "Codex \($0) is available" } ?? "Codex is available",
                    resolvedExecutable: executable,
                    version: probeFact.version,
                    launchability: .launchable,
                    diagnostics: diagnostics
                )
            }
        }

        fileprivate func classifyRemoteProbeFailure(
            detail: String
        ) -> (state: ProviderHealthSummary.State, summary: String, code: String, message: String?) {
            let normalized = detail.lowercased()

            if normalized.contains("nexus_remote_workspace_unavailable") {
                return (
                    .unavailable,
                    "Codex is unavailable on the Remote Workspace",
                    "remoteWorkspaceUnavailable",
                    "The Remote Workspace path is unavailable on the Host."
                )
            }

            if normalized.contains("nexus_remote_codex_not_found")
                || normalized.contains("command not found")
                || normalized.contains("no such file")
            {
                return (
                    .unavailable,
                    "Codex is unavailable on the Remote Workspace",
                    "remoteExecutableNotFound",
                    "Codex executable was not found in the remote shell environments Nexus checked."
                )
            }

            if normalized.contains("nexus_remote_tmux_unavailable")
                || normalized.contains("permission denied")
                || normalized.contains("bad configuration option")
                || normalized.contains("tmux")
            {
                return (
                    .misconfigured,
                    "Remote Codex launch prerequisites are misconfigured",
                    "remoteLaunchMisconfigured",
                    normalized.contains("nexus_remote_tmux_unavailable")
                        ? "tmux is not available in the remote shell." : nil
                )
            }

            if normalized.contains("connection timed out")
                || normalized.contains("operation timed out")
                || normalized.contains("connection refused")
                || normalized.contains("network is unreachable")
                || normalized.contains("no route to host")
            {
                return (
                    .unavailable,
                    "Remote Codex is currently unavailable",
                    "remoteUnavailable",
                    nil
                )
            }

            return (
                .misconfigured,
                "Codex is installed but failed the remote launch probe",
                "remoteLaunchProbeFailed",
                nil
            )
        }
    }
#endif
