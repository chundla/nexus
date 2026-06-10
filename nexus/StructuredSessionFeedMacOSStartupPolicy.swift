#if os(macOS)
import Foundation

/// macOS structured feed startup: split first `ScrollView` layout from bulk `LazyVStack` row mount (#225).
enum StructuredSessionFeedMacOSStartupPolicy {
    static var defersActivityRowsUntilAfterFirstLayoutTurn: Bool {
        true
    }
}
#endif