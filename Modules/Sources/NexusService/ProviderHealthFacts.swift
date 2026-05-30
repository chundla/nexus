#if os(macOS)
import Darwin
import Foundation
import NexusDomain

protocol ProviderExecutableResolving: Sendable {
    func resolveExecutable(named command: String) -> ProviderExecutableResolution
}

struct ProviderExecutableResolution: Equatable {
    let resolvedExecutable: String?
    let searchedDirectories: [String]
    let homeDirectories: [String]
    let pathEnvironment: String?
}

protocol ProviderCommandRunning: Sendable {
    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult
}

struct ProviderCommandResult: Equatable {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
}

protocol CodexReadinessProbing: Sendable {
    func probe(executable: String, workingDirectory: String) async throws
}

protocol RemoteCodexReadinessProbing: Sendable {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws -> RemoteCodexReadinessOutcome
}

protocol RemotePiReadinessProbing: Sendable {
    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws -> RemotePiReadinessOutcome
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

enum LocalCLIHealthProbeResult: Sendable, Equatable {
    case executableNotFound(ProviderExecutableResolution)
    case launchProbeFailed(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic],
        detail: String
    )
    case ready(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic]
    )
}

enum RemoteCLIHealthProbeResult: Sendable, Equatable {
    case sshLaunchFailed(String)
    case probeFailed(String)
    case ready(
        executable: String?,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic]
    )
}

enum LocalCodexHealthProbeResult: Sendable, Equatable {
    case executableNotFound(ProviderExecutableResolution)
    case readinessProbeFailed(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic],
        detail: String
    )
    case ready(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic]
    )
}

enum RemoteCodexHealthProbeResult: Sendable, Equatable {
    case sshResolutionLaunchFailed(String)
    case resolutionProbeFailed(String)
    case resolutionReturnedNoExecutable
    case readinessProbeFailed(executable: String, version: String?, detail: String)
    case authenticationRequired(executable: String, version: String?, message: String)
    case authenticationUncertain(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic],
        message: String?
    )
    case ready(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic]
    )
}

enum RemotePiHealthProbeResult: Sendable, Equatable {
    case sshResolutionLaunchFailed(String)
    case resolutionProbeFailed(String)
    case resolutionReturnedNoExecutable
    case readinessProbeFailed(executable: String, version: String?, detail: String)
    case authenticationRequired(executable: String, version: String?, message: String)
    case authenticationUncertain(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic],
        message: String?
    )
    case ready(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic]
    )
}

enum LocalIBMBobPassiveProbeResult: Sendable, Equatable {
    case executableNotFound(ProviderExecutableResolution)
    case passiveProbeLaunchFailed(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic],
        detail: String
    )
    case passiveProbeCompleted(
        executable: String,
        version: String?,
        diagnostics: [ProviderHealthDiagnostic],
        detail: String?
    )
}

enum RemoteIBMBobPassiveProbeResult: Sendable, Equatable {
    case sshResolutionLaunchFailed(String)
    case resolutionProbeFailed(String)
    case resolutionReturnedNoExecutable
    case passiveProbeSSHLaunchFailed(
        executable: String,
        version: String?,
        message: String
    )
    case passiveProbeCompleted(
        executable: String,
        version: String?,
        detail: String?
    )
}

protocol CLIProviderHealthFactProviding: Sendable {
    func localCLIHealthProbe(commandName: String, providerName: String, workspace: Workspace) async -> LocalCLIHealthProbeResult
    func remoteCLIHealthProbe(commandName: String, providerName: String, workspace: Workspace, host: NexusDomain.Host) async -> RemoteCLIHealthProbeResult
}

protocol CodexProviderHealthFactProviding: Sendable {
    func localCodexHealthProbe(workspace: Workspace) async -> LocalCodexHealthProbeResult
    func remoteCodexHealthProbe(workspace: Workspace, host: NexusDomain.Host) async -> RemoteCodexHealthProbeResult
}

