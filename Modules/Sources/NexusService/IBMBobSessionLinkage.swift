#if os(macOS)
import Foundation
import NexusDomain

struct IBMBobSessionLinkage: Equatable, Sendable {
    let sessionID: String?

    var isEmpty: Bool {
        guard let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return true
        }
        return sessionID.isEmpty
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        let metadata = SessionRecordAdapterMetadata(
            providerID: .ibmBob,
            values: ["bobSessionID": sessionID ?? ""]
        )
        return metadata.isEmpty ? nil : metadata
    }
}

extension SessionRecordAdapterMetadata {
    var ibmBobSessionLinkage: IBMBobSessionLinkage? {
        guard providerID == .ibmBob else {
            return nil
        }

        let linkage = IBMBobSessionLinkage(sessionID: values["bobSessionID"])
        return linkage.isEmpty ? nil : linkage
    }
}
#endif
