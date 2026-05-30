#if os(macOS)
import Foundation
import NexusDomain

struct PiProviderModule: ProviderModule {
    let provider = Provider(id: .pi)

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
        if workspace.kind == .remote {
            guard let healthFacts = providerHealthEvaluator as? any PiProviderHealthFactProviding else {
                return await providerHealthEvaluator.healthSummary(for: .pi, workspace: workspace, remoteContext: remoteContext)
            }

            return await remoteProviderHealthSummary(
                for: workspace,
                remoteContext: remoteContext,
                healthFacts: healthFacts
            )
        }

        guard let healthFacts = providerHealthEvaluator as? any CLIProviderHealthFactProviding else {
            return await providerHealthEvaluator.healthSummary(for: .pi, workspace: workspace, remoteContext: remoteContext)
        }

        return await localProviderHealthSummary(for: workspace, healthFacts: healthFacts)
    }

    func readCatalog(
        _ request: ProviderModuleCatalogReadRequest,
        actions: ProviderModuleCatalogReadActions
    ) async throws -> ProviderModuleCatalogReadResult {
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

    func reusesRemoteHealthSnapshot(
        _ snapshot: ProviderHealthSummary,
        remoteContext: RemoteWorkspaceHealthContext?
    ) -> Bool {
        shouldReuseRemoteCLIHealthSnapshot(snapshot, remoteContext: remoteContext)
    }

    func planPersistedSessionRelaunch(
        _ request: ProviderModulePersistedSessionRelaunchRequest
    ) -> ProviderModulePersistedSessionRelaunchPlan {
        guard request.execution.workspace.kind == .remote else {
            return .sharedLaunch
        }

        let freshRemoteRelaunch = ProviderModuleFreshRemotePersistedSessionRelaunch(
            sessionRecordAdapterMetadataSource: request.execution.sessionRecordAdapterMetadataSource,
            retriesWithoutContinuity: true
        )

        switch request.execution.mode {
        case .recoverRemoteRuntime:
            return .recoverRemoteRuntime(freshRemoteRelaunch)
        case let .launch(forceFreshRemoteRuntime):
            return forceFreshRemoteRuntime
                ? .launchFreshRemoteRuntime(freshRemoteRelaunch)
                : .sharedLaunch
        }
    }

    func interruptedSessionFailureMessage(
        for session: Session,
        workspace: Workspace?,
        persistedPrimarySurface: SessionSurface
    ) -> String {
        guard workspace?.kind == .local,
              persistedPrimarySurface == .structuredActivityFeed else {
            return providerModuleDefaultInterruptedSessionFailureMessage()
        }

        return structuredInterruptedSessionFailureMessage(for: provider.id)
    }

    func shouldRetryFreshRemotePersistedSessionRelaunchWithoutContinuity(
        _ error: Error,
        metadata: SessionRecordAdapterMetadata?
    ) throws -> Bool {
        guard metadata?.piSessionLinkage != nil else {
            return false
        }

        let normalized = error.localizedDescription.lowercased()
        return normalized.contains("invalid pi session")
            || normalized.contains("invalid session")
            || normalized.contains("session not found")
    }

    func constructRuntime(
        for session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration,
        actions: ProviderModuleRuntimeConstructionActions
    ) async throws -> (any SessionRuntime)? {
        if workspace.kind == .remote {
            return try await actions.makeRemotePiRuntime()
        }

        return try await actions.makeLocalPiRuntime()
    }
}