protocol PiProviderHealthFactProviding: Sendable {
    func remotePiHealthProbe(workspace: Workspace, host: NexusDomain.Host) async -> RemotePiHealthProbeResult
}

protocol IBMBobProviderHealthFactProviding: Sendable {
    func localIBMBobPassiveProbe(workspace: Workspace) async -> LocalIBMBobPassiveProbeResult
    func remoteIBMBobPassiveProbe(workspace: Workspace, host: NexusDomain.Host) async -> RemoteIBMBobPassiveProbeResult
}

protocol SharedRemoteCLIProviderHealthFactProviding: Sendable {
    func remoteCLIHealthProbe(
        commandName: String,
        providerName: String,
        workspace: Workspace,
        host: NexusDomain.Host,
        probeFacts: RemoteWorkspaceProbeFacts
    ) async -> RemoteCLIHealthProbeResult
}

protocol SharedRemoteCodexProviderHealthFactProviding: Sendable {
    func remoteCodexHealthProbe(
        workspace: Workspace,
        host: NexusDomain.Host,
        probeFacts: RemoteWorkspaceProbeFacts
    ) async -> RemoteCodexHealthProbeResult
}

protocol SharedRemotePiProviderHealthFactProviding: Sendable {
    func remotePiHealthProbe(
        workspace: Workspace,
        host: NexusDomain.Host,
        probeFacts: RemoteWorkspaceProbeFacts
    ) async -> RemotePiHealthProbeResult
}

protocol SharedRemoteIBMBobProviderHealthFactProviding: Sendable {
    func remoteIBMBobPassiveProbe(
        workspace: Workspace,
        host: NexusDomain.Host,
        probeFacts: RemoteWorkspaceProbeFacts
    ) async -> RemoteIBMBobPassiveProbeResult
}

struct RemoteWorkspaceHealthContext {
    let host: NexusDomain.Host
    let hostValidation: HostValidationSnapshot?
    let workspaceAvailability: WorkspaceAvailabilitySnapshot?
    let probeFacts: RemoteWorkspaceProbeFacts?

    init(
        host: NexusDomain.Host,
        hostValidation: HostValidationSnapshot?,
        workspaceAvailability: WorkspaceAvailabilitySnapshot?,
        probeFacts: RemoteWorkspaceProbeFacts? = nil
    ) {
        self.host = host
        self.hostValidation = hostValidation
        self.workspaceAvailability = workspaceAvailability
        self.probeFacts = probeFacts
    }

    init(
        host: NexusDomain.Host,
        hostValidation: HostValidationSnapshot?,
        workspaceAvailability: WorkspaceAvailabilitySnapshot?,
        browseFacts: RemoteWorkspaceBrowseFacts?
    ) {
        self.init(
            host: host,
            hostValidation: hostValidation,
            workspaceAvailability: workspaceAvailability,
            probeFacts: browseFacts
        )
    }

    var browseFacts: RemoteWorkspaceBrowseFacts? { probeFacts }
}

protocol ProviderHealthEvaluating: Sendable {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> [WorkspaceProviderCard]
    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) async -> ProviderHealthSummary
}

extension ProviderHealthEvaluating {
    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) -> [WorkspaceProviderCard] {
        (try? AsyncOperationSupport.blocking { await providerCards(for: workspace, remoteContext: remoteContext) }) ?? []
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext?) -> ProviderHealthSummary {
        (try? AsyncOperationSupport.blocking { await healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext) })
            ?? ProviderHealthSummary(
                state: .notChecked,
                summary: "Provider Health could not be evaluated",
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .error,
                        code: "providerHealthEvaluationFailed",
                        message: "Provider Health could not be evaluated."
                    )
                ]
            )
    }
}

