import SwiftUI

struct RemoteAccessManagementSheet: View {
    @Bindable var appModel: NexusAppModel
    @Binding var isPresented: Bool

    @State private var pendingRevocation: PairedDevice?
    @State private var presentedError: RemoteAccessPresentedError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote Access")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Enable Remote Access while Nexus is running, start first-time Pairing, and manage trusted Paired Devices.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
            }

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        isEnabled ? "Enabled" : "Disabled",
                        systemImage: isEnabled ? "dot.radiowaves.left.and.right" : "slash.circle"
                    )
                    .foregroundStyle(isEnabled ? .green : .secondary)

                    Text(isEnabled
                         ? "Remote Access is available while Nexus stays running on this Mac."
                         : "Enable Remote Access before starting first-time Pairing from iPhone.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(isEnabled ? "Disable Remote Access" : "Enable Remote Access") {
                            toggleRemoteAccess()
                        }

                        if isEnabled {
                            Button("Start Pairing") {
                                startPairing()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Pairing") {
                if let pairing = appModel.remoteAccessState?.activePairing {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use this code on iPhone to complete first-time Pairing.")
                            .foregroundStyle(.secondary)

                        Text(pairing.code)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))

                        if let remotePairingEndpoint = appModel.remotePairingEndpoint {
                            LabeledContent("Mac Address", value: remotePairingEndpoint.displayAddress)
                                .font(.caption)
                        }

                        LabeledContent("Expires", value: pairing.expiresAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)

                        Text(pairing.qrPayload)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "No active Pairing",
                        systemImage: "iphone.gen3.radiowaves.left.and.right",
                        description: Text(isEnabled ? "Start Pairing to generate a new code for iPhone." : "Enable Remote Access to start Pairing.")
                    )
                }
            }

            GroupBox("Paired Devices") {
                if appModel.pairedDevices.isEmpty {
                    ContentUnavailableView(
                        "No Paired Devices",
                        systemImage: "iphone.slash",
                        description: Text("Trusted iPhones will appear here after successful Pairing.")
                    )
                } else {
                    List {
                        ForEach(appModel.pairedDevices) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .fontWeight(.medium)
                                    Text("Paired \(device.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Revoke", role: .destructive) {
                                    pendingRevocation = device
                                }
                            }
                        }
                    }
                    .frame(minHeight: 180)
                }
            }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 520)
        .task {
            do {
                try await appModel.refreshRemoteAccess()
            } catch {
                presentedError = RemoteAccessPresentedError(message: error.localizedDescription)
            }
        }
        .confirmationDialog(
            "Revoke Paired Device?",
            isPresented: Binding(
                get: { pendingRevocation != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingRevocation = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingRevocation
        ) { device in
            Button("Revoke \(device.name)", role: .destructive) {
                pendingRevocation = nil
                revokePairedDevice(device)
            }
        } message: { device in
            Text("\(device.name) will need to repeat first-time Pairing before reconnecting.")
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("Remote Access"), message: Text(error.message))
        }
    }

    private var isEnabled: Bool {
        appModel.remoteAccessState?.isEnabled == true
    }

    private func toggleRemoteAccess() {
        Task {
            do {
                _ = try await appModel.setRemoteAccessEnabled(isEnabled == false)
            } catch {
                presentedError = RemoteAccessPresentedError(message: error.localizedDescription)
            }
        }
    }

    private func startPairing() {
        Task {
            do {
                _ = try await appModel.startPairing()
            } catch {
                presentedError = RemoteAccessPresentedError(message: error.localizedDescription)
            }
        }
    }

    private func revokePairedDevice(_ device: PairedDevice) {
        Task {
            do {
                _ = try await appModel.revokePairedDevice(deviceID: device.id)
            } catch {
                presentedError = RemoteAccessPresentedError(message: error.localizedDescription)
            }
        }
    }
}

private struct RemoteAccessPresentedError: Identifiable {
    let id = UUID()
    let message: String
}
