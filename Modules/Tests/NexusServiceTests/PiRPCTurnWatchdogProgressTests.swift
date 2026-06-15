#if os(macOS)
    @testable import NexusService
    import Testing

    @Suite struct PiRPCTurnWatchdogProgressTests {
        @Test func queueUpdateIsNotProgress() {
            #expect(
                PiRPCTurnWatchdog.countsAsMeaningfulStdoutProgress(
                    type: "queue_update",
                    object: ["steering": [], "followUp": []]
                ) == false)
        }

        @Test func emptyTextDeltaIsNotProgress() {
            #expect(
                PiRPCTurnWatchdog.countsAsMeaningfulStdoutProgress(
                    type: "message_update",
                    object: ["assistantMessageEvent": ["type": "text_delta", "delta": ""]]
                ) == false)
        }

        @Test func toolExecutionStartIsProgress() {
            #expect(
                PiRPCTurnWatchdog.countsAsMeaningfulStdoutProgress(
                    type: "tool_execution_start",
                    object: [:]
                ) == true)
        }
    }
#endif