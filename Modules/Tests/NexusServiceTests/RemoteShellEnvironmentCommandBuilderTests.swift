#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct RemoteShellEnvironmentCommandBuilderTests {
    @Test func remoteProtocolBridgeLaunchesProviderThroughResolvedShellEnvironment() async throws {
        let fixture = try makeRemoteShellBridgeFixture(
            providerScript: "#!/bin/sh\nsleep 0.2\nhelper-tool\n",
            remoteCommand: { host, runtimeIdentifier, workingDirectory, executable in
                RemoteProtocolSessionCommandBuilder().bridgeArguments(
                    host: host,
                    runtimeIdentifier: runtimeIdentifier,
                    workingDirectory: workingDirectory,
                    executable: executable,
                    providerArguments: [],
                    launchMode: .launchNew
                )
            }
        )

        let transport = try ProcessPiRPCTransport(
            executable: fixture.runnerURL.path(percentEncoded: false),
            arguments: [],
            workingDirectory: nil
        )
        let recorder = StdoutTransportRecorder<Int32>()
        transport.setStdoutLineHandler(recorder.record(line:))
        transport.setTerminationHandler(recorder.record(status:))

        try transport.start()
        try await waitForTransportOutput(recorder)

        #expect(recorder.stdoutLines == ["from-remote-shell"])
        #expect(recorder.status == 1)
    }

    @Test func remoteIBMBobBridgeLaunchesProviderThroughResolvedShellEnvironment() async throws {
        let fixture = try makeRemoteShellBridgeFixture(
            providerScript: "#!/bin/sh\nsleep 0.2\nhelper-tool\n",
            remoteCommand: { host, runtimeIdentifier, workingDirectory, executable in
                RemoteIBMBobCommandBuilder().bridgeArguments(
                    host: host,
                    runtimeIdentifier: runtimeIdentifier,
                    workingDirectory: workingDirectory,
                    executable: executable,
                    providerArguments: []
                )
            }
        )

        let transport = try ProcessIBMBobTransport(
            executable: fixture.runnerURL.path(percentEncoded: false),
            arguments: [],
            workingDirectory: nil
        )
        let recorder = StdoutTransportRecorder<Int32>()
        transport.setStdoutLineHandler(recorder.record(line:))
        transport.setTerminationHandler(recorder.record(status:))

        try transport.start()
        try await waitForTransportOutput(recorder)

        #expect(recorder.stdoutLines == ["from-remote-shell"])
        #expect(recorder.status == 0)
    }
}

private struct RemoteShellBridgeFixture {
    let runnerURL: URL
}

private func makeRemoteShellBridgeFixture(
    providerScript: String,
    remoteCommand: (NexusDomain.Host, String, String, String) -> [String]
) throws -> RemoteShellBridgeFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusServiceTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
    let workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
    let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
    let shellBinURL = rootURL.appendingPathComponent("shell-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shellBinURL, withIntermediateDirectories: true)

    let fakeTmuxURL = binURL.appendingPathComponent("tmux", isDirectory: false)
    try writeRemoteShellFixtureScript(
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
            shell_command="$1"
            (
              /bin/sh -lc "$shell_command"
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

    let helperToolURL = shellBinURL.appendingPathComponent("helper-tool", isDirectory: false)
    try writeRemoteShellFixtureScript(
        path: helperToolURL.path(percentEncoded: false),
        content: "#!/bin/sh\necho 'from-remote-shell'\n"
    )

    let bootstrapShellURL = binURL.appendingPathComponent("bootstrap-shell", isDirectory: false)
    try writeRemoteShellFixtureScript(
        path: bootstrapShellURL.path(percentEncoded: false),
        content: """
        #!/bin/sh
        set -eu
        command=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -c|-lc|-ic|-lic)
              shift
              command="$1"
              break
              ;;
            -i|-l)
              shift
              ;;
            -*)
              if printf '%s' "$1" | grep -q 'c' && [ "$#" -ge 2 ]; then
                shift
                command="$1"
                break
              fi
              shift
              ;;
            *)
              break
              ;;
          esac
        done
        export PATH=\(shellQuoted(shellBinURL.path(percentEncoded: false))):$PATH
        exec /bin/sh -lc "$command"
        """
    )

    let providerURL = binURL.appendingPathComponent("provider", isDirectory: false)
    try writeRemoteShellFixtureScript(
        path: providerURL.path(percentEncoded: false),
        content: providerScript
    )

    let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
    let arguments = remoteCommand(
        host,
        "nexus-runtime-1",
        workspaceURL.path(percentEncoded: false),
        providerURL.path(percentEncoded: false)
    )
    let command = try #require(arguments.last)

    let runnerURL = rootURL.appendingPathComponent("run-remote-shell-bridge", isDirectory: false)
    try writeRemoteShellFixtureScript(
        path: runnerURL.path(percentEncoded: false),
        content: """
        #!/bin/sh
        set -eu
        trap 'kill 0 2>/dev/null || true' EXIT INT TERM
        export HOME=\(shellQuoted(homeURL.path(percentEncoded: false)))
        export PATH=\(shellQuoted(binURL.path(percentEncoded: false))):$PATH
        export SHELL=\(shellQuoted(bootstrapShellURL.path(percentEncoded: false)))
        exec /bin/sh -c \(shellQuoted(command))
        """
    )

    return RemoteShellBridgeFixture(runnerURL: runnerURL)
}

private func writeRemoteShellFixtureScript(path: String, content: String) throws {
    try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private final class StdoutTransportRecorder<Status>: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stdoutLines: [String] = []
    private(set) var status: Status?

    func record(line: String) {
        lock.lock()
        stdoutLines.append(line)
        lock.unlock()
    }

    func record(status: Status) {
        lock.lock()
        self.status = status
        lock.unlock()
    }

    func snapshot() -> (stdoutLines: [String], status: Status?) {
        lock.lock()
        defer { lock.unlock() }
        return (stdoutLines, status)
    }
}

private func waitForTransportOutput<Status>(
    _ recorder: StdoutTransportRecorder<Status>,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
    while ContinuousClock.now < deadline {
        let snapshot = recorder.snapshot()
        if snapshot.status != nil, snapshot.stdoutLines.isEmpty == false {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    throw NSError(domain: "RemoteShellEnvironmentCommandBuilderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for transport output."])
}
#endif
