#if os(iOS)
import NexusDomain
import SwiftUI

struct RemoteClientHomeView: View {
    @Bindable var model: RemoteClientPairingModel

    @State private var isShowingPairingForm = false
    @State private var isPairing = false
    @State private var isRefreshingAvailability = false
    @State private var presentedError: RemoteClientHomePresentedError?

    var body: some View {
        NavigationStack {
            List {
                if let activePairedMac = model.activePairedMac {
                    Section("Active Paired Mac") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activePairedMac.name)
                                .font(.headline)
                            Text(model.availability(for: activePairedMac).summary)
                                .font(.subheadline)
                                .foregroundStyle(availabilityColor(for: activePairedMac))
                            Text("\(activePairedMac.host):\(activePairedMac.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if model.pairedMacs.isEmpty == false {
                    Section("Paired Macs") {
                        ForEach(model.pairedMacs) { pairedMac in
                            Button {
                                selectActivePairedMac(pairedMac)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pairedMac.name)
                                            .fontWeight(.medium)
                                        Text(model.availability(for: pairedMac).summary)
                                            .font(.caption)
                                            .foregroundStyle(availabilityColor(for: pairedMac))
                                        Text("\(pairedMac.host):\(pairedMac.port)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Paired \(pairedMac.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 12)

                                    if model.activePairedMac?.id == pairedMac.id {
                                        Label("Current", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Forget", role: .destructive) {
                                    forgetPairedMac(pairedMac)
                                }
                            }
                        }
                    }
                }

                if let catalog = model.catalog {
                    if catalog.recentNavigation.isEmpty == false {
                        Section("Recent") {
                            ForEach(catalog.recentNavigation) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .fontWeight(.medium)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    ForEach(catalog.workspaceGroups) { group in
                        let overviews = workspaceOverviews(in: group, catalog: catalog)
                        if overviews.isEmpty == false {
                            Section(group.name) {
                                ForEach(overviews, id: \.workspace.id) { overview in
                                    workspaceOverviewRow(overview)
                                }
                            }
                        }
                    }
                } else if let activePairedMac = model.activePairedMac,
                          model.availability(for: activePairedMac) == .available {
                    Section("Workspace Catalog") {
                        Text(model.catalogErrorMessage ?? "Loading Workspaces…")
                            .font(.footnote)
                            .foregroundStyle(model.catalogErrorMessage == nil ? .secondary : .orange)
                    }
                }

                if model.pairedMacs.isEmpty || isShowingPairingForm {
                    Section("Pair a Mac") {
                        TextField("Mac Address", text: $model.macHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Port", text: $model.macPort)
                            .keyboardType(.numberPad)
                        TextField("Pairing Code", text: $model.pairingCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("This iPhone's Name", text: $model.deviceName)

                        Button(isPairing ? "Pairing…" : "Complete Pairing") {
                            completePairing()
                        }
                        .disabled(isPairing)
                    }
                } else {
                    Section {
                        Button("Pair Another Mac") {
                            isShowingPairingForm = true
                        }
                    }
                }

                Section("What’s Next") {
                    Text("Trusted Macs now reconnect into a summary-first Workspace catalog. Detailed Session actions arrive in follow-on issues.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .refreshable {
                await refreshAvailability()
            }
            .task(id: availabilityRefreshID) {
                await refreshAvailability()
            }
            .navigationTitle("Nexus Remote")
            .toolbar {
                if model.pairedMacs.isEmpty == false, isShowingPairingForm {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingPairingForm = false
                        }
                    }
                }
            }
        }
        .onAppear {
            if model.pairedMacs.isEmpty {
                isShowingPairingForm = true
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("Nexus Remote"), message: Text(error.message))
        }
    }

    private func completePairing() {
        isPairing = true
        Task {
            defer { isPairing = false }

            do {
                try await model.completePairing()
                await refreshAvailability()
                model.pairingCode = ""
                isShowingPairingForm = false
            } catch {
                presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
            }
        }
    }

    private func selectActivePairedMac(_ pairedMac: PairedMac) {
        do {
            try model.selectActivePairedMac(id: pairedMac.id)
            Task {
                await refreshAvailability()
            }
        } catch {
            presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
        }
    }

    private func forgetPairedMac(_ pairedMac: PairedMac) {
        do {
            try model.forgetPairedMac(id: pairedMac.id)
            Task {
                await refreshAvailability()
            }
        } catch {
            presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
        }
    }

    private var availabilityRefreshID: String {
        model.pairedMacs.map(\.id).joined(separator: "|") + "::" + (model.activePairedMacID ?? "")
    }

    private func refreshAvailability() async {
        guard model.pairedMacs.isEmpty == false, isRefreshingAvailability == false else {
            return
        }

        isRefreshingAvailability = true
        defer { isRefreshingAvailability = false }
        await model.refreshPairedMacAvailability()

        if let activePairedMac = model.activePairedMac,
           model.availability(for: activePairedMac) == .available {
            await model.refreshActivePairedMacCatalog()
        } else {
            model.catalog = nil
            model.catalogErrorMessage = nil
        }
    }

    @ViewBuilder
    private func workspaceOverviewRow(_ overview: WorkspaceOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(overview.workspace.name)
                .font(.headline)
            Text(workspaceTargetSummary(for: overview))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(overview.providerCards) { providerCard in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(providerCard.provider.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if providerCard.alternateSessionCount > 0 {
                            Text("\(providerCard.alternateSessionCount) named")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(providerCard.health.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(providerCard.defaultSession.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func workspaceOverviews(in group: WorkspaceGroup, catalog: RemoteWorkspaceCatalog) -> [WorkspaceOverview] {
        catalog.workspaceOverviews.filter { $0.workspace.primaryGroupID == group.id }
    }

    private func workspaceTargetSummary(for overview: WorkspaceOverview) -> String {
        overview.remoteTarget.map { "\($0.host.name) • \(overview.workspace.folderPath)" } ?? overview.workspace.folderPath
    }

    private func availabilityColor(for pairedMac: PairedMac) -> Color {
        switch model.availability(for: pairedMac) {
        case .available:
            .green
        case .unavailable:
            .orange
        case .unknown:
            .secondary
        }
    }
}

private struct RemoteClientHomePresentedError: Identifiable {
    let id = UUID()
    let message: String
}
#endif
