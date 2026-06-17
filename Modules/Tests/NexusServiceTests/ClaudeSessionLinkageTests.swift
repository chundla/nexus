#if os(macOS)
    import Foundation
    @testable import NexusService
    import Testing

    struct ClaudeSessionLinkageTests {
        @Test func roundTripsClaudeSessionIDThroughSessionRecordAdapterMetadata() {
            let linkage = ClaudeSessionLinkage(claudeSessionID: "aa80e0d8-1234-4abc-9def-0123456789ab")

            let metadata = linkage.sessionRecordAdapterMetadata

            #expect(metadata?.providerID == .claude)
            #expect(metadata?.claudeSessionLinkage == linkage)
        }

        @Test func emptyClaudeSessionIDProducesNoAdapterMetadata() {
            let linkage = ClaudeSessionLinkage(claudeSessionID: nil)

            #expect(linkage.isEmpty)
            #expect(linkage.sessionRecordAdapterMetadata == nil)
        }

        @Test func nonClaudeAdapterMetadataHasNoClaudeSessionLinkage() {
            let metadata = SessionRecordAdapterMetadata(providerID: .codex, values: ["threadID": "abc"])

            #expect(metadata.claudeSessionLinkage == nil)
        }
    }
#endif
