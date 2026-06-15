#if os(macOS)
    import Foundation
    import NexusDomain

    struct HostValidationResult: Equatable {
        let state: HostValidationSnapshot.State
        let summary: String
        let diagnostics: [HostValidationDiagnostic]
    }

    protocol HostValidationEvaluating {
        func validate(host: NexusDomain.Host) -> HostValidationResult
    }

    struct HostValidationEvaluator: HostValidationEvaluating {
        let commandRunner: any ProviderCommandRunning

        init(commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner()) {
            self.commandRunner = commandRunner
        }

        func validate(host: NexusDomain.Host) -> HostValidationResult {
            var arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
            ]
            if let port = host.port {
                arguments += ["-p", String(port)]
            }
            arguments += [host.sshTarget, "command -v tmux >/dev/null 2>&1"]

            do {
                let result = try commandRunner.run(
                    executable: "/usr/bin/ssh", arguments: arguments, currentDirectoryURL: nil)
                if result.exitStatus == 0 {
                    return HostValidationResult(
                        state: .available,
                        summary: "Host is available",
                        diagnostics: [
                            HostValidationDiagnostic(
                                severity: .info, code: "sshTarget", message: "Validated \(host.sshTarget)")
                        ]
                    )
                }

                let detail = providerCommandFirstDiagnosticLine(stdout: result.stdout, stderr: result.stderr)
                if detail.isEmpty, result.exitStatus == 1 {
                    return HostValidationResult(
                        state: .broken,
                        summary: "Host is reachable but tmux is unavailable",
                        diagnostics: [
                            HostValidationDiagnostic(
                                severity: .error,
                                code: "tmuxUnavailable",
                                message: "The Host is reachable, but tmux is not available in the remote shell."
                            )
                        ]
                    )
                }

                let classification = classifyHostValidationFailure(detail: detail)
                return HostValidationResult(
                    state: classification.state,
                    summary: classification.summary,
                    diagnostics: [
                        HostValidationDiagnostic(
                            severity: .error, code: classification.code,
                            message: detail.isEmpty ? classification.summary : detail)
                    ]
                )
            } catch {
                return HostValidationResult(
                    state: .unavailable,
                    summary: "Host validation failed before the SSH check completed",
                    diagnostics: [
                        HostValidationDiagnostic(
                            severity: .error, code: "sshLaunchFailed", message: error.localizedDescription)
                    ]
                )
            }
        }

    }
#endif
