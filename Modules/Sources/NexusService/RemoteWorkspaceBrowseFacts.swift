#if os(macOS)
import Foundation
import NexusDomain

protocol RemoteWorkspaceBrowseFactCollecting: Sendable {
    func collect(workspace: Workspace, host: NexusDomain.Host) -> RemoteWorkspaceBrowseFactCollection
}

enum RemoteWorkspaceBrowseFactCollection: Equatable {
    case collected(RemoteWorkspaceBrowseFacts)
    case transportFailed(String)
}

enum RemoteWorkspacePathBrowseFact: Equatable {
    case notChecked
    case available
    case failed(String)
}

struct RemoteProviderBrowseFact: Equatable {
    let executable: String?
    let version: String?
    let resolutionDetail: String?
    let probeDetail: String?
}

struct RemoteWorkspaceBrowseFacts: Equatable {
    let tmuxAvailable: Bool
    let workspacePath: RemoteWorkspacePathBrowseFact
    let providerFacts: [ProviderID: RemoteProviderBrowseFact]
}

struct RemoteWorkspaceBrowseFactCollector: RemoteWorkspaceBrowseFactCollecting {
    let commandRunner: any ProviderCommandRunning

    init(commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func collect(workspace: Workspace, host: NexusDomain.Host) -> RemoteWorkspaceBrowseFactCollection {
        do {
            let result = try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: sshArguments(host: host, workspace: workspace),
                currentDirectoryURL: nil
            )

            if let facts = parse(stdout: result.stdout), result.exitStatus == 0 {
                return .collected(facts)
            }

            if let facts = parse(stdout: result.stdout), result.exitStatus != 0 {
                return .collected(facts)
            }

            return .transportFailed(providerCommandFirstDiagnosticLine(stdout: result.stdout, stderr: result.stderr))
        } catch {
            return .transportFailed(error.localizedDescription)
        }
    }

