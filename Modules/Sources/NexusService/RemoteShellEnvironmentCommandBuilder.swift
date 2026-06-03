#if os(macOS)
import Foundation

struct RemoteShellEnvironmentCommandBuilder {
    func commandInvokingPOSIXScriptThroughShellEnvironment(
        _ script: String,
        markerFilePath: String
    ) -> String {
        let shellCandidates = ShellSupport.remoteShellCandidateListScript()
        let providerCommand = "/bin/sh -lc \(shellQuoted(script))"
        let posixBootstrapCommand = "touch \(shellExpressionQuoted(markerFilePath)); exec \(providerCommand)"
        let cShellBootstrapCommand = "if ( -f ~/.login ) source ~/.login; \(posixBootstrapCommand)"

        return [
            "shell_env_marker=\(shellExpressionQuoted(markerFilePath))",
            "launch_with_shell_environment() {",
            "  for shell in \(shellCandidates); do",
            "    [ -n \"$shell\" ] || continue",
            "    [ -x \"$shell\" ] || continue",
            "    rm -f \"$shell_env_marker\"",
            "    case \"${shell##*/}\" in",
            "      csh|tcsh)",
            "        \"$shell\" -i -c \(shellQuoted(cShellBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        \"$shell\" -c \(shellQuoted(cShellBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        ;;",
            "      fish)",
            "        \"$shell\" -i -c \(shellQuoted(posixBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        \"$shell\" -l -c \(shellQuoted(posixBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        \"$shell\" -c \(shellQuoted(posixBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        ;;",
            "      *)",
            "        \"$shell\" -lic \(shellQuoted(posixBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        \"$shell\" -lc \(shellQuoted(posixBootstrapCommand))",
            "        status=$?",
            "        [ -e \"$shell_env_marker\" ] && exit \"$status\"",
            "        ;;",
            "    esac",
            "  done",
            "  exec \(providerCommand)",
            "}",
            "launch_with_shell_environment"
        ].joined(separator: "\n")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func shellExpressionQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }
}
#endif
