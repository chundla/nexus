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
        let launchCommand = shellExecCommand(executable: executable, arguments: providerArguments)
        let providerLaunchScript = "cd \(shellQuoted(workingDirectory)) || exit 1; cat \"$input_fifo\" | \(launchCommand) >> \"$output_log\" 2>&1"

        switch launchMode {
        case .launchNew:
            return [
                "runtime_root=\(runtimeRootAssignment(runtimeIdentifier: runtimeIdentifier))",
                "input_fifo=\"$runtime_root/stdin.fifo\"",
                "output_log=\"$runtime_root/stdout.log\"",
                "export runtime_root input_fifo output_log",
                "mkdir -p \"$runtime_root\"",
                "rm -f \"$input_fifo\" \"$output_log\"",
                "mkfifo \"$input_fifo\"",
                ": > \"$output_log\"",
                "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
                "tmux new-session -d -s \(shellQuoted(runtimeIdentifier)) \(shellQuoted(providerLaunchScript))",
                bridgeScript(runtimeIdentifier: runtimeIdentifier, inputFIFO: "$input_fifo", outputLog: "$output_log")
            ].joined(separator: "; ")
        case .attachExisting:
            return [
                "runtime_root=\(runtimeRootAssignment(runtimeIdentifier: runtimeIdentifier))",
                "input_fifo=\"$runtime_root/stdin.fifo\"",
                "output_log=\"$runtime_root/stdout.log\"",
                "export runtime_root input_fifo output_log",
                "tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || { echo 'NEXUS_REMOTE_RUNTIME_NOT_FOUND' >&2; exit 1; }",
                "[ -p \"$input_fifo\" ] || { echo 'NEXUS_REMOTE_BRIDGE_NOT_FOUND' >&2; exit 1; }",
                "[ -f \"$output_log\" ] || { echo 'NEXUS_REMOTE_BRIDGE_NOT_FOUND' >&2; exit 1; }",
                bridgeScript(runtimeIdentifier: runtimeIdentifier, inputFIFO: "$input_fifo", outputLog: "$output_log")
            ].joined(separator: "; ")
        }
    }

    private func bridgeScript(runtimeIdentifier: String, inputFIFO: String, outputLog: String) -> String {
        [
            "cat > \"\(inputFIFO)\" & input_pid=$!",
            "tail -n 0 -F \"\(outputLog)\" & tail_pid=$!",
            "cleanup() { kill \"$input_pid\" \"$tail_pid\" 2>/dev/null || true; wait \"$input_pid\" 2>/dev/null || true; wait \"$tail_pid\" 2>/dev/null || true; }",
            "trap 'cleanup' EXIT HUP INT TERM",
            "while tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null; do sleep 0.1; done",
            "cleanup",
            "last_line=$(grep -v '^[[:space:]]*$' \"\(outputLog)\" 2>/dev/null | tail -n 1)",
            "if [ -n \"$last_line\" ]; then printf '%s\\n' \"$last_line\" >&2; else echo 'NEXUS_REMOTE_RUNTIME_ENDED' >&2; fi",
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
        "\"$HOME/.nexus/remote-protocol/\(runtimeIdentifier)\""
    }

    private func shellExecCommand(executable: String, arguments: [String]) -> String {
        (["exec", shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
#endif
