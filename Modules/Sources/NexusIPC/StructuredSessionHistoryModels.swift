import Foundation
import NexusDomain

public struct StructuredSessionHistoryCursor: Codable, Equatable, Sendable {
    public let activityItemOffset: Int
    public let providerEventOffset: Int

    public init(activityItemOffset: Int, providerEventOffset: Int) {
        self.activityItemOffset = max(0, activityItemOffset)
        self.providerEventOffset = max(0, providerEventOffset)
    }
}

public struct StructuredSessionHistoryPage: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let activityItems: [SessionActivityItem]
    public let providerEvents: [SessionProviderEvent]
    public let nextCursor: StructuredSessionHistoryCursor?

    public init(
        sessionID: UUID,
        activityItems: [SessionActivityItem],
        providerEvents: [SessionProviderEvent],
        nextCursor: StructuredSessionHistoryCursor?
    ) {
        self.sessionID = sessionID
        self.activityItems = activityItems
        self.providerEvents = providerEvents
        self.nextCursor = nextCursor
    }
}
