#if os(iOS)
import SwiftUI

struct RemoteClientHomeView: View {
    @Bindable var model: RemoteClientPairingModel

    @State private var isShowingPairingForm = false
    @State private var isPairing = false
    @State private var presentedError: RemoteClientHomePresentedError?

    var body: some View {
        NavigationStack {
            List {
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
                    Text("Pairing now stores durable trust and the default reconnect Mac. Discovery, workspace browsing, and Session control arrive in follow-on issues.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        } catch {
            presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
        }
    }

    private func forgetPairedMac(_ pairedMac: PairedMac) {
        do {
            try model.forgetPairedMac(id: pairedMac.id)
        } catch {
            presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
        }
    }
}

private struct RemoteClientHomePresentedError: Identifiable {
    let id = UUID()
    let message: String
}
#endif
