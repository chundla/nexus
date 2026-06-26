#if os(macOS)
    import AppKit
    import NexusDomain
    import NexusSessionPresentation
    import SwiftUI

    struct ContentView: View {
        @Bindable var appModel: NexusAppModel
        let settingsTabSelection: NexusSettingsTabSelection

        @Environment(\.openSettings) private var openSettings

        @State private var selection: SidebarSelection?
        @State private var focusedSessionID: UUID?
        @State private var isShowingCreateWorkspaceGroupSheet = false
        @State private var isShowingQuickSwitchSheet = false
        @State private var isShowingCreateRemoteWorkspaceSheet = false
        @State private var newWorkspaceGroupName = ""
        @State private var quickSwitchQuery = ""
        @State private var quickSwitchResults: [NavigationItem] = []
        @State private var quickSwitchSearchCoordinator = QuickSwitchSearchCoordinator<[NavigationItem]>()
        @State private var sidebarMode: SidebarMode = .workspaces
        @State private var pendingWorkspaceFolderPath: String?
        @State private var pendingWorkspaceGroupID: UUID?
        @State private var isShowingWorkspaceGroupPicker = false
        @State private var terminalViewportSize: CGSize = .zero
        @State private var terminalViewportResizeCoordinator = TerminalViewportResizeCoordinator()
        @State private var terminalFocusToken = UUID()
        @State private var presentedError: PresentedError?
        @State private var structuredSessionAutoScrollCoordinator = StructuredSessionAutoScrollCoordinator()
        @State private var structuredSessionDraftGrowthScrollThrottle = StructuredSessionDraftGrowthScrollThrottle()
        @State private var structuredSessionPinState = StructuredSessionFeedPinState()
        @State private var structuredSessionFeedScrollSnapshot: StructuredSessionFeedScrollSnapshot?
        @State private var structuredSessionFeedScrollPosition = ScrollPosition()
        @State private var structuredSessionMacOSFeedVisibleTailRowCount = 0
        @State private var presentedStructuredSessionAssistantFullResponse:
            StructuredSessionAssistantFullResponsePresentation?
        @StateObject private var structuredSessionAgentTurnDisclosureState = StructuredSessionAgentTurnDisclosureState()

        private let terminalLayout = TerminalViewportLayout.live

        var body: some View {
            ZStack {
                NexusBackdrop()

                // Browsing (sidebar + Workspace/Provider middle pane) and a focused
                // Session are independent: picking a Workspace never has to evict the
                // Session you already opened — it keeps living in the detail pane.
                NavigationSplitView {
                    sidebarContent
                } content: {
                    middleColumnView
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        #if os(macOS)
                            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
                        #endif
                } detail: {
                    Group {
                        if focusedSessionID != nil {
                            focusedSessionColumnView
                                .padding(16)
                        } else {
                            sessionPlaceholderColumnView
                                .padding(20)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                #if os(macOS)
                    .navigationSplitViewStyle(.balanced)
                #endif
            }
            .tint(NexusMacTheme.gold)
            .nexusSeamlessWindowChrome()
            .task {
                if appModel.serviceStatus == nil, appModel.serviceErrorMessage == nil {
                    await appModel.refresh()
                }
            }
            .task(id: selection) {
                switch selection {
                case .workspaceGroup:
                    sidebarMode = .groups
                case .workspace, .provider:
                    sidebarMode = .workspaces
                case .none:
                    break
                }

                do {
                    if case .provider(let workspaceID, let providerID) = selection {
                        try await appModel.loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
                    }

                    if let navigationTarget = selection?.navigationTarget {
                        try await appModel.recordNavigation(navigationTarget)
                    }
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .task(id: focusedSessionID) {
                do {
                    if let focusedSessionID {
                        try await appModel.focusSession(sessionID: focusedSessionID)
                        try await appModel.recordNavigation(.session(focusedSessionID))
                    } else {
                        await appModel.stopFocusingSession()
                    }
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .onChange(of: appModel.focusedSessionScreen?.session.id) { _, sessionID in
                guard sessionID == focusedSessionID, let session = appModel.focusedSessionScreen?.session else {
                    return
                }

                if case .provider(let workspaceID, let providerID) = selection,
                    workspaceID == session.workspaceID, providerID == session.providerID
                {
                    return
                }

                selection = .provider(session.workspaceID, session.providerID)
            }
            .background {
                SidebarSelectionBootstrapBoundary(
                    appModel: appModel, selection: $selection, focusedSessionID: $focusedSessionID)
            }
            .sheet(isPresented: $isShowingCreateWorkspaceGroupSheet) {
                createWorkspaceGroupSheet
            }
            .sheet(isPresented: $isShowingQuickSwitchSheet) {
                quickSwitchSheet
            }
            .onChange(of: isShowingQuickSwitchSheet) { _, isShowing in
                guard isShowing == false else {
                    return
                }

                quickSwitchSearchCoordinator.cancel()
                quickSwitchQuery = ""
                quickSwitchResults = []
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
            .onReceive(NotificationCenter.default.publisher(for: .nexusOpenCommandPalette)) { _ in
                openCommandPalette()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusNewLocalWorkspace)) { _ in
                addLocalWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusNewRemoteWorkspace)) { _ in
                isShowingCreateRemoteWorkspaceSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusNewWorkspaceGroup)) { _ in
                newWorkspaceGroupName = ""
                isShowingCreateWorkspaceGroupSheet = true
            }

            .onReceive(NotificationCenter.default.publisher(for: .nexusTakeController)) { _ in
                takeFocusedSessionController()
            }
            .focusedValue(\.nexusSessionControllerIsTakeable, isFocusedSessionControllerTakeable)
        }

        private var isFocusedSessionControllerTakeable: Bool {
            guard case .pairedDevice = appModel.focusedSessionScreen?.controller else {
                return false
            }
            return true
        }

        private func takeFocusedSessionController() {
            guard isFocusedSessionControllerTakeable else {
                return
            }

            Task {
                do {
                    try await appModel.reclaimFocusedSessionController()
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
        }

        private var sidebarContent: some View {
            WorkspaceSidebarBoundary(appModel: appModel, selection: $selection) { presentation in
                sidebarContent(presentation: presentation)
            }
        }

        private func sidebarContent(presentation: WorkspaceBrowseSidebarPresentation) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nexus")
                                .font(NexusMacTheme.displayFont(24, relativeTo: .title2))
                                .foregroundStyle(NexusMacTheme.textPrimary)
                            Text("Your agent workspaces.")
                                .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                .foregroundStyle(NexusMacTheme.mutedText)
                        }

                        Spacer()

                        Button {
                            openCommandPalette()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())
                        .help("Command Palette (⌘K)")
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
                        if presentation.workspaces.isEmpty {
                            ContentUnavailableView(
                                "No Workspaces",
                                systemImage: "bubble.left.and.text.bubble.right",
                                description: Text("Add a local or remote workspace to start talking to your agents.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(presentation.workspaces) { summary in
                                sidebarNavigationItemView(
                                    title: summary.workspace.name,
                                    subtitle: summary.targetSummary,
                                    systemImage: summary.workspace.kind == .remote
                                        ? "macbook.and.iphone" : "folder.fill",
                                    accent: summary.workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold
                                )
                                .tag(SidebarSelection.workspace(summary.workspace.id))
                                .listRowBackground(Color.clear)
                            }
                        }
                    case .groups:
                        if presentation.workspaceGroups.isEmpty {
                            ContentUnavailableView(
                                "No Workspace Groups",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text(
                                    "Groups stay tucked away until you need them. Create one from the plus menu.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(presentation.workspaceGroups) { summary in
                                sidebarNavigationItemView(
                                    title: summary.group.name,
                                    subtitle:
                                        "\(summary.workspaceCount) workspace\(summary.workspaceCount == 1 ? "" : "s")",
                                    systemImage: "line.3.horizontal.decrease.circle.fill",
                                    accent: NexusMacTheme.gold
                                )
                                .tag(SidebarSelection.workspaceGroup(summary.group.id))
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
                            settingsTabSelection.tab = .hosts
                            openSettings()
                        }
                        Button("Remote Access") {
                            settingsTabSelection.tab = .remoteAccess
                            openSettings()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }

        @ViewBuilder
        private var middleColumnView: some View {
            switch selection {
            case .workspaceGroup(let groupID):
                WorkspaceGroupDetailBoundary(appModel: appModel, groupID: groupID) { presentation in
                    workspaceGroupDetail(presentation: presentation)
                }
            case .workspace(let workspaceID):
                WorkspaceDetailBoundary(appModel: appModel, workspaceID: workspaceID) { presentation in
                    workspaceDetail(presentation: presentation)
                }
            case .provider(let workspaceID, let providerID):
                ProviderDetailBoundary(appModel: appModel, workspaceID: workspaceID, providerID: providerID) {
                    detail in
                    providerDetail(workspaceID: workspaceID, providerID: providerID, detail: detail)
                }
            case .none:
                WorkspaceHomeBoundary(appModel: appModel) { presentation in
                    overviewDetail(presentation: presentation)
                }
            }
        }

        @ViewBuilder
        private var focusedSessionColumnView: some View {
            if let focusedSessionID {
                FocusedSessionDetailBoundary(sessionID: focusedSessionID, appModel: appModel) {
                    summary, screen, context in
                    sessionDetailContent(summary: summary, screen: screen, context: context)
                } unavailable: {
                    ContentUnavailableView(
                        "Session unavailable",
                        systemImage: "message",
                        description: Text("Open the session again from its workspace to continue the conversation.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .nexusPanel(tint: NexusMacTheme.coral)
                }
            }
        }

        private var sessionPlaceholderColumnView: some View {
            ContentUnavailableView(
                "No Session focused",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Open a Session from a Provider to start working.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func overviewDetail(presentation: WorkspaceHomePresentation) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if presentation.recentWorkspaces.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            NexusSectionHeader(
                                eyebrow: "Get started",
                                title: "Start with a workspace.",
                                detail:
                                    "Keep the sidebar focused on the places you actually work, then drop into a seamless agent conversation from there."
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
                                detail:
                                    "Nexus quietly reorders your workspaces as you move between them, so the sidebar behaves more like a conversation list."
                            )

                            ForEach(presentation.recentWorkspaces.prefix(6)) { summary in
                                Button {
                                    selection = .workspace(summary.workspace.id)
                                } label: {
                                    sidebarNavigationItemView(
                                        title: summary.workspace.name,
                                        subtitle: summary.targetSummary,
                                        systemImage: summary.workspace.kind == .remote
                                            ? "macbook.and.iphone" : "folder.fill",
                                        accent: summary.workspace.kind == .remote
                                            ? NexusMacTheme.teal : NexusMacTheme.gold
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                        .nexusPanel(tint: NexusMacTheme.gold)
                    }

                    if let serviceStatus = presentation.serviceStatus {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                            NexusMetricTile(
                                title: "Service", value: serviceStatus.state.rawValue.capitalized,
                                detail: serviceStatus.store.location.lastPathComponent, accent: NexusMacTheme.gold)
                            NexusMetricTile(
                                title: "Workspaces", value: "\(presentation.workspaceCount)",
                                detail: "Your active conversation list.", accent: NexusMacTheme.teal)
                            NexusMetricTile(
                                title: "Groups", value: "\(presentation.workspaceGroupCount)",
                                detail: "Hidden until you need a filter.", accent: NexusMacTheme.gold)
                            NexusMetricTile(
                                title: "Hosts", value: "\(presentation.hostCount)", detail: "Remote machines on call.",
                                accent: NexusMacTheme.coral)
                        }
                    } else if let serviceErrorMessage = presentation.serviceErrorMessage {
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
                            Text("Loading Nexus...")
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
            let trimmedQuery = quickSwitchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchingActions = commandPaletteActions.filter { $0.matches(trimmedQuery) }

            return ZStack {
                NexusBackdrop()

                VStack(alignment: .leading, spacing: 18) {
                    NexusSectionHeader(
                        eyebrow: "Command palette",
                        title: "Jump anywhere, or run an action.",
                        detail: "Search when you need it. Otherwise, your workspaces are already sorted by recency."
                    )

                    TextField("Search Workspaces, Providers, Sessions, and Actions", text: $quickSwitchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: quickSwitchQuery) { _, newValue in
                            quickSwitchSearchCoordinator.updateQuery(
                                newValue,
                                search: { query in
                                    try await appModel.searchNavigation(query: query)
                                },
                                applyResults: { quickSwitchResults = $0 },
                                clearResults: { quickSwitchResults = [] },
                                handleError: { presentedError = PresentedError(message: $0.localizedDescription) }
                            )
                        }

                    WorkspaceBrowseNavigationBoundary(appModel: appModel, selection: selection) { presentation in
                        let navigationItems =
                            trimmedQuery.isEmpty ? presentation.quickSwitchItems : quickSwitchResults

                        List {
                            if matchingActions.isEmpty == false {
                                Section("Actions") {
                                    ForEach(matchingActions) { action in
                                        Button {
                                            isShowingQuickSwitchSheet = false
                                            action.perform()
                                        } label: {
                                            sidebarNavigationItemView(
                                                title: action.title,
                                                subtitle: action.subtitle,
                                                systemImage: action.systemImage,
                                                accent: NexusMacTheme.gold
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }

                            if navigationItems.isEmpty == false {
                                Section("Workspaces & Sessions") {
                                    ForEach(navigationItems) { item in
                                        Button {
                                            quickSwitchSearchCoordinator.cancel()
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
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .overlay {
                            if trimmedQuery.isEmpty == false, navigationItems.isEmpty, matchingActions.isEmpty {
                                ContentUnavailableView(
                                    "No matches",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try a Workspace, Provider, Session, or Action name.")
                                )
                            }
                        }
                    }
                }
                .padding(24)
                .frame(minWidth: 480, minHeight: 460)
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

        private func workspaceGroupDetail(presentation: WorkspaceGroupDetailPresentation) -> some View {
            let group = presentation.group
            let workspaces = presentation.workspaces

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
                            ForEach(workspaces) { summary in
                                let workspace = summary.workspace

                                Button {
                                    selection = .workspace(workspace.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 14) {
                                        HStack {
                                            NexusStatusPill(
                                                text: workspace.kind == .remote ? "Remote" : "Local",
                                                color: workspace.kind == .remote
                                                    ? NexusMacTheme.teal : NexusMacTheme.gold
                                            )
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                                .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.5))
                                        }

                                        Text(workspace.name)
                                            .font(NexusMacTheme.displayFont(22, relativeTo: .title3))
                                            .foregroundStyle(NexusMacTheme.textPrimary)

                                        Text(summary.targetSummary)
                                            .font(NexusMacTheme.bodyFont(13))
                                            .foregroundStyle(NexusMacTheme.mutedText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .nexusPanel(
                                        tint: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold,
                                        radius: 18)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }

        private func workspaceDetail(presentation: WorkspaceBrowseDetailPresentation) -> some View {
            let workspace = presentation.workspace
            let overview = presentation.overview

            return ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let workspace {
                        workspaceDetailHeader(workspace: workspace, presentation: presentation)

                        if let remoteTarget = overview?.remoteTarget {
                            workspaceRemoteIssueStrip(remoteTarget: remoteTarget)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Agents")
                                .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                                .tracking(1.4)
                                .foregroundStyle(NexusMacTheme.mutedText)
                                .padding(.horizontal, 14)

                            if let overview {
                                if overview.providerCards.isEmpty {
                                    Text("No Providers configured.")
                                        .font(NexusMacTheme.bodyFont(14))
                                        .foregroundStyle(NexusMacTheme.mutedText)
                                        .padding(.horizontal, 14)
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(Array(overview.providerCards.enumerated()), id: \.element.id) {
                                            index, card in
                                            if index > 0 {
                                                NexusRowDivider()
                                            }
                                            providerRow(workspaceID: workspace.id, card: card)
                                        }
                                    }
                                }
                            } else {
                                Text("Loading providers...")
                                    .font(NexusMacTheme.bodyFont(14))
                                    .foregroundStyle(NexusMacTheme.mutedText)
                                    .padding(.horizontal, 14)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Workspace not found",
                            systemImage: "folder.badge.questionmark",
                            description: Text("Refresh Nexus or choose another workspace from the sidebar.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private func workspaceDetailHeader(
            workspace: Workspace, presentation: WorkspaceBrowseDetailPresentation
        ) -> some View {
            var subtitleParts: [String] = []
            if let hostName = presentation.hostName {
                subtitleParts.append(hostName)
            }
            subtitleParts.append(workspace.folderPath)
            if let groupName = presentation.groupName {
                subtitleParts.append(groupName)
            }

            return VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(workspace.name)
                        .font(NexusMacTheme.displayFont(24, relativeTo: .title2))
                        .foregroundStyle(NexusMacTheme.textPrimary)
                    Spacer()
                    NexusStatusPill(
                        text: workspace.kind == .remote ? "Remote" : "Local",
                        color: workspace.kind == .remote ? NexusMacTheme.teal : NexusMacTheme.gold
                    )
                }

                Text(subtitleParts.joined(separator: "  ·  "))
                    .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                    .foregroundStyle(NexusMacTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
        }

        /// Only renders when there's an actual Workspace or Host problem to act on \u2014
        /// a healthy remote target stays silent instead of repeating "everything is fine".
        @ViewBuilder
        private func workspaceRemoteIssueStrip(remoteTarget: RemoteWorkspaceTargetOverview) -> some View {
            let hostState = remoteTarget.hostValidation?.state
            let hasWorkspaceIssue =
                remoteTarget.workspaceAvailability.state != .available
                || remoteTarget.workspaceAvailability.diagnostics.isEmpty == false
            let hasHostIssue = hostState != .available

            if hasWorkspaceIssue || hasHostIssue {
                VStack(alignment: .leading, spacing: 8) {
                    if hasWorkspaceIssue {
                        issueRow(
                            symbol: remoteTarget.workspaceAvailability.state.tone.symbolName,
                            color: remoteTarget.workspaceAvailability.state.tone.color,
                            title: "Workspace "
                                + workspaceAvailabilityStateTitle(
                                    remoteTarget.workspaceAvailability.state
                                ).lowercased(),
                            detail: remoteTarget.workspaceAvailability.summary
                        )
                    }

                    if hasHostIssue {
                        issueRow(
                            symbol: hostState.tone.symbolName,
                            color: hostState.tone.color,
                            title: "Host " + hostValidationStateTitle(hostState).lowercased(),
                            detail: remoteTarget.hostValidation?.summary
                                ?? "Validate this Host to unblock deeper remote checks."
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
        }

        /// One scannable warning line \u2014 icon, title, detail \u2014 with no card chrome. Used
        /// anywhere a Workspace/Host/Provider problem needs to surface inline instead of a
        /// dedicated diagnostics panel nobody reads when things are fine.
        private func issueRow(symbol: String, color: Color, title: String, detail: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.prefix(1).uppercased() + title.dropFirst())
                        .font(NexusMacTheme.bodyFont(13).weight(.semibold))
                        .foregroundStyle(NexusMacTheme.textPrimary)
                    Text(detail)
                        .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        /// The entire row launches/resumes the Provider's default Session \u2014 matching how
        /// every other browse row in Nexus acts on tap. "View Details" moves to the right-click
        /// menu since it's the secondary, occasional action, not the primary one.
        private func providerRow(workspaceID: UUID, card: WorkspaceProviderCard) -> some View {
            let identityAccent = NexusMacTheme.providerAccent(card.provider.id)
            let healthColor = card.health.state.tone.color
            let action: () -> Void = {
                launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: card.provider.id)
            }

            return NexusListRow(action: action) {
                HStack(spacing: 14) {
                    NexusIconBadge(
                        systemImage: card.prelaunchPrimarySurface == .terminal ? "terminal.fill" : "message.fill",
                        accent: identityAccent
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.provider.displayName)
                            .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                            .foregroundStyle(NexusMacTheme.textPrimary)
                        Text(card.defaultSession.summary)
                            .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.mutedText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if card.alternateSessionCount > 0 {
                        Text("\(card.alternateSessionCount)")
                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(NexusMacTheme.mutedText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NexusMacTheme.overlay(0.06), in: Capsule())
                    }

                    Circle()
                        .fill(healthColor)
                        .frame(width: 6, height: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NexusMacTheme.mutedText.opacity(0.55))
                }
            }
            .disabled(card.capabilities.launchDefaultSession.isEnabled == false)
            .contextMenu {
                Button("View Details") {
                    selection = .provider(workspaceID, card.provider.id)
                }
            }
        }

        private func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) {
            selection = .provider(workspaceID, providerID)

            Task {
                do {
                    let session = try await appModel.launchOrResumeDefaultSession(
                        workspaceID: workspaceID, providerID: providerID)
                    focusedSessionID = session.id
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
        }

        private func providerDetail(workspaceID: UUID, providerID: ProviderID, detail: ProviderDetail?) -> some View {
            let placeholder = appModel.providerDetailPlaceholder(for: workspaceID, providerID: providerID)

            return ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let detail {
                        providerDetailHeader(
                            providerID: providerID,
                            workspace: detail.workspace,
                            health: detail.health,
                            prelaunchPrimarySurface: detail.prelaunchPrimarySurface
                        )

                        if detail.health.state != .available || detail.health.diagnostics.isEmpty == false {
                            providerIssueStrip(health: detail.health)
                        }

                        providerSessionsSection(workspaceID: workspaceID, providerID: providerID, detail: detail)
                    } else if let placeholder {
                        providerDetailHeader(
                            providerID: providerID,
                            workspace: placeholder.workspace,
                            health: placeholder.providerCard.health,
                            prelaunchPrimarySurface: placeholder.providerCard.prelaunchPrimarySurface
                        )

                        if placeholder.providerCard.health.state != .available
                            || placeholder.providerCard.health.diagnostics.isEmpty == false
                        {
                            providerIssueStrip(health: placeholder.providerCard.health)
                        }

                        providerPlaceholderSessionsSection(
                            workspaceID: workspaceID,
                            providerID: providerID,
                            placeholder: placeholder
                        )
                    } else {
                        Text("Loading provider detail...")
                            .font(NexusMacTheme.bodyFont(14))
                            .foregroundStyle(NexusMacTheme.mutedText)
                            .padding(.horizontal, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private func providerDetailHeader(
            providerID: ProviderID,
            workspace: Workspace,
            health: ProviderHealthSummary,
            prelaunchPrimarySurface: SessionSurface
        ) -> some View {
            HStack(spacing: 12) {
                NexusIconBadge(
                    systemImage: prelaunchPrimarySurface == .terminal ? "terminal.fill" : "message.fill",
                    accent: NexusMacTheme.providerAccent(providerID),
                    size: 34
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(providerID.displayName)
                        .font(NexusMacTheme.displayFont(22, relativeTo: .title2))
                        .foregroundStyle(NexusMacTheme.textPrimary)
                    Text(
                        [workspace.name, health.version].compactMap { $0 }.joined(separator: "  ·  ")
                    )
                    .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                    .foregroundStyle(NexusMacTheme.mutedText)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(health.state.tone.color)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 14)
        }

        private func providerIssueStrip(health: ProviderHealthSummary) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                issueRow(
                    symbol: health.state.tone.symbolName,
                    color: health.state.tone.color,
                    title: "Provider " + health.state.rawValue.lowercased(),
                    detail: health.summary
                )

                ForEach(Array(health.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Text(diagnostic.message)
                        .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .padding(.leading, 26)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
        }

        /// Default, Named, and Failed Sessions used to be three separate sections with
        /// their own headers and a "relaunch" button living apart from the row it acted
        /// on. They're really one concept \u2014 a Session you can return to \u2014 so they're one
        /// scannable list now: click a row to relaunch/resume it, right-click to delete it.
        private func providerSessionsSection(
            workspaceID: UUID, providerID: ProviderID, detail: ProviderDetail
        ) -> some View {
            let entries = providerSessionRowEntries(workspaceID: workspaceID, providerID: providerID, detail: detail)

            return VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sessions")
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(NexusMacTheme.mutedText)
                    Spacer()
                    Button("New Session") {
                        createNamedSession(workspaceID: workspaceID, providerID: providerID)
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(detail.capabilities.createNamedSession.isEnabled == false)
                }
                .padding(.horizontal, 14)

                if entries.isEmpty {
                    Text("No Sessions yet \u{2014} launch the default Session or start a new one.")
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .padding(.horizontal, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                NexusRowDivider()
                            }
                            sessionRow(
                                entry.session, workspace: detail.workspace, workspaceID: workspaceID,
                                providerID: providerID, primaryAction: entry.primaryAction)
                        }
                    }
                }
            }
        }

        private func providerPlaceholderSessionsSection(
            workspaceID: UUID,
            providerID: ProviderID,
            placeholder: ProviderDetailPlaceholder
        ) -> some View {
            let providerCard = placeholder.providerCard

            return VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sessions")
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(NexusMacTheme.mutedText)
                    Spacer()
                    Button("New Session") {
                        createNamedSession(workspaceID: workspaceID, providerID: providerID)
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(providerCard.capabilities.createNamedSession.isEnabled == false)
                }
                .padding(.horizontal, 14)

                if providerCard.defaultSession.state != .notCreated {
                    NexusListRow(
                        action: {
                            launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: providerID)
                        },
                        content: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(providerDefaultSessionTone(providerCard.defaultSession.state).color)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Default Session")
                                        .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                                        .foregroundStyle(NexusMacTheme.textPrimary)
                                    Text(providerCard.defaultSession.summary)
                                        .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                        .foregroundStyle(NexusMacTheme.mutedText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Text(providerCard.defaultSession.actionTitle)
                                    .font(NexusMacTheme.bodyFont(12, relativeTo: .caption).weight(.semibold))
                                    .foregroundStyle(NexusMacTheme.mutedText)
                            }
                        }
                    )
                }

                if providerCard.alternateSessionCount > 0 {
                    Text(
                        "Loading \(providerCard.alternateSessionCount) named session\(providerCard.alternateSessionCount == 1 ? "" : "s")…"
                    )
                    .font(NexusMacTheme.bodyFont(14))
                    .foregroundStyle(NexusMacTheme.mutedText)
                    .padding(.horizontal, 14)
                } else if providerCard.defaultSession.state == .notCreated {
                    Text("No Sessions yet — launch the default Session or start a new one.")
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.mutedText)
                        .padding(.horizontal, 14)
                }
            }
        }

        private func providerDefaultSessionTone(_ state: ProviderDefaultSessionSummary.State) -> NexusStatusTone {
            switch state {
            case .notCreated:
                .unknown
            case .ready:
                .healthy
            case .interrupted:
                .warning
            case .exited, .failed:
                .critical
            }
        }

        private func providerSessionRowEntries(
            workspaceID: UUID, providerID: ProviderID, detail: ProviderDetail
        ) -> [ProviderSessionRowEntry] {
            var entries: [ProviderSessionRowEntry] = []

            if let defaultSession = detail.defaultSession {
                entries.append(
                    ProviderSessionRowEntry(session: defaultSession) {
                        self.launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: providerID)
                    })
            }

            for session in detail.alternateSessions {
                entries.append(
                    ProviderSessionRowEntry(session: session) {
                        self.focusedSessionID = session.id
                        self.selection = .provider(workspaceID, providerID)
                    })
            }

            for session in detail.failedSessions {
                entries.append(
                    ProviderSessionRowEntry(session: session) {
                        self.focusedSessionID = session.id
                        self.selection = .provider(workspaceID, providerID)
                    })
            }

            return entries
        }

        private func sessionRow(
            _ session: Session,
            workspace: Workspace,
            workspaceID: UUID,
            providerID: ProviderID,
            primaryAction: @escaping () -> Void
        ) -> some View {
            let accent = session.state.tone.color
            let canDelete = providerSessionCanDeleteRecord(session, workspace: workspace)

            return NexusListRow(action: primaryAction) {
                HStack(spacing: 14) {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.isDefault ? "Default Session" : (session.name ?? "Named Session"))
                            .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                            .foregroundStyle(NexusMacTheme.textPrimary)
                        Text(session.failureMessage ?? session.state.rawValue.capitalized)
                            .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.mutedText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NexusMacTheme.mutedText.opacity(0.55))
                }
            }
            .contextMenu {
                if canDelete {
                    Button("Delete Session Record", role: .destructive) {
                        deleteSessionRecord(session, workspaceID: workspaceID, providerID: providerID)
                    }
                } else {
                    Button("Stop Session") {
                        stopSession(session, workspaceID: workspaceID, providerID: providerID)
                    }
                }
            }
        }

        private func createNamedSession(workspaceID: UUID, providerID: ProviderID) {
            Task {
                do {
                    let session = try await appModel.createNamedSession(
                        workspaceID: workspaceID, providerID: providerID)
                    focusedSessionID = session.id
                    selection = .provider(workspaceID, providerID)
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
        }

        private func sessionDetailContent(
            summary: FocusedSessionSummaryPresentation,
            screen: SessionScreen?,
            context: SessionPresentationContext?
        ) -> some View {
            let isReady = summary.session.state == .ready
            let isRemote = context?.isRemote == true
            let surface = summary.primarySurface
            let stateColor = summary.session.state.tone.color

            let providerAccent = NexusMacTheme.providerAccent(summary.session.providerID)

            return VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.session.providerID.displayName)
                            .font(NexusMacTheme.bodyFont(17).weight(.semibold))
                            .foregroundStyle(providerAccent)

                        if let context {
                            Text(sessionSubtitle(for: context, surface: surface))
                                .font(NexusMacTheme.bodyFont(12, relativeTo: .caption))
                                .foregroundStyle(NexusMacTheme.mutedText)
                        }
                    }

                    Spacer()

                    Button {
                        focusedSessionID = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title3)
                            .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Close (keeps the Session running)")

                    Menu {
                        if isRemote, isReady {
                            Button("Detach") {
                                detachSession(summary.session)
                            }
                        }

                        if isReady {
                            Button("Stop Session") {
                                stopSession(
                                    summary.session,
                                    workspaceID: summary.session.workspaceID,
                                    providerID: summary.session.providerID
                                )
                            }
                        }

                        if isReady == false {
                            Button("Relaunch Session") {
                                Task {
                                    do {
                                        let session = try await appModel.relaunchFocusedSession()
                                        focusedSessionID = session.id
                                    } catch {
                                        presentedError = PresentedError(message: error.localizedDescription)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.86))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .nexusPanel(tint: stateColor, radius: 16)

                if surface == .structuredActivityFeed {
                    structuredSessionFeed(isReady: isReady)
                } else if let screen {
                    terminalSessionFeed(screen: screen, isReady: isReady)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private func sessionSubtitle(for context: SessionPresentationContext, surface: SessionSurface) -> String {
            if context.isRemote {
                return surface == .terminal
                    ? "\(context.workspace.name) • \(context.hostName ?? "Remote") • terminal"
                    : "\(context.workspace.name) • \(context.hostName ?? "Remote")"
            }

            return surface == .terminal
                ? "\(context.workspace.name) • terminal"
                : context.workspace.name
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
                        .foregroundStyle(NexusMacTheme.textPrimary)
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
            .background(NexusMacTheme.overlay(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

        private func providerSessionRow(
            _ session: Session,
            primaryActionTitle: String,
            primaryAction: @escaping () -> Void,
            secondaryActionTitle: String? = nil,
            secondaryAction: (() -> Void)? = nil
        ) -> some View {
            let accent = session.state.tone.color

            return HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    NexusStatusPill(
                        text: session.isDefault ? "Default session" : (session.name ?? "Named session"),
                        color: accent
                    )
                    Text(session.failureMessage ?? session.state.rawValue.capitalized)
                        .font(NexusMacTheme.bodyFont(14))
                        .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.9))
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
                    _ = try await appModel.stopSession(
                        sessionID: session.id, workspaceID: workspaceID, providerID: providerID)
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
        }

        private func detachSession(_ session: Session) {
            Task {
                _ = await appModel.detachFocusedSession()
                focusedSessionID = nil
                selection = .provider(session.workspaceID, session.providerID)
            }
        }

        private func deleteSessionRecord(_ session: Session, workspaceID: UUID, providerID: ProviderID) {
            Task {
                do {
                    _ = try await appModel.deleteSessionRecord(
                        sessionID: session.id, workspaceID: workspaceID, providerID: providerID)
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
        }

        private func providerSessionCanDeleteRecord(_ session: Session, workspace: Workspace) -> Bool {
            if session.state != .ready {
                return true
            }

            return session.providerID == .ibmBob && workspace.kind == .local
        }

        private func openCommandPalette() {
            quickSwitchSearchCoordinator.cancel()
            quickSwitchQuery = ""
            quickSwitchResults = []
            isShowingQuickSwitchSheet = true
        }

        private var commandPaletteActions: [NexusCommandPaletteAction] {
            [
                NexusCommandPaletteAction(
                    id: "new-local-workspace",
                    title: "New Local Workspace",
                    subtitle: "Add a folder on this Mac.",
                    systemImage: "folder.badge.plus",
                    perform: { self.addLocalWorkspace() }
                ),
                NexusCommandPaletteAction(
                    id: "new-remote-workspace",
                    title: "New Remote Workspace",
                    subtitle: "Add a Host and remote path.",
                    systemImage: "macbook.and.iphone",
                    perform: { isShowingCreateRemoteWorkspaceSheet = true }
                ),
                NexusCommandPaletteAction(
                    id: "new-workspace-group",
                    title: "New Workspace Group",
                    subtitle: "Create a curated lane for related Workspaces.",
                    systemImage: "line.3.horizontal.decrease.circle",
                    perform: {
                        newWorkspaceGroupName = ""
                        isShowingCreateWorkspaceGroupSheet = true
                    }
                ),
                NexusCommandPaletteAction(
                    id: "show-hosts",
                    title: "Hosts",
                    subtitle: "Review saved remote Host profiles.",
                    systemImage: "network",
                    perform: {
                        settingsTabSelection.tab = .hosts
                        openSettings()
                    }
                ),
                NexusCommandPaletteAction(
                    id: "show-remote-access",
                    title: "Remote Access",
                    subtitle: "Manage Paired Devices and pairing.",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    perform: {
                        settingsTabSelection.tab = .remoteAccess
                        openSettings()
                    }
                ),
            ]
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
                focusedSessionID = sessionID
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

                    Picker(
                        "Workspace Group",
                        selection: Binding(
                            get: {
                                pendingWorkspaceGroupID ?? appModel.workspaceGroups.first?.id ?? UUID()
                            }, set: { pendingWorkspaceGroupID = $0 })
                    ) {
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
                                    let workspace = try await appModel.createLocalWorkspace(
                                        folderPath: folderPath, primaryGroupID: groupID)
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
                            reportTerminalSize(proxy.size, for: screen.session.id)
                            if isReady {
                                terminalFocusToken = UUID()
                            }
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            terminalViewportSize = newSize
                            reportTerminalSize(newSize, for: screen.session.id)
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
                reportTerminalSize(terminalViewportSize, for: screen.session.id)
            }
            .onDisappear {
                terminalViewportResizeCoordinator.cancel()
            }
        }

        @ViewBuilder
        private func structuredSessionFeed(isReady: Bool) -> some View {
            if let structuredPresentation = appModel.focusedStructuredSessionPresentation {
                let structuredChrome = appModel.focusedStructuredSessionChromePresentation
                let feedPresentation = structuredPresentation.feed
                let approvalRequestPresentation = structuredSessionApprovalRequestPresentation(hasWriterAuthority: true)
                let extensionUI = structuredChrome?.extensionUI
                let aboveEditorWidgets = extensionUI?.widgets.filter { $0.placement == .aboveEditor } ?? []
                let belowEditorWidgets = extensionUI?.widgets.filter { $0.placement == .belowEditor } ?? []

                VStack(spacing: 0) {
                    // Supplementary chrome (approvals, extension dialogs/summary) lives *above* the scrolling feed.
                    // This keeps live appends in the activity feed from forcing re-measurement of the chrome,
                    // and vice-versa. The feed ScrollView is now the only live-updating scroller.
                    if let extensionUI, extensionUI.pendingDialogs.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(extensionUI.pendingDialogs) { dialog in
                                structuredSessionExtensionDialogView(dialog)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    }

                    if feedPresentation.pendingApprovalRequests.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(feedPresentation.pendingApprovalRequests) { request in
                                structuredSessionApprovalRequestView(request, presentation: approvalRequestPresentation)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    }

                    if let extensionUI,
                        extensionUI.title != nil || extensionUI.statuses.isEmpty == false
                            || extensionUI.notifications.isEmpty == false
                    {
                        structuredSessionExtensionSummaryView(extensionUI)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    MacStructuredSessionFeedScrollLayer(
                        presentation: structuredPresentation,
                        feedPresentation: feedPresentation,
                        scrollPosition: $structuredSessionFeedScrollPosition,
                        pinState: $structuredSessionPinState,
                        scrollSnapshot: $structuredSessionFeedScrollSnapshot,
                        visibleTailRowCount: $structuredSessionMacOSFeedVisibleTailRowCount,
                        coordinator: structuredSessionAutoScrollCoordinator,
                        draftGrowthThrottle: structuredSessionDraftGrowthScrollThrottle,
                        onAppearSetup: {
                            structuredSessionPinState = StructuredSessionFeedPinState()
                            structuredSessionScheduleMacOSFeedActivityRowsIfNeeded()
                            if structuredSessionEffectiveAgentTurnInProgress(for: structuredPresentation) {
                                structuredSessionFeedScrollPosition = ScrollPosition()
                            }
                        },
                        onSessionIdentityChange: {
                            structuredSessionPinState = StructuredSessionFeedPinState()
                            structuredSessionFeedScrollSnapshot = nil
                            presentedStructuredSessionAssistantFullResponse = nil
                            structuredSessionMacOSFeedVisibleTailRowCount = 0
                            structuredSessionAgentTurnDisclosureState.reset()
                            structuredSessionFeedScrollPosition = ScrollPosition()
                            structuredSessionScheduleMacOSFeedActivityRowsIfNeeded()
                        },
                        content: {
                            MacStructuredSessionFeedScrollContent(
                                structuredPresentation: structuredPresentation,
                                feedPresentation: feedPresentation,
                                visibleTailRowCount: structuredSessionMacOSFeedVisibleTailRowCount,
                                disclosureState: structuredSessionAgentTurnDisclosureState,
                                historyPaging: { structuredSessionHistoryPagingControls() },
                                activityRow: { structuredSessionActivityRowView($0) },
                                onShowFullAssistantResponse: { presentedStructuredSessionAssistantFullResponse = $0 },
                                thinkingIndicator: { structuredSessionThinkingIndicatorView($0) }
                            )
                        }
                    )

                    if isReady, let structuredChrome {
                        MacStructuredSessionComposerSection(
                            chrome: structuredChrome,
                            appModel: appModel,
                            workspaceLocation: structuredSessionWorkspaceLocation(for: structuredChrome.session),
                            aboveEditorWidgets: aboveEditorWidgets,
                            belowEditorWidgets: belowEditorWidgets,
                            onError: { message in
                                presentedError = PresentedError(message: message)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .nexusPanel(tint: NexusMacTheme.teal, radius: 22)
                .sheet(item: $presentedStructuredSessionAssistantFullResponse) { presentation in
                    NavigationStack {
                        StructuredSessionAssistantFullResponseReader(markdown: presentation.markdown)
                            .navigationTitle("Assistant response")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") {
                                        presentedStructuredSessionAssistantFullResponse = nil
                                    }
                                }
                            }
                    }
                    .frame(minWidth: 520, minHeight: 420)
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

        private func structuredSessionScheduleMacOSFeedActivityRowsIfNeeded() {
            guard StructuredSessionFeedMacOSStartupPolicy.usesProgressiveActivityRowReveal else {
                structuredSessionMacOSFeedVisibleTailRowCount = Int.max
                return
            }
            guard structuredSessionMacOSFeedVisibleTailRowCount == 0 else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                structuredSessionRevealMacOSFeedActivityRowsProgressively()
            }
        }

        private func structuredSessionRevealMacOSFeedActivityRowsProgressively() {
            guard let feed = appModel.focusedStructuredSessionPresentation?.feed else {
                return
            }
            let total = feed.feedScrollItemCount
            guard total > 0 else {
                structuredSessionMacOSFeedVisibleTailRowCount = 0
                return
            }
            let initial = min(StructuredSessionFeedMacOSStartupPolicy.initialVisibleTailRowCount, total)
            structuredSessionMacOSFeedVisibleTailRowCount = initial
            guard initial < total else {
                return
            }
            Task { @MainActor in
                var visible = initial
                while visible < total {
                    await Task.yield()
                    visible = StructuredSessionFeedMacOSStartupPolicy.nextVisibleTailRowCount(
                        currentVisibleCount: visible,
                        totalRowCount: total
                    )
                    structuredSessionMacOSFeedVisibleTailRowCount = visible
                }
            }
        }

        @ViewBuilder
        private func structuredSessionHistoryPagingControls() -> some View {
            if appModel.canLoadOlderFocusedStructuredSessionHistory
                || appModel.isLoadingOlderFocusedStructuredSessionHistory
                || appModel.focusedStructuredSessionHistoryErrorMessage != nil
            {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task {
                            await appModel.loadOlderFocusedStructuredSessionHistory()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if appModel.isLoadingOlderFocusedStructuredSessionHistory {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(
                                appModel.isLoadingOlderFocusedStructuredSessionHistory
                                    ? "Loading older activity..." : "Load older activity")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NexusSecondaryButtonStyle())
                    .disabled(
                        appModel.isLoadingOlderFocusedStructuredSessionHistory
                            || appModel.canLoadOlderFocusedStructuredSessionHistory == false)

                    if let errorMessage = appModel.focusedStructuredSessionHistoryErrorMessage {
                        Text(errorMessage)
                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.coral)
                    }
                }
            }
        }

        @ViewBuilder
        private func structuredSessionActivityRowView(_ row: StructuredSessionActivityRow) -> some View {
            let accent = structuredSessionActivityColor(for: row.emphasis)
            let conversation =
                row.conversationPresentation
                ?? StructuredSessionConversationPresentation(
                    role: .system,
                    text: row.text
                )

            switch conversation.role {
            case .user:
                HStack {
                    Spacer(minLength: 48)
                    Text(conversation.text)
                        .font(NexusMacTheme.bodyFont(13))
                        .foregroundStyle(NexusMacTheme.textPrimary)
                        .structuredSessionFeedTextSelection()
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NexusMacTheme.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .frame(maxWidth: 520, alignment: .trailing)
                        .contextMenu {
                            Button("Copy") {
                                structuredSessionFeedMarkdownCopyToPasteboard(conversation.text)
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            case .assistant(let label):
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(NexusMacTheme.bodyFont(10, relativeTo: .caption).weight(.medium))
                        .foregroundStyle(NexusMacTheme.mutedText)

                    structuredSessionAssistantResponseView(
                        conversation,
                        rowID: row.id,
                        font: NexusMacTheme.bodyFont(13),
                        color: NexusMacTheme.terminalText.opacity(0.94)
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NexusMacTheme.overlay(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: 520, alignment: .leading)
                .contextMenu {
                    Button("Copy") {
                        structuredSessionFeedMarkdownCopyToPasteboard(conversation.text)
                    }
                }
            case .command:
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.title)
                        .font(NexusMacTheme.monoFont(10, relativeTo: .caption))
                        .foregroundStyle(accent)
                    Text(conversation.text)
                        .font(NexusMacTheme.monoFont(11, relativeTo: .callout))
                        .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                        .structuredSessionFeedTextSelection()
                        .fixedSize(horizontal: false, vertical: true)
                    if let detailText = row.detailText {
                        structuredSessionDetailTextView(
                            detailText,
                            isTruncated: row.isDetailTextTruncated,
                            font: NexusMacTheme.monoFont(11, relativeTo: .callout)
                        )
                    }
                }
                .padding(12)
                .background(NexusMacTheme.overlay(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 620, alignment: .leading)
            case .error:
                VStack(alignment: .leading, spacing: 5) {
                    Text("Error")
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                        .foregroundStyle(accent)
                    Text(conversation.text)
                        .font(NexusMacTheme.bodyFont(13))
                        .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.94))
                        .structuredSessionFeedTextSelection()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 620, alignment: .leading)
            case .system:
                Group {
                    if row.showsExpandedSystemCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.title)
                                .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.medium))
                                .foregroundStyle(NexusMacTheme.mutedText)
                            Text(verbatim: conversation.text)
                                .font(NexusMacTheme.bodyFont(13))
                                .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                                .structuredSessionFeedTextSelection()
                                .fixedSize(horizontal: false, vertical: true)
                            if let detailText = row.detailText {
                                structuredSessionDetailTextView(
                                    detailText,
                                    isTruncated: row.isDetailTextTruncated,
                                    font: NexusMacTheme.monoFont(11, relativeTo: .callout)
                                )
                            }
                        }
                        .padding(12)
                        .background(
                            NexusMacTheme.overlay(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .frame(maxWidth: 620, alignment: .leading)
                    } else {
                        Text(conversation.text)
                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.mutedText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NexusMacTheme.overlay(0.05), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }

        private func structuredSessionMarkdownText(_ text: String, font: Font, color: Color) -> some View {
            StructuredSessionMarkdownText(markdown: text, font: font, color: color)
        }

        @ViewBuilder
        private func structuredSessionAssistantResponseView(
            _ conversation: StructuredSessionConversationPresentation,
            rowID: UUID,
            font: Font,
            color: Color
        ) -> some View {
            if conversation.isStreaming {
                let streamingPolicy = structuredSessionFeedStreamingAssistantDisplayPolicy(
                    for: conversation.text,
                    charactersPerLine: 72
                )
                let streamingDisplayText = structuredSessionFeedStreamingAssistantDisplayText(
                    for: conversation.text,
                    policy: streamingPolicy
                )
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if streamingPolicy.usesBoundedViewport {
                            Text(verbatim: streamingDisplayText)
                                .font(font)
                                .foregroundStyle(color)
                                .structuredSessionFeedTextSelection()
                                .lineLimit(streamingPolicy.previewLineLimit)
                                .truncationMode(.tail)
                                .frame(
                                    height: structuredSessionFeedCollapsedDetailViewportHeight,
                                    alignment: .top
                                )
                                .clipped()
                        } else {
                            Text(verbatim: streamingDisplayText)
                                .font(font)
                                .foregroundStyle(color)
                                .structuredSessionFeedTextSelection()
                                .lineLimit(streamingPolicy.previewLineLimit)
                                .truncationMode(.tail)
                        }
                    }

                    if streamingPolicy.usesBoundedViewport {
                        Text("Streaming response preview truncated until completion.")
                            .font(NexusMacTheme.bodyFont(10, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.mutedText)
                    }
                }
            } else {
                let policy = structuredSessionFeedAssistantMarkdownDisplayPolicy(
                    for: conversation.text,
                    charactersPerLine: 72
                )
                if policy.showsCollapsedPreview {
                    let previewMarkdown = structuredSessionFeedAssistantMarkdownBoundedPreviewText(
                        for: conversation.text)
                    VStack(alignment: .leading, spacing: 8) {
                        structuredSessionMarkdownText(previewMarkdown, font: font, color: color)
                            .lineLimit(policy.previewLineLimit)
                            .truncationMode(.tail)
                            .frame(
                                height: structuredSessionFeedCollapsedDetailViewportHeight,
                                alignment: .top
                            )
                            .clipped()

                        Text(policy.collapsedFootnote)
                            .font(NexusMacTheme.bodyFont(10, relativeTo: .caption))
                            .foregroundStyle(NexusMacTheme.mutedText)

                        Button(policy.showFullResponseTitle) {
                            presentedStructuredSessionAssistantFullResponse =
                                structuredSessionAssistantFullResponsePresentation(
                                    rowID: rowID,
                                    markdown: conversation.text
                                )
                        }
                        .buttonStyle(.plain)
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.medium))
                        .foregroundStyle(NexusMacTheme.gold)
                    }
                } else {
                    structuredSessionMarkdownText(conversation.text, font: font, color: color)
                }
            }
        }

        @ViewBuilder
        private func structuredSessionDetailTextView(_ text: String, isTruncated: Bool, font: Font) -> some View {
            let showsCollapsedPreview = structuredSessionShouldCollapseDetailPreview(text, charactersPerLine: 84)

            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if showsCollapsedPreview {
                        Text(verbatim: text)
                            .font(font)
                            .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.84))
                            .structuredSessionFeedTextSelection()
                            .frame(
                                height: structuredSessionFeedCollapsedDetailViewportHeight,
                                alignment: .top
                            )
                            .clipped()
                    } else {
                        Text(verbatim: text)
                            .font(font)
                            .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.84))
                            .structuredSessionFeedTextSelection()
                    }
                }

                if isTruncated {
                    Text("Output preview truncated for smooth scrolling.")
                        .font(NexusMacTheme.bodyFont(10, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                } else if showsCollapsedPreview {
                    Text("Long output preview truncated for smooth scrolling.")
                        .font(NexusMacTheme.bodyFont(10, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(NexusMacTheme.terminalOverlay, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        private func structuredSessionThinkingIndicatorView(_ indicator: StructuredSessionThinkingIndicator)
            -> some View
        {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(NexusMacTheme.gold)
                Text(indicator.text)
                    .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                    .foregroundStyle(NexusMacTheme.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NexusMacTheme.overlay(0.05), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
        }

        private func structuredSessionApprovalRequestView(
            _ request: SessionApprovalRequest,
            presentation: StructuredSessionApprovalRequestPresentation
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("Approval Request", systemImage: "hand.raised.fill")
                    .font(NexusMacTheme.bodyFont(12, relativeTo: .headline).weight(.semibold))
                    .foregroundStyle(NexusMacTheme.gold)

                Text(request.title)
                    .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                    .foregroundStyle(NexusMacTheme.textPrimary)

                Text(request.text)
                    .font(NexusMacTheme.bodyFont(13))
                    .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                    .structuredSessionFeedTextSelection()
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
                .disabled(presentation.actionsAreEnabled == false)

                if presentation.actionsAreEnabled == false, let disabledReason = presentation.disabledReason {
                    Text(disabledReason)
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexusPanel(tint: NexusMacTheme.gold, radius: 16)
        }

        private func structuredSessionExtensionDialogView(_ dialog: SessionExtensionUIDialog) -> some View {
            StructuredSessionExtensionDialogCard(dialog: dialog) { response in
                respondToStructuredSessionExtensionDialog(dialog.id, response: response)
            }
        }

        private func structuredSessionExtensionSummaryView(_ extensionUI: SessionExtensionUIState) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                if let title = extensionUI.title, title.isEmpty == false {
                    Text(title)
                        .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                        .foregroundStyle(NexusMacTheme.textPrimary)
                }

                if extensionUI.statuses.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(NexusMacTheme.mutedText)

                        ForEach(extensionUI.statuses) { status in
                            Text(status.text)
                                .font(NexusMacTheme.bodyFont(12))
                                .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(NexusMacTheme.overlay(0.05), in: Capsule())
                        }
                    }
                }

                if extensionUI.notifications.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications")
                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(NexusMacTheme.mutedText)

                        ForEach(extensionUI.notifications.suffix(5)) { notification in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notification.kind.rawValue.capitalized)
                                    .font(NexusMacTheme.bodyFont(10, relativeTo: .caption).weight(.semibold))
                                    .foregroundStyle(structuredSessionExtensionNotificationColor(notification.kind))
                                Text(notification.message)
                                    .font(NexusMacTheme.bodyFont(12))
                                    .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                                    .structuredSessionFeedTextSelection()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                NexusMacTheme.overlay(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexusPanel(tint: NexusMacTheme.teal, radius: 16)
        }

        private func structuredSessionExtensionNotificationColor(_ kind: SessionExtensionUINotificationKind) -> Color {
            switch kind {
            case .info:
                NexusMacTheme.teal
            case .warning:
                NexusMacTheme.gold
            case .error:
                NexusMacTheme.coral
            }
        }

        private func structuredSessionActivityColor(for emphasis: StructuredSessionActivityEmphasis) -> Color {
            switch emphasis {
            case .neutral:
                NexusMacTheme.overlay(0.55)
            case .accent:
                NexusMacTheme.gold
            case .critical:
                NexusMacTheme.coral
            case .success:
                NexusMacTheme.teal
            }
        }

        private func structuredSessionWorkspaceLocation(for session: Session) -> String {
            appModel.sessionPresentationContext(for: session)?.targetSummary ?? "Workspace unavailable"
        }

        private func respondToStructuredSessionApprovalRequest(
            _ approvalRequestID: UUID, decision: ApprovalRequestDecision
        ) {
            Task { @MainActor in
                do {
                    try await appModel.respondToFocusedSessionApprovalRequest(approvalRequestID, decision: decision)
                } catch {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
        }

        private func respondToStructuredSessionExtensionDialog(
            _ dialogID: String, response: SessionExtensionUIDialogResponse
        ) {
            Task { @MainActor in
                do {
                    try await appModel.respondToFocusedSessionExtensionDialog(dialogID, response: response)
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

        private func renderedTerminalSegments(for line: TerminalLine, row: Int, screen: SessionScreen)
            -> [TerminalLineSegment]
        {
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
            let defaultForeground = NexusMacTheme.terminalText
            let defaultBackground = NexusMacTheme.terminalSurface
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
                    let blue = terminalColor.blue
                else {
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
                (255, 255, 255),
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

        private func reportTerminalSize(_ size: CGSize, for sessionID: UUID) {
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
                screen.terminalRows == rows
            {
                return
            }

            terminalViewportResizeCoordinator.report(
                .init(columns: columns, rows: rows),
                currentSize: {
                    guard let screen = appModel.focusedSessionScreen,
                        screen.session.id == sessionID
                    else {
                        return nil
                    }
                    return .init(columns: screen.terminalColumns, rows: screen.terminalRows)
                },
                submit: { size in
                    guard appModel.focusedSessionScreen?.session.id == sessionID else {
                        return
                    }
                    try await appModel.resizeFocusedSession(columns: size.columns, rows: size.rows)
                },
                onError: { error in
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            )
        }

    }

    private struct MacStructuredSessionComposerSection: View {
        let chrome: FocusedStructuredSessionChromePresentation
        let appModel: NexusAppModel
        let workspaceLocation: String
        let aboveEditorWidgets: [SessionExtensionUIWidget]
        let belowEditorWidgets: [SessionExtensionUIWidget]
        let onError: (String) -> Void

        @State private var draftState = StructuredSessionComposerDraftState()
        @State private var isComposerExpanded = false
        @State private var highlightedSlashCommandID: String?
        @FocusState private var isPromptFocused: Bool

        private static let collapsedLineLimit = 1...3
        private static let expandedLineLimit = 1...12
        private static let averageCharactersPerLine = 64

        private var needsDisclosureControl: Bool {
            ComposerOverflowHeuristic.exceedsCollapsedLineLimit(
                draftState.draft, collapsedLines: 3, averageCharactersPerLine: Self.averageCharactersPerLine)
        }

        var body: some View {
            let composerPresentation = structuredSessionComposerPresentation(for: chrome, hasWriterAuthority: true)
            let slashCommandMenuPresentation = structuredSessionSlashCommandMenuPresentation(
                for: draftState.draft,
                chrome: chrome
            )
            let highlightedSlashCommandID =
                slashCommandMenuPresentation.commands.first(where: { $0.id == self.highlightedSlashCommandID })?.id
                ?? slashCommandMenuPresentation.commands.first?.id
            let statusBarPresentation = structuredSessionStatusBarPresentation(
                for: chrome,
                workspaceLocation: workspaceLocation
            )

            VStack(alignment: .leading, spacing: 8) {
                if slashCommandMenuPresentation.isVisible {
                    slashCommandMenu(slashCommandMenuPresentation, highlightedCommandID: highlightedSlashCommandID)
                }

                if aboveEditorWidgets.isEmpty == false {
                    extensionWidgetsView(aboveEditorWidgets)
                }

                statusBar(statusBarPresentation)

                HStack(spacing: 8) {
                    TextField(composerPresentation.placeholder, text: draftBinding, axis: .vertical)
                        .focused($isPromptFocused)
                        .font(NexusMacTheme.bodyFont(13))
                        .textFieldStyle(.plain)
                        .lineLimit(isComposerExpanded ? Self.expandedLineLimit : Self.collapsedLineLimit)
                        .submitLabel(.send)
                        .disabled(composerPresentation.isEnabled == false || chrome.isAgentTurnInProgress)
                        .onKeyPress(.upArrow) {
                            guard slashCommandMenuPresentation.isVisible else {
                                return .ignored
                            }
                            moveSlashCommandHighlight(
                                by: -1,
                                from: highlightedSlashCommandID,
                                in: slashCommandMenuPresentation.commands
                            )
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            guard slashCommandMenuPresentation.isVisible else {
                                return .ignored
                            }
                            moveSlashCommandHighlight(
                                by: 1,
                                from: highlightedSlashCommandID,
                                in: slashCommandMenuPresentation.commands
                            )
                            return .handled
                        }
                        .onKeyPress(.tab) {
                            guard slashCommandMenuPresentation.isVisible,
                                let command = slashCommandMenuPresentation.commands.first(where: {
                                    $0.id == highlightedSlashCommandID
                                })
                            else {
                                return .ignored
                            }
                            draftState.apply(command)
                            return .handled
                        }
                        .onSubmit {
                            sendStructuredSessionPrompt()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            NexusMacTheme.overlay(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(NexusMacTheme.softLine, lineWidth: 1)
                        }
                        .overlay(alignment: .top) {
                            if needsDisclosureControl {
                                composerDisclosureControl
                                    .offset(y: -11)
                            }
                        }
                }

                if belowEditorWidgets.isEmpty == false {
                    extensionWidgetsView(belowEditorWidgets)
                }
            }
            .padding(14)
            .background(NexusMacTheme.overlay(0.02))
            .task(id: chrome.session.id) {
                draftState = StructuredSessionComposerDraftState()
                draftState.observe(editorText: chrome.extensionUI?.editorText)
            }
            .onChange(of: chrome.extensionUI?.editorText) { _, editorText in
                draftState.observe(editorText: editorText)
            }
        }

        private var composerDisclosureControl: some View {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isComposerExpanded.toggle()
                }
            } label: {
                Image(systemName: isComposerExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NexusMacTheme.mutedText)
                    .frame(width: 28, height: 16)
                    .background(NexusMacTheme.panelRaised, in: Capsule())
                    .overlay {
                        Capsule().stroke(NexusMacTheme.softLine, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(isComposerExpanded ? "Collapse" : "Expand")
        }

        private var draftBinding: Binding<String> {
            Binding(
                get: { draftState.draft },
                set: { draftState.updateDraft($0) }
            )
        }

        private func moveSlashCommandHighlight(
            by delta: Int,
            from currentID: String?,
            in commands: [StructuredSessionSlashCommand]
        ) {
            guard commands.isEmpty == false else {
                highlightedSlashCommandID = nil
                return
            }
            let currentIndex = commands.firstIndex { $0.id == currentID } ?? 0
            let nextIndex = (currentIndex + delta + commands.count) % commands.count
            highlightedSlashCommandID = commands[nextIndex].id
        }

        @ViewBuilder
        private func slashCommandMenu(
            _ menu: StructuredSessionSlashCommandMenuPresentation,
            highlightedCommandID: String?
        ) -> some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(menu.commands) { command in
                            let isHighlighted = command.id == highlightedCommandID
                            Button {
                                highlightedSlashCommandID = command.id
                                draftState.apply(command)
                                isPromptFocused = true
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(command.displayText)
                                            .font(NexusMacTheme.monoFont(12, relativeTo: .callout))
                                            .foregroundStyle(NexusMacTheme.textPrimary)
                                        Text(command.summary)
                                            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                                            .foregroundStyle(NexusMacTheme.mutedText)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        isHighlighted ? NexusMacTheme.gold.opacity(0.16) : NexusMacTheme.overlay(0.03))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isHighlighted ? NexusMacTheme.gold : NexusMacTheme.softLine.opacity(0.8),
                                        lineWidth: isHighlighted ? 1.5 : 1
                                    )
                            }
                            .id(command.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: highlightedCommandID) { _, newValue in
                    guard let newValue else {
                        return
                    }
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NexusMacTheme.terminalSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NexusMacTheme.softLine, lineWidth: 1)
            }
        }

        private func extensionWidgetsView(_ widgets: [SessionExtensionUIWidget]) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(widgets) { widget in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(widget.key)
                            .font(NexusMacTheme.bodyFont(10, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(NexusMacTheme.mutedText)
                        ForEach(Array(widget.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(NexusMacTheme.bodyFont(12))
                                .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NexusMacTheme.overlay(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }

        @ViewBuilder
        private func statusBar(_ presentation: StructuredSessionStatusBarPresentation) -> some View {
            HStack(spacing: 12) {
                Label {
                    Text(presentation.workspaceLocation)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "folder")
                }

                Spacer(minLength: 12)

                Label(presentation.tokenUsageText, systemImage: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(tokenUsageColor(presentation.tokenUsagePercent))
            }
            .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
            .foregroundStyle(NexusMacTheme.mutedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NexusMacTheme.overlay(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NexusMacTheme.softLine, lineWidth: 1)
            }
        }

        private func tokenUsageColor(_ percent: Int?) -> Color {
            guard let percent else {
                return NexusMacTheme.mutedText
            }

            switch percent {
            case 85...:
                return NexusMacTheme.coral
            case 60...:
                return NexusMacTheme.gold
            default:
                return NexusMacTheme.teal
            }
        }

        private func sendStructuredSessionPrompt() {
            let prompt = draftState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard prompt.isEmpty == false else {
                return
            }

            Task { @MainActor in
                do {
                    try await appModel.sendInputToFocusedSession(prompt)
                    draftState.clear()
                } catch {
                    onError(error.localizedDescription)
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
                        detail:
                            "Connect a saved Host to an absolute remote path so sessions can launch through Nexus from the same control deck."
                    )

                    if appModel.hosts.isEmpty == false {
                        Picker("Host", selection: $hostSource) {
                            Text("Existing Host").tag(HostSource.existing)
                            Text("New Host").tag(HostSource.new)
                        }
                        .pickerStyle(.segmented)
                    }

                    if hostSource == .existing, appModel.hosts.isEmpty == false {
                        Picker(
                            "Existing Host",
                            selection: Binding(
                                get: {
                                    selectedHostID ?? appModel.hosts.first?.id ?? UUID()
                                }, set: { selectedHostID = $0 })
                        ) {
                            ForEach(appModel.hosts) { host in
                                Text(host.name).tag(host.id)
                            }
                        }

                        if let detail = selectedHostDetail,
                            let snapshot = detail.latestValidation,
                            snapshot.state == .unavailable || snapshot.state == .broken
                        {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(snapshot.summary, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(NexusMacTheme.gold)
                                Text(
                                    "You can still create this Remote Workspace, but the Host is not currently validated."
                                )
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
                        let host = try await appModel.createHost(
                            name: newHostName, sshTarget: newHostTarget, port: port)
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
                throw NSError(
                    domain: "RemoteWorkspaceCreation", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Host port must be a number"])
            }
            return port
        }

        @MainActor
        private func loadSelectedHostDetail() async {
            guard hostSource == .existing,
                let selectedHostID,
                appModel.hostDetail(for: selectedHostID) == nil
            else {
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

    private struct StructuredSessionExtensionDialogCard: View {
        let dialog: SessionExtensionUIDialog
        let onRespond: (SessionExtensionUIDialogResponse) -> Void

        @State private var selectedOption: String
        @State private var textValue: String

        init(dialog: SessionExtensionUIDialog, onRespond: @escaping (SessionExtensionUIDialogResponse) -> Void) {
            self.dialog = dialog
            self.onRespond = onRespond
            _selectedOption = State(initialValue: dialog.options.first ?? "")
            _textValue = State(initialValue: dialog.prefill ?? "")
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label("Extension UI", systemImage: "puzzlepiece.extension.fill")
                    .font(NexusMacTheme.bodyFont(12, relativeTo: .headline).weight(.semibold))
                    .foregroundStyle(NexusMacTheme.teal)

                Text(dialog.title)
                    .font(NexusMacTheme.bodyFont(14).weight(.semibold))
                    .foregroundStyle(NexusMacTheme.textPrimary)

                if let message = dialog.message, message.isEmpty == false {
                    Text(message)
                        .font(NexusMacTheme.bodyFont(13))
                        .foregroundStyle(NexusMacTheme.textPrimary.opacity(0.92))
                        .textSelection(.enabled)
                }

                switch dialog.kind {
                case .select:
                    Picker("Options", selection: $selectedOption) {
                        ForEach(dialog.options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            onRespond(.cancelled)
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())

                        Button("Select") {
                            onRespond(.value(selectedOption))
                        }
                        .buttonStyle(NexusAccentButtonStyle())
                        .disabled(selectedOption.isEmpty)
                    }
                case .confirm:
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            onRespond(.confirmed(false))
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())

                        Button("Confirm") {
                            onRespond(.confirmed(true))
                        }
                        .buttonStyle(NexusAccentButtonStyle())
                    }
                case .input:
                    TextField(dialog.placeholder ?? dialog.title, text: $textValue, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            onRespond(.cancelled)
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())

                        Button("Submit") {
                            onRespond(.value(textValue))
                        }
                        .buttonStyle(NexusAccentButtonStyle())
                    }
                case .editor:
                    TextEditor(text: $textValue)
                        .font(NexusMacTheme.bodyFont(13))
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(
                            NexusMacTheme.overlay(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(NexusMacTheme.softLine, lineWidth: 1)
                        }

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            onRespond(.cancelled)
                        }
                        .buttonStyle(NexusSecondaryButtonStyle())

                        Button("Submit") {
                            onRespond(.value(textValue))
                        }
                        .buttonStyle(NexusAccentButtonStyle())
                    }
                }

                if let timeoutMilliseconds = dialog.timeoutMilliseconds {
                    Text("Auto-cancels after \(timeoutMilliseconds / 1000)s")
                        .font(NexusMacTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusMacTheme.mutedText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexusPanel(tint: NexusMacTheme.teal, radius: 16)
        }
    }

    private struct WorkspaceSidebarBoundary<Content: View>: View {
        @Bindable var appModel: NexusAppModel
        @Binding var selection: SidebarSelection?
        private let content: (WorkspaceBrowseSidebarPresentation) -> Content

        init(
            appModel: NexusAppModel,
            selection: Binding<SidebarSelection?>,
            @ViewBuilder content: @escaping (WorkspaceBrowseSidebarPresentation) -> Content
        ) {
            self.appModel = appModel
            self._selection = selection
            self.content = content
        }

        var body: some View {
            content(appModel.workspaceBrowseSidebarPresentation(currentWorkspaceID: currentWorkspaceID))
        }

        private var currentWorkspaceID: UUID? {
            switch selection {
            case .workspace(let workspaceID):
                workspaceID
            case .provider(let workspaceID, _):
                workspaceID
            case .none:
                appModel.focusedSessionWorkspaceID
            case .workspaceGroup:
                nil
            }
        }
    }

    private struct WorkspaceBrowseNavigationBoundary<Content: View>: View {
        @Bindable var appModel: NexusAppModel
        let selection: SidebarSelection?
        private let content: (WorkspaceBrowseNavigationPresentation) -> Content

        init(
            appModel: NexusAppModel,
            selection: SidebarSelection?,
            @ViewBuilder content: @escaping (WorkspaceBrowseNavigationPresentation) -> Content
        ) {
            self.appModel = appModel
            self.selection = selection
            self.content = content
        }

        var body: some View {
            content(appModel.workspaceBrowseNavigationPresentation(currentWorkspaceID: currentWorkspaceID))
        }

        private var currentWorkspaceID: UUID? {
            switch selection {
            case .workspace(let workspaceID):
                workspaceID
            case .provider(let workspaceID, _):
                workspaceID
            case .none:
                appModel.focusedSessionWorkspaceID
            case .workspaceGroup:
                nil
            }
        }
    }

    private struct SidebarSelectionBootstrapBoundary: View {
        @Bindable var appModel: NexusAppModel
        @Binding var selection: SidebarSelection?
        @Binding var focusedSessionID: UUID?

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: initialTarget) {
                    guard selection == nil, focusedSessionID == nil, let initialTarget else {
                        return
                    }

                    switch initialTarget {
                    case .workspace(let workspaceID):
                        selection = .workspace(workspaceID)
                    case .workspaceGroup(let groupID):
                        selection = .workspaceGroup(groupID)
                    case .session(let sessionID):
                        focusedSessionID = sessionID
                    }
                }
        }

        private var initialTarget: WorkspaceBrowseInitialSelection? {
            appModel.workspaceBrowseNavigationPresentation(currentWorkspaceID: nil).initialSelection
        }
    }

    private struct WorkspaceHomeBoundary<Content: View>: View {
        @Bindable var appModel: NexusAppModel
        private let content: (WorkspaceHomePresentation) -> Content

        init(
            appModel: NexusAppModel,
            @ViewBuilder content: @escaping (WorkspaceHomePresentation) -> Content
        ) {
            self.appModel = appModel
            self.content = content
        }

        var body: some View {
            content(appModel.workspaceHomePresentation())
        }
    }

    private struct WorkspaceDetailBoundary<Content: View>: View {
        @Bindable var appModel: NexusAppModel
        let workspaceID: UUID
        private let content: (WorkspaceBrowseDetailPresentation) -> Content

        init(
            appModel: NexusAppModel,
            workspaceID: UUID,
            @ViewBuilder content: @escaping (WorkspaceBrowseDetailPresentation) -> Content
        ) {
            self.appModel = appModel
            self.workspaceID = workspaceID
            self.content = content
        }

        var body: some View {
            content(appModel.workspaceBrowseDetailPresentation(workspaceID: workspaceID))
        }
    }

    private struct WorkspaceGroupDetailBoundary<Content: View>: View {
        @Bindable var appModel: NexusAppModel
        let groupID: UUID
        private let content: (WorkspaceGroupDetailPresentation) -> Content

        init(
            appModel: NexusAppModel,
            groupID: UUID,
            @ViewBuilder content: @escaping (WorkspaceGroupDetailPresentation) -> Content
        ) {
            self.appModel = appModel
            self.groupID = groupID
            self.content = content
        }

        var body: some View {
            content(appModel.workspaceGroupDetailPresentation(groupID: groupID))
        }
    }

    private struct ProviderDetailBoundary<Content: View>: View {
        @Bindable var appModel: NexusAppModel
        let workspaceID: UUID
        let providerID: ProviderID
        private let content: (ProviderDetail?) -> Content

        init(
            appModel: NexusAppModel,
            workspaceID: UUID,
            providerID: ProviderID,
            @ViewBuilder content: @escaping (ProviderDetail?) -> Content
        ) {
            self.appModel = appModel
            self.workspaceID = workspaceID
            self.providerID = providerID
            self.content = content
        }

        var body: some View {
            content(appModel.providerDetail(for: workspaceID, providerID: providerID))
        }
    }

    private struct FocusedSessionDetailBoundary<Content: View, Unavailable: View>: View {
        @Bindable var appModel: NexusAppModel
        let sessionID: UUID
        private let content: (FocusedSessionSummaryPresentation, SessionScreen?, SessionPresentationContext?) -> Content
        private let unavailable: () -> Unavailable

        init(
            sessionID: UUID,
            appModel: NexusAppModel,
            @ViewBuilder content:
                @escaping (FocusedSessionSummaryPresentation, SessionScreen?, SessionPresentationContext?) -> Content,
            @ViewBuilder unavailable: @escaping () -> Unavailable
        ) {
            self.sessionID = sessionID
            self.appModel = appModel
            self.content = content
            self.unavailable = unavailable
        }

        var body: some View {
            Group {
                if let summary = appModel.focusedSessionSummaryPresentation,
                    summary.session.id == sessionID,
                    appModel.focusedSessionID == sessionID
                {
                    if summary.primarySurface == .structuredActivityFeed {
                        content(summary, nil, appModel.focusedSessionPresentationContext)
                    } else if let screen = appModel.focusedSessionScreen,
                        screen.session.id == sessionID
                    {
                        content(summary, screen, appModel.focusedSessionPresentationContext)
                    } else {
                        unavailable()
                    }
                } else {
                    unavailable()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

    private struct ProviderSessionRowEntry: Identifiable {
        let session: Session
        let primaryAction: () -> Void

        var id: UUID { session.id }
    }

    private enum SidebarSelection: Hashable {
        case workspaceGroup(UUID)
        case workspace(UUID)
        case provider(UUID, ProviderID)

        var navigationTarget: NavigationTarget? {
            switch self {
            case .workspaceGroup:
                nil
            case .workspace(let workspaceID):
                .workspace(workspaceID)
            case .provider(let workspaceID, let providerID):
                .provider(workspaceID: workspaceID, providerID: providerID)
            }
        }
    }

    private struct PresentedError: Identifiable {
        let id = UUID()
        let message: String
    }

    nonisolated enum SessionTerminalCapturedInput: Equatable {
        case text(String)
        case key(SessionInputKey)
    }

    nonisolated func mapSessionTerminalInput(
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
            scalar.value <= 0x7A
        {
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

            guard
                let input = mapSessionTerminalInput(
                    modifierFlags: event.modifierFlags,
                    keyCode: event.keyCode,
                    characters: event.characters,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers
                )
            else {
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
        if let appModel = try? NexusAppModel.live() {
            ContentView(appModel: appModel, settingsTabSelection: NexusSettingsTabSelection())
        }
    }
#endif
