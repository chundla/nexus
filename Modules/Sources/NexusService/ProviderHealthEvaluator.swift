#if os(macOS)
import Darwin
import Foundation
import NexusDomain

protocol ProviderExecutableResolving {
    func resolveExecutable(named command: String) -> ProviderExecutableResolution
}

struct ProviderExecutableResolution: Equatable {
    let resolvedExecutable: String?
    let searchedDirectories: [String]
    let homeDirectories: [String]
    let pathEnvironment: String?
}

protocol ProviderCommandRunning {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult
}

struct ProviderCommandResult: Equatable {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
}

protocol CodexReadinessProbing {
    func probe(executable: String, workingDirectory: String) throws
}

protocol RemoteCodexReadinessProbing {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) throws -> RemoteCodexReadinessOutcome
}

protocol RemotePiReadinessProbing {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) throws -> RemotePiReadinessOutcome
}

enum RemoteCodexReadinessOutcome: Sendable, Equatable {
    case ready
    case authenticationRequired(String)
    case authenticationUncertain(String?)
}

enum RemotePiReadinessOutcome: Sendable, Equatable {
    case ready
    case authenticationRequired(String)
    case authenticationUncertain(String?)
}

struct RemoteWorkspaceHealthContext {
    let host: NexusDomain.Host
    let hostValidation: HostValidationSnapshot?
    let workspaceAvailability: WorkspaceAvailabilitySnapshot?
}

protocol ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) -> [WorkspaceProviderCard]
    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) -> ProviderHealthSummary
}

struct ProviderHealthEvaluator: ProviderHealthEvaluating {
    let executableResolver: any ProviderExecutableResolving
    let commandRunner: any ProviderCommandRunning
    let localShellCommandBuilder: LocalShellCommandBuilder
    let codexReadinessProbe: any CodexReadinessProbing
    let remoteCodexReadinessProbe: any RemoteCodexReadinessProbing
    let remotePiReadinessProbe: any RemotePiReadinessProbing

