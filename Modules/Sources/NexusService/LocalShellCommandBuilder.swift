#if os(macOS)
import Foundation

struct LocalShellCommand: Equatable {
    let executable: String
    let arguments: [String]
}

struct LocalShellCommandBuilder {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func candidateCommands(for shellCommand: String) -> [LocalShellCommand] {
        shellCandidates().flatMap { shell in
            shellProbeArguments().map { probeArgument in
                LocalShellCommand(executable: shell, arguments: [probeArgument, shellCommand])
            }
        }
    }

    func launchCommand(for executable: String, arguments: [String] = []) -> LocalShellCommand {
        let command = ([shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
        return LocalShellCommand(
            executable: preferredShell(),
            arguments: ["-lic", "exec \(command)"]
        )
    }

    private func preferredShell() -> String {
        shellCandidates().first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? "/bin/sh"
    }

    private func shellCandidates() -> [String] {
        var shells: [String] = []
        var seen: Set<String> = []

        for candidate in [
            environment["SHELL"],
            "/bin/zsh",
            "/usr/bin/zsh",
            "/bin/bash",
            "/usr/bin/bash",
            "/bin/sh"
        ] {
            guard let candidate, candidate.isEmpty == false, seen.insert(candidate).inserted else {
                continue
            }
            shells.append(candidate)
        }

        return shells
    }

    private func shellProbeArguments() -> [String] {
        ["-lic", "-lc"]
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
#endif