struct ProviderHealthFacts: ProviderHealthEvaluating, CLIProviderHealthFactProviding, CodexProviderHealthFactProviding, PiProviderHealthFactProviding, IBMBobProviderHealthFactProviding, SharedRemoteCLIProviderHealthFactProviding, SharedRemoteCodexProviderHealthFactProviding, SharedRemotePiProviderHealthFactProviding, SharedRemoteIBMBobProviderHealthFactProviding, @unchecked Sendable {
    let executableResolver: any ProviderExecutableResolving
    let commandRunner: any ProviderCommandRunning
    let localShellCommandBuilder: LocalShellCommandBuilder
    let codexReadinessProbe: any CodexReadinessProbing
    let remoteCodexReadinessProbe: any RemoteCodexReadinessProbing
    let remotePiReadinessProbe: any RemotePiReadinessProbing
    let providerModuleRegistry: ProviderModuleRegistry

    init(
        executableResolver: any ProviderExecutableResolving = SystemProviderExecutableResolver(),
        commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner(),
        localShellCommandBuilder: LocalShellCommandBuilder = LocalShellCommandBuilder(),
        codexReadinessProbe: any CodexReadinessProbing = CodexAppServerReadinessProbe(),
        remoteCodexReadinessProbe: any RemoteCodexReadinessProbing = SSHRemoteCodexAppServerReadinessProbe(),
        remotePiReadinessProbe: any RemotePiReadinessProbing = SSHRemotePiRPCReadinessProbe(),
        providerModuleRegistry: ProviderModuleRegistry = ServiceSessionProviderRegistry.providerModules()
    ) {
        self.executableResolver = executableResolver
        self.commandRunner = commandRunner
        self.localShellCommandBuilder = localShellCommandBuilder
        self.codexReadinessProbe = codexReadinessProbe
        self.remoteCodexReadinessProbe = remoteCodexReadinessProbe
        self.remotePiReadinessProbe = remotePiReadinessProbe
        self.providerModuleRegistry = providerModuleRegistry
    }