    init(
        executableResolver: any ProviderExecutableResolving = SystemProviderExecutableResolver(),
        commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner(),
        localShellCommandBuilder: LocalShellCommandBuilder = LocalShellCommandBuilder(),
        codexReadinessProbe: any CodexReadinessProbing = CodexAppServerReadinessProbe(),
        remoteCodexReadinessProbe: any RemoteCodexReadinessProbing = SSHRemoteCodexAppServerReadinessProbe(),
        remotePiReadinessProbe: any RemotePiReadinessProbing = SSHRemotePiRPCReadinessProbe()
    ) {
        self.executableResolver = executableResolver
        self.commandRunner = commandRunner
        self.localShellCommandBuilder = localShellCommandBuilder
        self.codexReadinessProbe = codexReadinessProbe
        self.remoteCodexReadinessProbe = remoteCodexReadinessProbe
        self.remotePiReadinessProbe = remotePiReadinessProbe
    }

    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext? = nil) -> [WorkspaceProviderCard] {
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

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext? = nil) -> ProviderHealthSummary {
        if workspace.kind == .remote {
            return remoteHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
        }

        switch providerID {
        case .claude:
            return localCLIHealthSummary(commandName: "claude", providerName: "Claude", workspace: workspace)
        case .codex:
            return localCodexHealthSummary(workspace: workspace)
        case .pi:
            return localCLIHealthSummary(commandName: "pi", providerName: "Pi", workspace: workspace)
        case .ibmBob:
            return localIBMBobHealthSummary(workspace: workspace)
        }
    }

    private func remoteHealthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) -> ProviderHealthSummary {
        let providerName = Provider(id: providerID).displayName

        if let blockedByHostValidation = blockedByHostValidation(providerName: providerName, remoteContext: remoteContext) {
            return blockedByHostValidation
        }

        if let blockedByWorkspaceAvailability = blockedByWorkspaceAvailability(providerName: providerName, remoteContext: remoteContext) {
            return blockedByWorkspaceAvailability
        }

        guard let remoteContext else {
            return ProviderHealthSummary(
                state: .blocked,
                summary: "Provider Health is blocked by Workspace Availability",
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "workspaceAvailabilityBlocked",
                        message: "Provider Health for \(providerName) is blocked until Workspace Availability is checked."
                    )
                ]
            )
        }

        switch providerID {
        case .claude:
            return remoteCLIHealthSummary(commandName: "claude", providerName: "Claude", workspace: workspace, host: remoteContext.host)
        case .codex:
            return remoteCodexHealthSummary(workspace: workspace, host: remoteContext.host)
        case .pi:
            return remotePiHealthSummary(workspace: workspace, host: remoteContext.host)
        case .ibmBob:
            return ProviderHealthSummary(
                state: .notChecked,
                summary: "Remote \(providerName) execution is not implemented yet",
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "remoteExecutionNotImplemented",
                        message: "Nexus shows \(providerName) on Remote Workspaces, but remote execution for this Provider is not implemented in this milestone."
                    )
                ]
            )
        }
    }

    private func blockedByHostValidation(providerName: String, remoteContext: RemoteWorkspaceHealthContext?) -> ProviderHealthSummary? {
        guard let hostValidation = remoteContext?.hostValidation else {
            return ProviderHealthSummary(
                state: .blocked,
                summary: "Provider Health is blocked by Host Validation",
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "hostValidationBlocked",
                        message: "Provider Health for \(providerName) is blocked until Host Validation runs."
                    )
                ]
            )
        }

        guard hostValidation.state != .available else {
            return nil
        }

        return ProviderHealthSummary(
            state: .blocked,
            summary: "Provider Health is blocked by Host Validation",
            diagnostics: [
                ProviderHealthDiagnostic(
                    severity: .warning,
                    code: "hostValidationBlocked",
                    message: "Provider Health for \(providerName) is blocked by Host Validation: \(hostValidation.summary)."
                )
            ]
        )
    }

    private func blockedByWorkspaceAvailability(providerName: String, remoteContext: RemoteWorkspaceHealthContext?) -> ProviderHealthSummary? {
        guard let workspaceAvailability = remoteContext?.workspaceAvailability else {
            return ProviderHealthSummary(
                state: .blocked,
                summary: "Provider Health is blocked by Workspace Availability",
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "workspaceAvailabilityBlocked",
                        message: "Provider Health for \(providerName) is blocked until Workspace Availability is checked."
                    )
                ]
            )
        }

        guard workspaceAvailability.state != .available else {
            return nil
        }

        return ProviderHealthSummary(
            state: .blocked,
            summary: "Provider Health is blocked by Workspace Availability",
            diagnostics: [
                ProviderHealthDiagnostic(
                    severity: .warning,
                    code: "workspaceAvailabilityBlocked",
                    message: "Provider Health for \(providerName) is blocked by Workspace Availability: \(workspaceAvailability.summary)."
                )
            ]
        )
    }

    private func remoteCLIHealthSummary(
        commandName: String,
        providerName: String,
        workspace: Workspace,
        host: NexusDomain.Host
    ) -> ProviderHealthSummary {
        do {
            let result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteCLIHealthProbeArguments(commandName: commandName, workspace: workspace, host: host),
                currentDirectoryURL: nil
            )

            guard result.exitStatus == 0 else {
                let detail = firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr)
                let classification = classifyRemoteCLIProbeFailure(
                    detail: detail,
                    providerName: providerName,
                    notFoundMarker: remoteExecutableNotFoundMarker(commandName: commandName)
                )
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

            let outputLines = result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            let executable = outputLines.first
            let version = outputLines.dropFirst().first

            return ProviderHealthSummary(
                state: .available,
                summary: version.map { "\(providerName) \($0) is available" } ?? "\(providerName) is available",
                resolvedExecutable: executable,
                version: version,
                launchability: .launchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote \(providerName) launch prerequisites on \(host.name) for \(workspace.folderPath)."
                    )
                ]
            )
        } catch {
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Remote \(providerName) health check failed before the SSH probe completed",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "sshLaunchFailed",
                        message: error.localizedDescription
                    )
                ]
            )
        }
    }

    private func remoteCodexHealthSummary(workspace: Workspace, host: NexusDomain.Host) -> ProviderHealthSummary {
        let result: ProviderCommandResult
        do {
            result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteCodexExecutableResolutionArguments(workspace: workspace, host: host),
                currentDirectoryURL: nil
            )
        } catch {
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Remote Codex health check failed before the SSH probe completed",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "sshLaunchFailed",
                        message: error.localizedDescription
                    )
                ]
            )
        }

        guard result.exitStatus == 0 else {
            let detail = firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr)
            let classification = classifyRemoteCLIProbeFailure(
                detail: detail,
                providerName: "Codex",
                notFoundMarker: remoteExecutableNotFoundMarker(commandName: "codex")
            )
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

        let outputLines = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let executable = outputLines.first else {
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
        let version = outputLines.dropFirst().first

        do {
            switch try remoteCodexReadinessProbe.probe(host: host, executable: executable, workingDirectory: workspace.folderPath) {
            case .ready:
                return ProviderHealthSummary(
                    state: .available,
                    summary: version.map { "Codex \($0) is available" } ?? "Codex is available",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .launchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .info,
                            code: "remoteProbe",
                            message: "Validated remote Codex launch prerequisites on \(host.name) for \(workspace.folderPath)."
                        )
                    ]
                )
            case let .authenticationRequired(message):
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
            case let .authenticationUncertain(message):
                var diagnostics = [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote Codex launch prerequisites on \(host.name) for \(workspace.folderPath)."
                    )
                ]
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
                    summary: version.map { "Codex \($0) is available" } ?? "Codex is available",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .launchable,
                    diagnostics: diagnostics
                )
            }
        } catch {
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
                        message: error.localizedDescription
                    )
                ]
            )
        }
    }

    private func remotePiHealthSummary(workspace: Workspace, host: NexusDomain.Host) -> ProviderHealthSummary {
        let result: ProviderCommandResult
        do {
            result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remotePiExecutableResolutionArguments(workspace: workspace, host: host),
                currentDirectoryURL: nil
            )
        } catch {
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Remote Pi health check failed before the SSH probe completed",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "sshLaunchFailed",
                        message: error.localizedDescription
                    )
                ]
            )
        }

        guard result.exitStatus == 0 else {
            let detail = firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr)
            let classification = classifyRemoteCLIProbeFailure(
                detail: detail,
                providerName: "Pi",
                notFoundMarker: remoteExecutableNotFoundMarker(commandName: "pi")
            )
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

        let outputLines = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let executable = outputLines.first else {
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
        }
        let version = outputLines.dropFirst().first

        do {
            switch try remotePiReadinessProbe.probe(host: host, executable: executable, workingDirectory: workspace.folderPath) {
            case .ready:
                return ProviderHealthSummary(
                    state: .available,
                    summary: version.map { "Pi \($0) is available" } ?? "Pi is available",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .launchable,
                    diagnostics: [
                        ProviderHealthDiagnostic(
                            severity: .info,
                            code: "remoteProbe",
                            message: "Validated remote Pi launch prerequisites on \(host.name) for \(workspace.folderPath)."
                        )
                    ]
                )
            case let .authenticationRequired(message):
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
            case let .authenticationUncertain(message):
                var diagnostics = [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote Pi launch prerequisites on \(host.name) for \(workspace.folderPath)."
                    )
                ]
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
                    summary: version.map { "Pi \($0) is available" } ?? "Pi is available",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .launchable,
                    diagnostics: diagnostics
                )
            }
        } catch {
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
                        message: error.localizedDescription
                    )
                ]
            )
        }
    }

    private func localCodexHealthSummary(workspace: Workspace) -> ProviderHealthSummary {
        let resolution = resolvedLocalExecutable(named: "codex")
        guard let executable = resolution.resolvedExecutable else {
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
        }

        var diagnostics: [ProviderHealthDiagnostic] = []
        let version = detectLocalVersion(executable: executable, providerName: "Codex", diagnostics: &diagnostics)

        do {
            try codexReadinessProbe.probe(executable: executable, workingDirectory: workspace.folderPath)
        } catch {
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
                        message: error.localizedDescription
                    )
                ]
            )
        }

        return ProviderHealthSummary(
            state: .available,
            summary: version.map { "Codex \($0) is available" } ?? "Codex is available",
            resolvedExecutable: executable,
            version: version,
            launchability: .launchable,
            diagnostics: diagnostics
        )
    }

    private func localIBMBobHealthSummary(workspace: Workspace) -> ProviderHealthSummary {
        let resolution = resolvedLocalExecutable(named: "bob")
        guard let executable = resolution.resolvedExecutable else {
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
                    )
                ]
            )
        }

        var diagnostics: [ProviderHealthDiagnostic] = []
        let version = detectLocalVersion(executable: executable, providerName: "IBM Bob", diagnostics: &diagnostics)

        do {
            let launchProbe = try runLocalCommandThroughShell(
                executable: executable,
                arguments: ["--list-sessions"],
                currentDirectoryURL: URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
            )

            guard launchProbe.exitStatus == 0 else {
                let detail = launchProbeFailureMessage(stdout: launchProbe.stdout, stderr: launchProbe.stderr, providerName: "IBM Bob")
                let classification = classifyLocalIBMBobPassiveProbeFailure(detail: detail)
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
        } catch {
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
                        message: error.localizedDescription
                    )
                ]
            )
        }

        return ProviderHealthSummary(
            state: .available,
            summary: version.map { "IBM Bob \($0) is available" } ?? "IBM Bob is available",
            resolvedExecutable: executable,
            version: version,
            launchability: .launchable,
            diagnostics: diagnostics
        )
    }

    private func localCLIHealthSummary(commandName: String, providerName: String, workspace: Workspace) -> ProviderHealthSummary {
        let resolution = resolvedLocalExecutable(named: commandName)
        guard let executable = resolution.resolvedExecutable else {
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "\(providerName) executable was not found",
                launchability: .notLaunchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "executableNotFound",
                        message: "\(providerName) executable was not found in the service search paths."
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
        }

        var diagnostics: [ProviderHealthDiagnostic] = []
        let version = detectLocalVersion(executable: executable, providerName: providerName, diagnostics: &diagnostics)

        do {
            let launchProbe = try runLocalCommandThroughShell(
                executable: executable,
                arguments: ["--help"],
                currentDirectoryURL: URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
            )

            guard launchProbe.exitStatus == 0 else {
                return ProviderHealthSummary(
                    state: .misconfigured,
                    summary: "\(providerName) is installed but failed the launch probe",
                    resolvedExecutable: executable,
                    version: version,
                    launchability: .notLaunchable,
                    diagnostics: diagnostics + [
                        ProviderHealthDiagnostic(
                            severity: .error,
                            code: "launchProbeFailed",
                            message: launchProbeFailureMessage(stdout: launchProbe.stdout, stderr: launchProbe.stderr, providerName: providerName)
                        )
                    ]
                )
            }
        } catch {
            return ProviderHealthSummary(
                state: .misconfigured,
                summary: "\(providerName) is installed but failed the launch probe",
                resolvedExecutable: executable,
                version: version,
                launchability: .notLaunchable,
                diagnostics: diagnostics + [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "launchProbeFailed",
                        message: error.localizedDescription
                    )
                ]
            )
        }

        return ProviderHealthSummary(
            state: .available,
            summary: version.map { "\(providerName) \($0) is available" } ?? "\(providerName) is available",
            resolvedExecutable: executable,
            version: version,
            launchability: .launchable,
            diagnostics: diagnostics
        )
    }

    private func resolvedLocalExecutable(named commandName: String) -> ProviderExecutableResolution {
        let resolution = executableResolver.resolveExecutable(named: commandName)
        guard resolution.resolvedExecutable == nil else {
            return resolution
        }

        guard let shellResolvedExecutable = resolveExecutableViaLocalShell(named: commandName) else {
            return resolution
        }

        return ProviderExecutableResolution(
            resolvedExecutable: shellResolvedExecutable,
            searchedDirectories: resolution.searchedDirectories,
            homeDirectories: resolution.homeDirectories,
            pathEnvironment: resolution.pathEnvironment
        )
    }

    private func resolveExecutableViaLocalShell(named commandName: String) -> String? {
        let shellCommand = "command -v \(commandName)"

        for command in localShellCommandBuilder.candidateCommands(for: shellCommand) {
            do {
                let result = try commandRunner.run(
                    executable: command.executable,
                    arguments: command.arguments,
                    currentDirectoryURL: nil
                )
                guard result.exitStatus == 0 else {
                    continue
                }

                let candidate = result.stdout
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { $0.hasPrefix("/") })

                if let candidate, FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func runLocalCommandThroughShell(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL?
    ) throws -> ProviderCommandResult {
        var lastResult: ProviderCommandResult?
        var lastError: Error?

        for command in localShellCommandBuilder.candidateCommands(
            for: ([shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
        ) {
            do {
                let result = try commandRunner.run(
                    executable: command.executable,
                    arguments: command.arguments,
                    currentDirectoryURL: currentDirectoryURL
                )
                if result.exitStatus == 0 {
                    return result
                }
                lastResult = result
            } catch {
                lastError = error
            }
        }

        if let lastResult {
            return lastResult
        }

        throw lastError ?? NSError(
            domain: "ProviderHealthEvaluator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Local shell launch probe failed before the command completed."]
        )
    }

    private func detectLocalVersion(executable: String, providerName: String, diagnostics: inout [ProviderHealthDiagnostic]) -> String? {
        do {
            let result = try runLocalCommandThroughShell(executable: executable, arguments: ["--version"], currentDirectoryURL: nil)
            guard result.exitStatus == 0 else {
                diagnostics.append(
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "versionUnavailable",
                        message: launchProbeFailureMessage(stdout: result.stdout, stderr: result.stderr, providerName: providerName)
                    )
                )
                return nil
            }

            let version = result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let version, version.isEmpty == false {
                return version
            }

            diagnostics.append(
                ProviderHealthDiagnostic(
                    severity: .warning,
                    code: "versionUnavailable",
                    message: "\(providerName) did not return a version string."
                )
            )
            return nil
        } catch {
            diagnostics.append(
                ProviderHealthDiagnostic(
                    severity: .warning,
                    code: "versionUnavailable",
                    message: error.localizedDescription
                )
            )
            return nil
        }
    }

    private func remoteCodexExecutableResolutionArguments(workspace: Workspace, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteCodexExecutableResolutionScript(workspace: workspace)]
        return arguments
    }

    private func remoteCodexExecutableResolutionScript(workspace: Workspace) -> String {
        let commandPathVariable = "CODEX_PATH"
        let resolveFunctionName = "resolve_codex_path"
        let notFoundMarker = remoteExecutableNotFoundMarker(commandName: "codex")
        let shellCommand = shellQuoted("command -v codex")
        let fallbackCandidates = [
            "$HOME/.local/bin/codex",
            "$HOME/bin/codex",
            "$HOME/.volta/bin/codex",
            "$HOME/.asdf/shims/codex",
            "$HOME/.local/share/mise/shims/codex",
            "$HOME/.nix-profile/bin/codex",
            "$HOME/.bun/bin/codex",
            "$HOME/.nvm/current/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/bin/codex"
        ].map { "\"\($0)\"" }.joined(separator: " ")
        let shellCandidates = ShellSupport.remoteShellCandidateListScript()

        return "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; \(resolveFunctionName)() { for shell in \(shellCandidates); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; case \"${shell##*/}\" in csh|tcsh) CANDIDATE=\"$(\"$shell\" -i -c \"if ( -f ~/.login ) source ~/.login; command -v codex\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"if ( -f ~/.login ) source ~/.login; command -v codex\" 2>/dev/null)\" || continue ;; fish) CANDIDATE=\"$(\"$shell\" -i -c \"command -v codex\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -l -c \"command -v codex\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"command -v codex\" 2>/dev/null)\" || continue ;; *) CANDIDATE=\"$(\"$shell\" -lic \(shellCommand) 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -lc \(shellCommand) 2>/dev/null)\" || continue ;; esac; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \(fallbackCandidates); do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; \(commandPathVariable)=\"$(\(resolveFunctionName))\" || { echo '\(notFoundMarker)' >&2; exit 1; }; [ -n \"$\(commandPathVariable)\" ] || { echo '\(notFoundMarker)' >&2; exit 1; }; printf '%s\\n' \"$\(commandPathVariable)\"; \"$\(commandPathVariable)\" --version"
    }

    private func remotePiExecutableResolutionArguments(workspace: Workspace, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remotePiExecutableResolutionScript(workspace: workspace)]
        return arguments
    }

    private func remotePiExecutableResolutionScript(workspace: Workspace) -> String {
        let commandPathVariable = "PI_PATH"
        let resolveFunctionName = "resolve_pi_path"
        let notFoundMarker = remoteExecutableNotFoundMarker(commandName: "pi")
        let shellCommand = shellQuoted("command -v pi")
        let fallbackCandidates = [
            "$HOME/.local/bin/pi",
            "$HOME/bin/pi",
            "$HOME/.volta/bin/pi",
            "$HOME/.asdf/shims/pi",
            "$HOME/.local/share/mise/shims/pi",
            "$HOME/.nix-profile/bin/pi",
            "$HOME/.bun/bin/pi",
            "$HOME/.nvm/current/bin/pi",
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
            "/usr/bin/pi",
            "/bin/pi"
        ].map { "\"\($0)\"" }.joined(separator: " ")
        let shellCandidates = ShellSupport.remoteShellCandidateListScript()

        return "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; \(resolveFunctionName)() { for shell in \(shellCandidates); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; case \"${shell##*/}\" in csh|tcsh) CANDIDATE=\"$(\"$shell\" -i -c \"if ( -f ~/.login ) source ~/.login; command -v pi\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"if ( -f ~/.login ) source ~/.login; command -v pi\" 2>/dev/null)\" || continue ;; fish) CANDIDATE=\"$(\"$shell\" -i -c \"command -v pi\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -l -c \"command -v pi\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"command -v pi\" 2>/dev/null)\" || continue ;; *) CANDIDATE=\"$(\"$shell\" -lic \(shellCommand) 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -lc \(shellCommand) 2>/dev/null)\" || continue ;; esac; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \(fallbackCandidates); do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; \(commandPathVariable)=\"$(\(resolveFunctionName))\" || { echo '\(notFoundMarker)' >&2; exit 1; }; [ -n \"$\(commandPathVariable)\" ] || { echo '\(notFoundMarker)' >&2; exit 1; }; printf '%s\\n' \"$\(commandPathVariable)\"; \"$\(commandPathVariable)\" --version"
    }

    private func remoteCLIHealthProbeArguments(commandName: String, workspace: Workspace, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteCLIHealthProbeScript(commandName: commandName, workspace: workspace)]
        return arguments
    }

    private func remoteCLIHealthProbeScript(commandName: String, workspace: Workspace) -> String {
        let commandPathVariable = "\(commandName.uppercased())_PATH"
        let resolveFunctionName = "resolve_\(commandName)_path"
        let notFoundMarker = remoteExecutableNotFoundMarker(commandName: commandName)
        let shellCommand = shellQuoted("command -v \(commandName)")
        let fallbackCandidates = [
            "$HOME/.local/bin/\(commandName)",
            "$HOME/bin/\(commandName)",
            "$HOME/.volta/bin/\(commandName)",
            "$HOME/.asdf/shims/\(commandName)",
            "$HOME/.local/share/mise/shims/\(commandName)",
            "$HOME/.nix-profile/bin/\(commandName)",
            "$HOME/.bun/bin/\(commandName)",
            "$HOME/.nvm/current/bin/\(commandName)",
            "/opt/homebrew/bin/\(commandName)",
            "/usr/local/bin/\(commandName)",
            "/usr/bin/\(commandName)",
            "/bin/\(commandName)"
        ].map { "\"\($0)\"" }.joined(separator: " ")
        let shellCandidates = ShellSupport.remoteShellCandidateListScript()

        return "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; command -v tmux >/dev/null 2>&1 || { echo 'NEXUS_REMOTE_TMUX_UNAVAILABLE' >&2; exit 1; }; \(resolveFunctionName)() { for shell in \(shellCandidates); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; case \"${shell##*/}\" in csh|tcsh) CANDIDATE=\"$(\"$shell\" -i -c \"if ( -f ~/.login ) source ~/.login; command -v \(commandName)\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"if ( -f ~/.login ) source ~/.login; command -v \(commandName)\" 2>/dev/null)\" || continue ;; fish) CANDIDATE=\"$(\"$shell\" -i -c \"command -v \(commandName)\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -l -c \"command -v \(commandName)\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"command -v \(commandName)\" 2>/dev/null)\" || continue ;; *) CANDIDATE=\"$(\"$shell\" -lic \(shellCommand) 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -lc \(shellCommand) 2>/dev/null)\" || continue ;; esac; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \(fallbackCandidates); do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; \(commandPathVariable)=\"$(\(resolveFunctionName))\" || { echo '\(notFoundMarker)' >&2; exit 1; }; [ -n \"$\(commandPathVariable)\" ] || { echo '\(notFoundMarker)' >&2; exit 1; }; printf '%s\\n' \"$\(commandPathVariable)\"; \"$\(commandPathVariable)\" --version; \"$\(commandPathVariable)\" --help >/dev/null 2>&1"
    }

    private func firstDiagnosticLine(stdout: String, stderr: String) -> String {
        [stderr, stdout]
            .joined(separator: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false }) ?? ""
    }

    private func remoteExecutableNotFoundMarker(commandName: String) -> String {
        "NEXUS_REMOTE_\(commandName.uppercased())_NOT_FOUND"
    }

    private func classifyRemoteCLIProbeFailure(
        detail: String,
        providerName: String,
        notFoundMarker: String
    ) -> (state: ProviderHealthSummary.State, summary: String, code: String, message: String?) {
        let normalized = detail.lowercased()

        if normalized.contains("nexus_remote_workspace_unavailable") {
            return (
                .unavailable,
                "\(providerName) is unavailable on the Remote Workspace",
                "remoteWorkspaceUnavailable",
                "The Remote Workspace path is unavailable on the Host."
            )
        }

        if normalized.contains(notFoundMarker.lowercased())
            || normalized.contains("command not found")
            || normalized.contains("no such file") {
            return (
                .unavailable,
                "\(providerName) is unavailable on the Remote Workspace",
                "remoteExecutableNotFound",
                "\(providerName) executable was not found in the remote shell environments Nexus checked."
            )
        }

        if normalized.contains("nexus_remote_tmux_unavailable")
            || normalized.contains("permission denied")
            || normalized.contains("bad configuration option")
            || normalized.contains("tmux") {
            return (
                .misconfigured,
                "Remote \(providerName) launch prerequisites are misconfigured",
                "remoteLaunchMisconfigured",
                normalized.contains("nexus_remote_tmux_unavailable") ? "tmux is not available in the remote shell." : nil
            )
        }

        if normalized.contains("connection timed out")
            || normalized.contains("operation timed out")
            || normalized.contains("connection refused")
            || normalized.contains("network is unreachable")
            || normalized.contains("no route to host") {
            return (.unavailable, "Remote \(providerName) is currently unavailable", "remoteUnavailable", nil)
        }

        return (.misconfigured, "\(providerName) is installed but failed the remote launch probe", "remoteLaunchProbeFailed", nil)
    }

    private func classifyLocalIBMBobPassiveProbeFailure(detail: String) -> (
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
            || normalized.contains("install") {
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

    private func isExplicitAuthenticationFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("auth")
            || normalized.contains("login")
            || normalized.contains("not logged in")
            || normalized.contains("not authenticated")
            || normalized.contains("unauthorized")
        }

    private func launchProbeFailureMessage(stdout: String, stderr: String, providerName: String) -> String {
        let detail = firstDiagnosticLine(stdout: stdout, stderr: stderr)

        if detail.isEmpty == false {
            return detail
        }

        return "\(providerName) could not complete a basic launch probe."
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

struct CodexAppServerReadinessProbe: CodexReadinessProbing {
    func probe(executable: String, workingDirectory: String) throws {
        let transport = try ProcessCodexAppServerTransport(
            executable: executable,
            arguments: ["app-server"],
            workingDirectory: workingDirectory
        )

        let semaphore = DispatchSemaphore(value: 0)
        let state = CodexReadinessProbeState()

        transport.setStdoutLineHandler { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                state.error = NSError(domain: "CodexAppServerReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
                semaphore.signal()
                return
            }

            if let id = object["id"] as? String, id == "nexus-codex-readiness-initialize" {
                semaphore.signal()
            }
        }
        transport.setTerminationHandler { termination in
            if termination.status != 0, state.error == nil {
                let detail = termination.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
                state.error = NSError(
                    domain: "CodexAppServerReadinessProbe",
                    code: Int(termination.status),
                    userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! : "Codex app-server exited before readiness completed."]
                )
                semaphore.signal()
            }
        }

        try transport.start()
        try transport.sendLine(Self.jsonLine([
            "jsonrpc": "2.0",
            "id": "nexus-codex-readiness-initialize",
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "nexus",
                    "version": "1"
                ]
            ]
        ]))

        defer {
            try? transport.terminate()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            throw NSError(
                domain: "CodexAppServerReadinessProbe",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Codex app-server did not answer the readiness probe in time."]
            )
        }

        if let error = state.error {
            throw error
        }
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CodexAppServerReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Codex readiness probe request."])
        }
        return line
    }
}

