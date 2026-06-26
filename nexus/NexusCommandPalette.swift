import SwiftUI

/// A single Action result in the Command Palette, ranked alongside Workspace/Provider/
/// Session navigation results. Actions are filtered client-side by title; there is no
/// persistence or ranking-by-usage yet, matching the existing Quick Switch behavior for
/// navigation results.
struct NexusCommandPaletteAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let perform: () -> Void

    func matches(_ query: String) -> Bool {
        guard query.isEmpty == false else {
            return true
        }
        return title.localizedCaseInsensitiveContains(query) || subtitle.localizedCaseInsensitiveContains(query)
    }
}

/// Posted by macOS menu commands (`nexusApp.swift`) so `ContentView` can perform the
/// matching action without the App scene needing direct access to `ContentView`'s local
/// sheet/selection state.
extension Notification.Name {
    static let nexusOpenCommandPalette = Notification.Name("nexus.openCommandPalette")
    static let nexusNewLocalWorkspace = Notification.Name("nexus.newLocalWorkspace")
    static let nexusNewRemoteWorkspace = Notification.Name("nexus.newRemoteWorkspace")
    static let nexusNewWorkspaceGroup = Notification.Name("nexus.newWorkspaceGroup")
    static let nexusTakeController = Notification.Name("nexus.takeController")
}

/// Published by `ContentView` via `.focusedValue` so the `Session` menu (`nexusApp.swift`)
/// can enable "Take Controller" only when a Paired Device currently holds Controller for
/// the focused Session, without the App scene needing direct access to `NexusAppModel`.
/// Must stay a plain `Equatable` value (not a closure-bearing struct): SwiftUI can't diff
/// non-Equatable focused values, so every `ContentView` render would republish a
/// "changed" value and re-trigger the App's Scene body forever.
private struct NexusSessionControllerAvailabilityKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var nexusSessionControllerIsTakeable: Bool? {
        get { self[NexusSessionControllerAvailabilityKey.self] }
        set { self[NexusSessionControllerAvailabilityKey.self] = newValue }
    }
}