    private func parse(stdout: String) -> RemoteWorkspaceBrowseFacts? {
        var protocolVersion: String?
        var tmuxAvailable = false
        var workspacePath: RemoteWorkspacePathBrowseFact = .notChecked
        var workspacePathDetail: String?
        var providerFields: [ProviderID: [String: String]] = [:]

        for line in stdout.split(whereSeparator: \.isNewline).map(String.init) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0])
            let value = String(parts[1])

            if key == "protocol" {
                protocolVersion = value
                continue
            }

            if key == "tmuxAvailable" {
                tmuxAvailable = value == "true"
                continue
            }

            if key == "workspacePath" {
                switch value {
                case "available":
                    workspacePath = .available
                case "failed":
                    workspacePath = .failed("")
                default:
                    workspacePath = .notChecked
                }
                continue
            }

            if key == "workspacePathDetail" {
                workspacePathDetail = value
                continue
            }

            guard key.hasPrefix("provider.") else {
                continue
            }

            let components = key.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
            guard components.count == 3,
                  let providerID = ProviderID(rawValue: String(components[1])) else {
                continue
            }
            providerFields[providerID, default: [:]][String(components[2])] = value
        }

        guard protocolVersion == "v1" else {
            return nil
        }

        if case .failed = workspacePath {
            workspacePath = .failed(workspacePathDetail ?? "")
        }

        return RemoteWorkspaceBrowseFacts(
            tmuxAvailable: tmuxAvailable,
            workspacePath: workspacePath,
            providerFacts: providerFields.reduce(into: [:]) { partialResult, entry in
                let fields = entry.value
                partialResult[entry.key] = RemoteProviderBrowseFact(
                    executable: fields["executable"],
                    version: fields["version"],
                    resolutionDetail: fields["resolutionDetail"],
                    probeDetail: fields["probeDetail"]
                )
            }
        )
    }

    private func sshArguments(host: NexusDomain.Host, workspace: Workspace) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [host.sshTarget, remoteCommand(workspace: workspace)]
        return arguments
    }

    private func remoteCommand(workspace: Workspace) -> String {
        "/bin/sh -lc \(shellQuoted(script(workspace: workspace)))"
    }

    private func script(workspace: Workspace) -> String {
        """
        emit_fact() {
          printf '%s\t%s\n' "$1" "$2"
        }
        first_nonempty_line() {
          printf '%s\n' "$1" | awk '{ gsub(/\r/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if (length($0)) { print; exit } }'
        }
        resolve_command_path() {
          command_name="$1"
          shift
          for shell in \(ShellSupport.remoteShellCandidateListScript()); do
            [ -n "$shell" ] || continue
            [ -x "$shell" ] || continue
            case "${shell##*/}" in
              csh|tcsh)
                candidate="$("$shell" -i -c "if ( -f ~/.login ) source ~/.login; command -v $command_name" 2>/dev/null)" || candidate="$("$shell" -c "if ( -f ~/.login ) source ~/.login; command -v $command_name" 2>/dev/null)" || continue
                ;;
              fish)
                candidate="$("$shell" -i -c "command -v $command_name" 2>/dev/null)" || candidate="$("$shell" -l -c "command -v $command_name" 2>/dev/null)" || candidate="$("$shell" -c "command -v $command_name" 2>/dev/null)" || continue
                ;;
              *)
                candidate="$("$shell" -lic "command -v $command_name" 2>/dev/null)" || candidate="$("$shell" -lc "command -v $command_name" 2>/dev/null)" || continue
                ;;
            esac
            [ -x "$candidate" ] || continue
            printf '%s\n' "$candidate"
            return 0
          done
          for candidate in "$@"; do
            [ -x "$candidate" ] || continue
            printf '%s\n' "$candidate"
            return 0
          done
          return 1
        }
        collect_version() {
          output="$("$1" --version 2>/dev/null)"
          first_nonempty_line "$output"
        }
        collect_cli_provider() {
          provider_key="$1"
          command_name="$2"
          not_found_marker="$3"
          shift 3
          executable="$(resolve_command_path "$command_name" "$@")" || executable=""
          if [ -z "$executable" ]; then
            emit_fact "provider.$provider_key.resolutionDetail" "$not_found_marker"
            return 0
          fi
          emit_fact "provider.$provider_key.executable" "$executable"
          version="$(collect_version "$executable")"
          [ -n "$version" ] && emit_fact "provider.$provider_key.version" "$version"
          output="$("$executable" --help 2>&1)"
          status=$?
          if [ "$status" -ne 0 ]; then
            detail="$(first_nonempty_line "$output")"
            emit_fact "provider.$provider_key.probeDetail" "${detail:-$not_found_marker}"
          fi
        }
        collect_resolution_provider() {
          provider_key="$1"
          command_name="$2"
          not_found_marker="$3"
          shift 3
          executable="$(resolve_command_path "$command_name" "$@")" || executable=""
          if [ -z "$executable" ]; then
            emit_fact "provider.$provider_key.resolutionDetail" "$not_found_marker"
            return 0
          fi
          emit_fact "provider.$provider_key.executable" "$executable"
          version="$(collect_version "$executable")"
          [ -n "$version" ] && emit_fact "provider.$provider_key.version" "$version"
        }
        collect_bob_provider() {
          provider_key="$1"
          command_name="$2"
          not_found_marker="$3"
          shift 3
          executable="$(resolve_command_path "$command_name" "$@")" || executable=""
          if [ -z "$executable" ]; then
            emit_fact "provider.$provider_key.resolutionDetail" "$not_found_marker"
            return 0
          fi
          emit_fact "provider.$provider_key.executable" "$executable"
          version="$(collect_version "$executable")"
          [ -n "$version" ] && emit_fact "provider.$provider_key.version" "$version"
          output="$("$executable" --list-sessions 2>&1)"
          status=$?
          if [ "$status" -ne 0 ]; then
            detail="$(first_nonempty_line "$output")"
            emit_fact "provider.$provider_key.probeDetail" "$detail"
          fi
        }

        emit_fact protocol v1
        if command -v tmux >/dev/null 2>&1; then
          emit_fact tmuxAvailable true
        else
          emit_fact tmuxAvailable false
          exit 0
        fi

        workspace_check_output="$(cd \(shellQuoted(workspace.folderPath)) 2>&1 && pwd)"
        workspace_check_status=$?
        if [ "$workspace_check_status" -ne 0 ]; then
          emit_fact workspacePath failed
          emit_fact workspacePathDetail "$(first_nonempty_line "$workspace_check_output")"
          exit 0
        fi
        emit_fact workspacePath available
        cd \(shellQuoted(workspace.folderPath)) || exit 0

        collect_cli_provider claude claude NEXUS_REMOTE_CLAUDE_NOT_FOUND \(fallbackCandidates(for: "claude"))
        collect_resolution_provider codex codex NEXUS_REMOTE_CODEX_NOT_FOUND \(fallbackCandidates(for: "codex"))
        collect_resolution_provider pi pi NEXUS_REMOTE_PI_NOT_FOUND \(fallbackCandidates(for: "pi"))
        collect_bob_provider ibmBob bob NEXUS_REMOTE_BOB_NOT_FOUND \(fallbackCandidates(for: "bob"))
        """
    }

    private func fallbackCandidates(for commandName: String) -> String {
        [
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
        ]
        .map { "\"\($0)\"" }
        .joined(separator: " ")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

func providerCommandFirstDiagnosticLine(stdout: String, stderr: String) -> String {
    [stderr, stdout]
        .joined(separator: "\n")
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { $0.isEmpty == false }) ?? ""
}

func classifyHostValidationFailure(detail: String) -> (state: HostValidationSnapshot.State, summary: String, code: String) {
    let normalized = detail.lowercased()

    if normalized.contains("permission denied")
        || normalized.contains("could not resolve hostname")
        || normalized.contains("bad configuration option")
        || normalized.contains("no such host") {
        return (.broken, "Host requires configuration repair", "sshConfigurationFailed")
    }

    if normalized.contains("connection timed out")
        || normalized.contains("operation timed out")
        || normalized.contains("connection refused")
        || normalized.contains("network is unreachable")
        || normalized.contains("no route to host") {
        return (.unavailable, "Host is currently unavailable", "sshUnavailable")
    }

    return (.broken, "Host validation failed", "sshValidationFailed")
}

func classifyWorkspaceAvailabilityFailure(detail: String) -> (state: WorkspaceAvailabilitySnapshot.State, summary: String, code: String) {
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
#endif