struct SSHRemoteCodexAppServerReadinessProbe: RemoteCodexReadinessProbing {
    typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any CodexAppServerTransporting

    private let transportFactory: TransportFactory

    init(transportFactory: @escaping TransportFactory = { executable, arguments, workingDirectory in
        try ProcessCodexAppServerTransport(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }) {
        self.transportFactory = transportFactory
    }

    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) throws -> RemoteCodexReadinessOutcome {
        let transport = try transportFactory(
            "/usr/bin/ssh",
            sshArguments(host: host, executable: executable, workingDirectory: workingDirectory),
            nil
        )

        let semaphore = DispatchSemaphore(value: 0)
        let state = CodexReadinessProbeState()

        transport.setStdoutLineHandler { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                state.error = NSError(domain: "SSHRemoteCodexAppServerReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
                semaphore.signal()
                return
            }

            if let id = object["id"] as? String, id == "nexus-codex-readiness-initialize" {
                semaphore.signal()
            }
        }
        transport.setTerminationHandler { termination in
            if termination.status != 0, state.error == nil {
                let detail = termination.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
                state.error = NSError(
                    domain: "SSHRemoteCodexAppServerReadinessProbe",
                    code: Int(termination.status),
                    userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! : "Codex app-server exited before remote readiness completed."]
                )
                semaphore.signal()
            }
        }

