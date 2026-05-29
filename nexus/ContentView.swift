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
    @State private var sidebarMode: SidebarMode = .workspaces
    @State private var pendingWorkspaceFolderPath: String?
    @State private var pendingWorkspaceGroupID: UUID?
    @State private var isShowingWorkspaceGroupPicker = false
    @State private var terminalViewportSize: CGSize = .zero
    @State private var terminalFocusToken = UUID()
    @State private var structuredSessionPrompt = ""
    @State private var presentedError: PresentedError?

    private let terminalLayout = TerminalViewportLayout.live

    var body: some View {
        ZStack {
            NexusBackdrop()

            NavigationSplitView {
                sidebarContent
            } detail: {
                detailView
                    .padding(detailPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
#if os(macOS)
            .navigationSplitViewStyle(.balanced)
#endif
        }
        .preferredColorScheme(.dark)
        .task {
            if appModel.serviceStatus == nil, appModel.serviceErrorMessage == nil {
                await appModel.refresh()
            }
        }
        .task(id: selection) {
            switch selection {
            case .workspaceGroup:
                sidebarMode = .groups
            case .workspace, .provider, .session:
                sidebarMode = .workspaces
            case .none:
                break
            }

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
        .task(id: appModel.workspaces.map(\.id)) {
            selectDefaultIfNeeded()
        }
        .task(id: appModel.recentNavigation.map(\.id)) {
            selectDefaultIfNeeded()
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

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nexus")
                            .font(NexusMacTheme.displayFont(24, relativeTo: .title2))
                            .foregroundStyle(.white)
                        Text("Your agent workspaces.")
                            .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.mutedText)
                    }

                    Spacer()

                    Button {
                        quickSwitchQuery = ""
                        quickSwitchResults = []
                        isShowingQuickSwitchSheet = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())
                    .help("Quick Switch")
                }

                Picker("Sidebar Mode", selection: $sidebarMode) {
                    ForEach(SidebarMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .nexusPanel(tint: NexusMacTheme.gold, radius: 18)

            List(selection: $selection) {
                switch sidebarMode {
                case .workspaces:
                    if sortedWorkspaces.isEmpty {
                        ContentUnavailableView(
                            "No Workspaces",
                            systemImage: "bubble.left.and.text.bubble.right",
                            description: Text("Add a local or remote workspace to start talking to your agents.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedWorkspaces) { workspace in
                            sidebarNavigationItemView(
                                title: workspace.name,
                                subtitle: appModel.workspaceTargetSummary(for: workspace),
                                systemImage: workspace.kind == .remote ? "macbook.and.iphone" : "folder.fill",
                                accent: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold
                            )
                            .tag(SidebarSelection.workspace(workspace.id))
                            .listRowBackground(Color.clear)
                        }
                    }
                case .groups:
                    if appModel.workspaceGroups.isEmpty {
                        ContentUnavailableView(
                            "No Workspace Groups",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Groups stay tucked away until you need them. Create one from the plus menu.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedWorkspaceGroups) { group in
                            sidebarNavigationItemView(
                                title: group.name,
                                subtitle: "\(workspaceCount(in: group.id)) workspace\(workspaceCount(in: group.id) == 1 ? "" : "s")",
                                systemImage: "line.3.horizontal.decrease.circle.fill",
                                accent: NexusMacTheme.gold
                            )
                            .tag(SidebarSelection.workspaceGroup(group.id))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 280, ideal: 310)
#endif
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Local Workspace", action: addLocalWorkspace)
                    Button("Remote Workspace") {
                        isShowingCreateRemoteWorkspaceSheet = true
                    }
                    Divider()
                    Button("Workspace Group") {
                        newWorkspaceGroupName = ""
                        isShowingCreateWorkspaceGroupSheet = true
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }

                Menu {
                    Button("Hosts") {
                        isShowingHostsSheet = true
                    }
                    Button("Remote Access") {
                        isShowingRemoteAccessSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var detailPadding: CGFloat {
        if case .session = selection {
            return 16
        }
        return 20
    }

    private var sortedWorkspaceGroups: [WorkspaceGroup] {
        appModel.workspaceGroups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var sortedWorkspaces: [Workspace] {
        let ranking = workspaceRecencyRanking
        return appModel.workspaces.sorted { lhs, rhs in
            let lhsRank = ranking[lhs.id] ?? Int.max
            let rhsRank = ranking[rhs.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var workspaceRecencyRanking: [UUID: Int] {
        var workspaceIDs: [UUID] = []

        switch selection {
        case .workspace(let workspaceID):
            workspaceIDs.append(workspaceID)
        case .provider(let workspaceID, _):
            workspaceIDs.append(workspaceID)
        case .session:
            if let workspaceID = appModel.focusedSessionScreen?.session.workspaceID {
                workspaceIDs.append(workspaceID)
            }
        default:
            break
        }

        for item in appModel.recentNavigation {
            switch item.target.kind {
            case .workspace, .provider:
                if let workspaceID = item.target.workspaceID {
                    workspaceIDs.append(workspaceID)
                }
            case .session:
                if let sessionID = item.target.sessionID,
                   let workspaceID = workspaceID(forSessionID: sessionID) {
                    workspaceIDs.append(workspaceID)
                }
            }
        }

        var ranking: [UUID: Int] = [:]
        for (index, workspaceID) in workspaceIDs.enumerated() where ranking[workspaceID] == nil {
            ranking[workspaceID] = index
        }
        return ranking
    }

    private var defaultSidebarSelection: SidebarSelection? {
        sortedWorkspaces.first.map { .workspace($0.id) }
            ?? sortedWorkspaceGroups.first.map { .workspaceGroup($0.id) }
    }

    private var quickSwitchDefaultItems: [NavigationItem] {
        sortedWorkspaces.map { workspace in
            NavigationItem(
                target: .workspace(workspace.id),
                title: workspace.name,
                subtitle: appModel.workspaceTargetSummary(for: workspace)
            )
        }
    }

    private func workspaceCount(in groupID: UUID) -> Int {
        appModel.workspaces.filter { $0.primaryGroupID == groupID }.count
    }

    private func workspaceID(forSessionID sessionID: UUID) -> UUID? {
        if appModel.focusedSessionScreen?.session.id == sessionID {
            return appModel.focusedSessionScreen?.session.workspaceID
        }

        for detail in appModel.providerDetails.values {
            if detail.defaultSession?.id == sessionID {
                return detail.workspace.id
            }
            if detail.alternateSessions.contains(where: { $0.id == sessionID }) {
                return detail.workspace.id
            }
            if detail.failedSessions.contains(where: { $0.id == sessionID }) {
                return detail.workspace.id
            }
        }

        return nil
    }

    private func selectDefaultIfNeeded() {
        guard selection == nil, let defaultSidebarSelection else {
            return
        }
        selection = defaultSidebarSelection
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if sortedWorkspaces.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        NexusSectionHeader(
                            eyebrow: "Get started",
                            title: "Start with a workspace.",
                            detail: "Keep the sidebar focused on the places you actually work, then drop into a seamless agent conversation from there."
                        )

                        HStack(spacing: 10) {
                            Button("Add Local Workspace", action: addLocalWorkspace)
                                .buttonStyle(NexusAccentButtonStyle())

                            Button("Add Remote Workspace") {
                                isShowingCreateRemoteWorkspaceSheet = true
                            }
                            .buttonStyle(NexusSecondaryButtonStyle())
                        }
                    }
                    .padding(24)
                    .nexusPanel(tint: NexusMacTheme.gold)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        NexusSectionHeader(
                            eyebrow: "Pick up where you left off",
                            title: "Recent workspaces stay at the top.",
                            detail: "Nexus quietly reorders your workspaces as you move between them, so the sidebar behaves more like a conversation list."
                        )

                        ForEach(sortedWorkspaces.prefix(6)) { workspace in
                            Button {
                                selection = .workspace(workspace.id)
                            } label: {
                                sidebarNavigationItemView(
                                    title: workspace.name,
                                    subtitle: appModel.workspaceTargetSummary(for: workspace),
                                    systemImage: workspace.kind == .remote ? "macbook.and.iphone" : "folder.fill",
                                    accent: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                    .nexusPanel(tint: NexusMacTheme.gold)
                }

                if let serviceStatus = appModel.serviceStatus {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        NexusMetricTile(title: "Service", value: serviceStatus.state.rawValue.capitalized, detail: serviceStatus.store.location.lastPathComponent, accent: NexusMacTheme.gold)
                        NexusMetricTile(title: "Workspaces", value: "\(appModel.workspaces.count)", detail: "Your active conversation list.", accent: NexusMacTheme.teal)
                        NexusMetricTile(title: "Groups", value: "\(appModel.workspaceGroups.count)", detail: "Hidden until you need a filter.", accent: NexusMacTheme.gold)
                        NexusMetricTile(title: "Hosts", value: "\(appModel.hosts.count)", detail: "Remote machines on call.", accent: NexusMacTheme.coral)
                    }
                } else if let serviceErrorMessage = appModel.serviceErrorMessage {
                    ContentUnavailableView(
                        "Background Service unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(serviceErrorMessage)
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .nexusPanel(tint: NexusMacTheme.coral)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView()
                            .tint(NexusMacTheme.gold)
                        Text("Loading Nexus…")
                            .font(NexusMacTheme.bodyFont(15))
                            .foregroundStyle(NexusMacTheme.mutedText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nexusPanel(tint: NexusMacTheme.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
    }

    private var quickSwitchSheet: some View {
        ZStack {
            NexusBackdrop()

            VStack(alignment: .leading, spacing: 18) {
                NexusSectionHeader(
                    eyebrow: "Quick switch",
                    title: "Jump to a workspace or session.",
                    detail: "Search when you need it. Otherwise, your workspaces are already sorted by recency."
                )

                TextField("Search Workspaces, Providers, and Sessions", text: $quickSwitchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: quickSwitchQuery) { _, _ in
                        Task {
                            await updateQuickSwitchResults()
                        }
                    }

                List(quickSwitchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? quickSwitchDefaultItems : quickSwitchResults) { item in
                    Button {
                        isShowingQuickSwitchSheet = false
                        navigate(to: item.target)
                    } label: {
                        sidebarNavigationItemView(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: navigationItemIcon(for: item.kind),
                            accent: item.kind == .session ? NexusMacTheme.teal : NexusMacTheme.gold
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
            .padding(24)
            .frame(minWidth: 480, minHeight: 380)
            .nexusPanel(tint: NexusMacTheme.teal, radius: 28)
            .padding(28)
        }
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

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NexusSectionHeader(
                    eyebrow: "Workspace group",
                    title: group?.name ?? "Workspace Group",
                    detail: "A curated lane for related Workspaces, ready to launch across providers."
                )
                .padding(26)
                .nexusPanel(tint: NexusMacTheme.gold)

                if workspaces.isEmpty {
                    ContentUnavailableView(
                        "No Workspaces in this group yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Add a local or remote Workspace to start building this lane.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .nexusPanel(tint: NexusMacTheme.teal)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(workspaces) { workspace in
                            Button {
                                selection = .workspace(workspace.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        NexusStatusPill(
                                            text: workspace.kind == .remote ? "Remote" : "Local",
                                            color: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold
                                        )
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Text(workspace.name)
                                        .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                        .foregroundStyle(.white)

                                    Text(appModel.workspaceTargetSummary(for: workspace))
                                        .font(NexusMacTheme.bodyFont(13))
                                        .foregroundStyle(NexusMacTheme.mutedText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .nexusPanel(tint: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold, radius: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func workspaceDetail(workspaceID: UUID) -> some View {
        let workspace = appModel.workspaces.first(where: { $0.id == workspaceID })
        let overview = appModel.workspaceOverview(for: workspaceID)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let workspace {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            NexusSectionHeader(
                                eyebrow: workspace.kind == .remote ? "Remote workspace" : "Local workspace",
                                title: workspace.name,
                                detail: "Open an agent, continue a session, or jump into a fresh one without leaving this workspace."
                            )
                            Spacer()
                            NexusStatusPill(
                                text: workspace.kind == .remote ? "Remote" : "Local",
                                color: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold
                            )
                        }

                        HStack(spacing: 10) {
                            if let hostName = appModel.workspaceHostName(for: workspace) {
                                NexusMetaBadge(icon: "network", text: hostName)
                            }
                            NexusMetaBadge(icon: workspace.kind == .remote ? "point.3.connected.trianglepath.dotted" : "folder", text: workspace.folderPath)
                            if let groupName = appModel.workspaceGroupName(for: workspace.primaryGroupID) {
                                NexusMetaBadge(icon: "line.3.horizontal.decrease.circle", text: groupName)
                            }
                        }
                    }
                    .padding(24)
                    .nexusPanel(tint: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold)

                    if let remoteTarget = overview?.remoteTarget {
                        HStack(alignment: .top, spacing: 14) {
                            remoteStatusPanel(
                                title: "Workspace",
                                stateTitle: workspaceAvailabilityStateTitle(remoteTarget.workspaceAvailability.state),
                                stateSymbol: workspaceAvailabilityStateSymbol(remoteTarget.workspaceAvailability.state),
                                stateColor: workspaceAvailabilityStateColor(remoteTarget.workspaceAvailability.state),
                                summary: remoteTarget.workspaceAvailability.summary,
                                checkedAt: remoteTarget.workspaceAvailability.checkedAt,
                                diagnostics: remoteTarget.workspaceAvailability.diagnostics.map { ($0.code, $0.message) }
                            )

                            remoteStatusPanel(
                                title: "Host",
                                stateTitle: hostValidationStateTitle(remoteTarget.hostValidation?.state),
                                stateSymbol: hostValidationStateSymbol(remoteTarget.hostValidation?.state),
                                stateColor: hostValidationStateColor(remoteTarget.hostValidation?.state),
                                summary: remoteTarget.hostValidation?.summary ?? "Validate this Host to unblock deeper remote checks.",
                                checkedAt: remoteTarget.hostValidation?.checkedAt,
                                diagnostics: remoteTarget.hostValidation?.diagnostics.map { ($0.code, $0.message) } ?? []
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Agents")
                            .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                            .foregroundStyle(.white)

                        if let overview {
                            VStack(spacing: 12) {
                                ForEach(overview.providerCards) { card in
                                    providerCard(workspaceID: workspace.id, card: card)
                                }
                            }
                        } else {
                            Text("Loading providers…")
                                .font(NexusMacTheme.bodyFont(14))
                                .foregroundStyle(NexusMacTheme.mutedText)
                                .padding(18)
                                .nexusPanel(tint: NexusMacTheme.gold, radius: 18)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Workspace not found",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Refresh Nexus or choose another workspace from the sidebar.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .nexusPanel(tint: NexusMacTheme.coral)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func providerDetail(workspaceID: UUID, providerID: ProviderID) -> some View {
        let detail = appModel.providerDetail(for: workspaceID, providerID: providerID)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let detail {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            NexusSectionHeader(
                                eyebrow: "Provider briefing",
                                title: providerID.displayName,
                                detail: detail.health.summary
                            )
                            Spacer()
                            NexusStatusPill(
                                text: detail.health.state.rawValue,
                                color: providerHealthColor(detail.health.state)
                            )
                        }

                        HStack(spacing: 10) {
                            NexusMetaBadge(icon: "folder", text: detail.workspace.name)
                            NexusMetaBadge(icon: detail.prelaunchPrimarySurface == .terminal ? "terminal" : "sparkles.rectangle.stack", text: detail.prelaunchPrimarySurface == .terminal ? "Terminal surface" : "Structured surface")
                            if let version = detail.health.version {
                                NexusMetaBadge(icon: "number", text: version)
                            }
                        }
                    }
                    .padding(26)
                    .nexusPanel(tint: providerHealthColor(detail.health.state))

                    if detail.health.diagnostics.isEmpty == false {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Diagnostics")
                                .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                .foregroundStyle(.white)
                            ForEach(Array(detail.health.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                Text(diagnostic.message)
                                    .font(NexusMacTheme.bodyFont(13))
                                    .foregroundStyle(NexusMacTheme.mutedText)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .nexusPanel(tint: providerHealthColor(detail.health.state), radius: 16)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Default Session")
                                .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                .foregroundStyle(.white)
                            Spacer()
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
                            .buttonStyle(NexusAccentButtonStyle())
                            .disabled(detail.capabilities.launchDefaultSession.isEnabled == false)
                        }

                        if let defaultSession = detail.defaultSession {
                            providerSessionRow(
                                defaultSession,
                                primaryActionTitle: defaultSession.state == .ready ? "Open" : "Inspect",
                                primaryAction: {
                                    selection = .session(defaultSession.id)
                                },
                                secondaryActionTitle: providerSessionCanDeleteRecord(defaultSession, workspace: detail.workspace) ? "Delete" : "Stop",
                                secondaryAction: {
                                    if providerSessionCanDeleteRecord(defaultSession, workspace: detail.workspace) {
                                        deleteSessionRecord(defaultSession, workspaceID: workspaceID, providerID: providerID)
                                    } else {
                                        stopSession(defaultSession, workspaceID: workspaceID, providerID: providerID)
                                    }
                                }
                            )
                        } else {
                            Text("No default session yet.")
                                .font(NexusMacTheme.bodyFont(14))
                                .foregroundStyle(NexusMacTheme.mutedText)
                                .padding(18)
                                .nexusPanel(tint: NexusMacTheme.gold, radius: 18)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Named Sessions")
                                .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                .foregroundStyle(.white)
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
                            .buttonStyle(NexusSecondaryButtonStyle())
                            .disabled(detail.capabilities.createNamedSession.isEnabled == false)
                        }

                        if detail.alternateSessions.isEmpty {
                            Text("No Named Sessions yet.")
                                .font(NexusMacTheme.bodyFont(14))
                                .foregroundStyle(NexusMacTheme.mutedText)
                                .padding(18)
                                .nexusPanel(tint: NexusMacTheme.teal, radius: 18)
                        } else {
                            ForEach(detail.alternateSessions) { session in
                                providerSessionRow(
                                    session,
                                    primaryActionTitle: session.state == .ready ? "Open" : "Inspect",
                                    primaryAction: {
                                        selection = .session(session.id)
                                    },
                                    secondaryActionTitle: providerSessionCanDeleteRecord(session, workspace: detail.workspace) ? "Delete" : "Stop",
                                    secondaryAction: {
                                        if providerSessionCanDeleteRecord(session, workspace: detail.workspace) {
                                            deleteSessionRecord(session, workspaceID: workspaceID, providerID: providerID)
                                        } else {
                                            stopSession(session, workspaceID: workspaceID, providerID: providerID)
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if detail.failedSessions.isEmpty == false {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Failed Session Records")
                                .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                .foregroundStyle(.white)

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
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .padding(20)
                        .nexusPanel(tint: NexusMacTheme.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sessionDetail(sessionID: UUID) -> some View {
        let screen = appModel.focusedSessionScreen?.session.id == sessionID ? appModel.focusedSessionScreen : nil
        let context = appModel.focusedSessionPresentationContext

        return VStack(alignment: .leading, spacing: 14) {
            if let screen {
                let isReady = screen.session.state == .ready
                let isRemote = context?.isRemote == true
                let surface = focusedSessionSurface(for: screen)
                let stateColor = sessionStateColor(screen.session.state)

                HStack(spacing: 10) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(screen.session.providerID.displayName)
                            .font(NexusMacTheme.bodyFont(17).weight(.semibold))
                            .foregroundStyle(.white)

                        if let context {
                            Text(sessionSubtitle(for: context, surface: surface))
                                .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                .foregroundStyle(NexusMacTheme.mutedText)
                        }
                    }

                    Spacer()

                    Menu {
                        if isRemote, isReady {
                            Button("Detach") {
                                detachSession(screen.session)
                            }
                        }

                        if isReady {
                            Button("Stop Session") {
                                stopSession(
                                    screen.session,
                                    workspaceID: screen.session.workspaceID,
                                    providerID: screen.session.providerID
                                )
                            }
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .nexusPanel(tint: stateColor, radius: 16)

                if surface == .structuredActivityFeed {
                    structuredSessionFeed(screen: screen, isReady: isReady)
                } else {
                    terminalSessionFeed(screen: screen, isReady: isReady)
                }
            } else {
                ContentUnavailableView(
                    "Session unavailable",
                    systemImage: "message",
                    description: Text("Open the session again from its workspace to continue the conversation.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .nexusPanel(tint: NexusMacTheme.coral)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: sessionID) { _, _ in
            structuredSessionPrompt = ""
        }
    }

    private func sessionSubtitle(for context: SessionPresentationContext, surface: FocusedSessionSurface) -> String {
        if context.isRemote {
            return surface == .terminal
                ? "\(context.workspace.name) • \(context.hostName ?? "Remote") • terminal"
                : "\(context.workspace.name) • \(context.hostName ?? "Remote")"
        }

        return surface == .terminal
            ? "\(context.workspace.name) • terminal"
            : context.workspace.name
    }

    private func providerCard(workspaceID: UUID, card: WorkspaceProviderCard) -> some View {
        let accent = providerHealthColor(card.health.state)

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: card.prelaunchPrimarySurface == .terminal ? "terminal.fill" : "message.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(card.provider.displayName)
                        .font(NexusMacTheme.bodyFont(16).weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    NexusStatusPill(text: card.health.state.rawValue.replacingOccurrences(of: "Checked", with: " checked"), color: accent)
                }

                Text(card.defaultSession.summary)
                    .font(NexusMacTheme.bodyFont(14))
                    .foregroundStyle(.white.opacity(0.92))

                if let namedSessionSummary = card.namedSessionSummary {
                    Text(namedSessionSummary)
                        .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                } else {
                    Text(card.health.summary)
                        .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
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
                    .buttonStyle(NexusAccentButtonStyle())
                    .disabled(card.capabilities.launchDefaultSession.isEnabled == false)

                    Button("Details") {
                        selection = .provider(workspaceID, card.provider.id)
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .nexusPanel(tint: accent, radius: 18)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(NexusMacTheme.displayFont(20, relativeTo: .title3))
                        .foregroundStyle(.white)
                    Text(summary)
                        .font(NexusMacTheme.bodyFont(13))
                        .foregroundStyle(NexusMacTheme.mutedText)
                }
                Spacer()
                Label(stateTitle, systemImage: stateSymbol)
                    .font(NexusMacTheme.bodyFont(12, relativeTo: .caption).weight(.semibold))
                    .foregroundStyle(stateColor)
            }

            NexusInspectorRow(
                title: "Last Checked",
                value: checkedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not checked"
            )

            if diagnostics.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diagnostics")
                        .font(NexusMacTheme.monoFont(11, relativeTo: .caption))
                        .tracking(2)
                        .foregroundStyle(NexusMacTheme.gold)

                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnostic.message)
                                .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(diagnostic.code)
                                .font(NexusMacTheme.monoFont(11, relativeTo: .caption2))
                                .foregroundStyle(NexusMacTheme.mutedText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nexusPanel(tint: stateColor, radius: 14)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nexusPanel(tint: stateColor, radius: 20)
    }

    private func sidebarNavigationItemView(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                    .foregroundStyle(NexusMacTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func providerHealthColor(_ state: ProviderHealthSummary.State) -> Color {
        switch state {
        case .available:
            NexusMacTheme.teal
        case .unavailable, .blocked:
            NexusMacTheme.gold
        case .misconfigured:
            NexusMacTheme.coral
        case .notChecked:
            Color.white.opacity(0.65)
        }
    }

    private func sessionStateColor(_ state: Session.State) -> Color {
        switch state {
        case .ready:
            NexusMacTheme.teal
        case .interrupted:
            NexusMacTheme.gold
        case .exited, .failed:
            NexusMacTheme.coral
        }
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
        let accent = sessionStateColor(session.state)

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                NexusStatusPill(
                    text: session.isDefault ? "Default session" : (session.name ?? "Named session"),
                    color: accent
                )
                Text(session.failureMessage ?? session.state.rawValue.capitalized)
                    .font(NexusMacTheme.bodyFont(14))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            HStack(spacing: 8) {
                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(NexusSecondaryButtonStyle())
                }
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(NexusAccentButtonStyle())
            }
        }
        .padding(18)
        .nexusPanel(tint: accent, radius: 18)
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

    private func providerSessionCanDeleteRecord(_ session: Session, workspace: Workspace) -> Bool {
        if session.state != .ready {
            return true
        }

        return session.providerID == .ibmBob && workspace.kind == .local
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
        ZStack {
            NexusBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                NexusSectionHeader(
                    eyebrow: "Create lane",
                    title: "New Workspace Group",
                    detail: "Name the collection that will gather related Workspaces into one launch surface."
                )

                TextField("Name", text: $newWorkspaceGroupName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()

                    Button("Cancel") {
                        isShowingCreateWorkspaceGroupSheet = false
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())

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
        ZStack {
            NexusBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                NexusSectionHeader(
                    eyebrow: "Route assignment",
                    title: "Choose Primary Workspace Group",
                    detail: "Place this Workspace into the group that should own its primary route in Nexus."
                )

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
                    .buttonStyle(NexusSecondaryButtonStyle())

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
                    .buttonStyle(NexusAccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 420)
            .nexusPanel(tint: NexusMacTheme.teal, radius: 28)
            .padding(28)
        }
    }

    private func addLocalWorkspace() {
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
        Task {
            do {
                let workspace = try await appModel.createLocalWorkspace(folderPath: folderPath, primaryGroupID: nil)
                selection = .workspace(workspace.id)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
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

    @ViewBuilder
    private func terminalSessionFeed(screen: SessionScreen, isReady: Bool) -> some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("Live terminal")
                .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.medium))
                .foregroundStyle(NexusMacTheme.mutedText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NexusMacTheme.line, lineWidth: 1)
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
    }

    @ViewBuilder
    private func structuredSessionFeed(screen: SessionScreen, isReady: Bool) -> some View {
        let presentation = structuredSessionFeedPresentation(for: screen)

        VStack(spacing: 0) {
            if presentation.pendingApprovalRequests.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.pendingApprovalRequests) { request in
                        structuredSessionApprovalRequestView(request)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if presentation.activityRows.isEmpty {
                        ContentUnavailableView(
                            presentation.copy.emptyStateTitle,
                            systemImage: "message",
                            description: Text(presentation.copy.emptyStateDescription)
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(presentation.activityRows) { row in
                                structuredSessionActivityRowView(row, providerName: screen.session.providerID.displayName)
                                    .id(row.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("conversation-bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: presentation.activityRows.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: presentation.pendingApprovalRequests.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
            }

            if isReady {
                HStack(spacing: 8) {
                    TextField(presentation.copy.composerPlaceholder, text: $structuredSessionPrompt, axis: .vertical)
                        .font(NexusMacTheme.bodyFont(13))
                        .textFieldStyle(.plain)
                        .lineLimit(1 ... 4)
                        .submitLabel(.send)
                        .onSubmit {
                            sendStructuredSessionPrompt()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(NexusMacTheme.softLine, lineWidth: 1)
                        }
                }
                .padding(14)
                .background(Color.white.opacity(0.02))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nexusPanel(tint: NexusMacTheme.teal, radius: 22)
    }

    private func structuredSessionActivityRowView(_ row: StructuredSessionActivityRow, providerName: String) -> some View {
        let accent = structuredSessionActivityColor(for: row.emphasis)
        let role = structuredConversationRole(for: row, providerName: providerName)
        let messageText = structuredConversationText(for: row)

        switch role {
        case .user:
            return AnyView(
                HStack {
                    Spacer(minLength: 120)
                    Text(messageText)
                        .font(NexusMacTheme.bodyFont(13))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 520, alignment: .leading)
                        .background(NexusMacTheme.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            )
        case .assistant(let label):
            return AnyView(
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(NexusMacTheme.bodyFont(10, relativeTo: .caption).weight(.medium))
                            .foregroundStyle(NexusMacTheme.mutedText)
                        Text(messageText)
                            .font(NexusMacTheme.bodyFont(13))
                            .foregroundStyle(.white.opacity(0.94))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(NexusMacTheme.softLine, lineWidth: 1)
                    }
                    Spacer(minLength: 120)
                }
            )
        case .command:
            return AnyView(
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(row.title, systemImage: row.systemImage)
                            .font(NexusMacTheme.monoFont(10, relativeTo: .caption))
                            .foregroundStyle(accent)
                        Text(messageText)
                            .font(NexusMacTheme.monoFont(11, relativeTo: .callout))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                }
            )
        case .error:
            return AnyView(
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Error", systemImage: row.systemImage)
                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(accent)
                        Text(messageText)
                            .font(NexusMacTheme.bodyFont(13))
                            .foregroundStyle(.white.opacity(0.94))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    Spacer()
                }
                .padding(12)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                }
            )
        case .system:
            return AnyView(
                HStack {
                    Spacer()
                    Label(messageText, systemImage: row.systemImage)
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05), in: Capsule())
                    Spacer()
                }
            )
        }
    }

    private func structuredSessionApprovalRequestView(_ request: SessionApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Approval Request", systemImage: "hand.raised.fill")
                .font(NexusMacTheme.bodyFont(12, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(NexusMacTheme.gold)

            Text(request.title)
                .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                .foregroundStyle(.white)

            Text(request.text)
                .font(NexusMacTheme.bodyFont(13))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button("Deny") {
                    respondToStructuredSessionApprovalRequest(request.id, decision: .deny)
                }
                .buttonStyle(NexusSecondaryButtonStyle())

                Button("Approve") {
                    respondToStructuredSessionApprovalRequest(request.id, decision: .approve)
                }
                .buttonStyle(NexusAccentButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nexusPanel(tint: NexusMacTheme.gold, radius: 16)
    }

    private func structuredSessionActivityColor(for emphasis: StructuredSessionActivityEmphasis) -> Color {
        switch emphasis {
        case .neutral:
            Color.white.opacity(0.55)
        case .accent:
            NexusMacTheme.gold
        case .critical:
            NexusMacTheme.coral
        case .success:
            NexusMacTheme.teal
        }
    }

    private func structuredConversationRole(for row: StructuredSessionActivityRow, providerName: String) -> StructuredConversationRole {
        if row.title == "Message", let split = structuredConversationPrefixSplit(for: row.text) {
            if split.label.caseInsensitiveCompare("you") == .orderedSame {
                return .user
            }
            return .assistant(label: split.label)
        }

        switch row.title {
        case "Command", "Diff":
            return .command
        case "Error":
            return .error
        case "Message":
            return .assistant(label: providerName)
        default:
            return .system
        }
    }

    private func structuredConversationText(for row: StructuredSessionActivityRow) -> String {
        if row.title == "Message", let split = structuredConversationPrefixSplit(for: row.text) {
            return split.body
        }
        return row.text
    }

    private func structuredConversationPrefixSplit(for text: String) -> (label: String, body: String)? {
        guard let separatorRange = text.range(of: ": ") else {
            return nil
        }

        let label = String(text[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.isEmpty == false, body.isEmpty == false, label.count <= 24 else {
            return nil
        }
        return (label, body)
    }

    private func sendStructuredSessionPrompt() {
        let prompt = structuredSessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            return
        }

        Task { @MainActor in
            do {
                try await appModel.sendInputToFocusedSession(prompt)
                structuredSessionPrompt = ""
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func respondToStructuredSessionApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) {
        Task { @MainActor in
            do {
                try await appModel.respondToFocusedSessionApprovalRequest(approvalRequestID, decision: decision)
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private var terminalBackgroundColor: Color {
        Color(red: 0.07, green: 0.08, blue: 0.10)
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
        ZStack {
            NexusBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                NexusSectionHeader(
                    eyebrow: "Remote route",
                    title: "New Remote Workspace",
                    detail: "Connect a saved Host to an absolute remote path so sessions can launch through Nexus from the same control deck."
                )

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
                                .foregroundStyle(NexusMacTheme.gold)
                            Text("You can still create this Remote Workspace, but the Host is not currently validated.")
                                .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                .foregroundStyle(NexusMacTheme.mutedText)
                        }
                        .padding(14)
                        .nexusPanel(tint: NexusMacTheme.gold, radius: 16)
                    }
                } else {
                    TextField("Host Name", text: $newHostName)
                    TextField("SSH Target or Alias", text: $newHostTarget)
                    TextField("Port (optional)", text: $newHostPort)
                }

                TextField("Workspace Name (optional)", text: $workspaceName)
                TextField("Absolute Remote Path", text: $remotePath)

                if appModel.workspaceGroups.isEmpty == false {
                    Picker("Workspace Group", selection: $selectedGroupID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(appModel.workspaceGroups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Spacer()

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())

                    Button("Create") {
                        createRemoteWorkspace()
                    }
                    .buttonStyle(NexusAccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(canCreate == false || isSaving)
                }
            }
            .padding(24)
            .frame(minWidth: 460)
            .nexusPanel(tint: NexusMacTheme.teal, radius: 28)
            .padding(28)
        }
        .task {
            if appModel.hosts.isEmpty {
                hostSource = .new
            }
            if selectedGroupID == nil {
                selectedGroupID = nil
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
        guard remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
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

private enum SidebarMode: String, CaseIterable, Identifiable {
    case workspaces
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaces:
            "Workspaces"
        case .groups:
            "Groups"
        }
    }
}

private enum StructuredConversationRole {
    case user
    case assistant(label: String)
    case command
    case error
    case system
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
