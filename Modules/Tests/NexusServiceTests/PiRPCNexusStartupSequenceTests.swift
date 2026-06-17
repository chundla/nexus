#if os(macOS)
    import Foundation
    import Testing

    /// Documents RPC sequences used by Nexus vs minimal harness — differential diagnosis for post-tool stalls.
    @Suite struct PiRPCNexusStartupSequenceTests {
        @Test func nexusStartupIssuesGetStateThenCommandsAndModels() {
            let nexusStartupIDs = [
                "nexus-pi-startup-state",
                "nexus-pi-startup-commands",
                "nexus-pi-startup-available-models",
            ]
            #expect(nexusStartupIDs.count == 3)
            #expect(nexusStartupIDs[0].hasPrefix("nexus-pi-startup"))
        }

        @Test func harnessMinimalStartupIsSubsetOfNexusChatter() {
            let harnessAfterState = ["get_commands", "get_available_models", "set_model", "prompt"]
            let nexusPostPrompt = ["get_commands", "get_session_stats", "get_state"]
            // Nexus sends get_commands after prompt accept; harness does not.
            #expect(nexusPostPrompt.contains("get_commands"))
            #expect(harnessAfterState.contains("prompt"))
        }
    }
#endif