        try transport.start()
        try transport.sendLine(Self.jsonLine([
            "jsonrpc": "2.0",
            "id": "nexus-codex-readiness-initialize",
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "nexus",
                    "version": "1"
                ]
            ]
        ]))

        defer {
            try? transport.terminate()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            return .authenticationUncertain("Codex app-server did not answer the remote readiness probe in time.")
        }

        if let error = state.error {
            let message = error.localizedDescription
            if isExplicitAuthenticationFailure(message) {
                return .authenticationRequired(message)
            }
            throw error
        }

        return .ready
    }

    private func sshArguments(host: NexusDomain.Host, executable: String, workingDirectory: String) -> [String] {
        var arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteCommand(executable: executable, workingDirectory: workingDirectory)]
        return arguments
    }

    private func remoteCommand(executable: String, workingDirectory: String) -> String {
        "cd \(shellQuoted(workingDirectory)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec \(shellQuoted(executable)) app-server"
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func isExplicitAuthenticationFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("auth")
            || normalized.contains("login")
            || normalized.contains("not logged in")
            || normalized.contains("not authenticated")
            || normalized.contains("unauthorized")
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SSHRemoteCodexAppServerReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode remote Codex readiness probe request."])
        }
        return line
    }
}

struct SSHRemotePiRPCReadinessProbe: RemotePiReadinessProbing {
    typealias TransportFactory = (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any PiRPCTransporting

    private let transportFactory: TransportFactory

    init(transportFactory: @escaping TransportFactory = { executable, arguments, workingDirectory in
        try ProcessPiRPCTransport(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }) {
        self.transportFactory = transportFactory
    }

    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) throws -> RemotePiReadinessOutcome {
        let transport = try transportFactory(
            "/usr/bin/ssh",
            sshArguments(host: host, executable: executable, workingDirectory: workingDirectory),
            nil
        )

        let semaphore = DispatchSemaphore(value: 0)
        let state = CodexReadinessProbeState()
        let responseID = "nexus-pi-readiness-get-state"

        transport.setStdoutLineHandler { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "response",
                  object["id"] as? String == responseID else {
                return
            }

            if object["success"] as? Bool == true {
                semaphore.signal()
                return
            }

            let message = object["error"] as? String ?? "Pi RPC readiness probe failed."
            state.error = NSError(domain: "SSHRemotePiRPCReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            semaphore.signal()
        }
        transport.setTerminationHandler { status in
            if status != 0, state.error == nil {
                state.error = NSError(
                    domain: "SSHRemotePiRPCReadinessProbe",
                    code: Int(status),
                    userInfo: [NSLocalizedDescriptionKey: "Pi RPC mode exited before remote readiness completed."]
                )
                semaphore.signal()
            }
        }

        try transport.start()
        try transport.sendLine(Self.jsonLine(["id": responseID, "type": "get_state"]))

        defer {
            try? transport.terminate()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            return .authenticationUncertain("Pi RPC mode did not answer the remote readiness probe in time.")
        }

        if let error = state.error {
            let message = error.localizedDescription
            if isExplicitAuthenticationFailure(message) {
                return .authenticationRequired(message)
            }
            throw error
        }

        return .ready
    }

    private func sshArguments(host: NexusDomain.Host, executable: String, workingDirectory: String) -> [String] {
        var arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteCommand(executable: executable, workingDirectory: workingDirectory)]
        return arguments
    }

    private func remoteCommand(executable: String, workingDirectory: String) -> String {
        "cd \(shellQuoted(workingDirectory)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec \(shellQuoted(executable)) --mode rpc"
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func isExplicitAuthenticationFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("auth")
            || normalized.contains("login")
            || normalized.contains("not logged in")
            || normalized.contains("not authenticated")
            || normalized.contains("unauthorized")
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SSHRemotePiRPCReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode remote Pi readiness probe request."])
        }
        return line
    }
}

