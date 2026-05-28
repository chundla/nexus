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
        let runtimeRoot = runtimeRootExpression(runtimeIdentifier: runtimeIdentifier)
        let inputFIFO = "\(runtimeRoot)/stdin.fifo"
        let outputLog = "\(runtimeRoot)/stdout.log"
        let launchCommand = shellExecCommand(executable: executable, arguments: providerArguments)
        let providerLaunchScript = "cd \(shellQuoted(workingDirectory)) || exit 1; while true; do cat \(shellQuoted(inputFIFO)); done | \(launchCommand) >> \(shellQuoted(outputLog)) 2>&1"

        switch launchMode {
        case .launchNew:
            return [
                "runtime_root=\(shellQuoted(runtimeRoot))",
                "input_fifo=\(shellQuoted(inputFIFO))",
                "output_log=\(shellQuoted(outputLog))",
                "mkdir -p \"$runtime_root\"",
                "rm -f \"$input_fifo\" \"$output_log\"",
                "mkfifo \"$input_fifo\"",
                ": > \"$output_log\"",
                "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
                "tmux new-session -d -s \(shellQuoted(runtimeIdentifier)) \(shellQuoted(providerLaunchScript))",
                bridgeScript(inputFIFO: "$input_fifo", outputLog: "$output_log")
            ].joined(separator: "; ")
        case .attachExisting:
            return [
                "runtime_root=\(shellQuoted(runtimeRoot))",
                "input_fifo=\(shellQuoted(inputFIFO))",
                "output_log=\(shellQuoted(outputLog))",
                "tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || { echo 'NEXUS_REMOTE_RUNTIME_NOT_FOUND' >&2; exit 1; }",
                "[ -p \"$input_fifo\" ] || { echo 'NEXUS_REMOTE_BRIDGE_NOT_FOUND' >&2; exit 1; }",
                "[ -f \"$output_log\" ] || { echo 'NEXUS_REMOTE_BRIDGE_NOT_FOUND' >&2; exit 1; }",
                bridgeScript(inputFIFO: "$input_fifo", outputLog: "$output_log")
            ].joined(separator: "; ")
        }
    }

    private func bridgeScript(inputFIFO: String, outputLog: String) -> String {
        "cat > \"\(inputFIFO)\" & tail -n 0 -F \"\(outputLog)\""
    }

    private func stopCommand(runtimeIdentifier: String) -> String {
        let runtimeRoot = runtimeRootExpression(runtimeIdentifier: runtimeIdentifier)
        return [
            "runtime_root=\(shellQuoted(runtimeRoot))",
            "tmux kill-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || true",
            "rm -rf \"$runtime_root\""
        ].joined(separator: "; ")
    }

    private func runtimeRootExpression(runtimeIdentifier: String) -> String {
        "$HOME/.nexus/remote-protocol/\(runtimeIdentifier)"
    }

    private func shellExecCommand(executable: String, arguments: [String]) -> String {
        (["exec", shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
#endif
