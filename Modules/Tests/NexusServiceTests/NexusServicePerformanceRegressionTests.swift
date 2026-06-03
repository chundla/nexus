#if os(macOS)
import XCTest
import NexusDomain
@testable import NexusService

final class NexusServicePerformanceRegressionTests: XCTestCase {
    func testWorkspaceRefreshRegressionMatchesTheAuditedBaselineShape() throws {
        let fixture = try ServicePerformanceBaselineFixtures.makeWorkspaceCatalogFixture()

        _ = try fixture.service.refreshWorkspaceOverview(workspaceID: fixture.workspace.id)

        let record = try XCTUnwrap(
            try ServicePerformanceBaselineFixtures.latestDiagnostic(
                in: fixture.service,
                matching: { $0.operation == .workspaceOverview }
            )
        )

        XCTAssertEqual(record.outcome, .success)
        XCTAssertEqual(record.workspaceID, fixture.workspace.id)
        XCTAssertNil(record.providerID)
        XCTAssertNil(record.sessionID)

        let expectedStepNames = [
            "loadWorkspace",
            "loadRemoteTarget",
            "loadSessions.claude",
            "readProviderCatalog.claude",
            "loadSessions.codex",
            "readProviderCatalog.codex",
            "loadSessions.ibmBob",
            "readProviderCatalog.ibmBob",
            "loadSessions.pi",
            "readProviderCatalog.pi"
        ]
        XCTAssertEqual(record.steps.count, expectedStepNames.count)
        XCTAssertEqual(Set(record.steps.map(\.name)), Set(expectedStepNames))
    }

    func testStructuredSessionActivityAppendRegressionMatchesTheAuditedBaselineShape() throws {
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

        XCTAssertEqual(record.outcome, .success)
        XCTAssertEqual(record.workspaceID, fixture.workspace.id)
        XCTAssertEqual(record.providerID, .pi)
        XCTAssertEqual(record.sessionID, session.id)
        XCTAssertEqual(record.steps.map(\.name), ["buildStructuredDelta"])
        XCTAssertEqual(record.metrics["deltaBuildCount"], 1)
        XCTAssertEqual(record.metrics["snapshotBuildCount"], 0)
        XCTAssertEqual(record.metrics["changeCount"], 3)
        XCTAssertEqual(record.metrics["activityItemCount"], 3)
        XCTAssertEqual(record.metrics["approvalRequestCount"], 1)
        XCTAssertEqual(record.metrics["baseRevision"], 1)
        XCTAssertEqual(record.metrics["structuredRevision"], 2)
        XCTAssertEqual(record.metrics["transcriptCharacterCount"], 8)
        XCTAssertNotNil(record.metrics["fullReplaceFallbackCount"])
    }
}
#endif
