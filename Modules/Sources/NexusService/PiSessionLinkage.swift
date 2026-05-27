#if os(macOS)
import Foundation

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
}
#endif
