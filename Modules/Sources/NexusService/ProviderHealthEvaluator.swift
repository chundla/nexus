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
            return remoteHealthSummary(for: providerID, remoteContext: remoteContext)
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

    private func remoteHealthSummary(for providerID: ProviderID, remoteContext: RemoteWorkspaceHealthContext?) -> ProviderHealthSummary {
        let providerName = Provider(id: providerID).displayName

        if let blockedByHostValidation = blockedByHostValidation(providerName: providerName, remoteContext: remoteContext) {
            return blockedByHostValidation
        }

        if let blockedByWorkspaceAvailability = blockedByWorkspaceAvailability(providerName: providerName, remoteContext: remoteContext) {
            return blockedByWorkspaceAvailability
        }

        return ProviderHealthSummary(
            state: .notChecked,
            summary: "Remote \(providerName) health checks are not implemented yet",
            diagnostics: [
                ProviderHealthDiagnostic(
                    severity: .warning,
                    code: "remoteHealthNotImplemented",
                    message: "Nexus does not yet evaluate \(providerName) health for Remote Workspaces over SSH."
                )
            ]
        )
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

    private func launchProbeFailureMessage(stdout: String, stderr: String) -> String {
        let detail = [stderr, stdout]
            .joined(separator: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let detail, detail.isEmpty == false {
            return detail
        }

        return "Claude could not complete a basic launch probe."
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
