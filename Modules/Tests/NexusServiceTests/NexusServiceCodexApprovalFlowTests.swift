#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    private func codexApprovalTestTransportJSONLine(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            preconditionFailure("invalid test JSON object")
        }
        return String(decoding: data, as: UTF8.self)
    }

    struct NexusServiceCodexApprovalFlowTests {
        @Test func localCodexApprovalDecisionFlowsThroughSharedServiceContract() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusServiceTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

            let transportHarness = CodexApprovalTransportHarness()
            let launcher = ProcessSessionRuntimeLauncher(
                codexTransportFactory: { _, _, _ in transportHarness.transport }
            )

            let service = try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthFacts(
                    executableResolver: CodexApprovalStubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                    commandRunner: CodexApprovalStubCommandRunner(results: [
                        .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-codex' '--version'"]): .success(
                            stdout: "1.2.3\n")
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                    codexReadinessProbe: CodexApprovalReadinessProbe()
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )

            let group = try service.createWorkspaceGroup(name: "Solo Group")
            let workspace = try service.createLocalWorkspace(
                name: "Local Workspace",
                folderPath: workspaceFolder.path(percentEncoded: false),
                primaryGroupID: group.id
            )
            let session = try await service.launchOrResumeDefaultSession(
                workspaceID: workspace.id, providerID: .codex)

            transportHarness.transport.emitCommandApprovalRequest(
                requestID: "approval-1",
                itemID: "command-1",
                command: "deploy --prod",
                reason: "Codex needs approval to deploy to production."
            )

            let pendingScreen = try service.getSessionScreen(sessionID: session.id)
            let approvalRequest = try #require(pendingScreen.approvalRequests.first)
            let approvedScreen = try await service.respondToApprovalRequest(
                sessionID: session.id,
                approvalRequestID: approvalRequest.id,
                decision: .approve
            )

            #expect(
                approvedScreen.activityItems.suffix(2).map(\.text) == [
                    "Approval Request: deploy --prod",
                    "Approved: deploy --prod",
                ])
            #expect(approvedScreen.approvalRequests.first?.state == .approved)
            #expect(transportHarness.transport.sentMessages.last?["id"] as? String == "approval-1")
            #expect(
                (transportHarness.transport.sentMessages.last?["result"] as? [String: String])?["decision"] == "accept")
        }
    }

    private struct CodexApprovalStubExecutableResolver: ProviderExecutableResolving {
        let executables: [String: String]

        func resolveExecutable(named command: String) -> ProviderExecutableResolution {
            ProviderExecutableResolution(
                resolvedExecutable: executables[command],
                searchedDirectories: ["/tmp/bin"],
                homeDirectories: ["/tmp/home"],
                pathEnvironment: "/tmp/bin"
            )
        }
    }

    private struct CodexApprovalStubCommandRunner: ProviderCommandRunning {
        struct Invocation: Hashable {
            let executable: String
            let arguments: [String]
        }

        enum StubbedResult {
            case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
        }

        let results: [Invocation: StubbedResult]

        func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
            guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
                throw NSError(
                    domain: "CodexApprovalStubCommandRunner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
            }

            switch result {
            case .success(let stdout, let stderr, let exitStatus):
                return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
            }
        }
    }

    private struct CodexApprovalReadinessProbe: CodexReadinessProbing {
        func probe(executable: String, workingDirectory: String) async throws {}
    }

    private final class CodexApprovalTransportHarness: @unchecked Sendable {
        let transport = ApprovalFlowTestCodexTransport(threadID: "codex-thread-1")
    }

    private final class ApprovalFlowTestCodexTransport: CodexAppServerTransporting, @unchecked Sendable {
        private let threadID: String
        private var stdoutLineHandler: (@Sendable (String) -> Void)?
        private var terminationHandler: (@Sendable (CodexAppServerTermination) -> Void)?
        private(set) var sentMessages: [[String: Any]] = []

        init(threadID: String) {
            self.threadID = threadID
        }

        func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
            stdoutLineHandler = handler
        }

        func setTerminationHandler(_ handler: (@Sendable (CodexAppServerTermination) -> Void)?) {
            terminationHandler = handler
        }

        func start() throws {}

        func sendLine(_ line: String) throws {
            guard let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                Issue.record("Invalid JSON line: \(line)")
                return
            }
            sentMessages.append(object)

            switch object["method"] as? String {
            case "initialize":
                stdoutLineHandler?(
                    codexApprovalTestTransportJSONLine([
                        "id": object["id"] ?? 0,
                        "result": [
                            "userAgent": "nexus-test",
                            "codexHome": "/tmp/codex-home",
                            "platformFamily": "unix",
                            "platformOs": "macos",
                        ],
                    ]))
            case "thread/start", "thread/resume":
                stdoutLineHandler?(
                    codexApprovalTestTransportJSONLine([
                        "id": object["id"] ?? 0,
                        "result": [
                            "thread": [
                                "id": threadID,
                                "sessionId": threadID,
                                "preview": "",
                                "ephemeral": false,
                                "modelProvider": "openai",
                                "createdAt": 0,
                                "updatedAt": 0,
                                "status": ["type": "idle"],
                                "path": "/tmp/codex-thread.jsonl",
                                "cwd": "/tmp/workspace",
                                "cliVersion": "0.132.0",
                                "source": "appServer",
                                "turns": [],
                            ],
                            "model": "gpt-5.5",
                            "modelProvider": "openai",
                            "cwd": "/tmp/workspace",
                            "approvalPolicy": "on-request",
                            "approvalsReviewer": "user",
                            "sandbox": ["type": "readOnly", "networkAccess": false],
                        ],
                    ]))
            case "model/list":
                stdoutLineHandler?(
                    codexApprovalTestTransportJSONLine([
                        "id": object["id"] ?? 0,
                        "result": [
                            "data": []
                        ],
                    ]))
            default:
                break
            }
        }

        func terminate() throws {
            terminationHandler?(CodexAppServerTermination(status: 0, stderr: nil))
        }

        func emitCommandApprovalRequest(requestID: String, itemID: String, command: String, reason: String) {
            stdoutLineHandler?(
                codexApprovalTestTransportJSONLine([
                    "jsonrpc": "2.0",
                    "id": requestID,
                    "method": "item/commandExecution/requestApproval",
                    "params": [
                        "threadId": threadID,
                        "turnId": "turn-1",
                        "itemId": itemID,
                        "startedAtMs": 1,
                        "reason": reason,
                        "command": command,
                        "cwd": "/tmp/workspace",
                    ],
                ]))
        }

    }
#endif
