#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct RemoteWorkspaceProbeCollectorTests {
    @Test func collectBuildsSingleSSHFactPassAndParsesRemoteProbeFacts() throws {
        let runner = RecordingRemoteWorkspaceProbeCommandRunner(
            result: ProviderCommandResult(
                exitStatus: 0,
                stdout: """
                protocol	v1
                tmuxAvailable	true
                workspacePath	available
                provider.claude.executable	/opt/tools/claude
                provider.claude.version	1.2.3
                provider.codex.executable	/opt/tools/codex
                provider.codex.version	0.9.0
                provider.pi.executable	/opt/tools/pi
                provider.pi.version	3.1.4
                provider.ibmBob.executable	/opt/tools/bob
                provider.ibmBob.version	2026.05
                """,
                stderr: ""
            )
        )
        let collector = RemoteWorkspaceProbeCollector(commandRunner: runner)
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let workspace = Workspace(
            id: UUID(),
            name: "Remote API",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: host.id
        )

        let facts = collector.collect(workspace: workspace, host: host)
        let invocation = try #require(runner.invocation)

        #expect(facts == .collected(
            RemoteWorkspaceProbeFacts(
                tmuxAvailable: true,
                workspacePath: .available,
                providerFacts: [
                    .claude: RemoteProviderProbeFacts(executable: "/opt/tools/claude", version: "1.2.3", resolutionDetail: nil, probeDetail: nil),
                    .codex: RemoteProviderProbeFacts(executable: "/opt/tools/codex", version: "0.9.0", resolutionDetail: nil, probeDetail: nil),
                    .pi: RemoteProviderProbeFacts(executable: "/opt/tools/pi", version: "3.1.4", resolutionDetail: nil, probeDetail: nil),
                    .ibmBob: RemoteProviderProbeFacts(executable: "/opt/tools/bob", version: "2026.05", resolutionDetail: nil, probeDetail: nil)
                ]
            )
        ))
        #expect(invocation.executable == "/usr/bin/ssh")
        #expect(invocation.arguments.contains("build-box"))
        #expect(invocation.arguments.contains("2222"))
        #expect(invocation.arguments.last?.contains("/bin/sh -lc") == true)
        #expect(invocation.arguments.last?.contains("collect_cli_provider claude claude") == true)
    }

    @Test func collectReturnsTransportFailureWhenSSHProbeFactsDoNotArrive() throws {
        let runner = RecordingRemoteWorkspaceProbeCommandRunner(
            result: ProviderCommandResult(
                exitStatus: 255,
                stdout: "",
                stderr: "Permission denied (publickey)."
            )
        )
        let collector = RemoteWorkspaceProbeCollector(commandRunner: runner)
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")
        let workspace = Workspace(
            id: UUID(),
            name: "Remote API",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: host.id
        )

        let facts = collector.collect(workspace: workspace, host: host)

        #expect(facts == .transportFailed("Permission denied (publickey)."))
        #expect(runner.invocation?.arguments.last?.contains("/bin/sh -lc") == true)
    }

    @Test func collectReturnsRawProbeFailureWhenSSHReturnsUnsupportedProbeEnvelope() throws {
        let runner = RecordingRemoteWorkspaceProbeCommandRunner(
            result: ProviderCommandResult(
                exitStatus: 0,
                stdout: """
                protocol	v2
                tmuxAvailable	true
                """,
                stderr: ""
            )
        )
        let collector = RemoteWorkspaceProbeCollector(commandRunner: runner)
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box")
        let workspace = Workspace(
            id: UUID(),
            name: "Remote API",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: UUID(),
            remoteHostID: host.id
        )

        let facts = collector.collect(workspace: workspace, host: host)

        #expect(facts == .rawProbeFailed("Unsupported remote probe protocol: v2"))
    }
}

private final class RecordingRemoteWorkspaceProbeCommandRunner: ProviderCommandRunning, @unchecked Sendable {
    let result: ProviderCommandResult
    private(set) var invocation: (executable: String, arguments: [String])?

    init(result: ProviderCommandResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        invocation = (executable, arguments)
        return result
    }
}
#endif
