#if os(macOS)
import Foundation
import NexusDomain

struct PiStructuredSessionPersistedState: Codable, Equatable, Sendable {
    let activityItems: [SessionActivityItem]
    let approvalRequests: [SessionApprovalRequest]
    let extensionUIState: SessionExtensionUIState?
    let providerEvents: [SessionProviderEvent]
}

final class PiStructuredSessionHistoryStore: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func persistedState(sessionID: UUID) throws -> PiStructuredSessionPersistedState? {
        try withLock {
            try readStateWithoutLock(sessionID: sessionID)
        }
    }

    func recordCurrentState(
        sessionID: UUID,
        screen: SessionScreen,
        overflow: StructuredSessionPersistedHistoryOverflow = .empty
    ) throws {
        guard screen.primarySurface == .structuredActivityFeed else {
            return
        }

        let currentState = PiStructuredSessionPersistedState(
            activityItems: screen.activityItems,
            approvalRequests: screen.approvalRequests,
            extensionUIState: screen.extensionUI,
            providerEvents: screen.providerEvents
        )

        try withLock {
            let previousState = try readStateWithoutLock(sessionID: sessionID)
            let activityOverflow = mergedActivityOverflow(
                explicitOverflow: overflow.activityItems,
                previous: previousState?.activityItems ?? [],
                current: currentState.activityItems
            )
            let providerEventOverflow = mergedProviderEventOverflow(
                explicitOverflow: overflow.providerEvents,
                previous: previousState?.providerEvents ?? [],
                current: currentState.providerEvents
            )
            let directoryURL = historyDirectoryURL(sessionID: sessionID)

            if activityOverflow.isEmpty == false || providerEventOverflow.isEmpty == false {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            if activityOverflow.isEmpty == false {
                try appendJSONLines(activityOverflow, to: activityOverflowURL(sessionID: sessionID))
            }
            if providerEventOverflow.isEmpty == false {
                try appendJSONLines(providerEventOverflow, to: providerEventOverflowURL(sessionID: sessionID))
            }

            try writeStateWithoutLock(currentState, sessionID: sessionID)
        }
    }

    func deleteHistory(sessionID: UUID) throws {
        try withLock {
            let directoryURL = historyDirectoryURL(sessionID: sessionID)
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                return
            }
            try fileManager.removeItem(at: directoryURL)
        }
    }

    func moveHistory(from sourceSessionID: UUID, to targetSessionID: UUID) throws {
        guard sourceSessionID != targetSessionID else {
            return
        }

        try withLock {
            let sourceURL = historyDirectoryURL(sessionID: sourceSessionID)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                return
            }

            let targetURL = historyDirectoryURL(sessionID: targetSessionID)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            } else {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            }
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        }
    }

    private func readStateWithoutLock(sessionID: UUID) throws -> PiStructuredSessionPersistedState? {
        let stateURL = stateURL(sessionID: sessionID)
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: stateURL)
        return try decoder.decode(PiStructuredSessionPersistedState.self, from: data)
    }

    private func writeStateWithoutLock(_ state: PiStructuredSessionPersistedState, sessionID: UUID) throws {
        let directoryURL = historyDirectoryURL(sessionID: sessionID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL(sessionID: sessionID), options: .atomic)
    }

    private func appendJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        let fileExists = fileManager.fileExists(atPath: url.path)
        if fileExists == false {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        handle.seekToEndOfFile()

        for value in values {
            let lineData = try encoder.encode(value)
            handle.write(lineData)
            handle.write(Data([0x0A]))
        }
    }

    private func mergedActivityOverflow(
        explicitOverflow: [SessionActivityItem],
        previous: [SessionActivityItem],
        current: [SessionActivityItem]
    ) -> [SessionActivityItem] {
        deduplicatedActivityItems(explicitOverflow + evictedActivityItems(previous: previous, current: current))
    }

    private func evictedActivityItems(
        previous: [SessionActivityItem],
        current: [SessionActivityItem]
    ) -> [SessionActivityItem] {
        guard previous.isEmpty == false else {
            return []
        }
        guard let firstCurrentID = current.first?.id else {
            return previous
        }
        guard let overlapIndex = previous.firstIndex(where: { $0.id == firstCurrentID }) else {
            return previous
        }
        return Array(previous.prefix(overlapIndex))
    }

    private func mergedProviderEventOverflow(
        explicitOverflow: [SessionProviderEvent],
        previous: [SessionProviderEvent],
        current: [SessionProviderEvent]
    ) -> [SessionProviderEvent] {
        deduplicatedProviderEvents(explicitOverflow + evictedProviderEvents(previous: previous, current: current))
    }

    private func evictedProviderEvents(
        previous: [SessionProviderEvent],
        current: [SessionProviderEvent]
    ) -> [SessionProviderEvent] {
        guard previous.isEmpty == false else {
            return []
        }
        guard let firstCurrentSequence = current.first?.sequence else {
            return previous
        }
        guard let overlapIndex = previous.firstIndex(where: { $0.sequence == firstCurrentSequence }) else {
            return previous
        }
        return Array(previous.prefix(overlapIndex))
    }

    private func deduplicatedActivityItems(_ items: [SessionActivityItem]) -> [SessionActivityItem] {
        var seen: Set<UUID> = []
        var deduplicated: [SessionActivityItem] = []
        for item in items where seen.insert(item.id).inserted {
            deduplicated.append(item)
        }
        return deduplicated
    }

    private func deduplicatedProviderEvents(_ events: [SessionProviderEvent]) -> [SessionProviderEvent] {
        var seen: Set<Int> = []
        var deduplicated: [SessionProviderEvent] = []
        for event in events where seen.insert(event.sequence).inserted {
            deduplicated.append(event)
        }
        return deduplicated
    }

    private func historyDirectoryURL(sessionID: UUID) -> URL {
        rootURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func stateURL(sessionID: UUID) -> URL {
        historyDirectoryURL(sessionID: sessionID).appendingPathComponent("current.json", isDirectory: false)
    }

    private func activityOverflowURL(sessionID: UUID) -> URL {
        historyDirectoryURL(sessionID: sessionID).appendingPathComponent("activity-items.jsonl", isDirectory: false)
    }

    private func providerEventOverflowURL(sessionID: UUID) -> URL {
        historyDirectoryURL(sessionID: sessionID).appendingPathComponent("provider-events.jsonl", isDirectory: false)
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
#endif
