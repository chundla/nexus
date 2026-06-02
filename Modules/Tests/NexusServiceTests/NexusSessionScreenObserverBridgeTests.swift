#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusIPC
import Testing

struct NexusSessionScreenObserverBridgeTests {
    @Test func bridgeSerializesObservationUpdateDeliveryPerObservation() async throws {
        let bridge = NexusSessionScreenObserverBridge()
        let observationID = UUID()
        let sink = OrderedUpdateSink(expectedCount: 2)

        bridge.registerHandler({ update in
            guard case let .screen(screen) = update,
                  let marker = screen.activityItems.last?.text else {
                return
            }

            if marker == "first" {
                Thread.sleep(forTimeInterval: 0.05)
            }

            Task {
                await sink.record(marker)
            }
        }, for: observationID)

        let firstPayload = try JSONEncoder().encode(SessionScreenObservationUpdate.screen(makeScreen(marker: "first")))
        let secondPayload = try JSONEncoder().encode(SessionScreenObservationUpdate.screen(makeScreen(marker: "second")))

        DispatchQueue.global().async {
            bridge.sessionScreenDidUpdate(observationID: observationID.uuidString, payload: firstPayload)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.005) {
            bridge.sessionScreenDidUpdate(observationID: observationID.uuidString, payload: secondPayload)
        }

        let markers = try await sink.waitForAll()
        #expect(markers == ["first", "second"])
    }

    private func makeScreen(marker: String) -> SessionScreen {
        SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            controller: .mac,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .message, text: marker)]
        )
    }
}

private actor OrderedUpdateSink {
    private let expectedCount: Int
    private var values: [String] = []

    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    func record(_ value: String) {
        values.append(value)
    }

    func waitForAll(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 10_000_000
    ) async throws -> [String] {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

        while true {
            if values.count >= expectedCount {
                return values
            }

            guard ContinuousClock.now < deadline else {
                throw NSError(
                    domain: "NexusSessionScreenObserverBridgeTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for ordered updates"]
                )
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }
}
#endif
