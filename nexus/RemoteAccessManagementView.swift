#if os(macOS)
import SwiftUI

struct RemoteAccessManagementSheet: View {
    @Bindable var appModel: NexusAppModel
    @Binding var isPresented: Bool

    @State private var pendingRevocation: PairedDevice?
    @State private var presentedError: RemoteAccessPresentedError?

    var body: some View {
        ZStack {
            NexusBackdrop()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NexusSectionHeader(
                        eyebrow: "Remote client lane",
                        title: "Remote Access",
                        detail: "Enable Remote Access while Nexus is running, start first-time Pairing, and manage trusted Paired Devices."
                    )

                    Spacer()

                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        NexusStatusPill(
                            text: isEnabled ? "Enabled" : "Disabled",
                            color: isEnabled ? NexusMacTheme.teal : NexusMacTheme.gold
                        )
                        Spacer()
                    }

                    Text(isEnabled
                         ? "Remote Access is available while Nexus stays running on this Mac."
                         : "Enable Remote Access before starting first-time Pairing from iPhone.")
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.mutedText)

                    HStack {
                        Button(isEnabled ? "Disable Remote Access" : "Enable Remote Access") {
                            toggleRemoteAccess()
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())

                        if isEnabled {
                            Button("Start Pairing") {
                                startPairing()
                            }
                            .buttonStyle(NexusAccentButtonStyle())
                        }
                    }
                }
                .padding(20)
                .nexusPanel(tint: isEnabled ? NexusMacTheme.teal : NexusMacTheme.gold, radius: 22)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Pairing")
                        .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                        .foregroundStyle(.white)

                    if let pairing = appModel.remoteAccessState?.activePairing {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Use this code on iPhone to complete first-time Pairing.")
                                .font(NexusMacTheme.bodyFont(14))
                                .foregroundStyle(NexusMacTheme.mutedText)

                            Text(pairing.code)
                                .font(NexusMacTheme.monoFont(30, relativeTo: .largeTitle))
                                .foregroundStyle(.white)

                            if let remotePairingEndpoint = appModel.remotePairingEndpoint {
                                NexusInspectorRow(title: "Mac Address", value: remotePairingEndpoint.displayAddress)
                            }

                            NexusInspectorRow(title: "Expires", value: pairing.expiresAt.formatted(date: .omitted, time: .shortened))
                            NexusInspectorRow(title: "QR Payload", value: pairing.qrPayload)
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
                .padding(20)
                .nexusPanel(tint: NexusMacTheme.gold, radius: 22)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Paired Devices")
                        .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                        .foregroundStyle(.white)

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
                                            .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("Paired \(device.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                            .foregroundStyle(NexusMacTheme.mutedText)
                                    }

                                    Spacer()

                                    Button("Revoke") {
                                        pendingRevocation = device
                                    }
                                    .buttonStyle(NexusSecondaryButtonStyle())
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                        .frame(minHeight: 180)
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(20)
                .nexusPanel(tint: NexusMacTheme.coral, radius: 22)
            }
            .padding(24)
            .frame(minWidth: 720, minHeight: 560)
            .nexusPanel(tint: NexusMacTheme.teal, radius: 30)
            .padding(28)
        }
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
#endif
