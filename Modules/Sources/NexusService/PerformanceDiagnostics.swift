import Foundation
import NexusDomain

struct PerformanceDiagnosticTrace {
    private let operation: PerformanceDiagnosticOperation
    private let workspaceID: UUID?
    private let providerID: ProviderID?
    private let sessionID: UUID?
    private let startedAtUptimeNanoseconds: UInt64
    private let recordedAt: Date
    private let currentUptimeNanoseconds: () -> UInt64
    private(set) var steps: [PerformanceDiagnosticStep] = []

    init(
        operation: PerformanceDiagnosticOperation,
        workspaceID: UUID? = nil,
        providerID: ProviderID? = nil,
        sessionID: UUID? = nil,
        recordedAt: Date = Date(),
        currentUptimeNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.operation = operation
        self.workspaceID = workspaceID
        self.providerID = providerID
        self.sessionID = sessionID
        self.recordedAt = recordedAt
        self.currentUptimeNanoseconds = currentUptimeNanoseconds
        self.startedAtUptimeNanoseconds = currentUptimeNanoseconds()
    }

    mutating func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        let startedAt = currentUptimeNanoseconds()
        let value = try block()
        steps.append(
            PerformanceDiagnosticStep(
                name: name,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        )
        return value
    }

    mutating func measure<T>(_ name: String, _ block: () async throws -> T) async rethrows -> T {
        let startedAt = currentUptimeNanoseconds()
        let value = try await block()
        steps.append(
            PerformanceDiagnosticStep(
                name: name,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        )
        return value
    }

    mutating func appendSteps(_ steps: [PerformanceDiagnosticStep]) {
        self.steps.append(contentsOf: steps)
    }

    func finish(
        outcome: PerformanceDiagnosticOutcome,
        metrics: [String: Int] = [:],
        failureMessage: String? = nil
    ) -> PerformanceDiagnosticRecord {
        PerformanceDiagnosticRecord(
            operation: operation,
            outcome: outcome,
            workspaceID: workspaceID,
            providerID: providerID,
            sessionID: sessionID,
            totalElapsedMilliseconds: elapsedMilliseconds(since: startedAtUptimeNanoseconds),
            steps: steps,
            metrics: metrics,
            failureMessage: failureMessage,
            recordedAt: recordedAt
        )
    }

    private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        Int(currentUptimeNanoseconds().saturatingSubtract(startedAt) / 1_000_000)
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
