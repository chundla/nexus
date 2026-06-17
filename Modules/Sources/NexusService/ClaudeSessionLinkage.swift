#if os(macOS)
    import Foundation
    import NexusDomain

    struct ClaudeSessionLinkage: Equatable, Sendable {
        let claudeSessionID: String?

        var isEmpty: Bool {
            guard let claudeSessionID = claudeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return true
            }
            return claudeSessionID.isEmpty
        }

        var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
            let metadata = SessionRecordAdapterMetadata(
                providerID: .claude,
                values: ["claudeSessionID": claudeSessionID ?? ""]
            )
            return metadata.isEmpty ? nil : metadata
        }
    }

    extension SessionRecordAdapterMetadata {
        var claudeSessionLinkage: ClaudeSessionLinkage? {
            guard providerID == .claude else {
                return nil
            }

            let linkage = ClaudeSessionLinkage(claudeSessionID: values["claudeSessionID"])
            return linkage.isEmpty ? nil : linkage
        }
    }
#endif
