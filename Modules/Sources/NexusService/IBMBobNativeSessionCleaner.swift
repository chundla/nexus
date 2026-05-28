#if os(macOS)
import Foundation
import NexusDomain

protocol IBMBobNativeSessionCleaning {
    func bestEffortDeleteStoredContinuity(
        for session: Session,
        workspace: Workspace,
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
        sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
    ) {
        guard session.providerID == .ibmBob,
              workspace.kind == .local,
              let nativeSessionID = trimmedNativeSessionID(from: sessionRecordAdapterMetadata) else {
            return
        }

        let resolution = executableResolver.resolveExecutable(named: "bob")
        guard let executable = resolution.resolvedExecutable else {
            log("Skipping IBM Bob native cleanup because the executable could not be resolved for Session Record \(session.id).")
            return
        }

        let workingDirectoryURL = URL(fileURLWithPath: workspace.folderPath, isDirectory: true)

        guard let deleteTarget = resolveDeleteTarget(
            executable: executable,
            workingDirectoryURL: workingDirectoryURL,
            nativeSessionID: nativeSessionID
        ) else {
            log("Skipping IBM Bob native cleanup because a safe delete target could not be resolved for Session Record \(session.id).")
            return
        }

        do {
            let result = try runLocalCommandThroughShell(
                executable: executable,
                arguments: ["--delete-session", deleteTarget],
                currentDirectoryURL: workingDirectoryURL
            )
            guard result.exitStatus == 0 else {
                log("IBM Bob native cleanup failed for Session Record \(session.id): \(failureMessage(stdout: result.stdout, stderr: result.stderr, fallback: "IBM Bob delete exited with status \(result.exitStatus)."))")
                return
            }
        } catch {
            log("IBM Bob native cleanup threw for Session Record \(session.id): \(error.localizedDescription)")
        }
    }

    private func trimmedNativeSessionID(from metadata: SessionRecordAdapterMetadata?) -> String? {
        let trimmed = metadata?.ibmBobSessionLinkage?.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveDeleteTarget(
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
            log("IBM Bob native cleanup could not list sessions: \(failureMessage(stdout: result.stdout, stderr: result.stderr, fallback: "IBM Bob list-sessions exited with status \(result.exitStatus)."))")
            return nil
        }

        let matches = parsedSessionEntries(from: result.stdout).filter { $0.nativeSessionID == nativeSessionID }
        guard matches.count == 1 else {
            return nil
        }

        return matches.first?.deleteTarget
    }

    private func parsedSessionEntries(from stdout: String) -> [BobNativeSessionEntry] {
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let array = object as? [Any] {
            return parsedSessionEntries(from: array)
        }

        if let dictionary = object as? [String: Any],
           let array = dictionary["sessions"] as? [Any] {
            return parsedSessionEntries(from: array)
        }

        return []
    }

    private func parsedSessionEntries(from array: [Any]) -> [BobNativeSessionEntry] {
        array.compactMap { item in
            guard let dictionary = item as? [String: Any],
                  let nativeSessionID = stringValue(in: dictionary, keys: ["session_id", "sessionId", "id", "conversation_id", "conversationId"]),
                  let deleteTarget = deleteTarget(in: dictionary) else {
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

        throw lastError ?? NSError(
            domain: "IBMBobNativeSessionCleaner",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "IBM Bob native cleanup failed before the command completed."]
        )
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
