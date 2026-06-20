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
        @State private var appModel = {
            do {
                return try NexusAppModel.bootstrap()
            } catch {
                fatalError("Could not bootstrap Nexus background service: \(error)")
            }
        }()
    #else
        @State private var pairingModel = RemoteClientPairingModel.bootstrap()
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
                ContentView(appModel: appModel)
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
                        NotificationCenter.default.post(name: .nexusShowHosts, object: nil)
                    }

                    Button("Remote Access\u{2026}") {
                        NotificationCenter.default.post(name: .nexusShowRemoteAccess, object: nil)
                    }
                }
            }
        #endif
    }
}
