#if os(macOS)
import Foundation
import NexusDomain

struct CodexSessionLinkage: Equatable, Sendable {
    let threadID: String?

    var isEmpty: Bool {
        guard let threadID = threadID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return true
        }
        return threadID.isEmpty
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        let metadata = SessionRecordAdapterMetadata(
            providerID: .codex,
            values: ["threadID": threadID ?? ""]
        )
        return metadata.isEmpty ? nil : metadata
    }
}

extension SessionRecordAdapterMetadata {
    var codexSessionLinkage: CodexSessionLinkage? {
        guard providerID == .codex else {
            return nil
        }

        let linkage = CodexSessionLinkage(threadID: values["threadID"])
        return linkage.isEmpty ? nil : linkage
    }
}
#endif
