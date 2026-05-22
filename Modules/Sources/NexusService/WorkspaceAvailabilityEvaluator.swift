#if os(macOS)
import Foundation
import NexusDomain

struct WorkspaceAvailabilityResult: Equatable {
    let state: WorkspaceAvailabilitySnapshot.State
    let summary: String
    let diagnostics: [WorkspaceAvailabilityDiagnostic]
}

protocol WorkspaceAvailabilityEvaluating {
    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult
}

struct WorkspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluating {
    let commandRunner: any ProviderCommandRunning

    init(commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func evaluate(workspace: Workspace, host: NexusDomain.Host, hostValidation: HostValidationSnapshot?) -> WorkspaceAvailabilityResult {
        guard let hostValidation else {
            return WorkspaceAvailabilityResult(
                state: .blocked,
                summary: "Workspace Availability is blocked by Host Validation",
                diagnostics: [
                    WorkspaceAvailabilityDiagnostic(
                        severity: .warning,
                        code: "hostValidationBlocked",
                        message: "Workspace Availability is blocked until Host Validation runs for \(host.name)."
                    )
                ]
            )
        }

        guard hostValidation.state == .available else {
            return WorkspaceAvailabilityResult(
                state: .blocked,
                summary: "Workspace Availability is blocked by Host Validation",
                diagnostics: [
                    WorkspaceAvailabilityDiagnostic(
                        severity: .warning,
                        code: "hostValidationBlocked",
                        message: "Workspace Availability is blocked by Host Validation: \(hostValidation.summary)."
                    )
                ]
            )
        }

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, "cd \(shellQuoted(workspace.folderPath)) && pwd"]

        do {
            let result = try commandRunner.run(executable: "/usr/bin/ssh", arguments: arguments, currentDirectoryURL: nil)
            if result.exitStatus == 0 {
                return WorkspaceAvailabilityResult(
                    state: .available,
                    summary: "Workspace is available",
                    diagnostics: [
                        WorkspaceAvailabilityDiagnostic(
                            severity: .info,
                            code: "remotePath",
                            message: "Validated remote path \(workspace.folderPath) on \(host.name)."
                        )
                    ]
                )
            }

            let detail = firstDiagnosticLine(stdout: result.stdout, stderr: result.stderr)
            let classification = classifyFailure(detail: detail)
            return WorkspaceAvailabilityResult(
                state: classification.state,
                summary: classification.summary,
                diagnostics: [
                    WorkspaceAvailabilityDiagnostic(
                        severity: .error,
                        code: classification.code,
                        message: detail.isEmpty ? classification.summary : detail
                    )
                ]
            )
        } catch {
            return WorkspaceAvailabilityResult(
                state: .unavailable,
                summary: "Workspace availability check failed before the SSH check completed",
                diagnostics: [
                    WorkspaceAvailabilityDiagnostic(
                        severity: .error,
                        code: "sshLaunchFailed",
                        message: error.localizedDescription
                    )
                ]
            )
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

    private func classifyFailure(detail: String) -> (state: WorkspaceAvailabilitySnapshot.State, summary: String, code: String) {
        let normalized = detail.lowercased()

        if normalized.contains("no such file")
            || normalized.contains("not a directory")
            || normalized.contains("permission denied") {
            return (.broken, "Workspace requires repair", "workspaceTargetBroken")
        }

        if normalized.contains("connection timed out")
            || normalized.contains("operation timed out")
            || normalized.contains("connection refused")
            || normalized.contains("network is unreachable")
            || normalized.contains("no route to host") {
            return (.unavailable, "Workspace is currently unavailable", "workspaceUnavailable")
        }

        return (.broken, "Workspace availability check failed", "workspaceAvailabilityFailed")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
#endif
