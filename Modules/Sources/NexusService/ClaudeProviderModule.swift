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
        guard let healthFacts = providerHealthEvaluator as? any CLIProviderHealthFactProviding else {
            return await providerHealthEvaluator.healthSummary(for: .claude, workspace: workspace, remoteContext: remoteContext)
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
        .terminal
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

    func constructRuntime(
        for session: Session,
        workspace: Workspace,
        launchConfiguration: SessionRuntimeLaunchConfiguration,
        actions: ProviderModuleRuntimeConstructionActions
    ) async throws -> (any SessionRuntime)? {
        if workspace.kind == .remote {
            return try actions.makeRemoteTerminalRuntime()
        }

        return try actions.makeLocalTerminalRuntime()
    }
}

private extension ClaudeProviderModule {
    func localProviderHealthSummary(
        for workspace: Workspace,
        healthFacts: any CLIProviderHealthFactProviding
    ) async -> ProviderHealthSummary {
        switch await healthFacts.localCLIHealthProbe(
            commandName: "claude",
            providerName: provider.displayName,
            workspace: workspace
        ) {
        case let .executableNotFound(resolution):
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
                    )
                ]
            )
        case let .launchProbeFailed(executable, version, diagnostics, detail):
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
        case let .ready(executable, version, diagnostics):
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

    func remoteProviderHealthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        healthFacts: any CLIProviderHealthFactProviding
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
                            message: "Provider Health for Claude is blocked by Host Validation: \(hostValidation.summary)."
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
                            message: "Provider Health for Claude is blocked by Workspace Availability: \(workspaceAvailability.summary)."
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

        let remoteProbeResult: RemoteCLIHealthProbeResult
        if let probeFacts = remoteContext?.probeFacts,
           let sharedHealthFacts = healthFacts as? any SharedRemoteCLIProviderHealthFactProviding {
            remoteProbeResult = await sharedHealthFacts.remoteCLIHealthProbe(
                commandName: "claude",
                providerName: provider.displayName,
                workspace: workspace,
                host: host,
                probeFacts: probeFacts
            )
        } else {
            remoteProbeResult = await healthFacts.remoteCLIHealthProbe(
                commandName: "claude",
                providerName: provider.displayName,
                workspace: workspace,
                host: host
            )
        }

        switch remoteProbeResult {
        case let .sshLaunchFailed(message):
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
        case let .probeFailed(detail):
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
        case let .ready(executable, version, diagnostics):
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

    func classifyRemoteClaudeCLIProbeFailure(
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
            || normalized.contains("no such file") {
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
            || normalized.contains("tmux") {
            return (
                .misconfigured,
                "Remote Claude launch prerequisites are misconfigured",
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
