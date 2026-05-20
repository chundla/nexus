import AppKit
import NexusDomain
import SwiftUI

struct ContentView: View {
    @Bindable var appModel: NexusAppModel

    @State private var selection: SidebarSelection?
    @State private var isShowingCreateWorkspaceGroupSheet = false
    @State private var newWorkspaceGroupName = ""
    @State private var pendingWorkspaceFolderPath: String?
    @State private var pendingWorkspaceGroupID: UUID?
    @State private var isShowingWorkspaceGroupPicker = false
    @State private var terminalViewportSize: CGSize = .zero
    @State private var terminalFocusToken = UUID()
    @State private var presentedError: PresentedError?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace Groups") {
                    ForEach(appModel.workspaceGroups) { group in
                        Label(group.name, systemImage: "folder.badge.plus")
                            .tag(SidebarSelection.workspaceGroup(group.id))
                    }
                }

                Section("Workspaces") {
                    ForEach(appModel.workspaces) { workspace in
                        Label(workspace.name, systemImage: "folder")
                            .tag(SidebarSelection.workspace(workspace.id))
                    }
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
#endif
            .toolbar {
                ToolbarItemGroup {
                    Button("New Workspace Group") {
                        newWorkspaceGroupName = ""
                        isShowingCreateWorkspaceGroupSheet = true
                    }

                    Button("Add Local Workspace") {
                        addLocalWorkspace()
                    }
                }
            }
        } detail: {
            detailView
                .padding()
        }
        .task {
            if appModel.serviceStatus == nil, appModel.serviceErrorMessage == nil {
                await appModel.refresh()
            }
        }
        .sheet(isPresented: $isShowingCreateWorkspaceGroupSheet) {
            createWorkspaceGroupSheet
        }
        .sheet(isPresented: $isShowingWorkspaceGroupPicker) {
            workspaceGroupPickerSheet
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("Nexus"), message: Text(error.message))
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let selection {
            switch selection {
            case .workspaceGroup(let groupID):
                workspaceGroupDetail(groupID: groupID)
            case .workspace(let workspaceID):
                workspaceDetail(workspaceID: workspaceID)
            case .session(let sessionID):
                sessionDetail(sessionID: sessionID)
            }
        } else {
            overviewDetail
        }
    }

    private var overviewDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nexus")
                .font(.title2)
                .fontWeight(.semibold)

            if let serviceStatus = appModel.serviceStatus {
                LabeledContent("Background Service", value: serviceStatus.state.rawValue)
                LabeledContent("Store", value: serviceStatus.store.location.path(percentEncoded: false))
                LabeledContent("Workspace Groups", value: "\(appModel.workspaceGroups.count)")
                LabeledContent("Workspaces", value: "\(appModel.workspaces.count)")
            } else if let serviceErrorMessage = appModel.serviceErrorMessage {
                ContentUnavailableView(
                    "Background Service unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(serviceErrorMessage)
                )
            } else {
                Text("Loading Nexus…")
                    .foregroundStyle(.secondary)
            }

            Button("Refresh") {
                Task {
                    await appModel.refresh()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func workspaceGroupDetail(groupID: UUID) -> some View {
        let group = appModel.workspaceGroups.first(where: { $0.id == groupID })
        let workspaces = appModel.workspaces.filter { $0.primaryGroupID == groupID }

        return VStack(alignment: .leading, spacing: 16) {
            Text(group?.name ?? "Workspace Group")
                .font(.title2)
                .fontWeight(.semibold)

            if workspaces.isEmpty {
                Text("No Workspaces in this group yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workspaces) { workspace in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.name)
                            .fontWeight(.medium)
                        Text(workspace.folderPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func workspaceDetail(workspaceID: UUID) -> some View {
        let workspace = appModel.workspaces.first(where: { $0.id == workspaceID })
        let overview = appModel.workspaceOverview(for: workspaceID)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(workspace?.name ?? "Workspace")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let workspace {
                    LabeledContent("Kind", value: workspace.kind.rawValue)
                    LabeledContent("Folder", value: workspace.folderPath)
                    LabeledContent("Primary Group", value: appModel.workspaceGroupName(for: workspace.primaryGroupID) ?? workspace.primaryGroupID.uuidString)

                    Divider()

                    Text("Providers")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let overview {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(overview.providerCards) { card in
                                providerCard(workspaceID: workspace.id, card: card)
                            }
                        }
                    } else {
                        Text("Loading provider overview…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Workspace not found.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sessionDetail(sessionID: UUID) -> some View {
        let screen = appModel.focusedSessionScreen?.session.id == sessionID ? appModel.focusedSessionScreen : nil

        return VStack(alignment: .leading, spacing: 16) {
            if let screen {
                let isReady = screen.session.state == .ready

                Text("\(screen.session.providerID.displayName) Session")
                    .font(.title2)
                    .fontWeight(.semibold)

                Label(screen.session.state.rawValue.capitalized, systemImage: isReady ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(isReady ? Color.secondary : Color.orange)

                Text("Terminal: \(screen.terminalColumns) × \(screen.terminalRows)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(screen.visibleLines.enumerated()), id: \.offset) { index, line in
                            Text(renderedTerminalLine(line, row: index, screen: screen))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                terminalViewportSize = proxy.size
                                reportTerminalSize(proxy.size)
                                if isReady {
                                    terminalFocusToken = UUID()
                                }
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                terminalViewportSize = newSize
                                reportTerminalSize(newSize)
                            }
                    }
                }
                .background {
                    SessionTerminalKeyCaptureView(
                        isEnabled: isReady,
                        focusToken: terminalFocusToken,
                        onText: handleTerminalTypedText,
                        onKey: handleTerminalInputKey
                    )
                    .frame(width: 0, height: 0)
                }
                .onTapGesture {
                    terminalFocusToken = UUID()
                }

                if isReady == false {
                    Button("Relaunch Session") {
                        Task {
                            do {
                                let session = try await appModel.relaunchFocusedSession()
                                selection = .session(session.id)
                            } catch {
                                presentedError = PresentedError(message: error.localizedDescription)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Session unavailable",
                    systemImage: "terminal",
                    description: Text("Launch or resume the session from a Workspace provider card.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: sessionID) {
            await pollSessionScreen(sessionID: sessionID)
        }
    }

    private func providerCard(workspaceID: UUID, card: WorkspaceProviderCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.provider.displayName)
                .font(.headline)

            Label(card.health.state.rawValue.replacingOccurrences(of: "Checked", with: " checked"), systemImage: "waveform.path.ecg")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(card.health.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let version = card.health.version {
                LabeledContent("Version", value: version)
                    .font(.caption)
            }

            if let resolvedExecutable = card.health.resolvedExecutable {
                LabeledContent("Executable", value: resolvedExecutable)
                    .font(.caption)
            }

            if card.health.diagnostics.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(card.health.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Text(diagnostic.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Session")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(card.defaultSession.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(card.defaultSession.actionTitle) {
                Task {
                    do {
                        let session = try await appModel.launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: card.provider.id)
                        selection = .session(session.id)
                    } catch {
                        presentedError = PresentedError(message: error.localizedDescription)
                    }
                }
            }
            .disabled(card.provider.id != .claude)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var createWorkspaceGroupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workspace Group")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name", text: $newWorkspaceGroupName)

            HStack {
                Spacer()

                Button("Cancel") {
                    isShowingCreateWorkspaceGroupSheet = false
                }

                Button("Create") {
                    let name = newWorkspaceGroupName
                    Task {
                        do {
                            let group = try await appModel.createWorkspaceGroup(name: name)
                            selection = .workspaceGroup(group.id)
                            isShowingCreateWorkspaceGroupSheet = false
                        } catch {
                            presentedError = PresentedError(message: error.localizedDescription)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }

    private var workspaceGroupPickerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Primary Workspace Group")
                .font(.title3)
                .fontWeight(.semibold)

            Picker("Workspace Group", selection: Binding(get: {
                pendingWorkspaceGroupID ?? appModel.workspaceGroups.first?.id ?? UUID()
            }, set: { pendingWorkspaceGroupID = $0 })) {
                ForEach(appModel.workspaceGroups) { group in
                    Text(group.name).tag(group.id)
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Spacer()

                Button("Cancel") {
                    pendingWorkspaceFolderPath = nil
                    pendingWorkspaceGroupID = nil
                    isShowingWorkspaceGroupPicker = false
                }

                Button("Add Workspace") {
                    guard let folderPath = pendingWorkspaceFolderPath else {
                        return
                    }

                    let groupID = pendingWorkspaceGroupID
                    Task {
                        do {
                            let workspace = try await appModel.createLocalWorkspace(folderPath: folderPath, primaryGroupID: groupID)
                            selection = .workspace(workspace.id)
                            pendingWorkspaceFolderPath = nil
                            pendingWorkspaceGroupID = nil
                            isShowingWorkspaceGroupPicker = false
                        } catch {
                            presentedError = PresentedError(message: error.localizedDescription)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }

    private func addLocalWorkspace() {
        guard appModel.workspaceGroups.isEmpty == false else {
            presentedError = PresentedError(message: "Create a Workspace Group before adding a Workspace")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Workspace"
        panel.message = "Choose a local folder for the Workspace"

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        let folderPath = folderURL.path(percentEncoded: false)
        if appModel.workspaceGroups.count == 1 {
            Task {
                do {
                    let workspace = try await appModel.createLocalWorkspace(folderPath: folderPath, primaryGroupID: nil)
                    selection = .workspace(workspace.id)
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            return
        }

        pendingWorkspaceFolderPath = folderPath
        pendingWorkspaceGroupID = appModel.workspaceGroups.first?.id
        isShowingWorkspaceGroupPicker = true
    }

    private func handleTerminalTypedText(_ text: String) {
        Task {
            do {
                try await appModel.sendTypedTextToFocusedSession(text)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func handleTerminalInputKey(_ key: SessionInputKey) {
        Task {
            do {
                try await appModel.sendInputKeyToFocusedSession(key)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func renderedTerminalLine(_ line: String, row: Int, screen: SessionScreen) -> String {
        guard screen.cursorVisible, row == screen.cursorRow else {
            return line.isEmpty ? " " : line
        }

        let clampedColumn = max(0, min(screen.cursorColumn, line.count))
        let insertionIndex = line.index(line.startIndex, offsetBy: clampedColumn)
        let withCursor = String(line[..<insertionIndex]) + "█" + String(line[insertionIndex...])
        return withCursor.isEmpty ? "█" : withCursor
    }

    private func reportTerminalSize(_ size: CGSize) {
        guard appModel.focusedSessionScreen?.session.state == .ready else {
            return
        }

        let columns = max(40, Int(size.width / 8))
        let rows = max(12, Int(size.height / 18))
        guard columns > 0, rows > 0 else {
            return
        }

        if let screen = appModel.focusedSessionScreen,
           screen.terminalColumns == columns,
           screen.terminalRows == rows {
            return
        }

        Task {
            do {
                try await appModel.resizeFocusedSession(columns: columns, rows: rows)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func pollSessionScreen(sessionID: UUID) async {
        while Task.isCancelled == false,
              case .session(sessionID) = selection {
            do {
                try await appModel.loadSessionScreen(sessionID: sessionID)
            } catch {
                if Task.isCancelled {
                    return
                }
                presentedError = PresentedError(message: error.localizedDescription)
                return
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

private enum SidebarSelection: Hashable {
    case workspaceGroup(UUID)
    case workspace(UUID)
    case session(UUID)
}

private struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

enum SessionTerminalCapturedInput: Equatable {
    case text(String)
    case key(SessionInputKey)
}

func mapSessionTerminalInput(
    modifierFlags: NSEvent.ModifierFlags,
    keyCode: UInt16,
    characters: String?,
    charactersIgnoringModifiers: String?
) -> SessionTerminalCapturedInput? {
    let nonShiftModifiers = modifierFlags.intersection([.command, .control, .option])

    if nonShiftModifiers == .control,
       let controlCharacter = charactersIgnoringModifiers?.lowercased(),
       controlCharacter.count == 1,
       let scalar = controlCharacter.unicodeScalars.first,
       scalar.value >= 0x61,
       scalar.value <= 0x7A {
        switch controlCharacter {
        case "c":
            return .key(.interrupt)
        case "d":
            return .key(.endOfTransmission)
        default:
            guard let controlScalar = UnicodeScalar(scalar.value - 0x60) else {
                return nil
            }
            return .text(String(controlScalar))
        }
    }

    if nonShiftModifiers.isEmpty == false {
        return nil
    }

    switch keyCode {
    case 51:
        return .key(.backspace)
    case 53:
        return .key(.escape)
    case 115:
        return .key(.home)
    case 117:
        return .key(.deleteForward)
    case 119:
        return .key(.end)
    case 123:
        return .key(.leftArrow)
    case 124:
        return .key(.rightArrow)
    case 125:
        return .key(.downArrow)
    case 126:
        return .key(.upArrow)
    default:
        break
    }

    guard let characters else {
        return nil
    }

    switch characters {
    case "\r", "\n":
        return .key(.enter)
    case "\t":
        return .key(.tab)
    case "\u{001B}":
        return .key(.escape)
    default:
        let printableScalars = characters.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        guard printableScalars.isEmpty == false else {
            return nil
        }
        return .text(String(String.UnicodeScalarView(printableScalars)))
    }
}

private struct SessionTerminalKeyCaptureView: NSViewRepresentable {
    let isEnabled: Bool
    let focusToken: UUID
    let onText: (String) -> Void
    let onKey: (SessionInputKey) -> Void

    func makeNSView(context: Context) -> SessionTerminalKeyCaptureNSView {
        let view = SessionTerminalKeyCaptureNSView()
        view.onText = onText
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: SessionTerminalKeyCaptureNSView, context: Context) {
        nsView.onText = onText
        nsView.onKey = onKey
        nsView.isEnabled = isEnabled
        nsView.focusToken = focusToken
        nsView.focusIfNeeded()
    }
}

private final class SessionTerminalKeyCaptureNSView: NSView {
    var onText: ((String) -> Void)?
    var onKey: ((SessionInputKey) -> Void)?
    var isEnabled = false
    var focusToken = UUID()

    private var lastFocusedToken: UUID?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            super.keyDown(with: event)
            return
        }

        guard let input = mapSessionTerminalInput(
            modifierFlags: event.modifierFlags,
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        ) else {
            super.keyDown(with: event)
            return
        }

        switch input {
        case .text(let text):
            onText?(text)
        case .key(let key):
            onKey?(key)
        }
    }

    func focusIfNeeded() {
        guard isEnabled, lastFocusedToken != focusToken else {
            return
        }

        lastFocusedToken = focusToken
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled else {
                return
            }

            self.window?.makeFirstResponder(self)
        }
    }
}

#Preview {
    ContentView(appModel: try! .live())
}