private extension PiProviderModule {
    func localProviderHealthSummary(
        for workspace: Workspace,
        healthFacts: any CLIProviderHealthFactProviding
    ) async -> ProviderHealthSummary {
        switch await healthFacts.localCLIHealthProbe(
            commandName: "pi",
            providerName: provider.displayName,
            workspace: workspace
        ) {
        case let .executableNotFound(resolution):
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Pi executable was not found",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "executableNotFound",
                        message: "Pi executable was not found in the service search paths."
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
                    )
                ]
            )
        case let .launchProbeFailed(executable, version, diagnostics, detail):
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "Pi is installed but failed the launch probe",
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
        case let .ready(executable, version, diagnostics):
            return ProviderHealthSummary(
                state: .available,
                summary: version.map { "Pi \($0) is available" } ?? "Pi is available",
                resolvedExecutable: executable,
                version: version,
                launchability: .launchable,
                diagnostics: diagnostics
            )
        }
    }

    func remoteProviderHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        healthFacts: any PiProviderHealthFactProviding
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
                            message: "Provider Health for Pi is blocked by Host Validation: \(hostValidation.summary)."
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
                        message: "Provider Health for Pi is blocked until Host Validation runs."
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
                            message: "Provider Health for Pi is blocked by Workspace Availability: \(workspaceAvailability.summary)."
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
                        message: "Provider Health for Pi is blocked until Workspace Availability is checked."
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
                        message: "Provider Health for Pi is blocked until Workspace Availability is checked."
                    )
                ]
            )
        }

        switch await healthFacts.remotePiHealthProbe(workspace: workspace, host: host) {
        case let .sshResolutionLaunchFailed(message):
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Remote Pi health check failed before the SSH probe completed",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "sshLaunchFailed",
                        message: message
                    )
                ]
            )
        case let .resolutionProbeFailed(detail):
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
        case .resolutionReturnedNoExecutable:
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "Pi executable resolution returned no executable path",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "remoteExecutableResolutionFailed",
                        message: "The remote Pi executable resolution probe did not return an executable path."
                    )
                ]
            )
        case let .readinessProbeFailed(executable, version, detail):
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "Pi is installed but failed the remote protocol-native readiness probe",
                resolvedExecutable: executable,
                version: version,
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "remoteLaunchProbeFailed",
                        message: detail
                    )
                ]
            )
        case let .authenticationRequired(executable, version, message):
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Pi requires authentication on the Remote Workspace",
                resolvedExecutable: executable,
                version: version,
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "remoteAuthRequired",
                        message: message
                    )
                ]
            )
        case let .authenticationUncertain(executable, version, diagnostics, message):
            var finalDiagnostics = diagnostics
            if let message, message.isEmpty == false {
                finalDiagnostics.append(
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "remoteAuthUncertain",
                        message: message
                    )
                )
            }
            return ProviderHealthSummary(
                state: .available,
                summary: version.map { "Pi \($0) is available" } ?? "Pi is available",
                resolvedExecutable: executable,
                version: version,
                launchability: .launchable,
                diagnostics: finalDiagnostics
            )
        case let .ready(executable, version, diagnostics):
            return ProviderHealthSummary(
                state: .available,
                summary: version.map { "Pi \($0) is available" } ?? "Pi is available",
                resolvedExecutable: executable,
                version: version,
                launchability: .launchable,
                diagnostics: diagnostics
            )
        }
    }

    func classifyRemoteProbeFailure(
        detail: String
    ) -> (state: ProviderHealthSummary.State, summary: String, code: String, message: String?) {
        let normalized = detail.lowercased()

        if normalized.contains("nexus_remote_workspace_unavailable") {
            return (
                .unavailable,
                "Pi is unavailable on the Remote Workspace",
                "remoteWorkspaceUnavailable",
                "The Remote Workspace path is unavailable on the Host."
            )
        }

        if normalized.contains("nexus_remote_pi_not_found")
            || normalized.contains("command not found")
            || normalized.contains("no such file") {
            return (
                .unavailable,
                "Pi is unavailable on the Remote Workspace",
                "remoteExecutableNotFound",
                "Pi executable was not found in the remote shell environments Nexus checked."
            )
        }

        if normalized.contains("nexus_remote_tmux_unavailable")
            || normalized.contains("permission denied")
            || normalized.contains("bad configuration option")
            || normalized.contains("tmux") {
            return (
                .misconfigured,
                "Remote Pi launch prerequisites are misconfigured",
                "remoteLaunchMisconfigured",
                normalized.contains("nexus_remote_tmux_unavailable") ? "tmux is not available in the remote shell." : nil
            )
        }

        if normalized.contains("connection timed out")
            || normalized.contains("operation timed out")
            || normalized.contains("connection refused")
            || normalized.contains("network is unreachable")
            || normalized.contains("no route to host") {
            return (
                .unavailable,
                "Remote Pi is currently unavailable",
                "remoteUnavailable",
                nil
            )
        }

        return (
            .misconfigured,
            "Pi is installed but failed the remote launch probe",
            "remoteLaunchProbeFailed",
            nil
        )
    }
}
#endif