    func providerCards(for workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext? = nil) async -> [WorkspaceProviderCard] {
        var cards: [WorkspaceProviderCard] = []
        for providerID in ProviderID.allCases {
            cards.append(
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: await healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .notCreated,
                        summary: "No default session yet",
                        actionTitle: "Launch"
                    )
                )
            )
        }
        return cards
    }

    func healthSummary(for providerID: ProviderID, workspace: Workspace, remoteContext: RemoteWorkspaceHealthContext? = nil) async -> ProviderHealthSummary {
        await providerModuleRegistry.module(for: providerID).providerHealthSummary(
            for: workspace,
            remoteContext: remoteContext,
            providerHealthEvaluator: self
        )
    }

    func remoteCLIHealthProbe(
        commandName: String,
        providerName: String,
        workspace: Workspace,
        host: NexusDomain.Host
    ) async -> RemoteCLIHealthProbeResult {
        do {
            let result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteCLIHealthProbeArguments(commandName: commandName, workspace: workspace, host: host),
                currentDirectoryURL: nil
            )

            guard result.exitStatus == 0 else {
                return .probeFailed(firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr))
            }

            let outputLines = result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            let executable = outputLines.first
            let version = outputLines.dropFirst().first

            return .ready(
                executable: executable,
                version: version,
                diagnostics: [
                    ProviderHealthDiagnostic(
                        severity: .info,
                        code: "remoteProbe",
                        message: "Validated remote \(providerName) launch prerequisites on \(host.name) for \(workspace.folderPath)."
                    )
                ]
            )
        } catch {
            return .sshLaunchFailed(error.localizedDescription)
        }
    }

    func remoteCLIHealthProbe(
        commandName: String,
        providerName: String,
        workspace: Workspace,
        host: NexusDomain.Host,
        probeFacts: RemoteWorkspaceProbeFacts
    ) async -> RemoteCLIHealthProbeResult {
        let providerID = providerID(forRemoteCommandName: commandName)
        let fact = providerID.flatMap { probeFacts.providerFacts[$0] }

        if let resolutionDetail = fact?.resolutionDetail {
            return .probeFailed(resolutionDetail)
        }

        if let probeDetail = fact?.probeDetail {
            return .probeFailed(probeDetail)
        }

        guard let executable = fact?.executable else {
            return .probeFailed(remoteExecutableNotFoundMarker(commandName: commandName))
        }

        return .ready(
            executable: executable,
            version: fact?.version,
            diagnostics: [
                ProviderHealthDiagnostic(
                    severity: .info,
                    code: "remoteProbe",
                    message: "Validated remote \(providerName) launch prerequisites on \(host.name) for \(workspace.folderPath)."
                )
            ]
        )
    }

    func remoteCodexHealthProbe(workspace: Workspace, host: NexusDomain.Host, probeFacts: RemoteWorkspaceProbeFacts) async -> RemoteCodexHealthProbeResult {
        let fact = probeFacts.providerFacts[.codex]
        if let resolutionDetail = fact?.resolutionDetail {
            return .resolutionProbeFailed(resolutionDetail)
        }
        guard let executable = fact?.executable else {
            return .resolutionReturnedNoExecutable
        }
        let version = fact?.version
        let diagnostics = [
            ProviderHealthDiagnostic(
                severity: .info,
                code: "remoteProbe",
                message: "Validated remote Codex launch prerequisites on \(host.name) for \(workspace.folderPath)."
            )
        ]

        do {
            switch try await remoteCodexReadinessProbe.probe(host: host, executable: executable, workingDirectory: workspace.folderPath) {
            case .ready:
                return .ready(executable: executable, version: version, diagnostics: diagnostics)
            case let .authenticationRequired(message):
                return .authenticationRequired(executable: executable, version: version, message: message)
            case let .authenticationUncertain(message):
                return .authenticationUncertain(
                    executable: executable,
                    version: version,
                    diagnostics: diagnostics,
                    message: message
                )
            }
        } catch {
            return .readinessProbeFailed(
                executable: executable,
                version: version,
                detail: error.localizedDescription
            )
        }
    }

    func remoteCodexHealthProbe(workspace: Workspace, host: NexusDomain.Host) async -> RemoteCodexHealthProbeResult {
        let result: ProviderCommandResult
        do {
            result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteCodexExecutableResolutionArguments(workspace: workspace, host: host),
                currentDirectoryURL: nil
            )
        } catch {
            return .sshResolutionLaunchFailed(error.localizedDescription)
        }

        guard result.exitStatus == 0 else {
            return .resolutionProbeFailed(firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr))
        }

        let outputLines = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let executable = outputLines.first else {
            return .resolutionReturnedNoExecutable
        }
        let version = outputLines.dropFirst().first
        let diagnostics = [
            ProviderHealthDiagnostic(
                severity: .info,
                code: "remoteProbe",
                message: "Validated remote Codex launch prerequisites on \(host.name) for \(workspace.folderPath)."
            )
        ]

        do {
            switch try await remoteCodexReadinessProbe.probe(host: host, executable: executable, workingDirectory: workspace.folderPath) {
            case .ready:
                return .ready(executable: executable, version: version, diagnostics: diagnostics)
            case let .authenticationRequired(message):
                return .authenticationRequired(executable: executable, version: version, message: message)
            case let .authenticationUncertain(message):
                return .authenticationUncertain(
                    executable: executable,
                    version: version,
                    diagnostics: diagnostics,
                    message: message
                )
            }
        } catch {
            return .readinessProbeFailed(
                executable: executable,
                version: version,
                detail: error.localizedDescription
            )
        }
    }

    func remotePiHealthProbe(workspace: Workspace, host: NexusDomain.Host, probeFacts: RemoteWorkspaceProbeFacts) async -> RemotePiHealthProbeResult {
        let fact = probeFacts.providerFacts[.pi]
        if let resolutionDetail = fact?.resolutionDetail {
            return .resolutionProbeFailed(resolutionDetail)
        }
        guard let executable = fact?.executable else {
            return .resolutionReturnedNoExecutable
        }
        let version = fact?.version
        let diagnostics = [
            ProviderHealthDiagnostic(
                severity: .info,
                code: "remoteProbe",
                message: "Validated remote Pi launch prerequisites on \(host.name) for \(workspace.folderPath)."
            )
        ]

        do {
            switch try await remotePiReadinessProbe.probe(host: host, executable: executable, workingDirectory: workspace.folderPath) {
            case .ready:
                return .ready(executable: executable, version: version, diagnostics: diagnostics)
            case let .authenticationRequired(message):
                return .authenticationRequired(executable: executable, version: version, message: message)
            case let .authenticationUncertain(message):
                return .authenticationUncertain(
                    executable: executable,
                    version: version,
                    diagnostics: diagnostics,
                    message: message
                )
            }
        } catch {
            return .readinessProbeFailed(
                executable: executable,
                version: version,
                detail: error.localizedDescription
            )
        }
    }

    func remotePiHealthProbe(workspace: Workspace, host: NexusDomain.Host) async -> RemotePiHealthProbeResult {
        let result: ProviderCommandResult
        do {
            result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remotePiExecutableResolutionArguments(workspace: workspace, host: host),
                currentDirectoryURL: nil
            )
        } catch {
            return .sshResolutionLaunchFailed(error.localizedDescription)
        }

        guard result.exitStatus == 0 else {
            return .resolutionProbeFailed(firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr))
        }

        let outputLines = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let executable = outputLines.first else {
            return .resolutionReturnedNoExecutable
        }
        let version = outputLines.dropFirst().first
        let diagnostics = [
            ProviderHealthDiagnostic(
                severity: .info,
                code: "remoteProbe",
                message: "Validated remote Pi launch prerequisites on \(host.name) for \(workspace.folderPath)."
            )
        ]

        do {
            switch try await remotePiReadinessProbe.probe(host: host, executable: executable, workingDirectory: workspace.folderPath) {
            case .ready:
                return .ready(executable: executable, version: version, diagnostics: diagnostics)
            case let .authenticationRequired(message):
                return .authenticationRequired(executable: executable, version: version, message: message)
            case let .authenticationUncertain(message):
                return .authenticationUncertain(
                    executable: executable,
                    version: version,
                    diagnostics: diagnostics,
                    message: message
                )
            }
        } catch {
            return .readinessProbeFailed(
                executable: executable,
                version: version,
                detail: error.localizedDescription
            )
        }
    }

    func remoteIBMBobPassiveProbe(workspace: Workspace, host: NexusDomain.Host, probeFacts: RemoteWorkspaceProbeFacts) async -> RemoteIBMBobPassiveProbeResult {
        let fact = probeFacts.providerFacts[.ibmBob]
        if let resolutionDetail = fact?.resolutionDetail {
            return .resolutionProbeFailed(resolutionDetail)
        }
        guard let executable = fact?.executable else {
            return .resolutionReturnedNoExecutable
        }
        return .passiveProbeCompleted(
            executable: executable,
            version: fact?.version,
            detail: fact?.probeDetail
        )
    }

    func remoteIBMBobPassiveProbe(workspace: Workspace, host: NexusDomain.Host) async -> RemoteIBMBobPassiveProbeResult {
        let resolutionResult: ProviderCommandResult
        do {
            resolutionResult = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteIBMBobExecutableResolutionArguments(workspace: workspace, host: host),
                currentDirectoryURL: nil
            )
        } catch {
            return .sshResolutionLaunchFailed(error.localizedDescription)
        }

        guard resolutionResult.exitStatus == 0 else {
            return .resolutionProbeFailed(firstDiagnosticLine(stdout: resolutionResult.stdout, stderr: resolutionResult.stderr))
        }

        let outputLines = resolutionResult.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let executable = outputLines.first else {
            return .resolutionReturnedNoExecutable
        }
        let version = outputLines.dropFirst().first

        let readinessProbe: ProviderCommandResult
        do {
            readinessProbe = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteIBMBobPassiveProbeArguments(executable: executable, workspace: workspace, host: host),
                currentDirectoryURL: nil
            )
        } catch {
            return .passiveProbeSSHLaunchFailed(
                executable: executable,
                version: version,
                message: error.localizedDescription
            )
        }

        let detail = readinessProbe.exitStatus == 0
            ? nil
            : firstDiagnosticLine(stdout: readinessProbe.stdout, stderr: readinessProbe.stderr)
        return .passiveProbeCompleted(
            executable: executable,
            version: version,
            detail: detail
        )
    }

    func localCodexHealthProbe(workspace: Workspace) async -> LocalCodexHealthProbeResult {
        let resolution = resolvedLocalExecutable(named: "codex")
        guard let executable = resolution.resolvedExecutable else {
            return .executableNotFound(resolution)
        }

        var diagnostics: [ProviderHealthDiagnostic] = []
        let version = detectLocalVersion(executable: executable, providerName: "Codex", diagnostics: &diagnostics)

        do {
            try await codexReadinessProbe.probe(executable: executable, workingDirectory: workspace.folderPath)
        } catch {
            return .readinessProbeFailed(
                executable: executable,
                version: version,
                diagnostics: diagnostics,
                detail: error.localizedDescription
            )
        }

        return .ready(executable: executable, version: version, diagnostics: diagnostics)
    }

    func localIBMBobPassiveProbe(workspace: Workspace) async -> LocalIBMBobPassiveProbeResult {
        let resolution = resolvedLocalExecutable(named: "bob")
        guard let executable = resolution.resolvedExecutable else {
            return .executableNotFound(resolution)
        }

        var diagnostics: [ProviderHealthDiagnostic] = []
        let version = detectLocalVersion(executable: executable, providerName: "IBM Bob", diagnostics: &diagnostics)

        do {
            let launchProbe = try runLocalCommandThroughShell(
                executable: executable,
                arguments: ["--list-sessions"],
                currentDirectoryURL: URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
            )

            return .passiveProbeCompleted(
                executable: executable,
                version: version,
                diagnostics: diagnostics,
                detail: launchProbe.exitStatus == 0
                    ? nil
                    : launchProbeFailureMessage(stdout: launchProbe.stdout, stderr: launchProbe.stderr, providerName: "IBM Bob")
            )
        } catch {
            return .passiveProbeLaunchFailed(
                executable: executable,
                version: version,
                diagnostics: diagnostics,
                detail: error.localizedDescription
            )
        }
    }

    func localCLIHealthProbe(commandName: String, providerName: String, workspace: Workspace) async -> LocalCLIHealthProbeResult {
        let resolution = resolvedLocalExecutable(named: commandName)
        guard let executable = resolution.resolvedExecutable else {
            return .executableNotFound(resolution)
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
                return .launchProbeFailed(
                    executable: executable,
                    version: version,
                    diagnostics: diagnostics,
                    detail: launchProbeFailureMessage(
                        stdout: launchProbe.stdout,
                        stderr: launchProbe.stderr,
                        providerName: providerName
                    )
                )
            }
        } catch {
            return .launchProbeFailed(
                executable: executable,
                version: version,
                diagnostics: diagnostics,
                detail: error.localizedDescription
            )
        }

        return .ready(
            executable: executable,
            version: version,
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
            domain: "ProviderHealthFacts",
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

    private func remoteIBMBobExecutableResolutionArguments(workspace: Workspace, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteIBMBobExecutableResolutionScript(workspace: workspace)]
        return arguments
    }

    private func remoteIBMBobExecutableResolutionScript(workspace: Workspace) -> String {
        let commandPathVariable = "BOB_PATH"
        let resolveFunctionName = "resolve_bob_path"
        let notFoundMarker = remoteExecutableNotFoundMarker(commandName: "bob")
        let shellCommand = shellQuoted("command -v bob")
        let fallbackCandidates = [
            "$HOME/.local/bin/bob",
            "$HOME/bin/bob",
            "$HOME/.volta/bin/bob",
            "$HOME/.asdf/shims/bob",
            "$HOME/.local/share/mise/shims/bob",
            "$HOME/.nix-profile/bin/bob",
            "$HOME/.bun/bin/bob",
            "$HOME/.nvm/current/bin/bob",
            "/opt/homebrew/bin/bob",
            "/usr/local/bin/bob",
            "/usr/bin/bob",
            "/bin/bob"
        ].map { "\"\($0)\"" }.joined(separator: " ")
        let shellCandidates = ShellSupport.remoteShellCandidateListScript()

        return "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; \(resolveFunctionName)() { for shell in \(shellCandidates); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; case \"${shell##*/}\" in csh|tcsh) CANDIDATE=\"$(\"$shell\" -i -c \"if ( -f ~/.login ) source ~/.login; command -v bob\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"if ( -f ~/.login ) source ~/.login; command -v bob\" 2>/dev/null)\" || continue ;; fish) CANDIDATE=\"$(\"$shell\" -i -c \"command -v bob\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -l -c \"command -v bob\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"command -v bob\" 2>/dev/null)\" || continue ;; *) CANDIDATE=\"$(\"$shell\" -lic \(shellCommand) 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -lc \(shellCommand) 2>/dev/null)\" || continue ;; esac; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \(fallbackCandidates); do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; \(commandPathVariable)=\"$(\(resolveFunctionName))\" || { echo '\(notFoundMarker)' >&2; exit 1; }; [ -n \"$\(commandPathVariable)\" ] || { echo '\(notFoundMarker)' >&2; exit 1; }; printf '%s\\n' \"$\(commandPathVariable)\"; \"$\(commandPathVariable)\" --version"
    }

    private func remoteIBMBobPassiveProbeArguments(executable: String, workspace: Workspace, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteIBMBobPassiveProbeScript(executable: executable, workspace: workspace)]
        return arguments
    }

    private func remoteIBMBobPassiveProbeScript(executable: String, workspace: Workspace) -> String {
        "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec \(shellQuoted(executable)) '--list-sessions'"
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

    private func providerID(forRemoteCommandName commandName: String) -> ProviderID? {
        switch commandName {
        case "claude":
            .claude
        case "codex":
            .codex
        case "pi":
            .pi
        case "bob":
            .ibmBob
        default:
            nil
        }
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
    func probe(executable: String, workingDirectory: String) async throws {
        let transport = try ProcessCodexAppServerTransport(
            executable: executable,
            arguments: ["app-server"],
            workingDirectory: workingDirectory
        )

        let waiter = AsyncResultWaiter<Void>()
        let state = CodexReadinessProbeState()

        transport.setStdoutLineHandler { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                let resolvedError = NSError(domain: "CodexAppServerReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
                state.record(error: resolvedError)
                waiter.fail(resolvedError)
                return
            }

            if let id = object["id"] as? String, id == "nexus-codex-readiness-initialize" {
                waiter.succeed()
            }
        }
        transport.setTerminationHandler { termination in
            guard termination.status != 0, state.error == nil else {
                return
            }

            let detail = termination.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedError = NSError(
                domain: "CodexAppServerReadinessProbe",
                code: Int(termination.status),
                userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! : "Codex app-server exited before readiness completed."]
            )
            state.record(error: resolvedError)
            waiter.fail(resolvedError)
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

        do {
            try await waiter.wait(
                timeoutNanoseconds: 5_000_000_000,
                timeoutError: {
                    NSError(
                        domain: "CodexAppServerReadinessProbe",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Codex app-server did not answer the readiness probe in time."]
                    )
                }
            )
        } catch {
            throw state.error ?? error
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

struct SSHRemoteCodexAppServerReadinessProbe: RemoteCodexReadinessProbing, @unchecked Sendable {
    typealias TransportFactory = @Sendable (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any CodexAppServerTransporting

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

    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws -> RemoteCodexReadinessOutcome {
        let transport = try transportFactory(
            "/usr/bin/ssh",
            sshArguments(host: host, executable: executable, workingDirectory: workingDirectory),
            nil
        )

        let waiter = AsyncResultWaiter<Void>()
        let state = CodexReadinessProbeState()

        transport.setStdoutLineHandler { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                let resolvedError = NSError(domain: "SSHRemoteCodexAppServerReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
                state.record(error: resolvedError)
                waiter.fail(resolvedError)
                return
            }

            if let id = object["id"] as? String, id == "nexus-codex-readiness-initialize" {
                waiter.succeed()
            }
        }
        transport.setTerminationHandler { termination in
            guard termination.status != 0, state.error == nil else {
                return
            }

            let detail = termination.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedError = NSError(
                domain: "SSHRemoteCodexAppServerReadinessProbe",
                code: Int(termination.status),
                userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! : "Codex app-server exited before remote readiness completed."]
            )
            state.record(error: resolvedError)
            waiter.fail(resolvedError)
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

        do {
            try await waiter.wait(
                timeoutNanoseconds: 5_000_000_000,
                timeoutError: {
                    NSError(
                        domain: "SSHRemoteCodexAppServerReadinessProbe",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Codex app-server did not answer the remote readiness probe in time."]
                    )
                }
            )
        } catch {
            let message = (state.error ?? error).localizedDescription
            if message == "Codex app-server did not answer the remote readiness probe in time." {
                return .authenticationUncertain(message)
            }

            if let resolvedError = state.error {
                let resolvedMessage = resolvedError.localizedDescription
                if isExplicitAuthenticationFailure(resolvedMessage) {
                    return .authenticationRequired(resolvedMessage)
                }
                throw resolvedError
            }

            throw error
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

struct SSHRemotePiRPCReadinessProbe: RemotePiReadinessProbing, @unchecked Sendable {
    typealias TransportFactory = @Sendable (_ executable: String, _ arguments: [String], _ workingDirectory: String?) throws -> any PiRPCTransporting

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

    func probe(host: NexusDomain.Host, executable: String, workingDirectory: String) async throws -> RemotePiReadinessOutcome {
        let transport = try transportFactory(
            "/usr/bin/ssh",
            sshArguments(host: host, executable: executable, workingDirectory: workingDirectory),
            nil
        )

        let waiter = AsyncResultWaiter<Void>()
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
                waiter.succeed()
                return
            }

            let message = object["error"] as? String ?? "Pi RPC readiness probe failed."
            let resolvedError = NSError(domain: "SSHRemotePiRPCReadinessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            state.record(error: resolvedError)
            waiter.fail(resolvedError)
        }
        transport.setTerminationHandler { status in
            guard status != 0, state.error == nil else {
                return
            }

            let resolvedError = NSError(
                domain: "SSHRemotePiRPCReadinessProbe",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Pi RPC mode exited before remote readiness completed."]
            )
            state.record(error: resolvedError)
            waiter.fail(resolvedError)
        }

        try transport.start()
        try transport.sendLine(Self.jsonLine(["id": responseID, "type": "get_state"]))

        defer {
            try? transport.terminate()
        }

        do {
            try await waiter.wait(
                timeoutNanoseconds: 5_000_000_000,
                timeoutError: {
                    NSError(
                        domain: "SSHRemotePiRPCReadinessProbe",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Pi RPC mode did not answer the remote readiness probe in time."]
                    )
                }
            )
        } catch {
            let message = (state.error ?? error).localizedDescription
            if message == "Pi RPC mode did not answer the remote readiness probe in time." {
                return .authenticationUncertain(message)
            }

            if let resolvedError = state.error {
                let resolvedMessage = resolvedError.localizedDescription
                if isExplicitAuthenticationFailure(resolvedMessage) {
                    return .authenticationRequired(resolvedMessage)
                }
                throw resolvedError
            }

            throw error
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
    private let lock = NSLock()
    private var resolvedError: Error?

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedError
    }

    func record(error: Error) {
        lock.lock()
        if resolvedError == nil {
            resolvedError = error
        }
        lock.unlock()
    }
}

struct SystemProviderExecutableResolver: ProviderExecutableResolving, @unchecked Sendable {
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
