#if os(macOS)
    import Foundation
    import NexusDomain
    @testable import NexusService
    import Testing

    /// Opt-in end-to-end coverage against the real `claude` CLI (no scripted transport, no fake approval hook
    /// bridge). Disabled by default — set `NEXUS_CLAUDE_INTEGRATION=1` to run it; it spends real API usage and
    /// depends on a locally authenticated `claude` install. Override the binary location with
    /// `NEXUS_CLAUDE_INTEGRATION_BINARY` if it isn't at `~/.local/bin/claude`.
    struct ClaudeStreamJSONRuntimeIntegrationTests {
        @Test(.enabled(if: ClaudeIntegrationEnvironment.isEnabled))
        func realClaudeBinaryLaunchPromptApprovalAndResumeRoundTrip() async throws {
            let claudeExecutable = try ClaudeIntegrationEnvironment.resolveExecutablePath()
            let workspaceDirectory = try Self.makeTemporaryWorkspaceDirectory()
            defer { try? FileManager.default.removeItem(at: workspaceDirectory) }
            let markerFileURL = workspaceDirectory.appendingPathComponent("integration-marker.txt")
            let session = Session(
                id: UUID(), workspaceID: UUID(), providerID: .claude, isDefault: true, state: .ready)

            let firstRuntime = try ClaudeStreamJSONRuntime(
                executable: claudeExecutable,
                workingDirectory: workspaceDirectory.path,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." }
            )

            try firstRuntime.sendInput(
                """
                Use the Write tool to create a file named integration-marker.txt in the current directory \
                containing exactly the text NEXUS_INTEGRATION_OK. Do not use any other tools.
                """)

            try await Self.approveApprovalRequestsAsTheyArrive(runtime: firstRuntime, session: session) {
                FileManager.default.fileExists(atPath: markerFileURL.path)
            }

            let writtenContents = try String(contentsOf: markerFileURL, encoding: .utf8)
            #expect(writtenContents.contains("NEXUS_INTEGRATION_OK"))

            let firstScreen = firstRuntime.sessionScreen(for: session)
            #expect(firstScreen.approvalRequests.contains { $0.state == .approved })

            let linkage = try #require(firstRuntime.sessionRecordAdapterMetadata?.claudeSessionLinkage)
            #expect(linkage.claudeSessionID?.isEmpty == false)

            try firstRuntime.stop()

            let secondRuntime = try ClaudeStreamJSONRuntime(
                executable: claudeExecutable,
                workingDirectory: workspaceDirectory.path,
                sessionLinkage: linkage,
                terminationStatusMessageBuilder: { "Claude exited with status \($0)." }
            )

            try secondRuntime.sendInput(
                "What file did you create in the previous turn? Reply with just the filename, nothing else.")

            try await Self.waitUntil(timeout: 60) {
                secondRuntime.state == .failed
                    || secondRuntime.sessionScreen(for: session).activityItems.last?.kind == .completion
            }

            let resumedScreen = secondRuntime.sessionScreen(for: session)
            #expect(secondRuntime.state != .failed)
            let mentionsMarkerFile = resumedScreen.activityItems.contains {
                $0.text.localizedCaseInsensitiveContains("integration-marker.txt")
            }
            #expect(
                mentionsMarkerFile, "Expected --resume to retain conversation continuity about the file just created")

            try secondRuntime.stop()
        }

        private static func makeTemporaryWorkspaceDirectory() throws -> URL {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "nexus-claude-integration-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        private static func approveApprovalRequestsAsTheyArrive(
            runtime: ClaudeStreamJSONRuntime,
            session: Session,
            timeout: TimeInterval = 60,
            until condition: () -> Bool
        ) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() {
                    return
                }
                let screen = runtime.sessionScreen(for: session)
                for request in screen.approvalRequests where request.state == .pending {
                    try runtime.respondToApprovalRequest(request.id, decision: .approve)
                }
                if runtime.state == .failed {
                    Issue.record(
                        "Claude runtime entered .failed while awaiting approval: \(screen.activityItems.last?.text ?? "<no activity>")"
                    )
                    return
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            Issue.record("Timed out waiting for the real claude process to write the integration marker file")
        }

        private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() {
                    return
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            Issue.record("Timed out waiting for the real claude process")
        }
    }

    private enum ClaudeIntegrationEnvironmentError: LocalizedError {
        case executableNotFound(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound(let path):
                "No claude executable found at \(path). Set NEXUS_CLAUDE_INTEGRATION_BINARY to override."
            }
        }
    }

    private enum ClaudeIntegrationEnvironment {
        static var isEnabled: Bool {
            ProcessInfo.processInfo.environment["NEXUS_CLAUDE_INTEGRATION"] == "1"
        }

        static func resolveExecutablePath() throws -> String {
            if let overridePath = ProcessInfo.processInfo.environment["NEXUS_CLAUDE_INTEGRATION_BINARY"],
                overridePath.isEmpty == false
            {
                return overridePath
            }
            let defaultPath = NSHomeDirectory() + "/.local/bin/claude"
            guard FileManager.default.isExecutableFile(atPath: defaultPath) else {
                throw ClaudeIntegrationEnvironmentError.executableNotFound(defaultPath)
            }
            return defaultPath
        }
    }
#endif
