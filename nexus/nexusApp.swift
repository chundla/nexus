//
//  nexusApp.swift
//  nexus
//
//  Created by Chandler on 5/18/26.
//

import SwiftUI

@main
struct nexusApp: App {
    @State private var appModel = {
        do {
            return try NexusAppModel.live()
        } catch {
            fatalError("Could not bootstrap Nexus background service: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
        }
    }
}
