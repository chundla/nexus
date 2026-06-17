#if os(macOS)
    import Foundation
    @testable import NexusService
    import Testing

    @Suite struct PiToolExecutionResultTextTests {
        @Test func extractsReadToolDetailsDiff() {
            let result: [String: Any] = [
                "content": [] as [Any],
                "details": ["diff": "--- a\n+++ b\n@@"],
            ]
            let text = PiToolExecutionResultText.extract(from: result)
            #expect(text == "--- a\n+++ b\n@@")
        }

        @Test func extractsBashDetailsOutput() {
            let partial: [String: Any] = [
                "content": [["type": "text", "text": "partial"]],
                "details": ["output": "total 48\nfile.txt"],
            ]
            let text = PiToolExecutionResultText.extract(from: partial)
            #expect(text == "total 48\nfile.txt")
        }

        @Test func prefersContentTextOverEmptyDetails() {
            let result: [String: Any] = [
                "content": [["type": "text", "text": "hello"]],
                "details": ["truncation": NSNull()],
            ]
            #expect(PiToolExecutionResultText.extract(from: result) == "hello")
        }

        @Test func extractsTextDeltaContentBlocks() {
            let update: [String: Any] = [
                "content": [
                    ["type": "text_delta", "delta": "line one\nline two"]
                ]
            ]
            #expect(PiToolExecutionResultText.extract(from: update) == "line one\nline two")
        }
    }
#endif
