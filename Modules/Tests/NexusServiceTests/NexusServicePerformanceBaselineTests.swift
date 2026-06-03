#if os(macOS)
import XCTest
import NexusDomain
@testable import NexusService

final class NexusServicePerformanceBaselineTests: XCTestCase {
    func testWorkspaceRefreshBaseline() throws {
        measureBaseline {
            let fixture = try ServicePerformanceBaselineFixtures.makeWorkspaceCatalogFixture()
            _ = try fixture.service.refreshWorkspaceOverview(workspaceID: fixture.workspace.id)
        }

        let fixture = try ServicePerformanceBaselineFixtures.makeWorkspaceCatalogFixture()
        _ = try fixture.service.refreshWorkspaceOverview(workspaceID: fixture.workspace.id)
        let record = try XCTUnwrap(
            try ServicePerformanceBaselineFixtures.latestDiagnostic(
                in: fixture.service,
                matching: { $0.operation == .workspaceOverview }
            )
        )

        XCTAssertTrue(record.steps.contains(where: { $0.name == "loadWorkspace" }))
        XCTAssertTrue(record.steps.contains(where: { $0.name == "readProviderCatalog.claude" }))
        print(PerformanceBaselineReport.render(flow: "Workspace refresh", record: record))
    }

    func testProviderDetailOpenBaseline() throws {
        measureBaseline {
            let fixture = try ServicePerformanceBaselineFixtures.makeWorkspaceCatalogFixture()
            _ = try fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .claude)
        }

        let fixture = try ServicePerformanceBaselineFixtures.makeWorkspaceCatalogFixture()
        _ = try fixture.service.getProviderDetail(workspaceID: fixture.workspace.id, providerID: .claude)
        let record = try XCTUnwrap(
            try ServicePerformanceBaselineFixtures.latestDiagnostic(
                in: fixture.service,
                matching: { $0.operation == .providerDetail }
            )
        )

        XCTAssertTrue(record.steps.contains(where: { $0.name == "loadSessions" }))
        XCTAssertTrue(record.steps.contains(where: { $0.name == "readProviderCatalog" }))
        print(PerformanceBaselineReport.render(flow: "Provider Detail open", record: record))
    }

    func testSessionOpenBaseline() throws {
        measureBaseline {
            let fixture = try ServicePerformanceBaselineFixtures.makeIBMBobSessionFixture()
            _ = try fixture.service.launchOrResumeDefaultSession(workspaceID: fixture.workspace.id, providerID: .ibmBob)
        }

        let fixture = try ServicePerformanceBaselineFixtures.makeIBMBobSessionFixture()
        _ = try fixture.service.launchOrResumeDefaultSession(workspaceID: fixture.workspace.id, providerID: .ibmBob)
        let record = try XCTUnwrap(
            try ServicePerformanceBaselineFixtures.latestDiagnostic(
                in: fixture.service,
                matching: { $0.operation == .launchDefaultSession }
            )
        )

        XCTAssertTrue(record.steps.contains(where: { $0.name == "planFreshSessionOpen" }))
        XCTAssertTrue(record.steps.contains(where: { $0.name == "launchFreshSession" }))
        print(PerformanceBaselineReport.render(flow: "Session open", record: record))
    }

    func testStructuredSessionActivityAppendBaseline() throws {
        measureBaseline {
            let fixture = try ServicePerformanceBaselineFixtures.makeStructuredSessionFixture()
            let session = try XCTUnwrap(fixture.session)
            _ = try fixture.service.getSessionScreenObservationSnapshot(sessionID: session.id)
            _ = try fixture.service.sendSessionInput(sessionID: session.id, text: "deploy")
        }

        let fixture = try ServicePerformanceBaselineFixtures.makeStructuredSessionFixture()
        let session = try XCTUnwrap(fixture.session)
        _ = try fixture.service.getSessionScreenObservationSnapshot(sessionID: session.id)
        _ = try fixture.service.sendSessionInput(sessionID: session.id, text: "deploy")
        let record = try XCTUnwrap(
            try ServicePerformanceBaselineFixtures.latestDiagnostic(
                in: fixture.service,
                matching: {
                    $0.operation == .structuredSessionObservation
                        && $0.metrics["deltaBuildCount"] == 1
                }
            )
        )

        XCTAssertTrue(record.steps.contains(where: { $0.name == "buildStructuredDelta" }))
        XCTAssertEqual(record.metrics["approvalRequestCount"], 1)
        print(PerformanceBaselineReport.render(flow: "Structured Session activity append", record: record))
    }

    private func measureBaseline(_ block: @escaping () throws -> Void) {
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric()], options: options) {
            do {
                try block()
            } catch {
                XCTFail("Unexpected baseline error: \(error)")
            }
        }
    }
}
#endif
