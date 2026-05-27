#if os(macOS)
import Foundation
import NexusDomain

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
        let metadata = SessionRecordAdapterMetadata(
            providerID: .pi,
            values: [
                "piSessionID": piSessionID ?? "",
                "sessionFile": sessionFile ?? ""
            ]
        )
        return metadata.isEmpty ? nil : metadata
    }
}

extension SessionRecordAdapterMetadata {
    var piSessionLinkage: PiSessionLinkage? {
        guard providerID == .pi else {
            return nil
        }

        let linkage = PiSessionLinkage(
            piSessionID: values["piSessionID"],
            sessionFile: values["sessionFile"]
        )
        return linkage.isEmpty ? nil : linkage
    }
}
#endif
