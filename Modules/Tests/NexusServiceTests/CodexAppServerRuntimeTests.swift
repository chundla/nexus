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

    @Test func resumesStructuredSessionFromExistingCodexThreadLinkage() throws {
        let transport = TestCodexAppServerTransport(threadID: "codex-thread-1")
        _ = try CodexAppServerRuntime(
            executable: "/tmp/fake-codex",
            workingDirectory: "/tmp/workspace",
            sessionLinkage: CodexSessionLinkage(threadID: "codex-thread-1"),
            terminationStatusMessageBuilder: { _ in "" },
            transportFactory: { _, _, _ in transport }
        )

        let resumeParameters = try #require(transport.sentMessages.last?["params"] as? [String: Any])

        #expect(transport.sentMessages.compactMap { $0["method"] as? String } == ["initialize", "initialized", "thread/resume"])
        #expect(resumeParameters["threadId"] as? String == "codex-thread-1")
        #expect(resumeParameters["cwd"] as? String == "/tmp/workspace")
    }

    @Test func surfacesPendingCommandApprovalRequestInSharedSessionStream() throws {
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

        transport.emitCommandApprovalRequest(
            requestID: "approval-1",
            itemID: "command-1",
            command: "deploy --prod",
            reason: "Codex needs approval to deploy to production."
        )
        let screen = runtime.sessionScreen(for: session)

        #expect(screen.activityItems.map(\.kind) == [.status, .approvalRequest])
        #expect(screen.activityItems.map(\.text) == [
            "Codex shared Session stream connected",
            "Approval Request: deploy --prod"
        ])
        #expect(screen.approvalRequests.count == 1)
        #expect(screen.approvalRequests.first?.title == "deploy --prod")
        #expect(screen.approvalRequests.first?.text == "Codex needs approval to deploy to production.")
        #expect(screen.approvalRequests.first?.state == .pending)
    }

    @Test func approvingPendingCommandApprovalRequestUpdatesSharedStateAndRepliesToCodex() throws {
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

        transport.emitCommandApprovalRequest(
            requestID: "approval-1",
            itemID: "command-1",
            command: "deploy --prod",
            reason: "Codex needs approval to deploy to production."
        )
        let approvalRequest = try #require(runtime.sessionScreen(for: session).approvalRequests.first)

        try runtime.respondToApprovalRequest(approvalRequest.id, decision: .approve)
        let screen = runtime.sessionScreen(for: session)

        #expect(screen.activityItems.suffix(2).map(\.text) == [
            "Approval Request: deploy --prod",
            "Approved: deploy --prod"
        ])
        #expect(screen.approvalRequests.first?.state == .approved)
        #expect(transport.sentMessages.last?["id"] as? String == "approval-1")
        #expect((transport.sentMessages.last?["result"] as? [String: String])?["decision"] == "accept")
    }

    @Test func denyingPendingFileChangeApprovalRequestUpdatesSharedStateAndRepliesToCodex() throws {
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

        transport.emitFileChangeApprovalRequest(
            requestID: "approval-2",
            itemID: "file-change-1",
            reason: "Codex wants to write outside the Workspace."
        )
        let approvalRequest = try #require(runtime.sessionScreen(for: session).approvalRequests.first)

        try runtime.respondToApprovalRequest(approvalRequest.id, decision: .deny)
        let screen = runtime.sessionScreen(for: session)

        #expect(screen.activityItems.suffix(2).map(\.text) == [
            "Approval Request: File changes need approval",
            "Denied: File changes need approval"
        ])
        #expect(screen.approvalRequests.first?.title == "File changes need approval")
        #expect(screen.approvalRequests.first?.text == "Codex wants to write outside the Workspace.")
        #expect(screen.approvalRequests.first?.state == .denied)
        #expect(transport.sentMessages.last?["id"] as? String == "approval-2")
        #expect((transport.sentMessages.last?["result"] as? [String: String])?["decision"] == "decline")
    }

    @Test func startupFailureSurfacesEarlyThreadStartTerminationInsteadOfTimingOut() {
        #expect {
            try CodexAppServerRuntime(
                executable: "/tmp/fake-codex",
                workingDirectory: "/tmp/workspace",
                terminationStatusMessageBuilder: { _ in "" },
                transportFactory: { _, _, _ in ExitDuringThreadStartCodexTransport() }
            )
        } throws: { error in
            error.localizedDescription == "Codex app-server exited with status 127 before startup completed."
        }
    }

    @Test func processCodexAppServerTransportLaunchesSiblingInterpreterForEnvShebangScripts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let interpreterURL = binURL.appendingPathComponent("fake-node-interpreter", isDirectory: false)
        try "#!/bin/sh\nIFS= read -r _line\nprintf '%s\\n' '{\"id\":\"nexus-codex-readiness-initialize\",\"result\":{\"userAgent\":\"nexus-test\"}}'\nsleep 1\n".write(to: interpreterURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: interpreterURL.path)

        let scriptURL = binURL.appendingPathComponent("fake-codex", isDirectory: false)
        try "#!/usr/bin/env fake-node-interpreter\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let transport = try ProcessCodexAppServerTransport(
            executable: scriptURL.path,
            arguments: ["app-server"],
            workingDirectory: rootURL.path(percentEncoded: false)
        )
        let startupSemaphore = DispatchSemaphore(value: 0)
        let response = LockedValue<String?>(nil)
        transport.setStdoutLineHandler { line in
            response.set(line)
            startupSemaphore.signal()
        }

        try transport.start()
        defer { try? transport.terminate() }
        try transport.sendLine("{\"jsonrpc\":\"2.0\",\"id\":\"nexus-codex-readiness-initialize\",\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"nexus\",\"version\":\"1\"}}}")

        #expect(startupSemaphore.wait(timeout: .now() + 2) == .success)
        #expect(response.get()?.contains("\"nexus-codex-readiness-initialize\"") == true)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class ExitDuringThreadStartCodexTransport: CodexAppServerTransporting, @unchecked Sendable {
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

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
            return
        }

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
            terminationHandler?(127)
        default:
            break
        }
    }

    func terminate() throws {}

    private func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
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
        case "thread/start", "thread/resume":
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

    func emitCommandApprovalRequest(requestID: String, itemID: String, command: String, reason: String) {
        stdoutLineHandler?(jsonLine([
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
                "cwd": "/tmp/workspace"
            ]
        ]))
    }

    func emitFileChangeApprovalRequest(requestID: String, itemID: String, reason: String) {
        stdoutLineHandler?(jsonLine([
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "item/fileChange/requestApproval",
            "params": [
                "threadId": threadID,
                "turnId": "turn-1",
                "itemId": itemID,
                "startedAtMs": 1,
                "reason": reason
            ]
        ]))
    }

    private func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
