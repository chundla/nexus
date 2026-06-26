import Foundation
import Testing

@testable import nexus

@MainActor
@Suite(.serialized)
struct CoalescingMainActorValuePumpTests {
    @Test func deliversLatestQueuedValueAfterInFlightDeliveryCompletes() async throws {
        let gate = AsyncGate()
        let recorder = DeliveryRecorder<String>()
        let pump = CoalescingMainActorValuePump<String>()
        pump.installDeliver { value in
            await recorder.record(value)
            if value == "first" {
                await gate.wait()
            }
        }

        pump.submit("first")
        try await waitUntil { await recorder.values == ["first"] }

        pump.submit("second")
        pump.submit("third")
        await gate.open()

        try await waitUntil { await recorder.values == ["first", "third"] }
    }

    @Test func resetDropsQueuedValueBeforeItIsDelivered() async throws {
        let gate = AsyncGate()
        let recorder = DeliveryRecorder<String>()
        let pump = CoalescingMainActorValuePump<String>()
        pump.installDeliver { value in
            await recorder.record(value)
            if value == "first" {
                await gate.wait()
            }
        }

        pump.submit("first")
        try await waitUntil { await recorder.values == ["first"] }

        pump.submit("second")
        pump.reset()
        await gate.open()

        try await waitUntil { await recorder.values == ["first"] }
    }

    @Test func mergePendingValueCanPreserveEarlierPreferredQueuedValue() async throws {
        let gate = AsyncGate()
        let recorder = DeliveryRecorder<Int>()
        let pump = CoalescingMainActorValuePump<Int>(mergePendingValue: max)
        pump.installDeliver { value in
            await recorder.record(value)
            if value == 1 {
                await gate.wait()
            }
        }

        pump.submit(1)
        try await waitUntil { await recorder.values == [1] }

        pump.submit(5)
        pump.submit(3)
        await gate.open()

        try await waitUntil { await recorder.values == [1, 5] }
    }
}

private actor DeliveryRecorder<Value: Sendable & Equatable> {
    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard isOpen == false else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard isOpen == false else {
            return
        }

        isOpen = true
        let continuations = waiters
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    while await condition() == false {
        guard ContinuousClock.now < deadline else {
            throw TimeoutError()
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}

private struct TimeoutError: Error {}
