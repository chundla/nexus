#if os(macOS)
    import Foundation

    struct LocalShellCommand: Equatable {
        let executable: String
        let arguments: [String]
    }

    struct LocalShellCommandBuilder: @unchecked Sendable {
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
            shellLaunchStrategies().map { $0.command(shellCommand) }
        }

        func launchCommand(for executable: String, arguments: [String] = []) -> LocalShellCommand {
            preferredLaunchShellStrategy().command(shellExecCommand(executable: executable, arguments: arguments))
        }

        private func shellExecCommand(executable: String, arguments: [String]) -> String {
            (["exec", shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
        }

        private func preferredLaunchShellStrategy() -> ShellLaunchStrategy {
            launchShellStrategies().first(where: { fileManager.isExecutableFile(atPath: $0.executable) })
                ?? ShellLaunchStrategy(
                    executable: "/bin/sh",
                    argumentsPrefix: ["-lc"],
                    commandWrapper: { $0 }
                )
        }

        private func shellLaunchStrategies() -> [ShellLaunchStrategy] {
            shellCandidates().flatMap(Self.strategies(for:))
        }

        private func launchShellStrategies() -> [ShellLaunchStrategy] {
            shellCandidates().flatMap(Self.launchStrategies(for:))
        }

        private func shellCandidates() -> [String] {
            ShellSupport.localShellCandidates(environment: environment, fileManager: fileManager)
        }

        private static func strategies(for shell: String) -> [ShellLaunchStrategy] {
            switch ShellSupport.shellFamily(for: shell) {
            case .cShell:
                return [
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-i", "-c"],
                        commandWrapper: Self.cShellWrappedCommand
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-c"],
                        commandWrapper: Self.cShellWrappedCommand
                    ),
                ]
            case .fish:
                return [
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-i", "-c"],
                        commandWrapper: { $0 }
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-l", "-c"],
                        commandWrapper: { $0 }
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-c"],
                        commandWrapper: { $0 }
                    ),
                ]
            case .posix:
                return [
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-lic"],
                        commandWrapper: { $0 }
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-lc"],
                        commandWrapper: { $0 }
                    ),
                ]
            }
        }

        private static func launchStrategies(for shell: String) -> [ShellLaunchStrategy] {
            switch ShellSupport.shellFamily(for: shell) {
            case .cShell:
                return [
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-c"],
                        commandWrapper: Self.cShellWrappedCommand
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-i", "-c"],
                        commandWrapper: Self.cShellWrappedCommand
                    ),
                ]
            case .fish:
                return [
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-l", "-c"],
                        commandWrapper: { $0 }
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-c"],
                        commandWrapper: { $0 }
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-i", "-c"],
                        commandWrapper: { $0 }
                    ),
                ]
            case .posix:
                return [
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-lc"],
                        commandWrapper: { $0 }
                    ),
                    ShellLaunchStrategy(
                        executable: shell,
                        argumentsPrefix: ["-lic"],
                        commandWrapper: { $0 }
                    ),
                ]
            }
        }

        private static func cShellWrappedCommand(_ command: String) -> String {
            "if ( -f ~/.login ) source ~/.login; \(command)"
        }

        private func shellQuoted(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
    }

    private struct ShellLaunchStrategy {
        let executable: String
        let argumentsPrefix: [String]
        let commandWrapper: (String) -> String

        func command(_ command: String) -> LocalShellCommand {
            LocalShellCommand(executable: executable, arguments: argumentsPrefix + [commandWrapper(command)])
        }
    }
#endif
