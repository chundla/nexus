#if os(macOS)
import AppKit
import NexusDomain
import SwiftUI

struct ContentView: View {
    @Bindable var appModel: NexusAppModel

    @State private var selection: SidebarSelection?
    @State private var isShowingCreateWorkspaceGroupSheet = false
    @State private var isShowingQuickSwitchSheet = false
    @State private var isShowingCreateRemoteWorkspaceSheet = false
    @State private var newWorkspaceGroupName = ""
    @State private var isShowingHostsSheet = false
    @State private var isShowingRemoteAccessSheet = false
    @State private var quickSwitchQuery = ""
    @State private var quickSwitchResults: [NavigationItem] = []
    @State private var pendingWorkspaceFolderPath: String?
    @State private var pendingWorkspaceGroupID: UUID?
    @State private var isShowingWorkspaceGroupPicker = false
    @State private var terminalViewportSize: CGSize = .zero
    @State private var terminalFocusToken = UUID()
    @State private var presentedError: PresentedError?

    private let terminalLayout = TerminalViewportLayout.live

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if appModel.recentNavigation.isEmpty == false {
                    Section("Recents") {
                        ForEach(appModel.recentNavigation) { item in
                            Button {
                                navigate(to: item.target)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(item.title, systemImage: navigationItemIcon(for: item.kind))
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Workspace Groups") {
                    ForEach(appModel.workspaceGroups) { group in
                        Label(group.name, systemImage: "folder.badge.plus")
                            .tag(SidebarSelection.workspaceGroup(group.id))
                    }
                }

                Section("Workspaces") {
                    ForEach(appModel.workspaces) { workspace in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(workspace.name, systemImage: workspace.kind == .remote ? "externaldrive.connected.to.line.below" : "folder")
                            if workspace.kind == .remote {
                                Text(appModel.workspaceTargetSummary(for: workspace))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(SidebarSelection.workspace(workspace.id))
                    }
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
#endif
            .toolbar {
                ToolbarItemGroup {
                    Button("Quick Switch") {
                        quickSwitchQuery = ""
                        quickSwitchResults = []
                        isShowingQuickSwitchSheet = true
                    }
                    .keyboardShortcut("k", modifiers: [.command])

                    Button("New Workspace Group") {
                        newWorkspaceGroupName = ""
                        isShowingCreateWorkspaceGroupSheet = true
                    }

                    Button("Hosts") {
                        isShowingHostsSheet = true
                    }

                    Button("Remote Access") {
                        isShowingRemoteAccessSheet = true
                    }

                    Button("Add Local Workspace") {
                        addLocalWorkspace()
                    }

                    Button("Add Remote Workspace") {
                        isShowingCreateRemoteWorkspaceSheet = true
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
        .task(id: selection) {
            do {
                switch selection {
                case .session(let sessionID):
                    try await appModel.focusSession(sessionID: sessionID)
                case .provider(let workspaceID, let providerID):
                    await appModel.stopFocusingSession()
                    try await appModel.loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
                default:
                    await appModel.stopFocusingSession()
                }

                if let navigationTarget = selection?.navigationTarget {
                    try await appModel.recordNavigation(navigationTarget)
                }
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $isShowingCreateWorkspaceGroupSheet) {
            createWorkspaceGroupSheet
        }
        .sheet(isPresented: $isShowingHostsSheet) {
            HostManagementSheet(appModel: appModel, isPresented: $isShowingHostsSheet)
        }
        .sheet(isPresented: $isShowingRemoteAccessSheet) {
            RemoteAccessManagementSheet(appModel: appModel, isPresented: $isShowingRemoteAccessSheet)
        }
        .sheet(isPresented: $isShowingQuickSwitchSheet) {
            quickSwitchSheet
        }
        .sheet(isPresented: $isShowingCreateRemoteWorkspaceSheet) {
            remoteWorkspaceSheet
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
            case .provider(let workspaceID, let providerID):
                providerDetail(workspaceID: workspaceID, providerID: providerID)
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
                LabeledContent("Hosts", value: "\(appModel.hosts.count)")
                LabeledContent("Remote Access", value: appModel.remoteAccessState?.isEnabled == true ? "Enabled" : "Disabled")

                HStack {
                    Button("Manage Hosts") {
                        isShowingHostsSheet = true
                    }

                    Button("Manage Remote Access") {
                        isShowingRemoteAccessSheet = true
                    }
                }
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

    private var quickSwitchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Switch")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Search Workspaces, Providers, and Sessions", text: $quickSwitchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: quickSwitchQuery) { _, _ in
                    Task {
                        await updateQuickSwitchResults()
                    }
                }

            List(quickSwitchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appModel.recentNavigation : quickSwitchResults) { item in
                Button {
                    isShowingQuickSwitchSheet = false
                    navigate(to: item.target)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(item.title, systemImage: navigationItemIcon(for: item.kind))
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if quickSwitchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, quickSwitchResults.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a Workspace, Provider, or Session name.")
                    )
                }
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 360)
        .task {
            do {
                try await appModel.loadRecentNavigation()
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
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
                        Text(appModel.workspaceTargetSummary(for: workspace))
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
                    if let hostName = appModel.workspaceHostName(for: workspace) {
                        LabeledContent("Host", value: hostName)
                        LabeledContent("Remote Path", value: workspace.folderPath)
                    } else {
                        LabeledContent("Folder", value: workspace.folderPath)
                    }
                    LabeledContent("Primary Group", value: appModel.workspaceGroupName(for: workspace.primaryGroupID) ?? workspace.primaryGroupID.uuidString)

                    if let remoteTarget = overview?.remoteTarget {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Remote Status")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text("Last-known Host Validation and Workspace Availability for this Remote Workspace.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            remoteStatusPanel(
                                title: "Workspace Availability",
                                stateTitle: workspaceAvailabilityStateTitle(remoteTarget.workspaceAvailability.state),
                                stateSymbol: workspaceAvailabilityStateSymbol(remoteTarget.workspaceAvailability.state),
                                stateColor: workspaceAvailabilityStateColor(remoteTarget.workspaceAvailability.state),
                                summary: remoteTarget.workspaceAvailability.summary,
                                checkedAt: remoteTarget.workspaceAvailability.checkedAt,
                                diagnostics: remoteTarget.workspaceAvailability.diagnostics.map { ($0.code, $0.message) }
                            )

                            remoteStatusPanel(
                                title: "Host Validation",
                                stateTitle: hostValidationStateTitle(remoteTarget.hostValidation?.state),
                                stateSymbol: hostValidationStateSymbol(remoteTarget.hostValidation?.state),
                                stateColor: hostValidationStateColor(remoteTarget.hostValidation?.state),
                                summary: remoteTarget.hostValidation?.summary ?? "Validate this Host to unblock deeper remote checks.",
                                checkedAt: remoteTarget.hostValidation?.checkedAt,
                                diagnostics: remoteTarget.hostValidation?.diagnostics.map { ($0.code, $0.message) } ?? []
                            )
                        }
                    }

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

    private func providerDetail(workspaceID: UUID, providerID: ProviderID) -> some View {
        let detail = appModel.providerDetail(for: workspaceID, providerID: providerID)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(providerID.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let detail {
                    Label(detail.health.state.rawValue.replacingOccurrences(of: "Checked", with: " checked"), systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(detail.health.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if detail.health.diagnostics.isEmpty == false {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diagnostics")
                                .font(.headline)
                            ForEach(Array(detail.health.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                Text(diagnostic.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Session")
                            .font(.headline)

                        if let defaultSession = detail.defaultSession {
                            providerSessionRow(
                                defaultSession,
                                primaryActionTitle: defaultSession.state == .ready ? "Open" : "Inspect",
                                primaryAction: {
                                    selection = .session(defaultSession.id)
                                },
                                secondaryActionTitle: defaultSession.state == .ready ? "Stop" : "Delete",
                                secondaryAction: {
                                    if defaultSession.state == .ready {
                                        stopSession(defaultSession, workspaceID: workspaceID, providerID: providerID)
                                    } else {
                                        deleteSessionRecord(defaultSession, workspaceID: workspaceID, providerID: providerID)
                                    }
                                }
                            )
                        } else {
                            Text("No default session yet.")
                                .foregroundStyle(.secondary)
                        }

                        Button(defaultSessionButtonTitle(for: detail)) {
                            Task {
                                do {
                                    let session = try await appModel.launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: providerID)
                                    selection = .session(session.id)
                                } catch {
                                    presentedError = PresentedError(message: error.localizedDescription)
                                }
                            }
                        }
                        .disabled(providerID != .claude)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Alternate Sessions")
                                .font(.headline)
                            Spacer()
                            Button("New Session") {
                                Task {
                                    do {
                                        let session = try await appModel.createNamedSession(workspaceID: workspaceID, providerID: providerID)
                                        selection = .session(session.id)
                                    } catch {
                                        presentedError = PresentedError(message: error.localizedDescription)
                                    }
                                }
                            }
                            .disabled(providerID != .claude)
                        }

                        if detail.alternateSessions.isEmpty {
                            Text("No alternate sessions yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(detail.alternateSessions) { session in
                                providerSessionRow(
                                    session,
                                    primaryActionTitle: session.state == .ready ? "Open" : "Inspect",
                                    primaryAction: {
                                        selection = .session(session.id)
                                    },
                                    secondaryActionTitle: session.state == .ready ? "Stop" : "Delete",
                                    secondaryAction: {
                                        if session.state == .ready {
                                            stopSession(session, workspaceID: workspaceID, providerID: providerID)
                                        } else {
                                            deleteSessionRecord(session, workspaceID: workspaceID, providerID: providerID)
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if detail.failedSessions.isEmpty == false {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Failed Session Records")
                                .font(.headline)

                            ForEach(detail.failedSessions) { session in
                                providerSessionRow(
                                    session,
                                    primaryActionTitle: "Inspect",
                                    primaryAction: {
                                        selection = .session(session.id)
                                    },
                                    secondaryActionTitle: "Delete",
                                    secondaryAction: {
                                        deleteSessionRecord(session, workspaceID: workspaceID, providerID: providerID)
                                    }
                                )
                            }
                        }
                    }
                } else {
                    Text("Loading provider detail…")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sessionDetail(sessionID: UUID) -> some View {
        let screen = appModel.focusedSessionScreen?.session.id == sessionID ? appModel.focusedSessionScreen : nil
        let context = appModel.focusedSessionPresentationContext

        return VStack(alignment: .leading, spacing: 16) {
            if let screen {
                let isReady = screen.session.state == .ready
                let isRemote = context?.isRemote == true

                Text("\(screen.session.providerID.displayName) Session")
                    .font(.title2)
                    .fontWeight(.semibold)

                Label(screen.session.state.rawValue.capitalized, systemImage: isReady ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(isReady ? Color.secondary : Color.orange)

                if let context {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Workspace", value: context.workspace.name)
                        if context.isRemote {
                            LabeledContent("Host", value: context.hostName ?? "Unavailable Host")
                            LabeledContent("Remote Path", value: context.remotePath ?? context.workspace.folderPath)
                        } else {
                            LabeledContent("Path", value: context.targetSummary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Terminal: \(screen.terminalColumns) × \(screen.terminalRows)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isReady {
                        if isRemote {
                            Button("Detach") {
                                detachSession(screen.session)
                            }
                        }
                        Button("Stop Session", role: .destructive) {
                            stopSession(
                                screen.session,
                                workspaceID: screen.session.workspaceID,
                                providerID: screen.session.providerID
                            )
                        }
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(screen.styledVisibleLines.enumerated()), id: \.offset) { index, line in
                            terminalLineView(line, row: index, screen: screen)
                        }
                    }
                    .padding(.horizontal, terminalLayout.contentPadding.width)
                    .padding(.vertical, terminalLayout.contentPadding.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackgroundColor)
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
                    reportTerminalSize(terminalViewportSize)
                }

                if isRemote {
                    Text("Detach leaves the tmux-backed remote runtime alive. Stop Session terminates the remote runtime and keeps the Session record.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                if card.alternateSessionCount > 0 {
                    Text("\(card.alternateSessionCount) alternate session\(card.alternateSessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
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

                Button("Details") {
                    selection = .provider(workspaceID, card.provider.id)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func remoteStatusPanel(
        title: String,
        stateTitle: String,
        stateSymbol: String,
        stateColor: Color,
        summary: String,
        checkedAt: Date?,
        diagnostics: [(code: String, message: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Label(stateTitle, systemImage: stateSymbol)
                    .foregroundStyle(stateColor)
            }

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            LabeledContent("Last Checked", value: checkedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not checked")
                .font(.caption)

            if diagnostics.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostics")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnostic.message)
                                .font(.caption)
                            Text(diagnostic.code)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hostValidationStateTitle(_ state: HostValidationSnapshot.State?) -> String {
        switch state {
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

    private func hostValidationStateSymbol(_ state: HostValidationSnapshot.State?) -> String {
        switch state {
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

    private func hostValidationStateColor(_ state: HostValidationSnapshot.State?) -> Color {
        switch state {
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

    private func workspaceAvailabilityStateTitle(_ state: WorkspaceAvailabilitySnapshot.State) -> String {
        switch state {
        case .available:
            "Available"
        case .unavailable:
            "Unavailable"
        case .broken:
            "Broken"
        case .blocked:
            "Blocked"
        }
    }

    private func workspaceAvailabilityStateSymbol(_ state: WorkspaceAvailabilitySnapshot.State) -> String {
        switch state {
        case .available:
            "checkmark.circle"
        case .unavailable:
            "wifi.exclamationmark"
        case .broken:
            "exclamationmark.triangle"
        case .blocked:
            "pause.circle"
        }
    }

    private func workspaceAvailabilityStateColor(_ state: WorkspaceAvailabilitySnapshot.State) -> Color {
        switch state {
        case .available:
            .green
        case .unavailable:
            .orange
        case .broken:
            .red
        case .blocked:
            .secondary
        }
    }

    private func providerSessionRow(
        _ session: Session,
        primaryActionTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.isDefault ? "Default Session" : (session.name ?? "Session"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(session.failureMessage ?? session.state.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                }
                Button(primaryActionTitle, action: primaryAction)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stopSession(_ session: Session, workspaceID: UUID, providerID: ProviderID) {
        Task {
            do {
                _ = try await appModel.stopSession(sessionID: session.id, workspaceID: workspaceID, providerID: providerID)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func detachSession(_ session: Session) {
        Task {
            _ = await appModel.detachFocusedSession()
            selection = .provider(session.workspaceID, session.providerID)
        }
    }

    private func deleteSessionRecord(_ session: Session, workspaceID: UUID, providerID: ProviderID) {
        Task {
            do {
                _ = try await appModel.deleteSessionRecord(sessionID: session.id, workspaceID: workspaceID, providerID: providerID)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func defaultSessionButtonTitle(for detail: ProviderDetail) -> String {
        guard let session = detail.defaultSession else {
            return "Launch"
        }

        return session.state == .ready ? "Resume" : "Relaunch"
    }

    private func navigate(to target: NavigationTarget) {
        switch target.kind {
        case .workspace:
            guard let workspaceID = target.workspaceID else {
                return
            }
            selection = .workspace(workspaceID)
        case .provider:
            guard let workspaceID = target.workspaceID, let providerID = target.providerID else {
                return
            }
            selection = .provider(workspaceID, providerID)
        case .session:
            guard let sessionID = target.sessionID else {
                return
            }
            selection = .session(sessionID)
        }
    }

    private func navigationItemIcon(for kind: NavigationTarget.Kind) -> String {
        switch kind {
        case .workspace:
            "folder"
        case .provider:
            "square.stack.3d.up"
        case .session:
            "terminal"
        }
    }

    @MainActor
    private func updateQuickSwitchResults() async {
        let query = quickSwitchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            quickSwitchResults = []
            return
        }

        do {
            quickSwitchResults = try await appModel.searchNavigation(query: query)
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
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

    private var remoteWorkspaceSheet: some View {
        RemoteWorkspaceCreationSheet(
            appModel: appModel,
            isPresented: $isShowingCreateRemoteWorkspaceSheet,
            onCreated: { workspace in
                selection = .workspace(workspace.id)
            },
            onError: { message in
                presentedError = PresentedError(message: message)
            }
        )
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

    private var terminalBackgroundColor: Color {
        Color.black.opacity(0.92)
    }

    @ViewBuilder
    private func terminalLineView(_ line: TerminalLine, row: Int, screen: SessionScreen) -> some View {
        let segments = renderedTerminalSegments(for: line, row: row, screen: screen)

        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                terminalSegmentView(segment)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func terminalSegmentView(_ segment: TerminalLineSegment) -> some View {
        let colors = resolvedTerminalColors(for: segment.style)
        let text = Text(segment.text)
            .font(terminalLayout.font)
            .fontWeight(segment.style.isBold ? .bold : .regular)
            .foregroundStyle(colors.foreground)
            .background(colors.background)
            .opacity(segment.style.isDim ? 0.65 : 1)
            .lineLimit(1)

        if segment.style.isItalic {
            text.italic()
        } else {
            text
        }
    }

    private func renderedTerminalSegments(for line: TerminalLine, row: Int, screen: SessionScreen) -> [TerminalLineSegment] {
        var cells = line.cells

        if screen.cursorVisible, row == screen.cursorRow {
            let cursorIndex = max(0, min(screen.cursorColumn, cells.count))
            cells.insert(TerminalCell(text: "█"), at: cursorIndex)
        }

        if cells.isEmpty {
            cells = [TerminalCell(text: " ")]
        }

        var segments: [TerminalLineSegment] = []
        for cell in cells {
            if let lastIndex = segments.indices.last, segments[lastIndex].style == cell.style {
                segments[lastIndex].text.append(cell.text)
            } else {
                segments.append(TerminalLineSegment(text: cell.text, style: cell.style))
            }
        }

        return segments
    }

    private func resolvedTerminalColors(for style: TerminalStyle) -> (foreground: Color, background: Color) {
        let defaultForeground = Color.white
        let defaultBackground = Color.black
        let foreground = color(for: style.foregroundColor) ?? defaultForeground
        let background = color(for: style.backgroundColor)

        if style.isInverse {
            return (background ?? defaultBackground, foreground)
        }

        return (foreground, background ?? .clear)
    }

    private func color(for terminalColor: TerminalColor?) -> Color? {
        guard let terminalColor else {
            return nil
        }

        switch terminalColor.kind {
        case .ansi256:
            guard let index = terminalColor.index else {
                return nil
            }
            return color(forANSI256: index)
        case .rgb:
            guard let red = terminalColor.red,
                  let green = terminalColor.green,
                  let blue = terminalColor.blue else {
                return nil
            }
            return Color(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255
            )
        }
    }

    private func color(forANSI256 index: Int) -> Color {
        let clampedIndex = max(0, min(index, 255))
        let standardPalette: [(Double, Double, Double)] = [
            (0, 0, 0),
            (205, 49, 49),
            (13, 188, 121),
            (229, 229, 16),
            (36, 114, 200),
            (188, 63, 188),
            (17, 168, 205),
            (229, 229, 229),
            (102, 102, 102),
            (241, 76, 76),
            (35, 209, 139),
            (245, 245, 67),
            (59, 142, 234),
            (214, 112, 214),
            (41, 184, 219),
            (255, 255, 255)
        ]

        let rgb: (Double, Double, Double)
        switch clampedIndex {
        case 0..<16:
            rgb = standardPalette[clampedIndex]
        case 16..<232:
            let cubeIndex = clampedIndex - 16
            let redIndex = cubeIndex / 36
            let greenIndex = (cubeIndex / 6) % 6
            let blueIndex = cubeIndex % 6
            let levels: [Double] = [0, 95, 135, 175, 215, 255]
            rgb = (levels[redIndex], levels[greenIndex], levels[blueIndex])
        default:
            let grayscale = Double(8 + ((clampedIndex - 232) * 10))
            rgb = (grayscale, grayscale, grayscale)
        }

        return Color(
            red: rgb.0 / 255,
            green: rgb.1 / 255,
            blue: rgb.2 / 255
        )
    }

    private func reportTerminalSize(_ size: CGSize) {
        guard appModel.focusedSessionScreen?.session.state == .ready else {
            return
        }

        let gridSize = terminalLayout.gridSize(fitting: size)
        let columns = gridSize.columns
        let rows = gridSize.rows
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

}

private struct RemoteWorkspaceCreationSheet: View {
    @Bindable var appModel: NexusAppModel
    @Binding var isPresented: Bool
    let onCreated: (Workspace) -> Void
    let onError: (String) -> Void

    @State private var hostSource: HostSource = .existing
    @State private var selectedHostID: UUID?
    @State private var workspaceName = ""
    @State private var remotePath = ""
    @State private var selectedGroupID: UUID?
    @State private var newHostName = ""
    @State private var newHostTarget = ""
    @State private var newHostPort = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Remote Workspace")
                .font(.title3)
                .fontWeight(.semibold)

            if appModel.workspaceGroups.isEmpty {
                ContentUnavailableView(
                    "No Workspace Groups",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Create a Workspace Group before adding a Remote Workspace.")
                )
            } else {
                if appModel.hosts.isEmpty == false {
                    Picker("Host", selection: $hostSource) {
                        Text("Existing Host").tag(HostSource.existing)
                        Text("New Host").tag(HostSource.new)
                    }
                    .pickerStyle(.segmented)
                }

                if hostSource == .existing, appModel.hosts.isEmpty == false {
                    Picker("Existing Host", selection: Binding(get: {
                        selectedHostID ?? appModel.hosts.first?.id ?? UUID()
                    }, set: { selectedHostID = $0 })) {
                        ForEach(appModel.hosts) { host in
                            Text(host.name).tag(host.id)
                        }
                    }

                    if let detail = selectedHostDetail,
                       let snapshot = detail.latestValidation,
                       snapshot.state == .unavailable || snapshot.state == .broken {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(snapshot.summary, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("You can still create this Remote Workspace, but the Host is not currently validated.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    TextField("Host Name", text: $newHostName)
                    TextField("SSH Target or Alias", text: $newHostTarget)
                    TextField("Port (optional)", text: $newHostPort)
                }

                TextField("Workspace Name (optional)", text: $workspaceName)
                TextField("Absolute Remote Path", text: $remotePath)

                Picker("Primary Workspace Group", selection: Binding(get: {
                    selectedGroupID ?? appModel.workspaceGroups.first?.id ?? UUID()
                }, set: { selectedGroupID = $0 })) {
                    ForEach(appModel.workspaceGroups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }

                Button("Create") {
                    createRemoteWorkspace()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canCreate == false || isSaving)
            }
        }
        .padding()
        .frame(minWidth: 420)
        .task {
            if appModel.hosts.isEmpty {
                hostSource = .new
            }
            if selectedGroupID == nil {
                selectedGroupID = appModel.workspaceGroups.first?.id
            }
            if selectedHostID == nil {
                selectedHostID = appModel.hosts.first?.id
            }
            await loadSelectedHostDetail()
        }
        .task(id: selectedHostID) {
            await loadSelectedHostDetail()
        }
    }

    private var selectedHostDetail: HostDetail? {
        guard let selectedHostID else {
            return nil
        }
        return appModel.hostDetail(for: selectedHostID)
    }

    private var canCreate: Bool {
        guard appModel.workspaceGroups.isEmpty == false,
              remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }

        switch hostSource {
        case .existing:
            return selectedHostID != nil
        case .new:
            return newHostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && newHostTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func createRemoteWorkspace() {
        isSaving = true
        let resolvedName = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGroupID = selectedGroupID

        Task {
            do {
                let hostID: UUID
                switch hostSource {
                case .existing:
                    guard let selectedHostID else {
                        return
                    }
                    hostID = selectedHostID
                case .new:
                    let port = try resolveNewHostPort()
                    let host = try await appModel.createHost(name: newHostName, sshTarget: newHostTarget, port: port)
                    hostID = host.id
                }

                let workspace = try await appModel.createRemoteWorkspace(
                    name: resolvedName.isEmpty ? nil : resolvedName,
                    hostID: hostID,
                    remotePath: resolvedPath,
                    primaryGroupID: resolvedGroupID
                )
                onCreated(workspace)
                isPresented = false
            } catch {
                onError(error.localizedDescription)
            }
            isSaving = false
        }
    }

    private func resolveNewHostPort() throws -> Int? {
        let trimmedPort = newHostPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPort.isEmpty == false else {
            return nil
        }
        guard let port = Int(trimmedPort) else {
            throw NSError(domain: "RemoteWorkspaceCreation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Host port must be a number"])
        }
        return port
    }

    @MainActor
    private func loadSelectedHostDetail() async {
        guard hostSource == .existing,
              let selectedHostID,
              appModel.hostDetail(for: selectedHostID) == nil else {
            return
        }

        do {
            try await appModel.loadHostDetail(hostID: selectedHostID)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private enum HostSource: Hashable {
        case existing
        case new
    }
}

struct TerminalViewportLayout {
    let font: Font
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let contentPadding: CGSize
    let minimumColumns: Int
    let minimumRows: Int

    static let live: TerminalViewportLayout = {
        let pointSize: CGFloat = 13
        let nsFont = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let glyphWidth = ("M" as NSString).size(withAttributes: [.font: nsFont]).width
        let glyphHeight = ceil(nsFont.ascender - nsFont.descender + nsFont.leading)

        return TerminalViewportLayout(
            font: .system(size: pointSize, design: .monospaced),
            cellWidth: glyphWidth,
            cellHeight: glyphHeight,
            contentPadding: CGSize(width: 12, height: 12),
            minimumColumns: 40,
            minimumRows: 12
        )
    }()

    func gridSize(fitting viewportSize: CGSize) -> (columns: Int, rows: Int) {
        let contentWidth = max(0, viewportSize.width - (contentPadding.width * 2))
        let contentHeight = max(0, viewportSize.height - (contentPadding.height * 2))
        let columns = max(minimumColumns, Int(floor(contentWidth / max(1, cellWidth))))
        let rows = max(minimumRows, Int(floor(contentHeight / max(1, cellHeight))))
        return (columns, rows)
    }
}

private struct TerminalLineSegment {
    var text: String
    let style: TerminalStyle
}

private enum SidebarSelection: Hashable {
    case workspaceGroup(UUID)
    case workspace(UUID)
    case provider(UUID, ProviderID)
    case session(UUID)

    var navigationTarget: NavigationTarget? {
        switch self {
        case .workspaceGroup:
            nil
        case .workspace(let workspaceID):
            .workspace(workspaceID)
        case .provider(let workspaceID, let providerID):
            .provider(workspaceID: workspaceID, providerID: providerID)
        case .session(let sessionID):
            .session(sessionID)
        }
    }
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
#endif
