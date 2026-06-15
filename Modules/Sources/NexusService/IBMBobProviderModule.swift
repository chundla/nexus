#if os(macOS)
    import Foundation
    import NexusDomain

    struct IBMBobProviderModule: ProviderModule {
        let provider = Provider(id: .ibmBob)

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
            guard let healthFacts = providerHealthEvaluator as? any IBMBobProviderHealthFactProviding else {
                return await providerHealthEvaluator.healthSummary(
                    for: .ibmBob, workspace: workspace, remoteContext: remoteContext)
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
            providerHealthEvaluator is any SharedRemoteIBMBobProviderHealthFactProviding
        }

        func reusesRemoteHealthSnapshot(
            _ snapshot: ProviderHealthSummary,
            remoteContext: RemoteWorkspaceHealthContext?
        ) -> Bool {
            false
        }

        func persistedSessionRelaunchMetadataSource(
            for session: Session,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> SessionRecordAdapterMetadataLaunchSource {
            guard session.state != .ready else {
                return .stored
            }

            if session.state == .interrupted,
                let linkage = storedMetadata?.ibmBobSessionLinkage
            {
                return .explicit(
                    SessionRecordAdapterMetadata.ibmBob(
                        sessionID: linkage.sessionID,
                        activityItems: linkage.persistedActivityItems,
                        turnInProgress: false
                    )
                )
            }

            return .explicit(
                SessionRecordAdapterMetadata.ibmBob(sessionID: storedMetadata?.ibmBobSessionLinkage?.sessionID))
        }

        func sessionMayRemainReadyWithoutRuntime(
            _ session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface,
            storedMetadata: SessionRecordAdapterMetadata?
        ) -> Bool {
            guard persistedPrimarySurface == .structuredActivityFeed else {
                return false
            }

            return storedMetadata?.ibmBobTurnInProgress != true
        }

        func interruptedSessionFailureMessage(
            for session: Session,
            workspace: Workspace?,
            persistedPrimarySurface: SessionSurface
        ) -> String {
            guard persistedPrimarySurface == .structuredActivityFeed else {
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
                return try await actions.makeRemoteIBMBobRuntime()
            }

            return try await actions.makeLocalIBMBobRuntime()
        }

        func prepareDeleteSessionRecord(
            _ request: ProviderModuleDeleteSessionRecordRequest,
            actions: ProviderModuleDeleteSessionRecordActions
        ) {
            let nativeSessionID =
                request.sessionRecordAdapterMetadata?.ibmBobSessionLinkage?.sessionID?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard nativeSessionID.isEmpty == false else {
                return
            }

            actions.deleteStoredContinuity()
        }
    }

    extension IBMBobProviderModule {
        fileprivate func localProviderHealthSummary(
            for workspace: Workspace,
            healthFacts: any IBMBobProviderHealthFactProviding
        ) async -> ProviderHealthSummary {
            switch await healthFacts.localIBMBobPassiveProbe(workspace: workspace) {
            case .executableNotFound(let resolution):
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "IBM Bob executable was not found",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "executableNotFound",
                            message: "IBM Bob executable was not found in the service search paths."
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
            case .passiveProbeLaunchFailed(let executable, let version, let diagnostics, let detail):
                return ProviderHealthSummary(
                    state: .misconfigured,
                    summary: "IBM Bob is installed but failed the passive readiness probe",
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
            case .passiveProbeCompleted(let executable, let version, let diagnostics, let detail):
                guard let detail else {
                    return ProviderHealthSummary(
                        state: .available,
                        summary: availableSummary(version: version),
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .launchable,
                        diagnostics: diagnostics
                    )
                }

                let classification = classifyPassiveProbeFailure(detail: detail)
                return ProviderHealthSummary(
                    state: classification.state,
                    summary: classification.summary(version),
                    resolvedExecutable: executable,
                    version: version,
                    launchability: classification.launchability,
                    diagnostics: diagnostics + [
                        ProviderHealthDiagnostic(
                            severity: classification.severity,
                            code: classification.code,
                            message: classification.message
                        )
                    ]
                )
            }
        }

        fileprivate func remoteProviderHealthSummary(
            for workspace: Workspace,
            remoteContext: RemoteWorkspaceHealthContext?,
            healthFacts: any IBMBobProviderHealthFactProviding
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
                                    "Provider Health for IBM Bob is blocked by Host Validation: \(hostValidation.summary)."
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
                            message: "Provider Health for IBM Bob is blocked until Host Validation runs."
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
                                    "Provider Health for IBM Bob is blocked by Workspace Availability: \(workspaceAvailability.summary)."
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
                            message: "Provider Health for IBM Bob is blocked until Workspace Availability is checked."
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
                            message: "Provider Health for IBM Bob is blocked until Workspace Availability is checked."
                        )
                    ]
                )
            }

            let remoteProbeResult: RemoteIBMBobPassiveProbeResult
            if let probeFacts = remoteContext?.probeFacts,
                let sharedHealthFacts = healthFacts as? any SharedRemoteIBMBobProviderHealthFactProviding
            {
                remoteProbeResult = await sharedHealthFacts.remoteIBMBobPassiveProbe(
                    workspace: workspace,
                    host: host,
                    probeFacts: probeFacts
                )
            } else {
                remoteProbeResult = await healthFacts.remoteIBMBobPassiveProbe(workspace: workspace, host: host)
            }

            switch remoteProbeResult {
            case .sshResolutionLaunchFailed(let message):
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Remote IBM Bob health check failed before the SSH probe completed",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "sshLaunchFailed",
                            message: message
                        )
                    ]
                )
            case .resolutionProbeFailed(let detail):
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
                    summary: "IBM Bob executable resolution returned no executable path",
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "remoteExecutableResolutionFailed",
                            message: "The remote IBM Bob executable resolution probe did not return an executable path."
                        )
                    ]
                )
            case .passiveProbeSSHLaunchFailed(let executable, let version, let message):
                return ProviderHealthSummary(
                    state: .unavailable,
                    summary: "Remote IBM Bob health check failed before the passive readiness probe completed",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .notLaunchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "sshLaunchFailed",
                            message: message
                        )
                    ]
                )
            case .passiveProbeCompleted(let executable, let version, let detail):
                guard let detail else {
                    return ProviderHealthSummary(
                        state: .available,
                        summary: availableSummary(version: version),
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .launchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .info,
                                code: "remoteProbe",
                                message:
                                    "Validated remote IBM Bob launch prerequisites on \(host.name) for \(workspace.folderPath)."
                            )
                        ]
                    )
                }

                let bobClassification = classifyPassiveProbeFailure(detail: detail)
                if bobClassification.code != "passiveProbeInconclusive" {
                    return ProviderHealthSummary(
                        state: bobClassification.state,
                        summary: remoteBlockedSummary(for: bobClassification.code),
                        resolvedExecutable: executable,
                        version: version,
                        launchability: bobClassification.launchability,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: bobClassification.severity,
                                code: bobClassification.code,
                                message: bobClassification.message
                            )
                        ]
                    )
                }

                let genericClassification = classifyRemoteProbeFailure(detail: detail)
                if genericClassification.code != "remoteLaunchProbeFailed" {
                    return ProviderHealthSummary(
                        state: genericClassification.state,
                        summary: genericClassification.summary,
                        resolvedExecutable: executable,
                        version: version,
                        launchability: .notLaunchable,
                        diagnostics: [
                            ProviderHealthDiagnostic(
                                severity: .error,
                                code: genericClassification.code,
                                message: genericClassification.message
                                    ?? (detail.isEmpty ? genericClassification.summary : detail)
                            )
                        ]
                    )
                }

                return ProviderHealthSummary(
                    state: .available,
                    summary: availableSummary(version: version),
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .launchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .warning,
                            code: bobClassification.code,
                            message: bobClassification.message
                        )
                    ]
                )
            }
        }

        fileprivate func availableSummary(version: String?) -> String {
            version.map { "IBM Bob \($0) is available" } ?? "IBM Bob is available"
        }

        fileprivate func remoteBlockedSummary(for code: String) -> String {
            switch code {
            case "licenseRequired":
                "IBM Bob requires license acceptance"
            case "authenticationRequired":
                "IBM Bob requires authentication on the Remote Workspace"
            case "setupRequired":
                "IBM Bob requires setup on the Remote Workspace"
            default:
                "IBM Bob is unavailable on the Remote Workspace"
            }
        }

        fileprivate func classifyPassiveProbeFailure(detail: String) -> (
            state: ProviderHealthSummary.State,
            summary: (String?) -> String,
            launchability: ProviderHealthSummary.Launchability,
            severity: ProviderHealthDiagnostic.Severity,
            code: String,
            message: String
        ) {
            let normalized = detail.lowercased()

            if normalized.contains("license") || normalized.contains("licence") {
                return (
                    .misconfigured,
                    { _ in "IBM Bob requires license acceptance" },
                    .notLaunchable,
                    .error,
                    "licenseRequired",
                    detail
                )
            }

            if isExplicitAuthenticationFailure(normalized) {
                return (
                    .unavailable,
                    { _ in "IBM Bob requires authentication" },
                    .notLaunchable,
                    .error,
                    "authenticationRequired",
                    detail
                )
            }

            if normalized.contains("setup")
                || normalized.contains("configure")
                || normalized.contains("configuration")
                || normalized.contains("install")
            {
                return (
                    .misconfigured,
                    { _ in "IBM Bob requires setup" },
                    .notLaunchable,
                    .error,
                    "setupRequired",
                    detail
                )
            }

            return (
                .available,
                { version in version.map { "IBM Bob \($0) is available" } ?? "IBM Bob is available" },
                .launchable,
                .warning,
                "passiveProbeInconclusive",
                detail
            )
        }

        fileprivate func classifyRemoteProbeFailure(
            detail: String
        ) -> (state: ProviderHealthSummary.State, summary: String, code: String, message: String?) {
            let normalized = detail.lowercased()

            if normalized.contains("nexus_remote_workspace_unavailable") {
                return (
                    .unavailable,
                    "IBM Bob is unavailable on the Remote Workspace",
                    "remoteWorkspaceUnavailable",
                    "The Remote Workspace path is unavailable on the Host."
                )
            }

            if normalized.contains("nexus_remote_bob_not_found")
                || normalized.contains("command not found")
                || normalized.contains("no such file")
            {
                return (
                    .unavailable,
                    "IBM Bob is unavailable on the Remote Workspace",
                    "remoteExecutableNotFound",
                    "IBM Bob executable was not found in the remote shell environments Nexus checked."
                )
            }

            if normalized.contains("permission denied")
                || normalized.contains("bad configuration option")
            {
                return (
                    .misconfigured,
                    "Remote IBM Bob launch prerequisites are misconfigured",
                    "remoteLaunchMisconfigured",
                    nil
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
                    "Remote IBM Bob is currently unavailable",
                    "remoteUnavailable",
                    nil
                )
            }

            return (
                .misconfigured,
                "IBM Bob is installed but failed the remote launch probe",
                "remoteLaunchProbeFailed",
                nil
            )
        }

        fileprivate func isExplicitAuthenticationFailure(_ message: String) -> Bool {
            let normalized = message.lowercased()
            return normalized.contains("auth")
                || normalized.contains("login")
                || normalized.contains("not logged in")
                || normalized.contains("not authenticated")
                || normalized.contains("unauthorized")
        }
    }
#endif
