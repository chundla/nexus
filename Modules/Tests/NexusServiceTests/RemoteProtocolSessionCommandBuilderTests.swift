#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct RemoteProtocolSessionCommandBuilderTests {
    @Test func launchBridgeExitsAndSurfacesStartupFailureWhenProviderDiesBeforeInitialization() throws {
        let fixture = try makeFailingRemoteBridgeFixture()
        let result = try runProcess(executable: fixture.runnerURL.path(percentEncoded: false), timeout: 2)

        #expect(result.timedOut == false)
        #expect(result.exitStatus == 1)
        #expect(result.stderr.contains("remote startup exploded"))
    }

    @Test func codexRuntimeSurfacesRemoteBridgeStartupFailureInsteadOfTimingOut() throws {
        let fixture = try makeFailingRemoteBridgeFixture()

        #expect {
            try CodexAppServerRuntime(
                executable: "/usr/bin/ssh",
                workingDirectory: fixture.workspaceURL.path(percentEncoded: false),
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in
                    try ProcessCodexAppServerTransport(
                        executable: fixture.runnerURL.path(percentEncoded: false),
                        arguments: [],
                        workingDirectory: nil
                    )
                }
            )
        } throws: { error in
            error.localizedDescription == "remote startup exploded"
        }
    }
}

private struct FailingRemoteBridgeFixture {
    let runnerURL: URL
    let workspaceURL: URL
}

private func makeFailingRemoteBridgeFixture() throws -> FailingRemoteBridgeFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusServiceTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
    let workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
    let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

    let fakeTmuxURL = binURL.appendingPathComponent("tmux", isDirectory: false)
    try writeExecutableScript(
        path: fakeTmuxURL.path(percentEncoded: false),
        content: """
        #!/bin/sh
        set -eu
        state_dir="$HOME/.fake-tmux"
        mkdir -p "$state_dir"

        command="$1"
        shift

        case "$command" in
          new-session)
            session=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                -d)
                  shift
                  ;;
                -s)
                  session="$2"
                  shift 2
                  ;;
                *)
                  break
                  ;;
              esac
            done
            run_command="$1"
            (
              /bin/sh -c "$run_command"
              rm -f "$state_dir/$session.pid"
            ) &
            printf '%s\n' "$!" > "$state_dir/$session.pid"
            ;;
          has-session)
            [ "$1" = "-t" ]
            session="$2"
            pid_file="$state_dir/$session.pid"
            if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
              exit 0
            fi
            rm -f "$pid_file"
            exit 1
            ;;
          kill-session)
            [ "$1" = "-t" ]
            session="$2"
            pid_file="$state_dir/$session.pid"
            if [ -f "$pid_file" ]; then
              kill "$(cat "$pid_file")" 2>/dev/null || true
              rm -f "$pid_file"
            fi
            ;;
          *)
            echo "unsupported fake tmux command: $command" >&2
            exit 1
            ;;
        esac
        """
    )

    let fakeCodexURL = binURL.appendingPathComponent("codex", isDirectory: false)
    try writeExecutableScript(
        path: fakeCodexURL.path(percentEncoded: false),
        content: """
        #!/bin/sh
        echo 'remote startup exploded' >&2
        exit 1
        """
    )

    let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
    let arguments = RemoteProtocolSessionCommandBuilder().bridgeArguments(
        host: host,
        runtimeIdentifier: "nexus-runtime-1",
        workingDirectory: workspaceURL.path(percentEncoded: false),
        executable: fakeCodexURL.path(percentEncoded: false),
        providerArguments: ["app-server"],
        launchMode: .launchNew
    )
    let remoteCommand = try #require(arguments.last)

    let runnerURL = rootURL.appendingPathComponent("run-remote-bridge", isDirectory: false)
    try writeExecutableScript(
        path: runnerURL.path(percentEncoded: false),
        content: """
        #!/bin/sh
        set -eu
        trap 'kill 0 2>/dev/null || true' EXIT INT TERM
        export HOME=\(shellQuoted(homeURL.path(percentEncoded: false)))
        export PATH=\(shellQuoted(binURL.path(percentEncoded: false))):$PATH
        exec /bin/sh -c \(shellQuoted(remoteCommand))
        """
    )

    return FailingRemoteBridgeFixture(runnerURL: runnerURL, workspaceURL: workspaceURL)
}

private struct ProcessRunResult {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

private func runProcess(executable: String, timeout: TimeInterval) throws -> ProcessRunResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let semaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in semaphore.signal() }

    try process.run()

    let completed = semaphore.wait(timeout: .now() + timeout) == .success
    if completed == false {
        process.terminate()
        _ = semaphore.wait(timeout: .now() + 1)
    }

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return ProcessRunResult(
        exitStatus: process.terminationStatus,
        stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        timedOut: completed == false
    )
}

private func writeExecutableScript(path: String, content: String) throws {
    try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
#endif
