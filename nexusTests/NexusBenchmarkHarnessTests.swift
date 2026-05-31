import Foundation
import NexusDomain
import Testing
@testable import nexus

struct NexusBenchmarkHarnessTests {
    @Test func benchmarkScenarioParsesPlatformSpecificEnvironmentValues() {
        #expect(NexusBenchmarkScenario.macOSScenario(from: ["NEXUS_BENCHMARK_SCENARIO": "mac-terminal-busy"]) == .macTerminalBusy)
        #expect(NexusBenchmarkScenario.macOSScenario(from: ["NEXUS_BENCHMARK_SCENARIO": "iphone-terminal-busy"]) == nil)
        #expect(NexusBenchmarkScenario.iOSScenario(from: ["NEXUS_BENCHMARK_SCENARIO": "iphone-structured-streaming"]) == .iphoneStructuredStreaming)
        #expect(NexusBenchmarkScenario.iOSScenario(from: ["NEXUS_BENCHMARK_SCENARIO": "mac-structured-streaming"]) == nil)
        #expect(NexusBenchmarkScenario.macOSScenario(from: [:]) == nil)
    }

    @Test func structuredStreamingFixtureGrowsStructuredActivityAcrossFrames() {
        let fixture = NexusBenchmarkFixture.make(for: .macStructuredStreaming)
        let firstFrame = try! #require(fixture.frames.first)
        let lastFrame = try! #require(fixture.frames.last)

        #expect(firstFrame.primarySurface == .structuredActivityFeed)
        #expect(lastFrame.primarySurface == .structuredActivityFeed)
        #expect(firstFrame.activityItems.count < lastFrame.activityItems.count)
        #expect(lastFrame.isAgentTurnInProgress == false)
        #expect(lastFrame.activityItems.contains(where: { $0.kind == .completion }))
    }

    @Test func terminalBusyFixtureKeepsTerminalSurfaceAndScrollsVisibleRows() {
        let fixture = NexusBenchmarkFixture.make(for: .macTerminalBusy)
        let firstFrame = try! #require(fixture.frames.first)
        let secondFrame = try! #require(fixture.frames.dropFirst().first)

        #expect(firstFrame.primarySurface == .terminal)
        #expect(firstFrame.styledVisibleLines.count == firstFrame.terminalRows)
        #expect(secondFrame.styledVisibleLines.count == secondFrame.terminalRows)
        #expect(firstFrame.styledVisibleLines.first?.text != secondFrame.styledVisibleLines.first?.text)
        #expect(firstFrame.styledVisibleLines.last?.text != secondFrame.styledVisibleLines.last?.text)
    }
}
