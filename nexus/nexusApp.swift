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
            return try NexusAppModel.live(listeningPort: NexusAppModel.appBootstrapListeningPort())
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
#else
            RemoteClientHomeView(model: pairingModel)
#endif
        }
    }
}
