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
            return await providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
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

    func planSessionTransition(
        _ request: ProviderModuleSessionTransitionRequest
    ) async throws -> ProviderModuleSessionTransitionPlan {
        switch request {
        case let .openFresh(freshRequest, actions):
            return .openFresh(try await executeSharedFreshSessionOpen(freshRequest, actions: actions))
        case let .relaunchPersisted(relaunchRequest):
            return .relaunchPersisted(planPersistedSessionRelaunch(relaunchRequest))
        case let .bootstrapReadyWithoutRuntime(bootstrapRequest):
            return .bootstrapReadyWithoutRuntime(planReadyWithoutRuntimeBootstrap(bootstrapRequest))
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

private extension CodexProviderModule {
    func localProviderHealthSummary(
        for workspace: Workspace,
        healthFacts: any CodexProviderHealthFactProviding
    ) async -> ProviderHealthSummary {
        switch await healthFacts.localCodexHealthProbe(workspace: workspace) {
        case let .executableNotFound(resolution):
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
                    )
                ]
            )
        case let .readinessProbeFailed(executable, version, diagnostics, detail):
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "Codex is installed but failed the protocol-native readiness probe",
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
                summary: version.map { "Codex \($0) is available" } ?? "Codex is available",
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
                            message: "Provider Health for Codex is blocked by Host Validation: \(hostValidation.summary)."
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
                            message: "Provider Health for Codex is blocked by Workspace Availability: \(workspaceAvailability.summary)."
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

        switch await healthFacts.remoteCodexHealthProbe(workspace: workspace, host: host) {
        case let .sshResolutionLaunchFailed(message):
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
        case let .readinessProbeFailed(executable, version, detail):
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "Codex is installed but failed the remote protocol-native readiness probe",
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
                summary: "Codex requires authentication on the Remote Workspace",
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
                summary: version.map { "Codex \($0) is available" } ?? "Codex is available",
                resolvedExecutable: executable,
                version: version,
                launchability: .launchable,
                diagnostics: finalDiagnostics
            )
        case let .ready(executable, version, diagnostics):
            return ProviderHealthSummary(
                state: .available,
                summary: version.map { "Codex \($0) is available" } ?? "Codex is available",
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
                "Codex is unavailable on the Remote Workspace",
                "remoteWorkspaceUnavailable",
                "The Remote Workspace path is unavailable on the Host."
            )
        }

        if normalized.contains("nexus_remote_codex_not_found")
            || normalized.contains("command not found")
            || normalized.contains("no such file") {
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
            || normalized.contains("tmux") {
            return (
                .misconfigured,
                "Remote Codex launch prerequisites are misconfigured",
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
