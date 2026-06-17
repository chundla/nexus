import NexusDomain
import Testing

@Suite struct TerminalEscapeSequencesTests {
    @Test func stripForPlainDisplayRemovesTruecolorSGR() {
        let raw = "\u{001B}[38;5;109mMCP: 0/1 servers\u{001B}[39m"
        #expect(TerminalEscapeSequences.stripForPlainDisplay(raw) == "MCP: 0/1 servers")
    }

    @Test func stripForPlainDisplayRemovesInverseVideoSGR() {
        let raw = "/\u{001B}[7m \u{001B}[27m"
        #expect(TerminalEscapeSequences.stripForPlainDisplay(raw) == "/ ")
    }

    @Test func stripForPlainDisplayLeavesPlainTextUntouched() {
        #expect(TerminalEscapeSequences.stripForPlainDisplay("MCP: 0/1 servers") == "MCP: 0/1 servers")
    }
}
