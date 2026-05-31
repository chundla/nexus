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
        if NexusBenchmarkScenario.macOSScenario(from: ProcessInfo.processInfo.environment) != nil {
            return NexusAppModel.placeholderBenchmarkModel()
        }

        do {
            return try NexusAppModel.live(listeningPort: NexusAppModel.appBootstrapListeningPort())
        } catch {
            fatalError("Could not bootstrap Nexus background service: \(error)")
        }
    }()

    private let benchmarkScenario = NexusBenchmarkScenario.macOSScenario(from: ProcessInfo.processInfo.environment)
#else
    @State private var pairingModel = RemoteClientPairingModel(
        client: RemotePairingHTTPClient(),
        store: UserDefaultsPairedMacStore()
    )

    private let benchmarkScenario = NexusBenchmarkScenario.iOSScenario(from: ProcessInfo.processInfo.environment)
#endif

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            if let benchmarkScenario {
                NexusMacBenchmarkHostView(scenario: benchmarkScenario)
            } else {
                ContentView(appModel: appModel)
            }
#else
            if let benchmarkScenario {
                NexusRemoteBenchmarkHostView(scenario: benchmarkScenario)
            } else {
                RemoteClientHomeView(model: pairingModel)
            }
#endif
        }
    }
}
