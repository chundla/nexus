import Foundation
import NexusDomain

public struct StructuredSessionObservationProgressSample: Equatable, Sendable {
    public let structuredRevision: Int?
    public let transcriptCharacterCount: Int
    public let activityItemCount: Int
    public let approvalRequestCount: Int
    public let providerEventCount: Int
    public let lastActivityItemID: UUID?
    public let lastActivityItemText: String?
    public let lastProviderEventSequence: Int?
    public let lastProviderEventType: String?
    public let isAgentTurnInProgress: Bool

    public init(screen: SessionScreen, structuredRevision: Int? = nil) {
        self.structuredRevision = structuredRevision
        self.transcriptCharacterCount = screen.transcript.count
        self.activityItemCount = screen.activityItems.count
        self.approvalRequestCount = screen.approvalRequests.count
        self.providerEventCount =
            screen.providerFacts.providerEventCount == 0
            ? screen.providerEvents.count : screen.providerFacts.providerEventCount
        self.lastActivityItemID = screen.activityItems.last?.id
        self.lastActivityItemText = screen.activityItems.last?.text
        self.lastProviderEventSequence =
            screen.providerFacts.lastProviderEventSequence ?? screen.providerEvents.last?.sequence
        self.lastProviderEventType = screen.providerFacts.lastProviderEventType ?? screen.providerEvents.last?.type
        self.isAgentTurnInProgress = screen.isAgentTurnInProgress
    }

    public func hasAdvanced(since previous: StructuredSessionObservationProgressSample) -> Bool {
        self != previous
    }
}

public struct StructuredSessionPresentationProgressSample: Equatable, Sendable {
    public let activityRowCount: Int
    public let pendingApprovalRequestCount: Int
    public let lastActivityRowID: UUID?
    public let lastActivityRowText: String?
    public let hasThinkingIndicator: Bool

    public init(presentation: FocusedStructuredSessionPresentation) {
        self.activityRowCount = presentation.feed.activityRows.count
        self.pendingApprovalRequestCount = presentation.feed.pendingApprovalRequests.count
        self.lastActivityRowID = presentation.feed.activityRows.last?.id
        self.lastActivityRowText = presentation.feed.activityRows.last?.text
        self.hasThinkingIndicator = presentation.feed.thinkingIndicator != nil
    }

    public func hasAdvanced(since previous: StructuredSessionPresentationProgressSample) -> Bool {
        self != previous
    }
}

public struct StructuredSessionClientDiagnosticSnapshot: Equatable, Sendable {
    public let observation: StructuredSessionObservationProgressSample
    public let presentation: StructuredSessionPresentationProgressSample?
    public let finalOutputLatency: StructuredSessionFinalOutputLatencySample?

    public init(
        screen: SessionScreen,
        structuredRevision: Int? = nil,
        presentation: FocusedStructuredSessionPresentation?,
        finalOutputLatency: StructuredSessionFinalOutputLatencySample? = nil
    ) {
        self.observation = StructuredSessionObservationProgressSample(
            screen: screen,
            structuredRevision: structuredRevision
        )
        self.presentation = presentation.map(StructuredSessionPresentationProgressSample.init)
        self.finalOutputLatency = finalOutputLatency
    }
}

public enum StructuredSessionThinkingStallLayer: String, Equatable, Sendable {
    case none
    case runtime
    case observation
    case sessionPresentation
}

public struct StructuredSessionThinkingStallAttribution: Equatable, Sendable {
    public let layer: StructuredSessionThinkingStallLayer
    public let serviceAdvanced: Bool
    public let clientObservationAdvanced: Bool
    public let clientPresentationAdvanced: Bool
    public let stillThinking: Bool

    public init(
        layer: StructuredSessionThinkingStallLayer,
        serviceAdvanced: Bool,
        clientObservationAdvanced: Bool,
        clientPresentationAdvanced: Bool,
        stillThinking: Bool
    ) {
        self.layer = layer
        self.serviceAdvanced = serviceAdvanced
        self.clientObservationAdvanced = clientObservationAdvanced
        self.clientPresentationAdvanced = clientPresentationAdvanced
        self.stillThinking = stillThinking
    }
}

public func structuredSessionThinkingStallAttribution(
    previousService: StructuredSessionObservationProgressSample,
    currentService: StructuredSessionObservationProgressSample,
    previousClientObservation: StructuredSessionObservationProgressSample,
    currentClientObservation: StructuredSessionObservationProgressSample,
    previousClientPresentation: StructuredSessionPresentationProgressSample?,
    currentClientPresentation: StructuredSessionPresentationProgressSample?
) -> StructuredSessionThinkingStallAttribution {
    let serviceAdvanced = currentService.hasAdvanced(since: previousService)
    let clientObservationAdvanced = currentClientObservation.hasAdvanced(since: previousClientObservation)
    let clientPresentationAdvanced =
        switch (previousClientPresentation, currentClientPresentation) {
        case (.some(let previous), .some(let current)):
            current.hasAdvanced(since: previous)
        case (.none, .none):
            false
        default:
            true
        }
    let stillThinking =
        currentService.isAgentTurnInProgress
        || currentClientObservation.isAgentTurnInProgress
        || currentClientPresentation?.hasThinkingIndicator == true

    let layer: StructuredSessionThinkingStallLayer
    if stillThinking == false {
        layer = .none
    } else if serviceAdvanced == false {
        layer = .runtime
    } else if clientObservationAdvanced == false {
        layer = .observation
    } else if clientPresentationAdvanced == false {
        layer = .sessionPresentation
    } else {
        layer = .none
    }

    return StructuredSessionThinkingStallAttribution(
        layer: layer,
        serviceAdvanced: serviceAdvanced,
        clientObservationAdvanced: clientObservationAdvanced,
        clientPresentationAdvanced: clientPresentationAdvanced,
        stillThinking: stillThinking
    )
}
