#if os(macOS)
    import SwiftUI

    enum NexusSettingsTab: Hashable {
        case hosts
        case remoteAccess
    }

    /// Owned once by `nexusApp` and shared with `ContentView` so Command Palette
    /// actions and macOS menu commands can route to the right Settings tab before
    /// asking the environment to open the Settings window.
    @Observable
    final class NexusSettingsTabSelection {
        var tab: NexusSettingsTab = .hosts
    }

    struct NexusSettingsRootView: View {
        @Bindable var appModel: NexusAppModel
        @Bindable var tabSelection: NexusSettingsTabSelection

        var body: some View {
            TabView(selection: $tabSelection.tab) {
                HostManagementView(appModel: appModel)
                    .tabItem { Label("Hosts", systemImage: "network") }
                    .tag(NexusSettingsTab.hosts)

                RemoteAccessManagementView(appModel: appModel)
                    .tabItem { Label("Remote Access", systemImage: "point.3.connected.trianglepath.dotted") }
                    .tag(NexusSettingsTab.remoteAccess)
            }
            .frame(minWidth: 780, minHeight: 600)
            .nexusSeamlessWindowChrome()
        }
    }
#endif
