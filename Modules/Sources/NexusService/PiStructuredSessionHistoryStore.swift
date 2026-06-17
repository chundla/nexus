#if os(macOS)
    import Foundation
    import NexusDomain
    import NexusIPC

    struct PiStructuredSessionPersistedState: Codable, Equatable, Sendable {
        let activityItems: [SessionActivityItem]
        let approvalRequests: [SessionApprovalRequest]
        let extensionUIState: SessionExtensionUIState?
        let providerEvents: [SessionProviderEvent]
    }

    /// Persists structured Session history for reopen and paging on the owning Mac.
    /// By default this data lives with the Session Record and is removed when the Session Record
    /// is deleted or when a narrower explicit reset/replacement flow discards it.
    /// Provider-native export and full-capture remain separate explicit concerns.
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

        func historyPage(
            sessionID: UUID,
            pageSize: Int,
            before cursor: StructuredSessionHistoryCursor?
        ) throws -> StructuredSessionHistoryPage {
            try withLock {
                let resolvedPageSize = max(1, min(pageSize, 500))
                let activityPage = try pagedJSONLines(
                    SessionActivityItem.self,
                    from: activityOverflowURL(sessionID: sessionID),
                    before: cursor?.activityItemOffset,
                    pageSize: resolvedPageSize
                )
                let providerEventPage = try pagedJSONLines(
                    SessionProviderEvent.self,
                    from: providerEventOverflowURL(sessionID: sessionID),
                    before: cursor?.providerEventOffset,
                    pageSize: resolvedPageSize
                )
                let nextCursor: StructuredSessionHistoryCursor? =
                    if activityPage.nextOffset == nil,
                        providerEventPage.nextOffset == nil
                    {
                        nil
                    } else {
                        StructuredSessionHistoryCursor(
                            activityItemOffset: activityPage.nextOffset ?? 0,
                            providerEventOffset: providerEventPage.nextOffset ?? 0
                        )
                    }
                return StructuredSessionHistoryPage(
                    sessionID: sessionID,
                    activityItems: deduplicatedContiguousOverflowBlocks(activityPage.values),
                    providerEvents: providerEventPage.values,
                    nextCursor: nextCursor
                )
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

        private func pagedJSONLines<T: Decodable>(
            _ type: T.Type,
            from url: URL,
            before offset: Int?,
            pageSize: Int
        ) throws -> (values: [T], nextOffset: Int?) {
            let values = try readJSONLines(type, from: url)
            let endOffset = min(max(0, offset ?? values.count), values.count)
            let startOffset = max(0, endOffset - pageSize)
            let nextOffset = startOffset > 0 ? startOffset : nil
            return (Array(values[startOffset..<endOffset]), nextOffset)
        }

        private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
            _ = type
            guard fileManager.fileExists(atPath: url.path) else {
                return []
            }

            let lines = (try String(data: Data(contentsOf: url), encoding: .utf8) ?? "")
                .split(separator: "\n")
            return try lines.map { line in
                try decoder.decode(T.self, from: Data(line.utf8))
            }
        }

        private func mergedActivityOverflow(
            explicitOverflow: [SessionActivityItem],
            previous: [SessionActivityItem],
            current: [SessionActivityItem]
        ) -> [SessionActivityItem] {
            let implicitEvicted =
                explicitOverflow.isEmpty
                ? evictedActivityItems(previous: previous, current: current)
                : []
            return deduplicatedActivityItems(explicitOverflow + implicitEvicted)
        }

        private func evictedActivityItems(
            previous: [SessionActivityItem],
            current: [SessionActivityItem]
        ) -> [SessionActivityItem] {
            guard previous.isEmpty == false else {
                return []
            }
            guard let firstCurrentID = current.first?.id else {
                return []
            }
            guard let overlapIndex = previous.firstIndex(where: { $0.id == firstCurrentID }) else {
                return []
            }
            guard overlapIndex > 0 else {
                return []
            }
            if previous.count == current.count, previous.first?.id == current.first?.id {
                return []
            }
            return Array(previous.prefix(overlapIndex))
        }

        private func mergedProviderEventOverflow(
            explicitOverflow: [SessionProviderEvent],
            previous: [SessionProviderEvent],
            current: [SessionProviderEvent]
        ) -> [SessionProviderEvent] {
            let implicitEvicted =
                explicitOverflow.isEmpty
                ? evictedProviderEvents(previous: previous, current: current)
                : []
            return deduplicatedProviderEvents(explicitOverflow + implicitEvicted)
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
                return []
            }
            guard overlapIndex > 0 else {
                return []
            }
            return Array(previous.prefix(overlapIndex))
        }

        /// Collapses accidental double-writes where an overflow prefix was appended twice in one jsonl.
        private func deduplicatedContiguousOverflowBlocks(_ items: [SessionActivityItem]) -> [SessionActivityItem] {
            var result = items
            while result.count >= 2 {
                var merged = false
                let maxBlock = result.count / 2
                for blockSize in stride(from: maxBlock, through: 1, by: -1) {
                    let first = Array(result.prefix(blockSize))
                    let second = Array(result.dropFirst(blockSize).prefix(blockSize))
                    guard first == second else {
                        continue
                    }
                    result = first + Array(result.dropFirst(blockSize * 2))
                    merged = true
                    break
                }
                if merged == false {
                    break
                }
            }
            return result
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
            historyDirectoryURL(sessionID: sessionID).appendingPathComponent(
                "provider-events.jsonl", isDirectory: false)
        }

        private func withLock<T>(_ operation: () throws -> T) throws -> T {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }
#endif
