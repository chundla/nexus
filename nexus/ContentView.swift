//
//  ContentView.swift
//  nexus
//
//  Created by Chandler on 5/18/26.
//

import NexusDomain
import SwiftUI

struct ContentView: View {
    @Bindable var appModel: NexusAppModel

    var body: some View {
        NavigationSplitView {
            List {
                Label("Background Service", systemImage: "server.rack")
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
#endif
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nexus Service Status")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let serviceStatus = appModel.serviceStatus {
                    LabeledContent("State", value: serviceStatus.state.rawValue)
                    LabeledContent("Store", value: serviceStatus.store.kind.rawValue)
                    LabeledContent("Owner", value: serviceStatus.store.owner.rawValue)
                    LabeledContent("Location", value: serviceStatus.store.location.path(percentEncoded: false))
                } else if let serviceErrorMessage = appModel.serviceErrorMessage {
                    ContentUnavailableView("Background Service unavailable", systemImage: "exclamationmark.triangle", description: Text(serviceErrorMessage))
                } else {
                    Text("Loading service status…")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Status") {
                    Task {
                        await appModel.refreshServiceStatus()
                    }
                }
            }
            .padding()
            .task {
                if appModel.serviceStatus == nil {
                    await appModel.refreshServiceStatus()
                }
            }
        }
    }
}

#Preview {
    ContentView(appModel: try! .live())
}
