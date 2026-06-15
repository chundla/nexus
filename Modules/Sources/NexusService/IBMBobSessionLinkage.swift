#if os(macOS)
    import Foundation
    import NexusDomain

    private enum IBMBobSessionRecordMetadataKey {
        static let sessionID = "bobSessionID"
        static let activityItemsJSON = "activityItemsJSON"
        static let turnInProgress = "turnInProgress"
    }

    struct IBMBobSessionLinkage: Equatable, Sendable {
        let sessionID: String?
        let persistedActivityItems: [SessionActivityItem]
        let turnInProgress: Bool

        init(sessionID: String?, persistedActivityItems: [SessionActivityItem] = [], turnInProgress: Bool = false) {
            self.sessionID = sessionID
            self.persistedActivityItems = persistedActivityItems
            self.turnInProgress = turnInProgress
        }

        var isEmpty: Bool {
            let trimmedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedSessionID.isEmpty && persistedActivityItems.isEmpty && turnInProgress == false
        }

        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
            SessionRecordAdapterMetadata.ibmBob(
                sessionID: sessionID,
                activityItems: persistedActivityItems,
                turnInProgress: turnInProgress
            )
        }
    }

    extension SessionRecordAdapterMetadata {
        static func ibmBob(
            sessionID: String?,
            activityItems: [SessionActivityItem] = [],
            turnInProgress: Bool = false
        ) -> SessionRecordAdapterMetadata? {
            var values: [String: String] = [:]
            values[IBMBobSessionRecordMetadataKey.sessionID] = sessionID ?? ""
            if activityItems.isEmpty == false,
                let data = try? JSONEncoder().encode(activityItems),
                let json = String(data: data, encoding: .utf8)
            {
                values[IBMBobSessionRecordMetadataKey.activityItemsJSON] = json
            }
            if turnInProgress {
                values[IBMBobSessionRecordMetadataKey.turnInProgress] = "true"
            }

            let metadata = SessionRecordAdapterMetadata(providerID: .ibmBob, values: values)
            return metadata.isEmpty ? nil : metadata
        }

        var ibmBobSessionLinkage: IBMBobSessionLinkage? {
            guard providerID == .ibmBob else {
                return nil
            }

            let linkage = IBMBobSessionLinkage(
                sessionID: values[IBMBobSessionRecordMetadataKey.sessionID],
                persistedActivityItems: ibmBobPersistedActivityItems ?? [],
                turnInProgress: ibmBobTurnInProgress
            )
            return linkage.isEmpty ? nil : linkage
        }

        var ibmBobPersistedActivityItems: [SessionActivityItem]? {
            guard providerID == .ibmBob,
                let json = values[IBMBobSessionRecordMetadataKey.activityItemsJSON],
                let data = json.data(using: .utf8),
                let items = try? JSONDecoder().decode([SessionActivityItem].self, from: data),
                items.isEmpty == false
            else {
                return nil
            }

            return items
        }

        var ibmBobTurnInProgress: Bool {
            providerID == .ibmBob && values[IBMBobSessionRecordMetadataKey.turnInProgress] == "true"
        }
    }
#endif
