#if os(macOS)
import Foundation
import NexusDomain

private enum IBMBobSessionRecordMetadataKey {
    static let sessionID = "bobSessionID"
    static let activityItemsJSON = "activityItemsJSON"
}

struct IBMBobSessionLinkage: Equatable, Sendable {
    let sessionID: String?

    var isEmpty: Bool {
        guard let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return true
        }
        return sessionID.isEmpty
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        SessionRecordAdapterMetadata.ibmBob(sessionID: sessionID)
    }
}

extension SessionRecordAdapterMetadata {
    static func ibmBob(sessionID: String?, activityItems: [SessionActivityItem] = []) -> SessionRecordAdapterMetadata? {
        var values: [String: String] = [:]
        values[IBMBobSessionRecordMetadataKey.sessionID] = sessionID ?? ""
        if activityItems.isEmpty == false,
           let data = try? JSONEncoder().encode(activityItems),
           let json = String(data: data, encoding: .utf8) {
            values[IBMBobSessionRecordMetadataKey.activityItemsJSON] = json
        }

        let metadata = SessionRecordAdapterMetadata(providerID: .ibmBob, values: values)
        return metadata.isEmpty ? nil : metadata
    }

    var ibmBobSessionLinkage: IBMBobSessionLinkage? {
        guard providerID == .ibmBob else {
            return nil
        }

        let linkage = IBMBobSessionLinkage(sessionID: values[IBMBobSessionRecordMetadataKey.sessionID])
        return linkage.isEmpty ? nil : linkage
    }

    var ibmBobPersistedActivityItems: [SessionActivityItem]? {
        guard providerID == .ibmBob,
              let json = values[IBMBobSessionRecordMetadataKey.activityItemsJSON],
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([SessionActivityItem].self, from: data),
              items.isEmpty == false else {
            return nil
        }

        return items
    }
}
#endif
