import Foundation
import NexusDomain

public struct StructuredSessionFinalOutputLatencySample: Equatable, Sendable {
    public let trigger: StructuredSessionFinalOutputTrigger
    public let providerEventSequence: Int
    public let providerRuntimeLatencyMilliseconds: Int
    public let serviceObservationLatencyMilliseconds: Int?
    public let clientPresentationLatencyMilliseconds: Int?
    public let totalVisibleLatencyMilliseconds: Int?
    public let isVisibleInPresentation: Bool
    public let visibleActivityRowText: String?

    public init(
        trigger: StructuredSessionFinalOutputTrigger,
        providerEventSequence: Int,
        providerRuntimeLatencyMilliseconds: Int,
        serviceObservationLatencyMilliseconds: Int?,
        clientPresentationLatencyMilliseconds: Int?,
        totalVisibleLatencyMilliseconds: Int?,
        isVisibleInPresentation: Bool,
        visibleActivityRowText: String?
    ) {
        self.trigger = trigger
        self.providerEventSequence = providerEventSequence
        self.providerRuntimeLatencyMilliseconds = providerRuntimeLatencyMilliseconds
        self.serviceObservationLatencyMilliseconds = serviceObservationLatencyMilliseconds
        self.clientPresentationLatencyMilliseconds = clientPresentationLatencyMilliseconds
        self.totalVisibleLatencyMilliseconds = totalVisibleLatencyMilliseconds
        self.isVisibleInPresentation = isVisibleInPresentation
        self.visibleActivityRowText = visibleActivityRowText
    }
}

public struct StructuredSessionFinalOutputLatencyTracker: Sendable {
    private struct MilestoneKey: Equatable, Sendable {
        let providerEventSequence: Int
        let trigger: StructuredSessionFinalOutputTrigger
    }

    private let currentUptimeNanoseconds: @Sendable () -> UInt64
    private var currentMilestoneKey: MilestoneKey?
    private var observationReceivedAtNanoseconds: UInt64?
    private var presentationVisibleAtNanoseconds: UInt64?

    public init(currentUptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.currentUptimeNanoseconds = currentUptimeNanoseconds
    }

    public mutating func update(
        screen: SessionScreen?,
        presentation: FocusedStructuredSessionPresentation?
    ) -> StructuredSessionFinalOutputLatencySample? {
        guard let screen,
            screen.primarySurface == .structuredActivityFeed,
            let diagnostic = screen.finalOutputDiagnostic
        else {
            currentMilestoneKey = nil
            observationReceivedAtNanoseconds = nil
            presentationVisibleAtNanoseconds = nil
            return nil
        }

        let now = currentUptimeNanoseconds()
        let milestoneKey = MilestoneKey(
            providerEventSequence: diagnostic.providerEventSequence,
            trigger: diagnostic.trigger
        )
        if currentMilestoneKey != milestoneKey {
            currentMilestoneKey = milestoneKey
            observationReceivedAtNanoseconds = now
            presentationVisibleAtNanoseconds = nil
        }

        let match = matchingPresentationRow(for: diagnostic, in: presentation)
        if match.isVisible, presentationVisibleAtNanoseconds == nil {
            presentationVisibleAtNanoseconds = now
        }

        let clientPresentationLatencyMilliseconds: Int? =
            if let observationReceivedAtNanoseconds,
                let presentationVisibleAtNanoseconds
            {
                Int(presentationVisibleAtNanoseconds.saturatingSubtract(observationReceivedAtNanoseconds) / 1_000_000)
            } else {
                nil
            }
        let totalVisibleLatencyMilliseconds: Int? =
            if let clientPresentationLatencyMilliseconds {
                diagnostic.providerRuntimeLatencyMilliseconds
                    + (diagnostic.serviceObservationLatencyMilliseconds ?? 0)
                    + clientPresentationLatencyMilliseconds
            } else {
                nil
            }

        return StructuredSessionFinalOutputLatencySample(
            trigger: diagnostic.trigger,
            providerEventSequence: diagnostic.providerEventSequence,
            providerRuntimeLatencyMilliseconds: diagnostic.providerRuntimeLatencyMilliseconds,
            serviceObservationLatencyMilliseconds: diagnostic.serviceObservationLatencyMilliseconds,
            clientPresentationLatencyMilliseconds: clientPresentationLatencyMilliseconds,
            totalVisibleLatencyMilliseconds: totalVisibleLatencyMilliseconds,
            isVisibleInPresentation: presentationVisibleAtNanoseconds != nil,
            visibleActivityRowText: match.visibleActivityRowText
        )
    }

    private func matchingPresentationRow(
        for diagnostic: StructuredSessionFinalOutputDiagnostic,
        in presentation: FocusedStructuredSessionPresentation?
    ) -> (isVisible: Bool, visibleActivityRowText: String?) {
        guard let presentation else {
            return (false, nil)
        }

        let matchingRow = presentation.feed.activityRows.last(where: { row in
            let matchesID = diagnostic.expectedActivityItemID.map { row.id == $0 } ?? true
            let matchesText = diagnostic.expectedActivityItemText.map { row.text == $0 } ?? true
            return matchesID && matchesText
        })
        let matchesThinkingIndicator =
            (presentation.feed.thinkingIndicator != nil) == diagnostic.expectedThinkingIndicatorVisible
        let isVisible = matchingRow != nil && matchesThinkingIndicator
        return (isVisible, matchingRow?.text)
    }
}

extension UInt64 {
    fileprivate func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
