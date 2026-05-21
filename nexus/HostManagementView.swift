import NexusDomain
import SwiftUI

struct HostManagementSheet: View {
    @Bindable var appModel: NexusAppModel
    @Binding var isPresented: Bool

    @State private var selection: UUID?
    @State private var editorMode: HostEditorMode?
    @State private var presentedError: HostManagementPresentedError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hosts")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create, edit, validate, and inspect remote Hosts.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
            }

            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    List(selection: $selection) {
                        ForEach(appModel.hosts) { host in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(host.name)
                                    .fontWeight(.medium)
                                Text(host.sshTarget)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(host.id))
                        }
                    }

                    HStack {
                        Button("New Host") {
                            editorMode = .create
                        }

                        Button("Edit") {
                            guard let host = selectedHost else {
                                return
                            }
                            editorMode = .edit(host)
                        }
                        .disabled(selectedHost == nil)
                    }
                }
                .frame(minWidth: 220)

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
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 420)
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
}

private struct HostDetailPanel: View {
    let host: NexusDomain.Host
    let detail: HostDetail?
    let onEdit: () -> Void
    let onValidate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(host.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(host.sshTarget)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Edit", action: onEdit)
                }

                LabeledContent("SSH Target", value: host.sshTarget)
                LabeledContent("Port", value: host.port.map(String.init) ?? "Default from SSH config")

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(validationStateTitle, systemImage: validationStateSymbol)
                            .foregroundStyle(validationStateColor)
                        Spacer()
                        Button(detail?.latestValidation == nil ? "Validate" : "Revalidate", action: onValidate)
                    }

                    Text(validationSummary)
                        .foregroundStyle(.secondary)

                    if let checkedAt = detail?.latestValidation?.checkedAt {
                        LabeledContent("Last Checked", value: checkedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if let diagnostics = detail?.latestValidation?.diagnostics, diagnostics.isEmpty == false {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diagnostics")
                            .font(.headline)

                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(diagnostic.message)
                                    .font(.callout)
                                Text(diagnostic.code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name", text: $name)
            TextField("SSH target or alias", text: $sshTarget)
            TextField("Port (optional)", text: $portText)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(mode.actionTitle) {
                    saveHost()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 380)
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
