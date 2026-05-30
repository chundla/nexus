#if os(macOS)
import Foundation
import NexusDomain

private enum PiSessionRecordMetadataKey {
    static let sessionID = "piSessionID"
    static let sessionFile = "sessionFile"
    static let activityItemsJSON = "activityItemsJSON"
    static let approvalRequestsJSON = "approvalRequestsJSON"
    static let extensionUIStateJSON = "extensionUIStateJSON"
    static let providerEventsJSON = "providerEventsJSON"
}

struct PiSessionLinkage: Equatable, Sendable {
    let piSessionID: String?
    let sessionFile: String?

    var isEmpty: Bool {
        [piSessionID, sessionFile].allSatisfy { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return true
            }
            return trimmed.isEmpty
        }
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        SessionRecordAdapterMetadata.pi(linkage: self)
    }
}

extension SessionRecordAdapterMetadata {
    static func pi(
        linkage: PiSessionLinkage?,
        activityItems: [SessionActivityItem] = [],
        approvalRequests: [SessionApprovalRequest] = [],
        extensionUIState: SessionExtensionUIState? = nil,
        providerEvents: [SessionProviderEvent] = []
    ) -> SessionRecordAdapterMetadata? {
        var values: [String: String] = [:]
        values[PiSessionRecordMetadataKey.sessionID] = linkage?.piSessionID ?? ""
        values[PiSessionRecordMetadataKey.sessionFile] = linkage?.sessionFile ?? ""
        encode(activityItems, key: PiSessionRecordMetadataKey.activityItemsJSON, into: &values)
        encode(approvalRequests, key: PiSessionRecordMetadataKey.approvalRequestsJSON, into: &values)
        if let extensionUIState,
           piExtensionUIStateHasContent(extensionUIState) {
            encode(extensionUIState, key: PiSessionRecordMetadataKey.extensionUIStateJSON, into: &values)
        }
        encode(providerEvents, key: PiSessionRecordMetadataKey.providerEventsJSON, into: &values)

        let metadata = SessionRecordAdapterMetadata(providerID: .pi, values: values)
        return metadata.isEmpty ? nil : metadata
    }

    var piSessionLinkage: PiSessionLinkage? {
        guard providerID == .pi else {
            return nil
        }

        let linkage = PiSessionLinkage(
            piSessionID: values[PiSessionRecordMetadataKey.sessionID],
            sessionFile: values[PiSessionRecordMetadataKey.sessionFile]
        )
        return linkage.isEmpty ? nil : linkage
    }

    var piPersistedActivityItems: [SessionActivityItem]? {
        decode([SessionActivityItem].self, key: PiSessionRecordMetadataKey.activityItemsJSON)
    }

    var piPersistedApprovalRequests: [SessionApprovalRequest]? {
        decode([SessionApprovalRequest].self, key: PiSessionRecordMetadataKey.approvalRequestsJSON)
    }

    var piPersistedExtensionUIState: SessionExtensionUIState? {
        guard let state: SessionExtensionUIState = decode(SessionExtensionUIState.self, key: PiSessionRecordMetadataKey.extensionUIStateJSON),
              piExtensionUIStateHasContent(state) else {
            return nil
        }
        return state
    }

    var piPersistedProviderEvents: [SessionProviderEvent]? {
        decode([SessionProviderEvent].self, key: PiSessionRecordMetadataKey.providerEventsJSON)
    }

    private static func encode<T: Encodable>(_ value: T, key: String, into values: inout [String: String]) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8),
              json.isEmpty == false,
              json != "[]",
              json != "{}" else {
            return
        }
        values[key] = json
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard providerID == .pi,
              let json = values[key],
              let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        return value
    }
}

private func piExtensionUIStateHasContent(_ state: SessionExtensionUIState) -> Bool {
    state.title != nil
        || state.pendingDialogs.isEmpty == false
        || state.notifications.isEmpty == false
        || state.statuses.isEmpty == false
        || state.widgets.isEmpty == false
        || state.editorText != nil
}
#endif
