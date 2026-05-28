#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct IBMBobSessionRuntimeTests {
    @Test func launchesBobOnDemandWithStructuredFlagsAndReturnsToReadyAfterCompletion() throws {
        let launchRecorder = IBMBobLaunchRecorder()
        let runtime = try IBMBobSessionRuntime(
            executable: "/tmp/fake-bob",
            workingDirectory: "/tmp/workspace",
            terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
            transportFactory: { executable, arguments, workingDirectory in
                launchRecorder.record(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                return SynchronousIBMBobTransport(
                    stdoutLines: [
                        #"{"type":"status","text":"Bob turn started"}"#,
                        #"{"type":"message","text":"Hello from Bob"}"#,
                        #"{"type":"command","command":"npm test"}"#,
                        #"{"type":"diff","text":"diff --git a/file b/file"}"#,
                        #"{"type":"completion","text":"Bob turn complete"}"#
                    ],
                    terminationStatus: 0
                )
            }
        )

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )

        try runtime.sendInput("ship it")
        let screen = runtime.sessionScreen(for: session)

        #expect(launchRecorder.launches.count == 1)
        #expect(launchRecorder.launches.first?.executable == "/tmp/fake-bob")
        #expect(launchRecorder.launches.first?.workingDirectory == "/tmp/workspace")
        #expect(launchRecorder.launches.first?.arguments == [
            "-o", "stream-json",
            "--chat-mode", "advanced",
            "--hide-intermediary-output",
            "--approval-mode", "yolo",
            "ship it"
        ])
        #expect(launchRecorder.launches.first?.arguments.contains("--trust") == false)
        #expect(launchRecorder.launches.first?.arguments.contains("--accept-license") == false)
        #expect(launchRecorder.launches.first?.arguments.contains("--instance-id") == false)
        #expect(launchRecorder.launches.first?.arguments.contains("--team-id") == false)
        #expect(launchRecorder.launches.first?.arguments.contains("--include-directories") == false)
        #expect(runtime.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.kind) == [.status, .message, .status, .message, .command, .diff, .completion])
        #expect(screen.activityItems.map(\.text) == [
            "IBM Bob Session ready. Send a prompt to start IBM Bob.",
            "You: ship it",
            "Bob turn started",
            "Hello from Bob",
            "npm test",
            "diff --git a/file b/file",
            "Bob turn complete"
        ])
    }

    @Test func secondPromptStartsFreshBobTurnOnSameReadyRuntime() throws {
        let launchRecorder = IBMBobLaunchRecorder()
        let runtime = try IBMBobSessionRuntime(
            executable: "/tmp/fake-bob",
            workingDirectory: "/tmp/workspace",
            terminationStatusMessageBuilder: { status in "IBM Bob exited with status \(status)." },
            transportFactory: { executable, arguments, workingDirectory in
                launchRecorder.record(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
                let reply = launchRecorder.launches.count == 1 ? "First turn" : "Second turn"
                return SynchronousIBMBobTransport(
                    stdoutLines: [
                        #"{"type":"message","text":"\#(reply)"}"#,
                        #"{"type":"completion","text":"Done"}"#
                    ],
                    terminationStatus: 0
                )
            }
        )

        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .ibmBob,
            isDefault: true,
            state: .ready
        )

        try runtime.sendInput("first prompt")
        try runtime.sendInput("second prompt")
        let screen = runtime.sessionScreen(for: session)

        #expect(launchRecorder.launches.map(\.arguments.last) == ["first prompt", "second prompt"])
        #expect(runtime.state == .ready)
        #expect(screen.activityItems.map(\.text) == [
            "IBM Bob Session ready. Send a prompt to start IBM Bob.",
            "You: first prompt",
            "First turn",
            "Done",
            "You: second prompt",
            "Second turn",
            "Done"
        ])
    }
}

private final class IBMBobLaunchRecorder: @unchecked Sendable {
    struct Launch {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    private let lock = NSLock()
    private(set) var launches: [Launch] = []

    func record(executable: String, arguments: [String], workingDirectory: String?) {
        lock.lock()
        launches.append(Launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        lock.unlock()
    }
}

private final class SynchronousIBMBobTransport: IBMBobTransporting, @unchecked Sendable {
    private let stdoutLines: [String]
    private let stderrLines: [String]
    private let terminationStatus: Int32
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var stderrLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(stdoutLines: [String], stderrLines: [String] = [], terminationStatus: Int32) {
        self.stdoutLines = stdoutLines
        self.stderrLines = stderrLines
        self.terminationStatus = terminationStatus
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setStderrLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stderrLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {
        for line in stdoutLines {
            stdoutLineHandler?(line)
        }
        for line in stderrLines {
            stderrLineHandler?(line)
        }
        terminationHandler?(terminationStatus)
    }

    func terminate() throws {}
}
#endif
