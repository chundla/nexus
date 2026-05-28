#if os(macOS)
import Foundation
import NexusDomain

struct RemoteProtocolSessionCommandBuilder {
    func bridgeArguments(
        host: NexusDomain.Host,
        runtimeIdentifier: String,
        workingDirectory: String,
        executable: String,
        providerArguments: [String],
        launchMode: RemoteRuntimeLaunchMode
    ) -> [String] {
        var arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteCommand(
            runtimeIdentifier: runtimeIdentifier,
            workingDirectory: workingDirectory,
            executable: executable,
            providerArguments: providerArguments,
            launchMode: launchMode
        )]
        return arguments
    }

    func stopArguments(runtimeIdentifier: String, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
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
        providerArguments: [String],
        launchMode: RemoteRuntimeLaunchMode
    ) -> String {
        let providerRuntimeRoot = runtimeRootExpression(runtimeIdentifier: runtimeIdentifier)
        let providerInputFIFO = "\(providerRuntimeRoot)/stdin.fifo"
        let providerOutputLog = "\(providerRuntimeRoot)/stdout.log"
        let providerBootstrapLog = "\(providerRuntimeRoot)/bootstrap.log"
        let launchCommand = shellCommand(executable: executable, arguments: providerArguments)
        let providerLaunchScript = [
            ": > \(shellExpressionQuoted(providerBootstrapLog))",
            "printf \"%s\\n\" \"NEXUS_REMOTE_BOOTSTRAP_STARTED\" >> \(shellExpressionQuoted(providerBootstrapLog))",
            "cd \(shellDoubleQuoted(workingDirectory)) || { printf \"%s\\n\" \(shellDoubleQuoted("NEXUS_REMOTE_WORKING_DIRECTORY_NOT_FOUND: \(workingDirectory)")) >> \(shellExpressionQuoted(providerBootstrapLog)); exit 1; }",
            "[ -p \(shellExpressionQuoted(providerInputFIFO)) ] || { printf \"%s\\n\" \"NEXUS_REMOTE_INPUT_FIFO_NOT_FOUND\" >> \(shellExpressionQuoted(providerBootstrapLog)); exit 1; }",
            "printf \"%s\\n\" \"NEXUS_REMOTE_PROVIDER_LAUNCHING\" >> \(shellExpressionQuoted(providerBootstrapLog))",
            "cat \(shellExpressionQuoted(providerInputFIFO)) | \(launchCommand) >> \(shellExpressionQuoted(providerOutputLog)) 2>&1",
            "status=$?",
            "if [ \"$status\" -ne 0 ]; then printf \"NEXUS_REMOTE_PROVIDER_EXITED_WITH_STATUS:%s\\n\" \"$status\" >> \(shellExpressionQuoted(providerBootstrapLog)); fi",
            "exit \"$status\""
        ].joined(separator: "; ")

        switch launchMode {
        case .launchNew:
            return [
                "runtime_root=\(runtimeRootAssignment(runtimeIdentifier: runtimeIdentifier))",
                "input_fifo=\"$runtime_root/stdin.fifo\"",
                "output_log=\"$runtime_root/stdout.log\"",
                "bootstrap_log=\"$runtime_root/bootstrap.log\"",
                "export runtime_root input_fifo output_log bootstrap_log",
                "mkdir -p \"$runtime_root\"",
                "rm -f \"$input_fifo\" \"$output_log\" \"$bootstrap_log\"",
                "mkfifo \"$input_fifo\"",
                ": > \"$output_log\"",
                "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
                "tmux new-session -d -s \(shellQuoted(runtimeIdentifier)) \(shellQuoted("/bin/sh -lc \(shellQuoted(providerLaunchScript))")) || { echo 'NEXUS_REMOTE_TMUX_LAUNCH_FAILED' >&2; exit 1; }",
                bridgeScript(runtimeIdentifier: runtimeIdentifier, inputFIFO: "$input_fifo", outputLog: "$output_log", bootstrapLog: "$bootstrap_log")
            ].joined(separator: "; ")
        case .attachExisting:
            return [
                "runtime_root=\(runtimeRootAssignment(runtimeIdentifier: runtimeIdentifier))",
                "input_fifo=\"$runtime_root/stdin.fifo\"",
                "output_log=\"$runtime_root/stdout.log\"",
                "bootstrap_log=\"$runtime_root/bootstrap.log\"",
                "export runtime_root input_fifo output_log bootstrap_log",
                "tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || { echo 'NEXUS_REMOTE_RUNTIME_NOT_FOUND' >&2; exit 1; }",
                "[ -p \"$input_fifo\" ] || { echo 'NEXUS_REMOTE_INPUT_FIFO_NOT_FOUND' >&2; exit 1; }",
                "[ -f \"$output_log\" ] || { echo 'NEXUS_REMOTE_OUTPUT_LOG_NOT_FOUND' >&2; exit 1; }",
                "[ -f \"$bootstrap_log\" ] || { echo 'NEXUS_REMOTE_BOOTSTRAP_LOG_NOT_FOUND' >&2; exit 1; }",
                bridgeScript(runtimeIdentifier: runtimeIdentifier, inputFIFO: "$input_fifo", outputLog: "$output_log", bootstrapLog: "$bootstrap_log")
            ].joined(separator: "; ")
        }
    }

    private func bridgeScript(runtimeIdentifier: String, inputFIFO: String, outputLog: String, bootstrapLog: String) -> String {
        [
            "cat > \"\(inputFIFO)\" & input_pid=$!",
            "tail -n 0 -F \"\(outputLog)\" & tail_pid=$!",
            "cleanup() { kill \"$input_pid\" \"$tail_pid\" 2>/dev/null || true; wait \"$input_pid\" 2>/dev/null || true; wait \"$tail_pid\" 2>/dev/null || true; }",
            "trap 'cleanup' EXIT HUP INT TERM",
            "while tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null; do sleep 0.1; done",
            "cleanup",
            "last_line=$(grep -v '^[[:space:]]*$' \"\(outputLog)\" 2>/dev/null | tail -n 1)",
            "if [ -z \"$last_line\" ]; then last_line=$(grep -v '^[[:space:]]*$' \"\(bootstrapLog)\" 2>/dev/null | tail -n 1); fi",
            "if [ -n \"$last_line\" ]; then printf '%s\\n' \"$last_line\" >&2; else echo 'Remote Codex runtime ended before producing startup output.' >&2; fi",
            "exit 1"
        ].joined(separator: "; ")
    }

    private func stopCommand(runtimeIdentifier: String) -> String {
        [
            "runtime_root=\(runtimeRootAssignment(runtimeIdentifier: runtimeIdentifier))",
            "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
            "rm -rf \"$runtime_root\""
        ].joined(separator: "; ")
    }

    private func runtimeRootAssignment(runtimeIdentifier: String) -> String {
        shellExpressionQuoted(runtimeRootExpression(runtimeIdentifier: runtimeIdentifier))
    }

    private func runtimeRootExpression(runtimeIdentifier: String) -> String {
        "$HOME/.nexus/remote-protocol/\(runtimeIdentifier)"
    }

    private func shellCommand(executable: String, arguments: [String]) -> String {
        ([shellDoubleQuoted(executable)] + arguments.map(shellDoubleQuoted)).joined(separator: " ")
    }

    private func shellDoubleQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }

    private func shellExpressionQuoted(_ value: String) -> String {
        let escaped = value
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