private final class CodexReadinessProbeState: @unchecked Sendable {
    var error: Error?
}

struct SystemProviderExecutableResolver: ProviderExecutableResolving {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        let homeDirectories = resolvedHomeDirectories()
        let searchedDirectories = searchDirectories(homeDirectories: homeDirectories)

        for directory in searchedDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)
                .path

            if fileManager.isExecutableFile(atPath: candidate) {
                return ProviderExecutableResolution(
                    resolvedExecutable: candidate,
                    searchedDirectories: searchedDirectories,
                    homeDirectories: homeDirectories,
                    pathEnvironment: environment["PATH"]
                )
            }
        }

        return ProviderExecutableResolution(
            resolvedExecutable: nil,
            searchedDirectories: searchedDirectories,
            homeDirectories: homeDirectories,
            pathEnvironment: environment["PATH"]
        )
    }

    private func searchDirectories(homeDirectories: [String]) -> [String] {
        let pathDirectories = environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)

        var homeFallbackDirectories: [String] = []
        homeFallbackDirectories.reserveCapacity(homeDirectories.count * 8)
        for homeDirectory in homeDirectories {
            homeFallbackDirectories.append(homeDirectory + "/.local/bin")
            homeFallbackDirectories.append(homeDirectory + "/bin")
            homeFallbackDirectories.append(homeDirectory + "/.volta/bin")
            homeFallbackDirectories.append(homeDirectory + "/.asdf/shims")
            homeFallbackDirectories.append(homeDirectory + "/.local/share/mise/shims")
            homeFallbackDirectories.append(homeDirectory + "/.nix-profile/bin")
            homeFallbackDirectories.append(homeDirectory + "/.bun/bin")
            homeFallbackDirectories.append(homeDirectory + "/.nvm/current/bin")
        }
        let systemFallbackDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let fallbackDirectories = homeFallbackDirectories + systemFallbackDirectories

        var directories: [String] = []
        var seen: Set<String> = []
        for directory in pathDirectories + fallbackDirectories {
            guard seen.insert(directory).inserted else {
                continue
            }
            directories.append(directory)
        }
        return directories
    }

    private func resolvedHomeDirectories() -> [String] {
        var directories: [String] = []
        var seen: Set<String> = []

        let posixHomeDirectory = getpwuid(getuid()).flatMap { entry in
            entry.pointee.pw_dir.map { String(cString: $0) }
        }

        for candidate in [
            environment["HOME"],
            NSHomeDirectory(),
            fileManager.homeDirectoryForCurrentUser.path,
            posixHomeDirectory
        ] {
            guard let candidate, candidate.isEmpty == false, seen.insert(candidate).inserted else {
                continue
            }
            directories.append(candidate)
        }

        return directories
    }
}

struct SystemProviderCommandRunner: ProviderCommandRunning {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable, isDirectory: false)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProviderCommandResult(exitStatus: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
#endif
