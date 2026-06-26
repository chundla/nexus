//
//  nexusApp.swift
//  nexus
//
//  Created by Chandler on 5/18/26.
//

import SwiftUI

@main
struct nexusApp: App {
    #if os(macOS)
        @FocusedValue(\.nexusSessionControllerIsTakeable) private var isSessionControllerTakeable
        @Environment(\.openSettings) private var openSettings

        @State private var appModel = {
            do {
                return try NexusAppModel.bootstrap()
            } catch {
                fatalError("Could not bootstrap Nexus background service: \(error)")
            }
        }()
        @State private var settingsTabSelection = NexusSettingsTabSelection()
    #else
        @State private var pairingModel = RemoteClientPairingModel.bootstrap()
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
                ContentView(appModel: appModel, settingsTabSelection: settingsTabSelection)
                    .frame(minWidth: 1100, minHeight: 760)
            #else
                RemoteClientHomeView(model: pairingModel)
            #endif
        }
        #if os(macOS)
            .defaultSize(width: 1460, height: 920)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("New Local Workspace") {
                        NotificationCenter.default.post(name: .nexusNewLocalWorkspace, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button("New Remote Workspace") {
                        NotificationCenter.default.post(name: .nexusNewRemoteWorkspace, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Divider()

                    Button("New Workspace Group") {
                        NotificationCenter.default.post(name: .nexusNewWorkspaceGroup, object: nil)
                    }
                }

                CommandMenu("Go") {
                    Button("Command Palette\u{2026}") {
                        NotificationCenter.default.post(name: .nexusOpenCommandPalette, object: nil)
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }

                CommandMenu("Remote") {
                    Button("Hosts\u{2026}") {
                        settingsTabSelection.tab = .hosts
                        openSettings()
                    }

                    Button("Remote Access\u{2026}") {
                        settingsTabSelection.tab = .remoteAccess
                        openSettings()
                    }
                }

                CommandMenu("Session") {
                    Button("Take Controller") {
                        NotificationCenter.default.post(name: .nexusTakeController, object: nil)
                    }
                    .disabled(isSessionControllerTakeable != true)
                }
            }
        #endif

        #if os(macOS)
            Settings {
                NexusSettingsRootView(appModel: appModel, tabSelection: settingsTabSelection)
            }
        #endif
    }
}
