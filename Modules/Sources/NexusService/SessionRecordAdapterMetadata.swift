#if os(macOS)
import Foundation
import NexusDomain

struct SessionRecordAdapterMetadata: Codable, Equatable, Sendable {
    let providerID: ProviderID
    let values: [String: String]

    init(providerID: ProviderID, values: [String: String]) {
        self.providerID = providerID
        self.values = values.reduce(into: [:]) { result, entry in
            let trimmedValue = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedValue.isEmpty == false else {
                return
            }
            result[entry.key] = trimmedValue
        }
    }

    var isEmpty: Bool {
        values.isEmpty
    }
}
#endif
