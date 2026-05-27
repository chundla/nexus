#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct CodexAppServerRuntimeTests {
    @Test func startsStructuredSessionAndCapturesCodexThreadLinkage() throws {
        let transport = TestCodexAppServerTransport(threadID: "codex-thread-1")
        let runtime = try CodexAppServerRuntime(
            executable: "/tmp/fake-codex",
            workingDirectory: "/tmp/workspace",
            terminationStatusMessageBuilder: { _ in "" },
            transportFactory: { _, _, _ in transport }
        )
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )

        let screen = runtime.sessionScreen(for: session)

        #expect(runtime.sessionRecordAdapterMetadata == SessionRecordAdapterMetadata(
            providerID: .codex,
            values: ["threadID": "codex-thread-1"]
        ))
        #expect(screen.primarySurface == SessionSurface.structuredActivityFeed)
        #expect(screen.transcript.isEmpty)
        #expect(screen.activityItems.map { $0.kind } == [SessionActivityItem.Kind.status])
        #expect(screen.activityItems.map { $0.text } == ["Codex shared Session stream connected"])
        #expect(transport.sentMessages.compactMap { $0["method"] as? String } == ["initialize", "initialized", "thread/start"])
    }
}

private final class TestCodexAppServerTransport: CodexAppServerTransporting, @unchecked Sendable {
    private let threadID: String
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?
    private(set) var sentMessages: [[String: Any]] = []

    init(threadID: String) {
        self.threadID = threadID
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Invalid JSON line: \(line)")
            return
        }
        sentMessages.append(object)

        switch object["method"] as? String {
        case "initialize":
            stdoutLineHandler?(jsonLine([
                "id": object["id"] ?? 0,
                "result": [
                    "userAgent": "nexus-test",
                    "codexHome": "/tmp/codex-home",
                    "platformFamily": "unix",
                    "platformOs": "macos"
                ]
            ]))
        case "thread/start":
            stdoutLineHandler?(jsonLine([
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
                        "turns": []
                    ],
                    "model": "gpt-5.5",
                    "modelProvider": "openai",
                    "cwd": "/tmp/workspace",
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user",
                    "sandbox": ["type": "readOnly", "networkAccess": false]
                ]
            ]))
        default:
            break
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    private func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
