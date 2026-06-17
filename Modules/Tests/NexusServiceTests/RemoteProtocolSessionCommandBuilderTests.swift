#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    @Suite(.serialized)
    struct RemoteProtocolSessionCommandBuilderTests {
        @Test func codexRuntimeSurfacesRemoteBridgeStartupFailureInsteadOfTimingOut() throws {
            let fixture = try makeRemoteBridgeFixture(
                createWorkspace: true,
                codexScript: """
                    #!/bin/sh
                    echo 'remote startup exploded' >&2
                    exit 1
                    """
            )

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

        @Test func codexRuntimeSurfacesSilentProviderExitFromBootstrapLogInsteadOfFallback() throws {
            let fixture = try makeRemoteBridgeFixture(
                createWorkspace: true,
                codexScript: """
                    #!/bin/sh
                    exit 1
                    """
            )

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
                error.localizedDescription == "NEXUS_REMOTE_PROVIDER_EXITED_WITH_STATUS:1"
            }
        }

        @Test func codexRuntimeSurfacesMissingWorkingDirectoryBeforeTimeout() throws {
            let fixture = try makeRemoteBridgeFixture(
                createWorkspace: false,
                codexScript: """
                    #!/bin/sh
                    echo 'should not launch codex' >&2
                    exit 1
                    """
            )

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
                error.localizedDescription.contains(
                    "NEXUS_REMOTE_WORKING_DIRECTORY_NOT_FOUND: \(fixture.workspaceURL.path(percentEncoded: false))")
            }
        }
    }

    private struct RemoteBridgeFixture {
        let runnerURL: URL
        let workspaceURL: URL
    }

    private func makeRemoteBridgeFixture(createWorkspace: Bool, codexScript: String) throws -> RemoteBridgeFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        if createWorkspace {
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        }
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

        let fakeCodexURL = binURL.appendingPathComponent("codex", isDirectory: false)
        try writeExecutableScript(
            path: fakeCodexURL.path(percentEncoded: false),
            content: codexScript
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

        return RemoteBridgeFixture(runnerURL: runnerURL, workspaceURL: workspaceURL)
    }

    private func writeExecutableScript(path: String, content: String) throws {
        try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
#endif
