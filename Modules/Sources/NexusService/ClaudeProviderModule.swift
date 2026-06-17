#if os(macOS)
    import Foundation
    import NexusDomain

    struct ClaudeProviderModule: ProviderModule {
        let provider = Provider(id: .claude)

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
            guard let healthFacts = providerHealthEvaluator as? any ClaudeProviderHealthFactProviding else {
                return await providerHealthEvaluator.healthSummary(
                    for: .claude, workspace: workspace, remoteContext: remoteContext)
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
            providerHealthEvaluator is any ClaudeProviderHealthFactProviding
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
                return try actions.makeRemoteTerminalRuntime()
            }

            return try actions.makeLocalClaudeRuntime()
        }
    }

    extension ClaudeProviderModule {
        fileprivate func localProviderHealthSummary(
            for workspace: Workspace,
            healthFacts: any ClaudeProviderHealthFactProviding
        ) async -> ProviderHealthSummary {
            switch await healthFacts.localCLIHealthProbe(
                commandName: "claude",
                providerName: provider.displayName,
                workspace: workspace
            ) {
            case .executableNotFound(let resolution):
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Claude executable was not found",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "executableNotFound",
                            message: "Claude executable was not found in the service search paths."
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
            case .launchProbeFailed(let executable, let version, let diagnostics, let detail):
                return ProviderHealthSummary(
                    state: .misconfigured,
                    summary: "Claude is installed but failed the launch probe",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .notLaunchable,
                    diagnostics: diagnostics + [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "launchProbeFailed",
                            message: detail
                        )
                    ]
                )
            case .ready(let executable, let version, let diagnostics):
                switch await healthFacts.probeLocalClaudeStreamJSONReadiness(
                    workspace: workspace,
                    executable: executable
                ) {
                case .failed(let detail):
                    return ProviderHealthSummary(
                        state: .misconfigured,
                        summary: "Claude is installed but failed the stream-json readiness probe",
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .notLaunchable,
                        diagnostics: diagnostics + [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "streamJSONReadinessProbeFailed",
                                message: detail
                            )
                        ]
                    )
                case .ready:
                    return ProviderHealthSummary(
                        state: .available,
                        summary: version.map { "Claude \($0) is available" } ?? "Claude is available",
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .launchable,
                        diagnostics: diagnostics
                    )
                }
            }
        }

        fileprivate func remoteProviderHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            healthFacts: any ClaudeProviderHealthFactProviding
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
                                    "Provider Health for Claude is blocked by Host Validation: \(hostValidation.summary)."
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
                            message: "Provider Health for Claude is blocked until Host Validation runs."
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
                                    "Provider Health for Claude is blocked by Workspace Availability: \(workspaceAvailability.summary)."
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
                            message: "Provider Health for Claude is blocked until Workspace Availability is checked."
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
                            message: "Provider Health for Claude is blocked until Workspace Availability is checked."
                        )
                    ]
                )
            }

            if let probeFact = remoteContext?.probeFacts?.providerFacts[.claude] {
                if let detail = probeFact.resolutionDetail ?? probeFact.probeDetail {
                    let classification = classifyRemoteClaudeCLIProbeFailure(detail: detail)
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
                        summary: "Claude executable resolution returned no executable path",
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "remoteExecutableResolutionFailed",
                                message:
                                    "The remote Claude executable resolution probe did not return an executable path."
                            )
                        ]
                    )
                }

                switch await healthFacts.probeRemoteClaudeStreamJSONReadiness(
                    workspace: workspace,
                    host: host,
                    executable: executable
                ) {
                case .failed(let detail):
                    return ProviderHealthSummary(
                        state: .misconfigured,
                        summary: "Claude is installed but failed the remote stream-json readiness probe",
                        resolvedExecutable: executable,
                        version: probeFact.version,
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "remoteStreamJSONReadinessProbeFailed",
                                message: detail
                            )
                        ]
                    )
                case .ready:
                    return ProviderHealthSummary(
                        state: .available,
                        summary: probeFact.version.map { "Claude \($0) is available" } ?? "Claude is available",
                        resolvedExecutable: executable,
                        version: probeFact.version,
                        launchability: .launchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .info,
                                code: "remoteProbe",
                                message:
                                    "Validated remote Claude launch prerequisites on \(host.name) for \(workspace.folderPath)."
                            )
                        ]
                    )
                }
            }

            switch await healthFacts.remoteCLIHealthProbe(
                commandName: "claude",
                providerName: provider.displayName,
                workspace: workspace,
                host: host
            ) {
            case .sshLaunchFailed(let message):
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Remote Claude health check failed before the SSH probe completed",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "sshLaunchFailed",
                            message: message
                        )
                    ]
                )
            case .probeFailed(let detail):
                let classification = classifyRemoteClaudeCLIProbeFailure(detail: detail)
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
            case .ready(let executable, let version, let diagnostics):
                guard let executable else {
                    return ProviderHealthSummary(
                        state: .misconfigured,
                        summary: "Claude executable resolution returned no executable path",
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "remoteExecutableResolutionFailed",
                                message:
                                    "The remote Claude executable resolution probe did not return an executable path."
                            )
                        ]
                    )
                }

                switch await healthFacts.probeRemoteClaudeStreamJSONReadiness(
                    workspace: workspace,
                    host: host,
                    executable: executable
                ) {
                case .failed(let detail):
                    return ProviderHealthSummary(
                        state: .misconfigured,
                        summary: "Claude is installed but failed the remote stream-json readiness probe",
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: "remoteStreamJSONReadinessProbeFailed",
                                message: detail
                            )
                        ]
                    )
                case .ready:
                    return ProviderHealthSummary(
                        state: .available,
                        summary: version.map { "Claude \($0) is available" } ?? "Claude is available",
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .launchable,
                        diagnostics: diagnostics
                    )
                }
            }
        }

        fileprivate func classifyRemoteClaudeCLIProbeFailure(
            detail: String
        ) -> (state: ProviderHealthSummary.State, summary: String, code: String, message: String?) {
            let normalized = detail.lowercased()

            if normalized.contains("nexus_remote_workspace_unavailable") {
                return (
                    .unavailable,
                    "Claude is unavailable on the Remote Workspace",
                    "remoteWorkspaceUnavailable",
                    "The Remote Workspace path is unavailable on the Host."
                )
            }

            if normalized.contains("nexus_remote_claude_not_found")
                || normalized.contains("command not found")
                || normalized.contains("no such file")
            {
                return (
                    .unavailable,
                    "Claude is unavailable on the Remote Workspace",
                    "remoteExecutableNotFound",
                    "Claude executable was not found in the remote shell environments Nexus checked."
                )
            }

            if normalized.contains("nexus_remote_tmux_unavailable")
                || normalized.contains("permission denied")
                || normalized.contains("bad configuration option")
                || normalized.contains("tmux")
            {
                return (
                    .misconfigured,
                    "Remote Claude launch prerequisites are misconfigured",
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
                    "Remote Claude is currently unavailable",
                    "remoteUnavailable",
                    nil
                )
            }

            return (
                .misconfigured,
                "Claude is installed but failed the remote launch probe",
                "remoteLaunchProbeFailed",
                nil
            )
        }
    }
#endif
