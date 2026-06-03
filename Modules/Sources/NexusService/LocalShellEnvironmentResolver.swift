#if os(macOS)
import Foundation

protocol LocalShellEnvironmentResolving: Sendable {
    func resolvedEnvironment() -> [String: String]?
}

struct LocalShellEnvironmentResolver: LocalShellEnvironmentResolving {
    private let baseEnvironment: [String: String]
    private let commandRunner: any ProviderCommandRunning
    private let localShellCommandBuilder: LocalShellCommandBuilder

    init(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner(),
        localShellCommandBuilder: LocalShellCommandBuilder = LocalShellCommandBuilder()
    ) {
        self.baseEnvironment = baseEnvironment
        self.commandRunner = commandRunner
        self.localShellCommandBuilder = localShellCommandBuilder
    }

    func resolvedEnvironment() -> [String: String]? {
        guard let shellEnvironment = resolveViaLocalShell(), shellEnvironment.isEmpty == false else {
            return nil
        }

        return baseEnvironment.merging(shellEnvironment) { _, shellValue in
            shellValue
        }
    }

    private func resolveViaLocalShell() -> [String: String]? {
        for command in localShellCommandBuilder.candidateCommands(for: "/usr/bin/env -0") {
            do {
                let result = try commandRunner.run(
                    executable: command.executable,
                    arguments: command.arguments,
                    currentDirectoryURL: nil
                )
                guard result.exitStatus == 0 else {
                    continue
                }

                let environment = parseEnvironment(from: result.stdout)
                if environment.isEmpty == false {
                    return environment
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func parseEnvironment(from stdout: String) -> [String: String] {
        stdout
            .split(separator: "\0", omittingEmptySubsequences: true)
            .reduce(into: [String: String]()) { environment, entry in
                let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = parts.first, key.isEmpty == false else {
                    return
                }

                let value = parts.count == 2 ? String(parts[1]) : ""
                environment[String(key)] = value
            }
    }
}
#endif
