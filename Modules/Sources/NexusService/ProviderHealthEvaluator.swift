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

    init(
        executableResolver: any ProviderExecutableResolving = SystemProviderExecutableResolver(),
        commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner()
    ) {
        self.executableResolver = executableResolver
        self.commandRunner = commandRunner
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
            return claudeHealthSummary(for: workspace)
        case .codex, .ibmBob, .pi:
            return ProviderHealthSummary(
                state: .notChecked,
                summary: "Health checks coming soon"
            )
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
            return remoteClaudeHealthSummary(for: workspace, host: remoteContext.host)
        case .codex, .ibmBob, .pi:
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

    private func remoteClaudeHealthSummary(for workspace: Workspace, host: NexusDomain.Host) -> ProviderHealthSummary {
        do {
            let result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteClaudeHealthProbeArguments(for: workspace, host: host),
                currentDirectoryURL: nil
            )

            guard result.exitStatus == 0 else {
                let detail = firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr)
                let classification = classifyRemoteClaudeFailure(detail: detail)
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
                summary: version.map { "Claude \($0) is available" } ?? "Claude is available",
                resolvedExecutable: executable,
                version: version,
                launchability: .launchable,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote Claude launch prerequisites on \(host.name) for \(workspace.folderPath)."
                    )
                ]
            )
        } catch {
            return ProviderHealthSummary(
                state: .unavailable,
                summary: "Remote Claude health check failed before the SSH probe completed",
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

    private func claudeHealthSummary(for workspace: Workspace) -> ProviderHealthSummary {
        let resolution = executableResolver.resolveExecutable(named: "claude")
        guard let executable = resolution.resolvedExecutable else {
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
        }

        var diagnostics: [ProviderHealthDiagnostic] = []
        let version = detectVersion(executable: executable, diagnostics: &diagnostics)

        do {
            let launchProbe = try commandRunner.run(
                executable: executable,
                arguments: ["--help"],
                currentDirectoryURL: URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
            )

            guard launchProbe.exitStatus == 0 else {
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
                            message: launchProbeFailureMessage(stdout: launchProbe.stdout, stderr: launchProbe.stderr)
                        )
                    ]
                )
            }
        } catch {
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
                        message: error.localizedDescription
                    )
                ]
            )
        }

        return ProviderHealthSummary(
            state: .available,
            summary: version.map { "Claude \($0) is available" } ?? "Claude is available",
            resolvedExecutable: executable,
            version: version,
            launchability: .launchable,
            diagnostics: diagnostics
        )
    }

    private func detectVersion(executable: String, diagnostics: inout [ProviderHealthDiagnostic]) -> String? {
        do {
            let result = try commandRunner.run(executable: executable, arguments: ["--version"], currentDirectoryURL: nil)
            guard result.exitStatus == 0 else {
                diagnostics.append(
                    ProviderHealthDiagnostic(
                        severity: .warning,
                        code: "versionUnavailable",
                        message: launchProbeFailureMessage(stdout: result.stdout, stderr: result.stderr)
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
                    message: "Claude did not return a version string."
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

    private func remoteClaudeHealthProbeArguments(for workspace: Workspace, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteClaudeHealthProbeScript(for: workspace)]
        return arguments
    }

    private func remoteClaudeHealthProbeScript(for workspace: Workspace) -> String {
        "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; command -v tmux >/dev/null 2>&1 || { echo 'NEXUS_REMOTE_TMUX_UNAVAILABLE' >&2; exit 1; }; resolve_claude_path() { for shell in \"${SHELL:-}\" /bin/bash /usr/bin/bash /bin/sh /usr/bin/zsh /bin/zsh; do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; CANDIDATE=\"$(\"$shell\" -lc \(shellQuoted("command -v claude")) 2>/dev/null)\" || continue; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \"$HOME/.local/bin/claude\" \"$HOME/bin/claude\" /opt/homebrew/bin/claude /usr/local/bin/claude /usr/bin/claude /bin/claude; do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; CLAUDE_PATH=\"$(resolve_claude_path)\" || { echo 'NEXUS_REMOTE_CLAUDE_NOT_FOUND' >&2; exit 1; }; [ -n \"$CLAUDE_PATH\" ] || { echo 'NEXUS_REMOTE_CLAUDE_NOT_FOUND' >&2; exit 1; }; printf '%s\\n' \"$CLAUDE_PATH\"; \"$CLAUDE_PATH\" --version; \"$CLAUDE_PATH\" --help >/dev/null 2>&1"
    }

    private func firstDiagnosticLine(stdout: String, stderr: String) -> String {
        [stderr, stdout]
            .joined(separator: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false }) ?? ""
    }

    private func classifyRemoteClaudeFailure(detail: String) -> (state: ProviderHealthSummary.State, summary: String, code: String, message: String?) {
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
            return (.unavailable, "Remote Claude is currently unavailable", "remoteUnavailable", nil)
        }

        return (.misconfigured, "Claude is installed but failed the remote launch probe", "remoteLaunchProbeFailed", nil)
    }

    private func launchProbeFailureMessage(stdout: String, stderr: String) -> String {
        let detail = firstDiagnosticLine(stdout: stdout, stderr: stderr)

        if detail.isEmpty == false {
            return detail
        }

        return "Claude could not complete a basic launch probe."
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
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

        let fallbackDirectories = homeDirectories.flatMap { [
            $0 + "/.local/bin",
            $0 + "/bin"
        ] } + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

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
