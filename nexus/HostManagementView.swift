#if os(macOS)
    import NexusDomain
    import SwiftUI

    struct HostManagementSheet: View {
        @Bindable var appModel: NexusAppModel
        @Binding var isPresented: Bool

        @State private var selection: UUID?
        @State private var editorMode: HostEditorMode?
        @State private var pendingDeletionHost: NexusDomain.Host?
        @State private var presentedError: HostManagementPresentedError?

        var body: some View {
            ZStack {
                NexusBackdrop()

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        NexusSectionHeader(
                            eyebrow: "Remote catalog",
                            title: "Hosts",
                            detail: "Create, edit, validate, and inspect the remote Hosts that power Nexus workspaces."
                        )

                        Spacer()

                        Button("Done") {
                            isPresented = false
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())
                    }

                    HSplitView {
                        VStack(alignment: .leading, spacing: 12) {
                            List(selection: $selection) {
                                ForEach(appModel.hosts) { host in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(host.name)
                                            .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                                            .foregroundStyle(NexusMacTheme.textPrimary)
                                        Text(host.sshTarget)
                                            .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                            .foregroundStyle(NexusMacTheme.mutedText)
                                    }
                                    .padding(.vertical, 4)
                                    .tag(Optional(host.id))
                                    .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.sidebar)
                            .scrollContentBackground(.hidden)
                            .nexusPanel(tint: NexusMacTheme.gold, radius: 18)

                            HStack {
                                Button("New Host") {
                                    editorMode = .create
                                }
                                .buttonStyle(NexusAccentButtonStyle())

                                Button("Edit") {
                                    guard let host = selectedHost else {
                                        return
                                    }
                                    editorMode = .edit(host)
                                }
                                .buttonStyle(NexusSecondaryButtonStyle())
                                .disabled(selectedHost == nil)

                                Button("Delete") {
                                    pendingDeletionHost = selectedHost
                                }
                                .buttonStyle(NexusSecondaryButtonStyle())
                                .disabled(selectedHost == nil)
                            }
                        }
                        .frame(minWidth: 240)

                        Group {
                            if let host = selectedHost {
                                HostDetailPanel(
                                    host: host,
                                    detail: appModel.hostDetail(for: host.id),
                                    onEdit: {
                                        editorMode = .edit(host)
                                    },
                                    onValidate: validateSelectedHost
                                )
                            } else {
                                ContentUnavailableView(
                                    "No Host selected",
                                    systemImage: "network",
                                    description: Text("Create a Host or select an existing one to inspect diagnostics.")
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .nexusPanel(tint: NexusMacTheme.teal)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(24)
                .frame(minWidth: 820, minHeight: 480)
                .nexusPanel(tint: NexusMacTheme.teal, radius: 30)
                .padding(28)
            }
            .task {
                if selection == nil {
                    selection = appModel.hosts.first?.id
                }
            }
            .task(id: appModel.hosts.map(\.id)) {
                if appModel.hosts.contains(where: { $0.id == selection }) == false {
                    selection = appModel.hosts.first?.id
                }
            }
            .task(id: selection) {
                guard let selection, appModel.hostDetail(for: selection) == nil else {
                    return
                }

                do {
                    try await appModel.loadHostDetail(hostID: selection)
                } catch {
                    presentedError = HostManagementPresentedError(message: error.localizedDescription)
                }
            }
            .sheet(item: $editorMode) { mode in
                HostEditorSheet(
                    appModel: appModel,
                    mode: mode,
                    selection: $selection,
                    onError: { presentedError = HostManagementPresentedError(message: $0.localizedDescription) }
                )
            }
            .confirmationDialog(
                "Delete Host?",
                isPresented: Binding(
                    get: { pendingDeletionHost != nil },
                    set: { isPresented in
                        if isPresented == false {
                            pendingDeletionHost = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletionHost
            ) { host in
                Button("Delete \(host.name)", role: .destructive) {
                    pendingDeletionHost = nil
                    deleteHost(host)
                }
            } message: { host in
                Text("This removes \(host.name) from the saved Host catalog.")
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("Hosts"), message: Text(error.message))
            }
        }

        private var selectedHost: NexusDomain.Host? {
            guard let selection else {
                return nil
            }

            return appModel.hosts.first(where: { $0.id == selection })
        }

        private func validateSelectedHost() {
            guard let hostID = selection else {
                return
            }

            Task {
                do {
                    _ = try await appModel.validateHost(hostID: hostID)
                } catch {
                    presentedError = HostManagementPresentedError(message: error.localizedDescription)
                }
            }
        }

        private func deleteHost(_ host: NexusDomain.Host) {
            Task {
                do {
                    _ = try await appModel.deleteHost(hostID: host.id)
                } catch {
                    presentedError = HostManagementPresentedError(message: error.localizedDescription)
                }
            }
        }
    }

    private struct HostDetailPanel: View {
        let host: NexusDomain.Host
        let detail: HostDetail?
        let onEdit: () -> Void
        let onValidate: () -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(host.name)
                                .font(NexusMacTheme.displayFont(26, relativeTo: .title2))
                                .foregroundStyle(NexusMacTheme.textPrimary)
                            Text(host.sshTarget)
                                .font(NexusMacTheme.bodyFont(14))
                                .foregroundStyle(NexusMacTheme.mutedText)
                        }

                        Spacer()

                        Button("Edit", action: onEdit)
                            .buttonStyle(NexusSecondaryButtonStyle())
                    }

                    NexusInspectorRow(title: "SSH Target", value: host.sshTarget)
                    NexusInspectorRow(title: "Port", value: host.port.map(String.init) ?? "Default from SSH config")

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            NexusStatusPill(text: validationStateTitle, color: validationStateColor)
                            Spacer()
                            Button(detail?.latestValidation == nil ? "Validate" : "Revalidate", action: onValidate)
                                .buttonStyle(NexusAccentButtonStyle())
                        }

                        Text(validationSummary)
                            .font(NexusMacTheme.bodyFont(14))
                            .foregroundStyle(NexusMacTheme.mutedText)

                        if let checkedAt = detail?.latestValidation?.checkedAt {
                            NexusInspectorRow(
                                title: "Last Checked", value: checkedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(18)
                    .nexusPanel(tint: validationStateColor, radius: 18)

                    if let diagnostics = detail?.latestValidation?.diagnostics, diagnostics.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diagnostics")
                                .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                .foregroundStyle(NexusMacTheme.textPrimary)

                            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(diagnostic.message)
                                        .font(NexusMacTheme.bodyFont(14))
                                        .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.9))
                                    Text(diagnostic.code)
                                        .font(NexusMacTheme.monoFont(11, relativeTo: .caption))
                                        .foregroundStyle(NexusMacTheme.mutedText)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .nexusPanel(tint: validationStateColor, radius: 16)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .nexusPanel(tint: NexusMacTheme.teal, radius: 22)
            }
        }

        private var validationState: HostValidationSnapshot.State? {
            detail?.latestValidation?.state
        }

        private var validationStateTitle: String {
            switch validationState {
            case .available:
                "Available"
            case .unavailable:
                "Unavailable"
            case .broken:
                "Broken"
            case .notChecked, .none:
                "Not checked"
            }
        }

        private var validationStateSymbol: String {
            switch validationState {
            case .available:
                "checkmark.circle"
            case .unavailable:
                "wifi.exclamationmark"
            case .broken:
                "exclamationmark.triangle"
            case .notChecked, .none:
                "clock"
            }
        }

        private var validationStateColor: Color {
            switch validationState {
            case .available:
                .green
            case .unavailable:
                .orange
            case .broken:
                .red
            case .notChecked, .none:
                .secondary
            }
        }

        private var validationSummary: String {
            detail?.latestValidation?.summary ?? "Validate this Host to confirm SSH reachability and tmux support."
        }
    }

    private struct HostEditorSheet: View {
        @Environment(\.dismiss) private var dismiss

        @Bindable var appModel: NexusAppModel
        let mode: HostEditorMode
        @Binding var selection: UUID?
        let onError: (Error) -> Void

        @State private var name: String
        @State private var sshTarget: String
        @State private var portText: String

        init(
            appModel: NexusAppModel,
            mode: HostEditorMode,
            selection: Binding<UUID?>,
            onError: @escaping (Error) -> Void
        ) {
            self.appModel = appModel
            self.mode = mode
            self._selection = selection
            self.onError = onError

            switch mode {
            case .create:
                _name = State(initialValue: "")
                _sshTarget = State(initialValue: "")
                _portText = State(initialValue: "")
            case .edit(let host):
                _name = State(initialValue: host.name)
                _sshTarget = State(initialValue: host.sshTarget)
                _portText = State(initialValue: host.port.map(String.init) ?? "")
            }
        }

        var body: some View {
            ZStack {
                NexusBackdrop()

                VStack(alignment: .leading, spacing: 16) {
                    NexusSectionHeader(
                        eyebrow: "Host editor",
                        title: mode.title,
                        detail:
                            "Save the SSH identity Nexus should use for remote validation and remote workspace execution."
                    )

                    TextField("Name", text: $name)
                    TextField("SSH target or alias", text: $sshTarget)
                    TextField("Port (optional)", text: $portText)

                    HStack {
                        Spacer()

                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())

                        Button(mode.actionTitle) {
                            saveHost()
                        }
                        .buttonStyle(NexusAccentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .frame(minWidth: 420)
                .nexusPanel(tint: NexusMacTheme.gold, radius: 28)
                .padding(28)
            }
        }

        private func saveHost() {
            Task {
                do {
                    let host = try await persistHost()
                    selection = host.id
                    dismiss()
                } catch {
                    onError(error)
                }
            }
        }

        private func persistHost() async throws -> NexusDomain.Host {
            let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = trimmedPort.isEmpty ? nil : Int(trimmedPort)

            switch mode {
            case .create:
                return try await appModel.createHost(name: name, sshTarget: sshTarget, port: port)
            case .edit(let host):
                return try await appModel.updateHost(hostID: host.id, name: name, sshTarget: sshTarget, port: port)
            }
        }
    }

    private enum HostEditorMode: Identifiable {
        case create
        case edit(NexusDomain.Host)

        var id: String {
            switch self {
            case .create:
                "create"
            case .edit(let host):
                "edit-\(host.id.uuidString)"
            }
        }

        var title: String {
            switch self {
            case .create:
                "New Host"
            case .edit:
                "Edit Host"
            }
        }

        var actionTitle: String {
            switch self {
            case .create:
                "Create"
            case .edit:
                "Save"
            }
        }
    }

    private struct HostManagementPresentedError: Identifiable {
        let id = UUID()
        let message: String
    }
#endif
