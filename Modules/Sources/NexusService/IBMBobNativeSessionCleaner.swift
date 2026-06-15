#if os(macOS)
    import Foundation
    import NexusDomain

    protocol IBMBobNativeSessionCleaning {
        func bestEffortDeleteStoredContinuity(
            for session: Session,
            workspace: Workspace,
            host: NexusDomain.Host?,
            sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
        )
    }

    struct IBMBobNativeSessionCleaner: IBMBobNativeSessionCleaning {
        let executableResolver: any ProviderExecutableResolving
        let commandRunner: any ProviderCommandRunning
        let localShellCommandBuilder: LocalShellCommandBuilder

        init(
            executableResolver: any ProviderExecutableResolving = SystemProviderExecutableResolver(),
            commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner(),
            localShellCommandBuilder: LocalShellCommandBuilder = LocalShellCommandBuilder()
        ) {
            self.executableResolver = executableResolver
            self.commandRunner = commandRunner
            self.localShellCommandBuilder = localShellCommandBuilder
        }

        func bestEffortDeleteStoredContinuity(
            for session: Session,
            workspace: Workspace,
            host: NexusDomain.Host?,
            sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
        ) {
            guard session.providerID == .ibmBob,
                let nativeSessionID = trimmedNativeSessionID(from: sessionRecordAdapterMetadata)
            else {
                return
            }

            switch workspace.kind {
            case .local:
                bestEffortDeleteLocalStoredContinuity(
                    for: session,
                    workspace: workspace,
                    nativeSessionID: nativeSessionID
                )
            case .remote:
                guard let host else {
                    log(
                        "Skipping IBM Bob native cleanup because the Host could not be loaded for Session Record \(session.id)."
                    )
                    return
                }
                bestEffortDeleteRemoteStoredContinuity(
                    for: session,
                    workspace: workspace,
                    host: host,
                    nativeSessionID: nativeSessionID
                )
            }
        }

        private func bestEffortDeleteLocalStoredContinuity(
            for session: Session,
            workspace: Workspace,
            nativeSessionID: String
        ) {
            let resolution = executableResolver.resolveExecutable(named: "bob")
            guard let executable = resolution.resolvedExecutable else {
                log(
                    "Skipping IBM Bob native cleanup because the executable could not be resolved for Session Record \(session.id)."
                )
                return
            }

            let workingDirectoryURL = URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
            guard
                let deleteTarget = resolveLocalDeleteTarget(
                    executable: executable,
                    workingDirectoryURL: workingDirectoryURL,
                    nativeSessionID: nativeSessionID
                )
            else {
                log(
                    "Skipping IBM Bob native cleanup because a safe delete target could not be resolved for Session Record \(session.id)."
                )
                return
            }

            do {
                let result = try runLocalCommandThroughShell(
                    executable: executable,
                    arguments: ["--delete-session", deleteTarget],
                    currentDirectoryURL: workingDirectoryURL
                )
                guard result.exitStatus == 0 else {
                    let message = failureMessage(
                        stdout: result.stdout,
                        stderr: result.stderr,
                        fallback: exitStatusMessage(command: "IBM Bob delete", status: result.exitStatus)
                    )
                    log("IBM Bob native cleanup failed for Session Record \(session.id): \(message)")
                    return
                }
            } catch {
                log("IBM Bob native cleanup threw for Session Record \(session.id): \(error.localizedDescription)")
            }
        }

        private func bestEffortDeleteRemoteStoredContinuity(
            for session: Session,
            workspace: Workspace,
            host: NexusDomain.Host,
            nativeSessionID: String
        ) {
            guard let executable = resolvedRemoteExecutable(workspace: workspace, host: host) else {
                log(
                    "Skipping IBM Bob native cleanup because the remote executable could not be resolved for Session Record \(session.id)."
                )
                return
            }

            guard
                let deleteTarget = resolveRemoteDeleteTarget(
                    executable: executable,
                    workspace: workspace,
                    host: host,
                    nativeSessionID: nativeSessionID
                )
            else {
                log(
                    "Skipping IBM Bob native cleanup because a safe remote delete target could not be resolved for Session Record \(session.id)."
                )
                return
            }

            do {
                let result = try runRemoteCommand(
                    host: host,
                    script: remoteIBMBobCommandScript(
                        executable: executable,
                        workspace: workspace,
                        arguments: ["--delete-session", deleteTarget]
                    )
                )
                guard result.exitStatus == 0 else {
                    let message = failureMessage(
                        stdout: result.stdout,
                        stderr: result.stderr,
                        fallback: exitStatusMessage(command: "IBM Bob delete", status: result.exitStatus)
                    )
                    log("IBM Bob native cleanup failed for Session Record \(session.id): \(message)")
                    return
                }
            } catch {
                log("IBM Bob native cleanup threw for Session Record \(session.id): \(error.localizedDescription)")
            }
        }

        private func trimmedNativeSessionID(from metadata: SessionRecordAdapterMetadata?) -> String? {
            let trimmed =
                metadata?.ibmBobSessionLinkage?.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        private func resolveLocalDeleteTarget(
            executable: String,
            workingDirectoryURL: URL,
            nativeSessionID: String
        ) -> String? {
            let result: ProviderCommandResult
            do {
                result = try runLocalCommandThroughShell(
                    executable: executable,
                    arguments: ["--list-sessions"],
                    currentDirectoryURL: workingDirectoryURL
                )
            } catch {
                log("IBM Bob native cleanup could not list sessions: \(error.localizedDescription)")
                return nil
            }

            guard result.exitStatus == 0 else {
                let message = failureMessage(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    fallback: exitStatusMessage(command: "IBM Bob list-sessions", status: result.exitStatus)
                )
                log("IBM Bob native cleanup could not list sessions: \(message)")
                return nil
            }

            return resolvedDeleteTarget(from: result.stdout, nativeSessionID: nativeSessionID)
        }

        private func resolvedRemoteExecutable(workspace: Workspace, host: NexusDomain.Host) -> String? {
            let result: ProviderCommandResult
            do {
                result = try runRemoteCommand(
                    host: host,
                    script: remoteIBMBobExecutableResolutionScript(workspace: workspace)
                )
            } catch {
                log("IBM Bob native cleanup could not resolve the remote executable: \(error.localizedDescription)")
                return nil
            }

            guard result.exitStatus == 0 else {
                let message = failureMessage(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    fallback: exitStatusMessage(command: "IBM Bob executable resolution", status: result.exitStatus)
                )
                log("IBM Bob native cleanup could not resolve the remote executable: \(message)")
                return nil
            }

            return result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.isEmpty == false })
        }

        private func resolveRemoteDeleteTarget(
            executable: String,
            workspace: Workspace,
            host: NexusDomain.Host,
            nativeSessionID: String
        ) -> String? {
            let result: ProviderCommandResult
            do {
                result = try runRemoteCommand(
                    host: host,
                    script: remoteIBMBobCommandScript(
                        executable: executable,
                        workspace: workspace,
                        arguments: ["--list-sessions"]
                    )
                )
            } catch {
                log("IBM Bob native cleanup could not list remote sessions: \(error.localizedDescription)")
                return nil
            }

            guard result.exitStatus == 0 else {
                let message = failureMessage(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    fallback: exitStatusMessage(command: "IBM Bob list-sessions", status: result.exitStatus)
                )
                log("IBM Bob native cleanup could not list remote sessions: \(message)")
                return nil
            }

            return resolvedDeleteTarget(from: result.stdout, nativeSessionID: nativeSessionID)
        }

        private func resolvedDeleteTarget(from stdout: String, nativeSessionID: String) -> String? {
            let matches = parsedSessionEntries(from: stdout).filter { $0.nativeSessionID == nativeSessionID }
            guard matches.count == 1 else {
                return nil
            }

            return matches.first?.deleteTarget
        }

        private func parsedSessionEntries(from stdout: String) -> [BobNativeSessionEntry] {
            guard let data = stdout.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data)
            else {
                return []
            }

            if let array = object as? [Any] {
                return parsedSessionEntries(from: array)
            }

            if let dictionary = object as? [String: Any],
                let array = dictionary["sessions"] as? [Any]
            {
                return parsedSessionEntries(from: array)
            }

            return []
        }

        private func parsedSessionEntries(from array: [Any]) -> [BobNativeSessionEntry] {
            array.compactMap { item in
                guard let dictionary = item as? [String: Any],
                    let nativeSessionID = stringValue(
                        in: dictionary, keys: ["session_id", "sessionId", "id", "conversation_id", "conversationId"]),
                    let deleteTarget = deleteTarget(in: dictionary)
                else {
                    return nil
                }

                return BobNativeSessionEntry(nativeSessionID: nativeSessionID, deleteTarget: deleteTarget)
            }
        }

        private func deleteTarget(in dictionary: [String: Any]) -> String? {
            for key in ["index", "session_index", "sessionIndex", "delete_index", "deleteIndex"] {
                if let number = dictionary[key] as? NSNumber {
                    return number.stringValue
                }
                if let string = dictionary[key] as? String {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty == false {
                        return trimmed
                    }
                }
            }

            return nil
        }

        private func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let value = dictionary[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty == false {
                        return trimmed
                    }
                }
            }

            return nil
        }

        private func runLocalCommandThroughShell(
            executable: String,
            arguments: [String],
            currentDirectoryURL: URL?
        ) throws -> ProviderCommandResult {
            var lastResult: ProviderCommandResult?
            var lastError: Error?

            for command in localShellCommandBuilder.candidateCommands(
                for: ([shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
            ) {
                do {
                    let result = try commandRunner.run(
                        executable: command.executable,
                        arguments: command.arguments,
                        currentDirectoryURL: currentDirectoryURL
                    )
                    if result.exitStatus == 0 {
                        return result
                    }
                    lastResult = result
                } catch {
                    lastError = error
                }
            }

            if let lastResult {
                return lastResult
            }

            throw lastError
                ?? NSError(
                    domain: "IBMBobNativeSessionCleaner",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "IBM Bob native cleanup failed before the command completed."]
                )
        }

        private func runRemoteCommand(host: NexusDomain.Host, script: String) throws -> ProviderCommandResult {
            try commandRunner.run(
                executable: "/usr/bin/ssh",
                arguments: remoteSSHArguments(host: host, script: script),
                currentDirectoryURL: nil
            )
        }

        private func remoteSSHArguments(host: NexusDomain.Host, script: String) -> [String] {
            var arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
            ]
            if let port = host.port {
                arguments += ["-p", String(port)]
            }
            arguments += [host.sshTarget, script]
            return arguments
        }

        private func remoteIBMBobExecutableResolutionScript(workspace: Workspace) -> String {
            let commandPathVariable = "BOB_PATH"
            let resolveFunctionName = "resolve_bob_path"
            let notFoundMarker = remoteExecutableNotFoundMarker(commandName: "bob")
            let shellCommand = shellQuoted("command -v bob")
            let fallbackCandidates = [
                "$HOME/.local/bin/bob",
                "$HOME/bin/bob",
                "$HOME/.volta/bin/bob",
                "$HOME/.asdf/shims/bob",
                "$HOME/.local/share/mise/shims/bob",
                "$HOME/.nix-profile/bin/bob",
                "$HOME/.bun/bin/bob",
                "$HOME/.nvm/current/bin/bob",
                "/opt/homebrew/bin/bob",
                "/usr/local/bin/bob",
                "/usr/bin/bob",
                "/bin/bob",
            ].map { "\"\($0)\"" }.joined(separator: " ")
            let shellCandidates = ShellSupport.remoteShellCandidateListScript()

            return
                "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; \(resolveFunctionName)() { for shell in \(shellCandidates); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; case \"${shell##*/}\" in csh|tcsh) CANDIDATE=\"$(\"$shell\" -i -c \"if ( -f ~/.login ) source ~/.login; command -v bob\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"if ( -f ~/.login ) source ~/.login; command -v bob\" 2>/dev/null)\" || continue ;; fish) CANDIDATE=\"$(\"$shell\" -i -c \"command -v bob\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -l -c \"command -v bob\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"command -v bob\" 2>/dev/null)\" || continue ;; *) CANDIDATE=\"$(\"$shell\" -lic \(shellCommand) 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -lc \(shellCommand) 2>/dev/null)\" || continue ;; esac; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \(fallbackCandidates); do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; \(commandPathVariable)=\"$(\(resolveFunctionName))\" || { echo '\(notFoundMarker)' >&2; exit 1; }; [ -n \"$\(commandPathVariable)\" ] || { echo '\(notFoundMarker)' >&2; exit 1; }; printf '%s\\n' \"$\(commandPathVariable)\"; \"$\(commandPathVariable)\" --version"
        }

        private func remoteIBMBobCommandScript(executable: String, workspace: Workspace, arguments: [String]) -> String
        {
            let command = ([shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
            return
                "cd \(shellQuoted(workspace.folderPath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; exec \(command)"
        }

        private func remoteExecutableNotFoundMarker(commandName: String) -> String {
            "NEXUS_REMOTE_\(commandName.uppercased())_NOT_FOUND"
        }

        private func exitStatusMessage(command: String, status: Int32) -> String {
            "\(command) exited with status \(status)."
        }

        private func failureMessage(stdout: String, stderr: String, fallback: String) -> String {
            let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStderr.isEmpty == false {
                return trimmedStderr
            }

            let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty == false {
                return trimmedStdout
            }

            return fallback
        }

        private func shellQuoted(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }

        private func log(_ message: String) {
            NSLog("%@", message)
        }
    }

    private struct BobNativeSessionEntry {
        let nativeSessionID: String
        let deleteTarget: String
    }
#endif
