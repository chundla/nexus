#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    struct RemoteSessionCommandBuilderTests {
        @Test func launchArgumentsWrapProviderLaunchInLoginShell() throws {
            let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
            let configuration = SessionRuntimeLaunchConfiguration(
                executable: "/usr/local/bin/codex",
                workingDirectory: "/srv/api",
                remoteHost: host,
                remoteRuntimeIdentifier: "nexus-runtime-1"
            )

            let arguments = RemoteSessionCommandBuilder().launchArguments(configuration: configuration)

            #expect(
                arguments.prefix(8) == [
                    "-tt",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-p", "2222",
                    "build-box",
                ])
            let remoteCommand = try #require(arguments.last)
            #expect(remoteCommand.contains("cd '/srv/api'"))
            #expect(remoteCommand.contains("NEXUS_REMOTE_SHELL=\"$(for shell in \"${SHELL:-}\""))
            #expect(remoteCommand.contains("case \"${NEXUS_REMOTE_SHELL##*/}\" in csh|tcsh)"))
            #expect(remoteCommand.contains("source ~/.login; exec"))
            #expect(remoteCommand.contains("/usr/local/bin/codex"))
            #expect(
                remoteCommand.contains("fish) exec tmux new-session -s 'nexus-runtime-1' \"$NEXUS_REMOTE_SHELL\" -i -c")
            )
            #expect(
                remoteCommand.contains("*) exec tmux new-session -s 'nexus-runtime-1' \"$NEXUS_REMOTE_SHELL\" -lic"))
        }
    }
#endif
