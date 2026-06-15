#if os(macOS)
    import Foundation
    import NexusDomain

    struct RemoteIBMBobCommandBuilder {
        func bridgeArguments(
            host: NexusDomain.Host,
            runtimeIdentifier: String,
            workingDirectory: String,
            executable: String,
            providerArguments: [String]
        ) -> [String] {
            var arguments = [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
            ]
            if let port = host.port {
                arguments += ["-p", String(port)]
            }
            arguments += [
                host.sshTarget,
                remoteCommand(
                    runtimeIdentifier: runtimeIdentifier,
                    workingDirectory: workingDirectory,
                    executable: executable,
                    providerArguments: providerArguments
                ),
            ]
            return arguments
        }

        func stopArguments(runtimeIdentifier: String, host: NexusDomain.Host) -> [String] {
            var arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
            ]
            if let port = host.port {
                arguments += ["-p", String(port)]
            }
            arguments += [host.sshTarget, stopCommand(runtimeIdentifier: runtimeIdentifier)]
            return arguments
        }

        private func remoteCommand(
            runtimeIdentifier: String,
            workingDirectory: String,
            executable: String,
            providerArguments: [String]
        ) -> String {
            let runtimeRoot = runtimeRootExpression(runtimeIdentifier: runtimeIdentifier)
            let outputLog = "\(runtimeRoot)/stdout.log"
            let statusFile = "\(runtimeRoot)/status"
            let bootstrapLog = "\(runtimeRoot)/bootstrap.log"
            let shellEnvironmentMarker = "\(runtimeRoot)/shell-environment.ready"
            let launchCommand = shellCommand(executable: executable, arguments: providerArguments)
            let providerLaunchScript = [
                ": > \(shellExpressionQuoted(bootstrapLog))",
                "cd \(shellDoubleQuoted(workingDirectory)) || { printf \"%s\\n\" \(shellDoubleQuoted("NEXUS_REMOTE_WORKING_DIRECTORY_NOT_FOUND: \(workingDirectory)")) >> \(shellExpressionQuoted(bootstrapLog)); printf \"1\" > \(shellExpressionQuoted(statusFile)); exit 1; }",
                "\(launchCommand) >> \(shellExpressionQuoted(outputLog)) 2>> \(shellExpressionQuoted(bootstrapLog))",
                "status=$?",
                "printf \"%s\" \"$status\" > \(shellExpressionQuoted(statusFile))",
                "exit \"$status\"",
            ].joined(separator: "; ")

            let launchViaResolvedShellCommand = RemoteShellEnvironmentCommandBuilder()
                .commandInvokingPOSIXScriptThroughShellEnvironment(
                    providerLaunchScript,
                    markerFilePath: shellEnvironmentMarker
                )

            return [
                "runtime_root=\(shellExpressionQuoted(runtimeRoot))",
                "output_log=\(shellExpressionQuoted(outputLog))",
                "status_file=\(shellExpressionQuoted(statusFile))",
                "bootstrap_log=\(shellExpressionQuoted(bootstrapLog))",
                "mkdir -p \"$runtime_root\"",
                "rm -f \"$output_log\" \"$status_file\" \"$bootstrap_log\" \"$runtime_root/shell-environment.ready\"",
                ": > \"$output_log\"",
                ": > \"$bootstrap_log\"",
                "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
                "tmux new-session -d -s \(shellQuoted(runtimeIdentifier)) \(shellQuoted("/bin/sh -lc \(shellQuoted(launchViaResolvedShellCommand))")) || { echo 'NEXUS_REMOTE_TMUX_LAUNCH_FAILED' >&2; exit 1; }",
                "tail -n +1 -F \"$output_log\" & tail_pid=$!",
                "cleanup() { kill \"$tail_pid\" 2>/dev/null || true; wait \"$tail_pid\" 2>/dev/null || true; }",
                "trap 'cleanup' EXIT HUP INT TERM",
                "while tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null; do sleep 0.1; done",
                "cleanup",
                "status=$(cat \"$status_file\" 2>/dev/null || printf '1')",
                "if [ \"$status\" -ne 0 ]; then last_line=$(grep -v '^[[:space:]]*$' \"$bootstrap_log\" 2>/dev/null | tail -n 1); [ -n \"$last_line\" ] || last_line=$(grep -v '^[[:space:]]*$' \"$output_log\" 2>/dev/null | tail -n 1); if [ -n \"$last_line\" ]; then printf '%s\\n' \"$last_line\" >&2; fi; fi",
                "rm -rf \"$runtime_root\"",
                "exit \"$status\"",
            ].joined(separator: "; ")
        }

        private func stopCommand(runtimeIdentifier: String) -> String {
            let runtimeRoot = runtimeRootExpression(runtimeIdentifier: runtimeIdentifier)
            return [
                "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
                "rm -rf \(shellExpressionQuoted(runtimeRoot))",
            ].joined(separator: "; ")
        }

        private func runtimeRootExpression(runtimeIdentifier: String) -> String {
            "$HOME/.nexus/remote-bob/\(runtimeIdentifier)"
        }

        private func shellCommand(executable: String, arguments: [String]) -> String {
            ([shellDoubleQuoted(executable)] + arguments.map(shellDoubleQuoted)).joined(separator: " ")
        }

        private func shellDoubleQuoted(_ value: String) -> String {
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            return "\"\(escaped)\""
        }

        private func shellExpressionQuoted(_ value: String) -> String {
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "`", with: "\\`")
            return "\"\(escaped)\""
        }

        private func shellQuoted(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
    }
#endif
