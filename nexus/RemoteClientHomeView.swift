#if os(iOS)
    import NexusDomain
    import NexusSessionPresentation
    import SwiftUI

    private struct IOSEquatableStructuredSessionActivityRow<Content: View>: View, Equatable {
        let row: StructuredSessionActivityRow
        @ViewBuilder let content: () -> Content

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.row == rhs.row
        }

        var body: some View {
            content()
        }
    }

    struct RemoteClientHomeView: View {
        @Bindable var model: RemoteClientPairingModel

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        @State private var isShowingPairingForm = false
        @State private var isPairing = false
        @State private var isRefreshingAvailability = false
        @State private var isShowingPairedMacs = false
        @State private var workspaceBrowseMode: RemoteWorkspaceBrowseMode = .all
        @State private var selectedWorkspaceGroupID: UUID?
        @State private var presentedError: RemoteClientHomePresentedError?

        private var horizontalPadding: CGFloat {
            horizontalSizeClass == .regular ? 24 : 16
        }

        private var sectionSpacing: CGFloat {
            horizontalSizeClass == .regular ? 20 : 16
        }

        var body: some View {
            NavigationStack {
                ZStack {
                    NexusIOSBackdrop()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                            RemoteHomeHeroSection(
                                model: model,
                                horizontalSizeClass: horizontalSizeClass,
                                isRefreshingAvailability: isRefreshingAvailability,
                                onRefreshAvailability: {
                                    Task {
                                        await refreshAvailability()
                                    }
                                },
                                onShowPairingForm: {
                                    isShowingPairingForm = true
                                }
                            )

                            if let pairingRecoveryMessage = model.pairingRecoveryMessage {
                                RemoteMessageCard(
                                    eyebrow: "Pairing required",
                                    title: "Reconnect this iPhone.",
                                    detail: pairingRecoveryMessage,
                                    accent: NexusIOSTheme.coral
                                )
                            }

                            RemoteActivePairedMacBoundary(
                                model: model,
                                isShowingPairedMacs: $isShowingPairedMacs
                            )

                            if model.pairedMacs.isEmpty == false {
                                RemotePairedMacsBoundary(
                                    model: model,
                                    isShowingPairedMacs: isShowingPairedMacs,
                                    onSelectActivePairedMac: selectActivePairedMac,
                                    onForgetPairedMac: forgetPairedMac
                                )
                            }

                            RemoteWorkspaceCatalogBoundary(
                                model: model,
                                workspaceBrowseMode: $workspaceBrowseMode,
                                selectedWorkspaceGroupID: $selectedWorkspaceGroupID
                            )

                            RemotePairingSection(
                                model: model,
                                isShowingPairingForm: isShowingPairingForm,
                                isPairing: isPairing,
                                onCompletePairing: completePairing
                            )
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                    .refreshable {
                        await refreshAvailability()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    if model.pairedMacs.isEmpty == false, isShowingPairingForm {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                isShowingPairingForm = false
                            }
                        }
                    }
                }
                .task(id: availabilityRefreshID) {
                    await refreshAvailability()
                }
                .animation(.snappy(duration: 0.28), value: workspaceBrowseMode)
                .animation(.snappy(duration: 0.28), value: selectedWorkspaceGroupID)
                .animation(.snappy(duration: 0.28), value: isShowingPairedMacs)
            }

            .tint(NexusIOSTheme.gold)
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
        }

    }

    private struct RemoteHomeHeroSection: View {
        @Bindable var model: RemoteClientPairingModel
        let horizontalSizeClass: UserInterfaceSizeClass?
        let isRefreshingAvailability: Bool
        let onRefreshAvailability: () -> Void
        let onShowPairingForm: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nexus")
                            .font(
                                NexusIOSTheme.displayFont(
                                    horizontalSizeClass == .regular ? 34 : 30, relativeTo: .largeTitle)
                            )
                            .foregroundStyle(NexusIOSTheme.textPrimary)

                        Text("Simple remote chats for your workspaces.")
                            .font(NexusIOSTheme.bodyFont(15))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                    }

                    Spacer(minLength: 0)

                    if let activePairedMac = model.activePairedMac {
                        let availability = model.availability(for: activePairedMac)
                        NexusIOSStatusPill(
                            text: remotePairedMacAvailabilityTitle(availability),
                            color: remotePairedMacAvailabilityColor(availability)
                        )
                    }
                }

                Text(
                    model.pairedMacs.isEmpty
                        ? "Pair your Mac, then jump straight into workspace conversations."
                        : "Workspaces float to the top when you use them, and groups stay tucked away until you need a filter."
                )
                .font(NexusIOSTheme.bodyFont(14))
                .foregroundStyle(NexusIOSTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(isRefreshingAvailability ? "Refreshing…" : "Refresh") {
                        onRefreshAvailability()
                    }
                    .buttonStyle(NexusIOSSecondaryButtonStyle())
                    .disabled(isRefreshingAvailability)

                    Button(model.pairedMacs.isEmpty ? "Pair a Mac" : "Add Mac") {
                        onShowPairingForm()
                    }
                    .buttonStyle(NexusIOSPrimaryButtonStyle())
                }
            }
            .padding(horizontalSizeClass == .regular ? 24 : 20)
            .nexusIOSPanel(tint: NexusIOSTheme.gold, radius: 26, raised: true)
        }
    }

    private struct RemoteActivePairedMacBoundary: View {
        @Bindable var model: RemoteClientPairingModel
        @Binding var isShowingPairedMacs: Bool

        var body: some View {
            if let pairedMac = model.activePairedMac {
                let availability = model.availability(for: pairedMac)
                let accent = remotePairedMacAvailabilityColor(availability)

                Button {
                    withAnimation {
                        isShowingPairedMacs.toggle()
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(
                            systemName: availability == .available
                                ? "laptopcomputer.and.iphone" : "wifi.exclamationmark"
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 42, height: 42)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(pairedMac.name)
                                .font(NexusIOSTheme.bodyFont(17, weight: .semibold))
                                .foregroundStyle(NexusIOSTheme.textPrimary)
                            Text(availability.summary)
                                .font(NexusIOSTheme.bodyFont(13))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 6) {
                            Text("\(pairedMac.host):\(pairedMac.port)")
                                .font(NexusIOSTheme.monoFont(11, relativeTo: .caption))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                            Image(systemName: isShowingPairedMacs ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.55))
                        }
                    }
                    .padding(18)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .nexusIOSPanel(tint: accent, radius: 22)
            }
        }
    }

    private struct RemotePairedMacsBoundary: View {
        @Bindable var model: RemoteClientPairingModel
        let isShowingPairedMacs: Bool
        let onSelectActivePairedMac: (PairedMac) -> Void
        let onForgetPairedMac: (PairedMac) -> Void

        var body: some View {
            if isShowingPairedMacs || model.pairedMacs.count == 1 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Paired Macs")
                            .font(NexusIOSTheme.bodyFont(16, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                        Spacer()
                        Text("\(model.pairedMacs.count)")
                            .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                    }
                    .padding(.horizontal, 4)

                    ForEach(model.pairedMacs) { pairedMac in
                        let isActive = model.activePairedMac?.id == pairedMac.id
                        let availability = model.availability(for: pairedMac)
                        let accent =
                            isActive
                            ? remotePairedMacAvailabilityColor(availability)
                            : NexusIOSTheme.textPrimary.opacity(0.72)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(pairedMac.name)
                                            .font(NexusIOSTheme.bodyFont(16, weight: .semibold))
                                            .foregroundStyle(NexusIOSTheme.textPrimary)
                                        if isActive {
                                            NexusIOSStatusPill(
                                                text: "Current", color: remotePairedMacAvailabilityColor(availability))
                                        }
                                    }

                                    Text(availability.summary)
                                        .font(NexusIOSTheme.bodyFont(13))
                                        .foregroundStyle(
                                            isActive
                                                ? remotePairedMacAvailabilityColor(availability)
                                                : NexusIOSTheme.mutedText)
                                }

                                Spacer(minLength: 0)

                                Text("\(pairedMac.host):\(pairedMac.port)")
                                    .font(NexusIOSTheme.monoFont(11, relativeTo: .caption))
                                    .foregroundStyle(NexusIOSTheme.mutedText)
                            }

                            HStack(spacing: 10) {
                                if isActive == false {
                                    Button("Use This Mac") {
                                        onSelectActivePairedMac(pairedMac)
                                    }
                                    .buttonStyle(NexusIOSPrimaryButtonStyle())
                                }

                                Button("Forget") {
                                    onForgetPairedMac(pairedMac)
                                }
                                .buttonStyle(NexusIOSDangerButtonStyle())
                            }
                        }
                        .padding(16)
                        .nexusIOSPanel(tint: accent, radius: 20)
                    }
                }
            }
        }
    }

    private struct RemoteWorkspaceCatalogBoundary: View {
        @Bindable var model: RemoteClientPairingModel
        @Binding var workspaceBrowseMode: RemoteWorkspaceBrowseMode
        @Binding var selectedWorkspaceGroupID: UUID?

        private var presentation: RemoteWorkspaceBrowsePresentation? {
            model.workspaceBrowsePresentation(
                showingGroupsOnly: workspaceBrowseMode == .groups,
                selectedGroupID: selectedWorkspaceGroupID
            )
        }

        var body: some View {
            Group {
                if let presentation {
                    VStack(alignment: .leading, spacing: 14) {
                        if presentation.workspaceOverviews.isEmpty {
                            RemoteMessageCard(
                                eyebrow: workspaceBrowseMode == .groups
                                    ? "No workspaces in this filter" : "No workspaces yet",
                                title: workspaceBrowseMode == .groups
                                    ? "Try another group." : "Nothing remote is ready yet.",
                                detail: workspaceBrowseMode == .groups
                                    ? "This group is empty right now. Switch back to All or pick another group."
                                    : "Once your paired Mac shares a catalog, your workspace conversations will show up here.",
                                accent: NexusIOSTheme.gold
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Workspaces")
                                            .font(NexusIOSTheme.bodyFont(22, relativeTo: .title3, weight: .semibold))
                                            .foregroundStyle(NexusIOSTheme.textPrimary)
                                        Text("Your most recently used workspaces rise to the top.")
                                            .font(NexusIOSTheme.bodyFont(13))
                                            .foregroundStyle(NexusIOSTheme.mutedText)
                                    }

                                    Spacer(minLength: 0)

                                    Text("\(presentation.workspaceOverviews.count)")
                                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                                        .foregroundStyle(NexusIOSTheme.mutedText)
                                }
                                .padding(.horizontal, 4)

                                if presentation.availableWorkspaceGroups.isEmpty == false {
                                    Picker("Browse", selection: $workspaceBrowseMode) {
                                        ForEach(RemoteWorkspaceBrowseMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    if workspaceBrowseMode == .groups {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                RemoteWorkspaceGroupFilterChip(
                                                    title: "All Groups",
                                                    isSelected: selectedWorkspaceGroupID == nil
                                                ) {
                                                    selectedWorkspaceGroupID = nil
                                                }

                                                ForEach(presentation.availableWorkspaceGroups) { group in
                                                    RemoteWorkspaceGroupFilterChip(
                                                        title: group.name,
                                                        isSelected: selectedWorkspaceGroupID == group.id
                                                    ) {
                                                        selectedWorkspaceGroupID = group.id
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }

                            ForEach(presentation.workspaceOverviews, id: \.workspace.id) { overview in
                                NavigationLink {
                                    RemoteWorkspaceDetailView(model: model, overview: overview)
                                } label: {
                                    RemoteWorkspaceSummaryCard(
                                        overview: overview,
                                        groupName: remoteWorkspaceGroupName(
                                            for: overview.workspace.primaryGroupID,
                                            groups: presentation.availableWorkspaceGroups
                                        ),
                                        showsGroupName: workspaceBrowseMode == .groups
                                            && selectedWorkspaceGroupID == nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else if let activePairedMac = model.activePairedMac,
                    model.availability(for: activePairedMac) == .available
                {
                    RemoteMessageCard(
                        eyebrow: "Workspace catalog",
                        title: model.catalogErrorMessage == nil
                            ? "Loading your workspaces…" : "Catalog unavailable right now.",
                        detail: model.catalogErrorMessage
                            ?? "Nexus is fetching workspace conversations from \(activePairedMac.name).",
                        accent: model.catalogErrorMessage == nil ? NexusIOSTheme.gold : NexusIOSTheme.coral
                    )
                }
            }
            .onChange(of: presentation?.availableWorkspaceGroupIDs ?? []) { _, groupIDs in
                if let selectedWorkspaceGroupID, groupIDs.contains(selectedWorkspaceGroupID) == false {
                    self.selectedWorkspaceGroupID = nil
                }
            }
        }
    }

    private struct RemotePairingSection: View {
        @Bindable var model: RemoteClientPairingModel
        let isShowingPairingForm: Bool
        let isPairing: Bool
        let onCompletePairing: () -> Void

        var body: some View {
            if model.pairedMacs.isEmpty || isShowingPairingForm {
                VStack(alignment: .leading, spacing: 16) {
                    NexusIOSCardTitle(
                        eyebrow: "Pair a Mac",
                        title: "Bring your workspaces over.",
                        detail: "Use the Remote Access address and pairing code from your Mac.",
                        accent: NexusIOSTheme.gold
                    )

                    VStack(spacing: 12) {
                        TextField("Mac Address", text: $model.macHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .nexusIOSTextField()

                        TextField("Port", text: $model.macPort)
                            .keyboardType(.numberPad)
                            .nexusIOSTextField(tint: NexusIOSTheme.teal)

                        TextField("Pairing Code", text: $model.pairingCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .nexusIOSTextField(tint: NexusIOSTheme.gold)

                        TextField("This iPhone's Name", text: $model.deviceName)
                            .nexusIOSTextField(tint: NexusIOSTheme.teal)
                    }

                    Button(isPairing ? "Pairing…" : "Complete Pairing") {
                        onCompletePairing()
                    }
                    .buttonStyle(NexusIOSPrimaryButtonStyle())
                    .disabled(isPairing)
                }
                .padding(20)
                .nexusIOSPanel(tint: NexusIOSTheme.gold, radius: 24, raised: true)
            }
        }
    }

    private struct RemoteWorkspaceGroupFilterChip: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(NexusIOSTheme.bodyFont(13, relativeTo: .callout, weight: .medium))
                    .foregroundStyle(isSelected ? .white : NexusIOSTheme.mutedText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background((isSelected ? NexusIOSTheme.gold : NexusIOSTheme.overlay(0.06)), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(isSelected ? NexusIOSTheme.gold.opacity(0.3) : NexusIOSTheme.softLine, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private struct RemoteMessageCard: View {
        let eyebrow: String
        let title: String
        let detail: String
        let accent: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                NexusIOSCardTitle(eyebrow: eyebrow, title: title, detail: detail, accent: accent)
            }
            .padding(18)
            .nexusIOSPanel(tint: accent, radius: 22)
        }
    }

    private func remoteWorkspaceGroupName(for groupID: UUID?, groups: [WorkspaceGroup]) -> String? {
        guard let groupID else {
            return nil
        }
        return groups.first(where: { $0.id == groupID })?.name
    }

    private func remotePairedMacAvailabilityColor(_ availability: PairedMacAvailability) -> Color {
        switch availability {
        case .available:
            NexusIOSTheme.teal
        case .unavailablePairedMac, .remoteAccessDisabled:
            NexusIOSTheme.coral
        case .unknown:
            NexusIOSTheme.gold
        }
    }

    private func remotePairedMacAvailabilityTitle(_ availability: PairedMacAvailability) -> String {
        switch availability {
        case .available:
            "Available"
        case .unavailablePairedMac:
            "Offline"
        case .remoteAccessDisabled:
            "Access Off"
        case .unknown:
            "Checking"
        }
    }

    private enum RemoteWorkspaceBrowseMode: String, CaseIterable, Identifiable {
        case all
        case groups

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                "All"
            case .groups:
                "Groups"
            }
        }
    }

    private struct RemoteWorkspaceSummaryCard: View {
        let overview: WorkspaceOverview
        let groupName: String?
        let showsGroupName: Bool

        init(overview: WorkspaceOverview, groupName: String? = nil, showsGroupName: Bool = false) {
            self.overview = overview
            self.groupName = groupName
            self.showsGroupName = showsGroupName
        }

        private var accent: Color {
            if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability {
                return remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state)
            }
            return NexusIOSTheme.teal
        }

        private var subtitle: String {
            if let readyProvider = overview.providerCards.first(where: { $0.defaultSession.state == .ready }) {
                return "Continue with \(readyProvider.provider.displayName)."
            }
            return overview.providerCards.first?.health.summary ?? remoteWorkspaceTargetSummary(for: overview)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(overview.workspace.name)
                                .font(NexusIOSTheme.bodyFont(17, weight: .semibold))
                                .foregroundStyle(NexusIOSTheme.textPrimary)
                                .lineLimit(1)
                            if let groupName, showsGroupName {
                                Text(groupName)
                                    .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                                    .foregroundStyle(NexusIOSTheme.mutedText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(NexusIOSTheme.overlay(0.06), in: Capsule())
                            }
                        }

                        Text(subtitle)
                            .font(NexusIOSTheme.bodyFont(13))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                            .lineLimit(2)

                        if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability,
                            workspaceAvailability.state != .available
                        {
                            Text(workspaceAvailability.summary)
                                .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                                .foregroundStyle(accent)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("\(overview.providerCards.count)")
                            .font(NexusIOSTheme.bodyFont(18, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.42))
                    }
                }
            }
            .padding(16)
            .nexusIOSPanel(tint: accent, radius: 20)
        }
    }

    private struct RemoteNavigationItemCard: View {
        let item: NavigationItem

        private var accent: Color {
            switch item.kind {
            case .workspace, .provider:
                NexusIOSTheme.gold
            case .session:
                NexusIOSTheme.teal
            }
        }

        private var icon: String {
            switch item.kind {
            case .workspace:
                "folder"
            case .provider:
                "sparkles.rectangle.stack"
            case .session:
                "message"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(NexusIOSTheme.bodyFont(16, weight: .semibold))
                        .foregroundStyle(NexusIOSTheme.textPrimary)
                    Text(item.subtitle)
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.44))
            }
            .padding(18)
            .nexusIOSPanel(tint: accent, radius: 22)
        }
    }

    private struct RemoteWorkspaceDetailView: View {
        @Bindable var model: RemoteClientPairingModel
        let overview: WorkspaceOverview

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        private var accent: Color {
            if let availability = overview.remoteTarget?.workspaceAvailability.state {
                return remoteWorkspaceAvailabilityColor(for: availability)
            }
            return NexusIOSTheme.teal
        }

        private var horizontalPadding: CGFloat {
            horizontalSizeClass == .regular ? 24 : 16
        }

        var body: some View {
            ZStack {
                NexusIOSBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        headerCard

                        if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability,
                            workspaceAvailability.state != .available
                                || workspaceAvailability.diagnostics.isEmpty == false
                        {
                            workspaceIssueCard(workspaceAvailability)
                        }

                        providersSection
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }

        private var headerCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(overview.workspace.name)
                            .font(
                                NexusIOSTheme.displayFont(
                                    horizontalSizeClass == .regular ? 32 : 28, relativeTo: .largeTitle)
                            )
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                        Text("Pick an agent and continue the conversation.")
                            .font(NexusIOSTheme.bodyFont(14))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                    }

                    Spacer(minLength: 0)
                    NexusIOSStatusPill(text: "Remote", color: accent)
                }

                HStack(spacing: 10) {
                    if let remoteTarget = overview.remoteTarget {
                        NexusIOSMetaBadge(icon: "network", text: remoteTarget.host.name)
                    }
                    NexusIOSMetaBadge(icon: "folder", text: overview.workspace.folderPath)
                }
            }
            .padding(20)
            .nexusIOSPanel(tint: accent, radius: 24, raised: true)
        }

        private func workspaceIssueCard(_ workspaceAvailability: WorkspaceAvailabilitySnapshot) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                NexusIOSCardTitle(
                    eyebrow: "Workspace issue",
                    title: workspaceAvailabilityStateTitle(workspaceAvailability.state),
                    detail: workspaceAvailability.summary,
                    accent: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state)
                )

                ForEach(Array(workspaceAvailability.diagnostics.enumerated()), id: \.offset) { entry in
                    Text(entry.element.message)
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nexusIOSPanel(
                            tint: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state), radius: 16)
                }
            }
            .padding(18)
            .nexusIOSPanel(tint: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state), radius: 22)
        }

        private var providersSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agents")
                            .font(NexusIOSTheme.bodyFont(20, relativeTo: .title3, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                        Text(
                            overview.providerCards.isEmpty
                                ? "Nothing is available yet." : "Choose who you want to talk to."
                        )
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)

                if overview.providerCards.isEmpty {
                    Text("No Providers available yet.")
                        .font(NexusIOSTheme.bodyFont(14))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nexusIOSPanel(tint: NexusIOSTheme.gold, radius: 20)
                } else {
                    ForEach(overview.providerCards) { providerCard in
                        NavigationLink {
                            RemoteProviderDetailView(
                                model: model,
                                overview: overview,
                                providerCard: providerCard
                            )
                        } label: {
                            RemoteProviderCardRow(providerCard: providerCard)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct RemoteWorkspaceDestinationView: View {
        @Bindable var model: RemoteClientPairingModel
        let workspaceID: UUID

        var body: some View {
            if let overview = model.workspaceOverview(id: workspaceID) {
                RemoteWorkspaceDetailView(model: model, overview: overview)
            } else {
                RemoteUnavailableCard(
                    title: "Workspace unavailable",
                    detail: "Reconnect to the paired Mac and refresh the Workspace catalog.")
            }
        }
    }

    private struct RemoteProviderDestinationView: View {
        @Bindable var model: RemoteClientPairingModel
        let workspaceID: UUID
        let providerID: ProviderID

        var body: some View {
            if let overview = model.workspaceOverview(id: workspaceID),
                let providerCard = model.providerCard(workspaceID: workspaceID, providerID: providerID)
            {
                RemoteProviderDetailView(model: model, overview: overview, providerCard: providerCard)
            } else {
                RemoteUnavailableCard(
                    title: "Provider unavailable", detail: "Refresh this Workspace on the paired Mac and try again.")
            }
        }
    }

    private struct RemoteSessionDestinationView: View {
        @Bindable var model: RemoteClientPairingModel
        let workspaceID: UUID
        let providerID: ProviderID
        let sessionID: UUID

        var body: some View {
            Group {
                if let session = model.resolvedSession(
                    workspaceID: workspaceID, providerID: providerID, sessionID: sessionID)
                {
                    RemoteSessionScreenView(model: model, session: session)
                } else if let errorMessage = model.providerDetailErrorMessage(for: workspaceID, providerID: providerID)
                {
                    RemoteUnavailableCard(title: "Session unavailable", detail: errorMessage)
                } else {
                    RemoteUnavailableCard(
                        title: "Loading Session…", detail: "Nexus is resolving the Session from the paired Mac.")
                }
            }
            .task(id: sessionID) {
                if model.providerDetail(for: workspaceID, providerID: providerID) == nil {
                    await model.loadProviderDetail(workspaceID: workspaceID, providerID: providerID)
                }
            }
        }
    }

    private struct RemoteProviderCardRow: View {
        let providerCard: WorkspaceProviderCard

        private var accent: Color {
            providerCard.health.state.tone.color
        }

        private var subtitle: String {
            if providerCard.defaultSession.state == .ready {
                return "Resume your \(providerCard.provider.displayName) chat."
            }
            return providerCard.defaultSession.summary
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: providerCard.prelaunchPrimarySurface == .terminal ? "terminal" : "message.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(providerCard.provider.displayName)
                        .font(NexusIOSTheme.bodyFont(17, weight: .semibold))
                        .foregroundStyle(NexusIOSTheme.providerAccent(providerCard.provider.id))
                    Text(subtitle)
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .lineLimit(2)

                    if providerCard.alternateSessionCount > 0 {
                        Text(
                            "\(providerCard.alternateSessionCount) other chat\(providerCard.alternateSessionCount == 1 ? "" : "s")"
                        )
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                        .foregroundStyle(accent)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.42))
            }
            .padding(16)
            .nexusIOSPanel(tint: accent, radius: 20)
        }
    }

    private func remoteWorkspaceTargetSummary(for overview: WorkspaceOverview) -> String {
        overview.remoteTarget.map { "\($0.host.name) • \(overview.workspace.folderPath)" }
            ?? overview.workspace.folderPath
    }

    private func remoteWorkspaceAvailabilityColor(for state: WorkspaceAvailabilitySnapshot.State) -> Color {
        switch state {
        case .available:
            NexusIOSTheme.teal
        case .unavailable, .blocked:
            NexusIOSTheme.gold
        case .broken:
            NexusIOSTheme.coral
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

    private enum RemoteProviderDetailAction: Equatable {
        case launchDefaultSession
        case createNamedSession
        case deleteSessionRecord(UUID)
    }

    private struct RemoteProviderDetailView: View {
        @Bindable var model: RemoteClientPairingModel
        let overview: WorkspaceOverview
        let providerCard: WorkspaceProviderCard

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        @State private var openedSession: Session?
        @State private var activeAction: RemoteProviderDetailAction?
        @State private var pendingDeleteSessionRecord: Session?
        @State private var presentedError: RemoteClientHomePresentedError?

        private var detail: ProviderDetail? {
            model.providerDetail(for: overview.workspace.id, providerID: providerCard.provider.id)
        }

        private var errorMessage: String? {
            model.providerDetailErrorMessage(for: overview.workspace.id, providerID: providerCard.provider.id)
        }

        private var isLaunchingDefaultSession: Bool {
            activeAction == .launchDefaultSession
        }

        private var isCreatingNamedSession: Bool {
            activeAction == .createNamedSession
        }

        private var defaultSessionActionTitle: String {
            if let session = detail?.defaultSession {
                return session.state == .ready ? "Open conversation" : "Resume conversation"
            }

            if providerCard.defaultSession.state == .notCreated {
                return "Start conversation"
            }

            return "Open conversation"
        }

        private var defaultSessionActionState: RemoteProviderActionState {
            RemoteProviderActionState(
                capability: detail?.capabilities.launchDefaultSession ?? providerCard.capabilities.launchDefaultSession,
                provider: detail?.provider ?? providerCard.provider,
                prelaunchPrimarySurface: detail?.prelaunchPrimarySurface ?? providerCard.prelaunchPrimarySurface
            )
        }

        private var createNamedSessionActionState: RemoteProviderActionState {
            RemoteProviderActionState(
                capability: detail?.capabilities.createNamedSession ?? providerCard.capabilities.createNamedSession,
                provider: detail?.provider ?? providerCard.provider,
                prelaunchPrimarySurface: detail?.prelaunchPrimarySurface ?? providerCard.prelaunchPrimarySurface
            )
        }

        private var defaultSessionSection: RemoteDefaultSessionSectionState {
            RemoteDefaultSessionSectionState(detail: detail)
        }

        private var namedSessionsSection: RemoteNamedSessionsSectionState {
            RemoteNamedSessionsSectionState(
                capabilities: detail?.capabilities ?? providerCard.capabilities,
                detail: detail,
                errorMessage: errorMessage
            )
        }

        private var accent: Color {
            (detail?.health.state ?? providerCard.health.state).tone.color
        }

        private var horizontalPadding: CGFloat {
            horizontalSizeClass == .regular ? 24 : 16
        }

        private var showsProviderIssues: Bool {
            if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability,
                workspaceAvailability.state != .available || workspaceAvailability.diagnostics.isEmpty == false
            {
                return true
            }

            if let detail, detail.health.state != .available || detail.health.diagnostics.isEmpty == false {
                return true
            }

            return errorMessage != nil
        }

        var body: some View {
            ZStack {
                NexusIOSBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        headerCard
                        primaryConversationCard

                        if namedSessionsSection.content != .none {
                            namedConversationsCard
                        }

                        if let detail, detail.failedSessions.isEmpty == false {
                            failedSessionsCard(detail.failedSessions)
                        }

                        if showsProviderIssues {
                            issueSection
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await model.loadProviderDetail(
                        workspaceID: overview.workspace.id, providerID: providerCard.provider.id)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: providerCard.id) {
                await model.loadProviderDetail(workspaceID: overview.workspace.id, providerID: providerCard.provider.id)
            }
            .navigationDestination(item: $openedSession) { session in
                RemoteSessionScreenView(model: model, session: session)
            }
            .confirmationDialog(
                "Delete Session Record?",
                isPresented: Binding(
                    get: { pendingDeleteSessionRecord != nil },
                    set: { isPresented in
                        if isPresented == false {
                            pendingDeleteSessionRecord = nil
                        }
                    }
                ),
                presenting: pendingDeleteSessionRecord
            ) { session in
                Button("Delete Session Record", role: .destructive) {
                    deleteSessionRecord(session)
                }
            } message: { _ in
                Text("Delete this Session Record from Nexus on this Paired Mac? This does not stop a live runtime.")
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("Nexus Remote"), message: Text(error.message))
            }
        }

        private var headerCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(providerCard.provider.displayName)
                            .font(
                                NexusIOSTheme.displayFont(
                                    horizontalSizeClass == .regular ? 32 : 28, relativeTo: .largeTitle)
                            )
                            .foregroundStyle(NexusIOSTheme.providerAccent(providerCard.provider.id))
                        Text(overview.workspace.name)
                            .font(NexusIOSTheme.bodyFont(14, weight: .medium))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                    NexusIOSStatusPill(
                        text: (detail?.health.state ?? providerCard.health.state).rawValue.capitalized, color: accent)
                }

                Text(
                    providerCard.defaultSession.state == .ready
                        ? "Jump straight back into the main chat."
                        : "Start or resume a conversation with \(providerCard.provider.displayName)."
                )
                .font(NexusIOSTheme.bodyFont(14))
                .foregroundStyle(NexusIOSTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .nexusIOSPanel(tint: accent, radius: 24, raised: true)
        }

        private var primaryConversationCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                NexusIOSCardTitle(
                    eyebrow: "Main chat",
                    title: "Default conversation",
                    detail: defaultSessionSection.session?.failureMessage ?? providerCard.defaultSession.summary,
                    accent: NexusIOSTheme.gold
                )

                if let session = defaultSessionSection.session {
                    RemoteProviderSessionSummaryCard(session: session, accent: session.state.tone.color) {
                        openedSession = session
                    } deleteAction: {
                        if defaultSessionSection.canDeleteSessionRecord {
                            pendingDeleteSessionRecord = session
                        }
                    }
                    .disabledDelete(defaultSessionSection.canDeleteSessionRecord == false)
                }

                Button(isLaunchingDefaultSession ? "Working…" : defaultSessionActionTitle) {
                    launchDefaultSession()
                }
                .buttonStyle(NexusIOSPrimaryButtonStyle())
                .disabled(isLaunchingDefaultSession || defaultSessionActionState.isEnabled == false)

                if let disabledReason = defaultSessionActionState.disabledReason,
                    defaultSessionActionState.isEnabled == false
                {
                    Text(disabledReason)
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
            }
            .padding(18)
            .nexusIOSPanel(tint: NexusIOSTheme.gold, radius: 22)
        }

        @ViewBuilder
        private var namedConversationsCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Other chats")
                            .font(NexusIOSTheme.bodyFont(18, relativeTo: .title3, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                        Text("Keep side conversations tucked away until you need them.")
                            .font(NexusIOSTheme.bodyFont(13))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }

                switch namedSessionsSection.content {
                case .empty:
                    EmptyView()
                case .sessions(let sessions):
                    ForEach(sessions) { session in
                        RemoteProviderSessionSummaryCard(
                            session: session, accent: session.state.tone.color
                        ) {
                            openedSession = session
                        } deleteAction: {
                            if namedSessionsSection.deletableSessionIDs.contains(session.id) {
                                pendingDeleteSessionRecord = session
                            }
                        }
                        .disabledDelete(namedSessionsSection.deletableSessionIDs.contains(session.id) == false)
                    }
                case .loading:
                    RemoteUnavailableInsetCard(
                        title: "Loading chats…", detail: "Nexus is fetching the rest of this provider’s conversations.",
                        accent: NexusIOSTheme.teal)
                case .none:
                    EmptyView()
                }

                Button(isCreatingNamedSession ? "Creating…" : "New chat") {
                    createNamedSession()
                }
                .buttonStyle(NexusIOSSecondaryButtonStyle())
                .disabled(isCreatingNamedSession || createNamedSessionActionState.isEnabled == false)

                if let disabledReason = createNamedSessionActionState.disabledReason,
                    createNamedSessionActionState.isEnabled == false
                {
                    Text(disabledReason)
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
            }
            .padding(18)
            .nexusIOSPanel(tint: NexusIOSTheme.teal, radius: 22)
        }

        @ViewBuilder
        private var issueSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability,
                    workspaceAvailability.state != .available || workspaceAvailability.diagnostics.isEmpty == false
                {
                    providerAvailabilityCard(workspaceAvailability)
                }

                if let detail, detail.health.state != .available || detail.health.diagnostics.isEmpty == false {
                    providerHealthCard
                }

                if let errorMessage {
                    RemoteUnavailableInsetCard(
                        title: "Provider detail issue", detail: errorMessage, accent: NexusIOSTheme.coral)
                }
            }
        }

        private func providerAvailabilityCard(_ workspaceAvailability: WorkspaceAvailabilitySnapshot) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                NexusIOSCardTitle(
                    eyebrow: "Workspace issue",
                    title: workspaceAvailabilityStateTitle(workspaceAvailability.state),
                    detail: workspaceAvailability.summary,
                    accent: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state)
                )

                ForEach(Array(workspaceAvailability.diagnostics.enumerated()), id: \.offset) { entry in
                    Text(entry.element.message)
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nexusIOSPanel(
                            tint: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state), radius: 16)
                }
            }
            .padding(18)
            .nexusIOSPanel(tint: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state), radius: 22)
        }

        private var providerHealthCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                NexusIOSCardTitle(
                    eyebrow: "Agent issue",
                    title: "Provider readiness",
                    detail: detail?.health.summary ?? providerCard.health.summary,
                    accent: accent
                )

                if let detail, detail.health.diagnostics.isEmpty == false {
                    ForEach(Array(detail.health.diagnostics.enumerated()), id: \.offset) { entry in
                        Text(entry.element.message)
                            .font(NexusIOSTheme.bodyFont(13))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .nexusIOSPanel(tint: accent, radius: 16)
                    }
                }
            }
            .padding(18)
            .nexusIOSPanel(tint: accent, radius: 22)
        }

        private func failedSessionsCard(_ sessions: [Session]) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                NexusIOSCardTitle(
                    eyebrow: "Past chats",
                    title: "Failed or exited sessions",
                    detail: "Still available for review or cleanup.",
                    accent: NexusIOSTheme.coral
                )

                ForEach(sessions) { session in
                    RemoteProviderSessionSummaryCard(session: session, accent: NexusIOSTheme.coral) {
                        openedSession = session
                    } deleteAction: {
                        pendingDeleteSessionRecord = session
                    }
                }
            }
            .padding(18)
            .nexusIOSPanel(tint: NexusIOSTheme.coral, radius: 22)
        }

        private func launchDefaultSession() {
            performAction(.launchDefaultSession) {
                openedSession = try await model.launchOrResumeDefaultSession(
                    workspaceID: overview.workspace.id,
                    providerID: providerCard.provider.id
                )
            }
        }

        private func createNamedSession() {
            performAction(.createNamedSession) {
                openedSession = try await model.createNamedSession(
                    workspaceID: overview.workspace.id,
                    providerID: providerCard.provider.id
                )
            }
        }

        private func deleteSessionRecord(_ session: Session) {
            pendingDeleteSessionRecord = nil
            performAction(.deleteSessionRecord(session.id)) {
                _ = try await model.deleteSessionRecord(
                    sessionID: session.id,
                    workspaceID: overview.workspace.id,
                    providerID: providerCard.provider.id
                )
            }
        }

        private func performAction(
            _ action: RemoteProviderDetailAction,
            operation: @escaping @MainActor () async throws -> Void
        ) {
            activeAction = action
            Task { @MainActor in
                defer { activeAction = nil }

                do {
                    try await operation()
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                }
            }
        }
    }

    private enum RemoteSessionAction: Equatable {
        case relaunch
        case stop
        case takeController
        case returnToViewer
    }

    private struct RemoteSessionScreenView: View {
        @Bindable var model: RemoteClientPairingModel
        let session: Session

        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        @State private var terminalDraft = ""
        @State private var structuredPrompt = ""
        @State private var isComposerExpanded = false
        @State private var terminalViewportSize: CGSize = .zero
        @State private var terminalViewportResizeCoordinator = TerminalViewportResizeCoordinator()
        @State private var isShowingStopConfirmation = false
        @State private var activeAction: RemoteSessionAction?
        @State private var activeApprovalRequestID: UUID?
        @State private var activeExtensionDialogID: String?
        @State private var presentedError: RemoteClientHomePresentedError?
        @State private var structuredSessionAutoScrollCoordinator = StructuredSessionAutoScrollCoordinator()
        @State private var structuredSessionDraftGrowthScrollThrottle = StructuredSessionDraftGrowthScrollThrottle()
        @State private var structuredSessionPinState = StructuredSessionFeedPinState()
        @State private var structuredSessionFeedScrollSnapshot: StructuredSessionFeedScrollSnapshot?
        @State private var structuredSessionFeedScrollPosition = ScrollPosition()
        @State private var structuredSessionFeedVisibleTailRowCount = 0
        @State private var structuredSessionFeedScrollGeometrySample: StructuredSessionScrollGeometrySample?
        @State private var structuredSessionFeedScrollLastMovementAt = Date()
        @State private var structuredSessionFeedScrollIsIdle = false
        @State private var structuredSessionFeedStableFollowScrollToken = ""
        @State private var presentedStructuredSessionAssistantFullResponse:
            StructuredSessionAssistantFullResponsePresentation?
        @StateObject private var structuredSessionAgentTurnDisclosureState = StructuredSessionAgentTurnDisclosureState()
        @FocusState private var isStructuredPromptFocused: Bool
        @FocusState private var isTerminalInputFocused: Bool

        private var screen: SessionScreen? {
            guard model.focusedSessionID == session.id else {
                return nil
            }
            return model.focusedSessionScreen
        }

        private var currentSession: Session {
            structuredChromePresentation?.session ?? structuredPresentation?.session ?? screen?.session ?? session
        }

        private var isReady: Bool {
            currentSession.state == .ready
        }

        private var surfacePresentation: RemoteSessionSurfacePresentation? {
            guard model.focusedSessionID == session.id else {
                return nil
            }

            return model.focusedSessionSurfacePresentation
        }

        private var structuredPresentation: FocusedStructuredSessionPresentation? {
            guard model.focusedSessionID == session.id else {
                return nil
            }

            return model.focusedStructuredSessionPresentation
        }

        private var structuredChromePresentation: FocusedStructuredSessionChromePresentation? {
            guard model.focusedSessionID == session.id else {
                return nil
            }

            return model.focusedStructuredSessionChromePresentation
        }

        private var structuredFeedPresentation: StructuredSessionFeedPresentation? {
            structuredPresentation?.feed
        }

        private var latestFinalizedAssistantRowID: UUID? {
            guard let structuredFeedPresentation else {
                return nil
            }
            return structuredSessionLatestFinalizedAssistantActivityRowID(in: structuredFeedPresentation.activityRows)
        }

        private var isStructuredSessionFeedTailStableForInlineMarkdown: Bool {
            guard let structuredPresentation else {
                return false
            }
            let token = structuredSessionFeedFollowScrollToken(for: structuredPresentation)
            return structuredSessionFeedTailIsStableForInlineMarkdown(
                feedFollowScrollToken: token,
                lastStableFeedFollowScrollToken: structuredSessionFeedStableFollowScrollToken
            )
        }

        private var structuredComposerPresentation: StructuredSessionComposerPresentation? {
            guard let structuredChromePresentation else {
                return nil
            }

            return structuredSessionComposerPresentation(
                for: structuredChromePresentation,
                hasWriterAuthority: model.focusedSessionIsController
            )
        }

        private var structuredSendAffordance: StructuredSessionComposerSendAffordance? {
            guard let structuredChromePresentation, let composer = structuredComposerPresentation else {
                return nil
            }

            return structuredSessionComposerSendAffordance(
                for: structuredPrompt,
                composer: composer,
                isPerformingAction: isPerformingAction || structuredChromePresentation.isAgentTurnInProgress
            )
        }

        private var structuredApprovalRequestPresentation: StructuredSessionApprovalRequestPresentation? {
            guard structuredChromePresentation != nil else {
                return nil
            }

            return structuredSessionApprovalRequestPresentation(
                hasWriterAuthority: model.focusedSessionIsController
            )
        }

        private var structuredSlashCommandMenuPresentation: StructuredSessionSlashCommandMenuPresentation? {
            guard let structuredChromePresentation else {
                return nil
            }

            return structuredSessionSlashCommandMenuPresentation(
                for: structuredPrompt, chrome: structuredChromePresentation)
        }

        private var extensionUI: SessionExtensionUIState? {
            structuredChromePresentation?.extensionUI
        }

        private var aboveEditorWidgets: [SessionExtensionUIWidget] {
            extensionUI?.widgets.filter { $0.placement == .aboveEditor } ?? []
        }

        private var belowEditorWidgets: [SessionExtensionUIWidget] {
            extensionUI?.widgets.filter { $0.placement == .belowEditor } ?? []
        }

        private var supportsFocusedSessionSurface: Bool {
            surfacePresentation?.surfaceSupport == .supported
        }

        private var isPerformingAction: Bool {
            activeAction != nil || activeApprovalRequestID != nil || activeExtensionDialogID != nil
        }

        private var accent: Color {
            currentSession.state.tone.color
        }

        private var horizontalPadding: CGFloat {
            horizontalSizeClass == .regular ? 24 : 12
        }

        private var controllerActionTitle: String {
            switch activeAction {
            case .takeController:
                "Taking over…"
            case .returnToViewer:
                "Done editing…"
            default:
                model.focusedSessionIsController ? "Watch only" : "Take over"
            }
        }

        private var sessionTitle: String {
            currentSession.providerID.displayName
        }

        private var sessionSubtitle: String {
            if currentSession.isDefault {
                return currentSession.state.rawValue.capitalized
            }
            return currentSession.name ?? currentSession.state.rawValue.capitalized
        }

        var body: some View {
            ZStack {
                NexusIOSBackdrop()

                VStack(spacing: 0) {
                    if model.focusedSessionIsStale, model.focusedSessionID == session.id {
                        RemoteUnavailableInsetCard(
                            title: "Connection is stale",
                            detail: model.focusedSessionErrorMessage
                                ?? "Reconnecting… showing the last known conversation.",
                            accent: NexusIOSTheme.gold
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 10)
                    }

                    if let unsupportedCopy = surfacePresentation?.unsupportedCopy {
                        RemoteUnavailableInsetCard(
                            title: unsupportedCopy.title,
                            detail: "\(unsupportedCopy.summary)\n\n\(unsupportedCopy.recovery)",
                            accent: NexusIOSTheme.coral
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 10)
                    } else if surfacePresentation?.showsStructuredActivity == true {
                        structuredConversationView
                    } else {
                        terminalConversationView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { sessionToolbar }
            .safeAreaInset(edge: .bottom) {
                if surfacePresentation?.showsStructuredActivity == true {
                    structuredComposerBar
                } else if surfacePresentation?.showsTerminal == true, isReady {
                    terminalComposerBar
                }
            }
            .task(id: session.id) {
                await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)
            }
            .refreshable {
                await model.refreshFocusedSessionScreen()
            }
            .confirmationDialog(
                "Stop this Session?",
                isPresented: $isShowingStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Session", role: .destructive) {
                    stopSession()
                }
            } message: {
                Text(
                    "Stop terminates the live Session runtime and keeps the Session record for inspection or relaunch.")
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("Nexus Remote"), message: Text(error.message))
            }
            .onChange(of: terminalViewportSize) { _, _ in
                guard isReady, supportsFocusedSessionSurface, model.focusedSessionIsController else {
                    return
                }

                let viewport = terminalViewport()
                terminalViewportResizeCoordinator.report(
                    .init(columns: viewport.columns, rows: viewport.rows),
                    currentSize: {
                        guard let screen = model.focusedSessionScreen,
                            screen.session.id == session.id
                        else {
                            return nil
                        }
                        return .init(columns: screen.terminalColumns, rows: screen.terminalRows)
                    },
                    submit: { size in
                        guard model.focusedSessionID == session.id else {
                            return
                        }
                        await model.updateFocusedRemoteSessionViewport(columns: size.columns, rows: size.rows)
                    },
                    onError: { _ in }
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    Task {
                        await model.handleFocusedSessionBackgrounded()
                    }
                }
            }
            .onDisappear {
                terminalViewportResizeCoordinator.cancel()
                if model.focusedSessionID == session.id {
                    Task {
                        await model.handleFocusedSessionScreenDisappeared(preserveAttachment: scenePhase == .background)
                    }
                }
            }
        }

        @ToolbarContentBuilder
        private var sessionToolbar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(sessionTitle)
                        .font(NexusIOSTheme.bodyFont(15, weight: .semibold))
                        .foregroundStyle(NexusIOSTheme.providerAccent(currentSession.providerID))
                    Text(sessionSubtitle)
                        .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isReady, surfacePresentation?.showsAttachment == true {
                        Button(controllerActionTitle) {
                            toggleControllerState()
                        }
                        .disabled(isPerformingAction)
                    }

                    if isReady {
                        Button("Stop Session", role: .destructive) {
                            isShowingStopConfirmation = true
                        }
                        .disabled(isPerformingAction)
                    } else {
                        Button("Relaunch Session") {
                            relaunchSession()
                        }
                        .disabled(isPerformingAction || surfacePresentation?.relaunchIsEnabled == false)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(NexusIOSTheme.textPrimary)
                }
            }
        }

        private var structuredConversationView: some View {
            Group {
                if let structuredPresentation,
                    let approvalRequestPresentation = structuredApprovalRequestPresentation
                {
                    structuredSessionContent(
                        structuredPresentation,
                        approvalRequestPresentation: approvalRequestPresentation
                    )
                } else if let errorMessage = model.focusedSessionErrorMessage {
                    ScrollView {
                        RemoteUnavailableInsetCard(
                            title: "Conversation unavailable", detail: errorMessage, accent: NexusIOSTheme.coral
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 14)
                    }
                } else {
                    ScrollView {
                        RemoteUnavailableInsetCard(
                            title: "Loading conversation…", detail: "Nexus is connecting to the paired Mac.",
                            accent: NexusIOSTheme.gold
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 14)
                    }
                }
            }
        }

        private var terminalConversationView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let screen {
                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(screen.styledVisibleLines.enumerated()), id: \.offset) { row, line in
                                    terminalLineView(line, row: row, screen: screen)
                                }
                            }
                            .padding(14)
                        }
                        .frame(minHeight: horizontalSizeClass == .regular ? 520 : 380)
                        .background(
                            NexusIOSTheme.terminalSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay(alignment: .topLeading) {
                            Text("Live terminal")
                                .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(NexusIOSTheme.overlay(0.06), lineWidth: 1)
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        terminalViewportSize = proxy.size
                                    }
                                    .onChange(of: proxy.size) { _, newSize in
                                        terminalViewportSize = newSize
                                    }
                            }
                        }
                    } else if let errorMessage = model.focusedSessionErrorMessage {
                        RemoteUnavailableInsetCard(
                            title: "Session screen unavailable", detail: errorMessage, accent: NexusIOSTheme.coral)
                    } else {
                        RemoteUnavailableInsetCard(
                            title: "Loading terminal…", detail: "Nexus is connecting to the paired Mac.",
                            accent: NexusIOSTheme.gold)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 120)
            }
        }

        private var needsComposerDisclosureControl: Bool {
            ComposerOverflowHeuristic.exceedsCollapsedLineLimit(
                structuredPrompt, collapsedLines: 3, averageCharactersPerLine: 32)
        }

        private var composerDisclosureControl: some View {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isComposerExpanded.toggle()
                }
            } label: {
                Image(systemName: isComposerExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NexusIOSTheme.mutedText)
                    .frame(width: 28, height: 16)
                    .background(.thinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(NexusIOSTheme.softLine, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private var structuredComposerBar: some View {
            if let structuredChromePresentation,
                let composerPresentation = structuredComposerPresentation,
                let sendAffordance = structuredSendAffordance,
                let slashCommandMenuPresentation = structuredSlashCommandMenuPresentation
            {
                let statusBarPresentation = structuredSessionStatusBarPresentation(
                    for: structuredChromePresentation,
                    workspaceLocation: structuredSessionWorkspaceLocation(for: structuredChromePresentation.session)
                )

                VStack(spacing: 8) {
                    if composerPresentation.isEnabled {
                        if slashCommandMenuPresentation.isVisible {
                            iosStructuredSessionSlashCommandMenu(slashCommandMenuPresentation)
                        }

                        if aboveEditorWidgets.isEmpty == false {
                            structuredSessionExtensionWidgetsView(aboveEditorWidgets)
                        }

                        iosStructuredSessionStatusBar(statusBarPresentation)

                        HStack(alignment: .bottom, spacing: 10) {
                            TextField(composerPresentation.placeholder, text: $structuredPrompt, axis: .vertical)
                                .focused($isStructuredPromptFocused)
                                .textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled()
                                .lineLimit(isComposerExpanded ? 1...14 : 1...3)
                                .disabled(isPerformingAction || structuredChromePresentation.isAgentTurnInProgress)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .nexusIOSTextField(tint: NexusIOSTheme.gold)
                                .overlay(alignment: .top) {
                                    if needsComposerDisclosureControl {
                                        composerDisclosureControl.offset(y: -11)
                                    }
                                }

                            if sendAffordance.isVisible {
                                Button {
                                    sendStructuredPrompt()
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(NexusIOSTheme.textPrimary)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            sendAffordance.isEnabled
                                                ? NexusIOSTheme.gold
                                                : NexusIOSTheme.gold.opacity(0.32),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(sendAffordance.isEnabled == false)
                                .accessibilityLabel("Send")
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                            }
                        }
                        .animation(.easeOut(duration: 0.16), value: sendAffordance.isVisible)

                        if belowEditorWidgets.isEmpty == false {
                            structuredSessionExtensionWidgetsView(belowEditorWidgets)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Text(composerPresentation.disabledReason ?? "Take over to reply from this iPhone.")
                                .font(NexusIOSTheme.bodyFont(13))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            Button(controllerActionTitle) {
                                toggleControllerState()
                            }
                            .buttonStyle(NexusIOSPrimaryButtonStyle())
                            .disabled(isPerformingAction || surfacePresentation?.showsAttachment == false)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(NexusIOSTheme.overlay(0.08))
                        .frame(height: 1)
                }
            }
        }

        @ViewBuilder
        private func iosStructuredSessionSlashCommandMenu(_ menu: StructuredSessionSlashCommandMenuPresentation)
            -> some View
        {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(menu.commands) { command in
                        Button {
                            structuredPrompt = menu.applying(command, to: structuredPrompt)
                            isStructuredPromptFocused = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.displayText)
                                    .font(NexusIOSTheme.monoFont(13, relativeTo: .callout))
                                    .foregroundStyle(NexusIOSTheme.textPrimary)
                                Text(command.summary)
                                    .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                                    .foregroundStyle(NexusIOSTheme.mutedText)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(NexusIOSTheme.overlay(0.05))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(NexusIOSTheme.softLine, lineWidth: 1)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NexusIOSTheme.panelRaised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NexusIOSTheme.line, lineWidth: 1)
            }
            .shadow(color: NexusIOSTheme.shadow(0.16), radius: 18, y: 8)
        }

        private var terminalComposerBar: some View {
            VStack(spacing: 8) {
                if model.focusedSessionIsController {
                    TextField("Type and press return", text: $terminalDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($isTerminalInputFocused)
                        .nexusIOSTextField(tint: accent)
                        .onSubmit {
                            prepareAndSendDraftText()
                        }

                    HStack {
                        Text("Return sends")
                            .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                        Spacer(minLength: 0)
                        terminalKeyMenu
                    }
                } else {
                    HStack(spacing: 12) {
                        Text("Take over to type from this iPhone.")
                            .font(NexusIOSTheme.bodyFont(13))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                        Spacer(minLength: 0)
                        Button(controllerActionTitle) {
                            toggleControllerState()
                        }
                        .buttonStyle(NexusIOSPrimaryButtonStyle())
                        .disabled(isPerformingAction || surfacePresentation?.showsAttachment == false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NexusIOSTheme.overlay(0.08))
                    .frame(height: 1)
            }
        }

        private var terminalKeyMenu: some View {
            Menu {
                Button("Return") {
                    sendInputKey(.enter)
                }
                Button("Backspace") {
                    sendInputKey(.backspace)
                }
                Button("Ctrl-C") {
                    sendInputKey(.interrupt)
                }
            } label: {
                Label("Keys", systemImage: "command")
                    .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                    .foregroundStyle(NexusIOSTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(NexusIOSTheme.overlay(0.08), in: Capsule())
            }
        }

        private func relaunchSession() {
            performAction(.relaunch) {
                _ = try await model.launchOrResumeSession(
                    sessionID: currentSession.id,
                    workspaceID: currentSession.workspaceID,
                    providerID: currentSession.providerID
                )
            }
        }

        private func stopSession() {
            performAction(.stop) {
                _ = try await model.stopSession(
                    sessionID: currentSession.id,
                    workspaceID: currentSession.workspaceID,
                    providerID: currentSession.providerID
                )
            }
        }

        private func toggleControllerState() {
            let action: RemoteSessionAction = model.focusedSessionIsController ? .returnToViewer : .takeController
            performAction(action) {
                if model.focusedSessionIsController {
                    await model.releaseFocusedRemoteSessionControl()
                } else {
                    let viewport = terminalViewport()
                    try await model.takeFocusedRemoteSessionControl(columns: viewport.columns, rows: viewport.rows)
                }
            }
        }

        private func performAction(
            _ action: RemoteSessionAction,
            operation: @escaping @MainActor () async throws -> Void
        ) {
            activeAction = action
            Task { @MainActor in
                defer { activeAction = nil }

                do {
                    try await operation()
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                }
            }
        }

        private func prepareAndSendDraftText() {
            guard terminalDraft.isEmpty == false else {
                return
            }

            if isTerminalInputFocused {
                isTerminalInputFocused = false
                Task { @MainActor in
                    await Task.yield()
                    sendDraftText()
                }
                return
            }

            sendDraftText()
        }

        private func sendDraftText() {
            let text = terminalDraft
            guard text.isEmpty == false else {
                return
            }

            terminalDraft = ""
            Task {
                do {
                    try await model.sendTextToFocusedRemoteSession(text)
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                    terminalDraft = text
                }
            }
        }

        private func sendInputKey(_ key: SessionInputKey) {
            Task {
                do {
                    try await model.sendInputKeyToFocusedRemoteSession(key)
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                }
            }
        }

        private func structuredSessionContent(
            _ presentation: FocusedStructuredSessionPresentation,
            approvalRequestPresentation: StructuredSessionApprovalRequestPresentation
        ) -> some View {
            let feedPresentation = presentation.feed

            // Supplementary chrome (approvals, extension dialogs/summary) is rendered *outside*
            // the live feed ScrollView. This prevents live appends to the activity feed
            // from forcing re-measurement of the chrome (and vice-versa) during long sessions.
            // Matches the macOS isolation change.
            return VStack(spacing: 0) {
                structuredSessionSupplementaryContent(
                    presentation: presentation,
                    approvalRequestPresentation: approvalRequestPresentation
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        structuredSessionHistoryPagingControls()

                        structuredSessionActivityFeed(
                            feedPresentation: feedPresentation,
                            providerDisplayName: presentation.session.providerID.displayName
                        )

                        Color.clear
                            .frame(height: 1)
                            .id(structuredSessionFeedBottomSentinelID)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                    .scrollTargetLayout()
                }
                .scrollPosition($structuredSessionFeedScrollPosition)
                .onScrollGeometryChange(for: StructuredSessionScrollGeometrySample.self) { geometry in
                    StructuredSessionScrollGeometrySample(
                        distanceFromBottom: max(
                            0,
                            geometry.contentSize.height
                                - geometry.contentOffset.y
                                - geometry.containerSize.height
                        ),
                        contentOffsetY: geometry.contentOffset.y
                    )
                } action: { _, sample in
                    let idleState = structuredSessionFeedScrollReaderIdleState(
                        previousSample: structuredSessionFeedScrollGeometrySample,
                        currentSample: sample,
                        now: Date(),
                        lastMovementAt: structuredSessionFeedScrollLastMovementAt
                    )
                    structuredSessionFeedScrollGeometrySample = sample
                    structuredSessionFeedScrollLastMovementAt = idleState.lastMovementAt
                    structuredSessionFeedScrollIsIdle = idleState.isScrollIdle
                    if idleState.isScrollIdle, let structuredPresentation {
                        structuredSessionFeedStableFollowScrollToken = structuredSessionFeedFollowScrollToken(
                            for: structuredPresentation
                        )
                    }
                    if let next = structuredSessionFeedPinStateIfChangedDuringOpenAgentTurn(
                        previous: structuredSessionPinState,
                        sample: sample,
                        effectiveTurnInProgress: structuredSessionEffectiveAgentTurnInProgress(for: presentation)
                    ) {
                        structuredSessionPinState = next
                    }
                }
                .onAppear {
                    structuredSessionPinState = StructuredSessionFeedPinState()
                    structuredSessionScheduleFeedActivityRowsIfNeeded()
                    if structuredSessionEffectiveAgentTurnInProgress(for: presentation) {
                        structuredSessionFeedScrollPosition = ScrollPosition()
                    }
                    structuredSessionFeedScrollSnapshot =
                        StructuredSessionFeedScrollSupport
                        .applyStructuredSessionFeedScrollSnapshotTransition(
                            previous: nil,
                            current: presentation.structuredSessionFeedScrollSnapshot,
                            isFollowingBottom: structuredSessionPinState.isFollowingBottom,
                            coordinator: structuredSessionAutoScrollCoordinator,
                            draftGrowthThrottle: structuredSessionDraftGrowthScrollThrottle,
                            scrollPosition: $structuredSessionFeedScrollPosition,
                            scrollPositionUsesBottomEdge: structuredSessionFeedUsesBottomEdgeScrollPositionBinding(
                                for: presentation
                            )
                        )
                }
                .onChange(of: structuredSessionEffectiveAgentTurnInProgress(for: presentation)) { _, _ in
                    // Turn open/close changes content height a lot (Thinking, tool rows, final streaming).
                    // Reset the ScrollPosition binding to avoid sticking to a row that is growing/replaced.
                    // Do NOT hard-force pinState detached/following here.
                    // The live onScrollGeometryChange always runs distance-based pin logic
                    // (structuredSessionFeedPinStateIfChangedDuringOpenAgentTurn delegates to normal
                    // distance rule). This gives classic autoscroll:
                    // - viewport near bottom (distance <= 48pt) → isFollowingBottom = true → follow tail
                    // - user scrolled away (distance > threshold) → detached, no auto-scroll
                    // - user scrolls viewport back to bottom → geometry re-enables following
                    structuredSessionFeedScrollPosition = ScrollPosition()
                }

                .onChange(of: presentation.session.id) { _, _ in
                    structuredSessionPinState = StructuredSessionFeedPinState()
                    structuredSessionFeedScrollSnapshot = nil
                    structuredSessionFeedScrollGeometrySample = nil
                    structuredSessionFeedScrollLastMovementAt = Date()
                    structuredSessionFeedScrollIsIdle = false
                    structuredSessionFeedStableFollowScrollToken = ""
                    presentedStructuredSessionAssistantFullResponse = nil
                    structuredSessionFeedVisibleTailRowCount = 0
                    structuredSessionAgentTurnDisclosureState.reset()
                    structuredSessionFeedScrollPosition = ScrollPosition()
                    structuredSessionScheduleFeedActivityRowsIfNeeded()
                }
                .onChange(of: presentation.structuredSessionFeedScrollSnapshot) { _, current in
                    guard
                        structuredSessionFeedScrollSnapshotIfScrollPolicyChanged(
                            previous: structuredSessionFeedScrollSnapshot,
                            current: current
                        ) != nil
                    else {
                        return
                    }
                    structuredSessionFeedScrollSnapshot =
                        StructuredSessionFeedScrollSupport
                        .applyStructuredSessionFeedScrollSnapshotTransition(
                            previous: structuredSessionFeedScrollSnapshot,
                            current: current,
                            isFollowingBottom: structuredSessionPinState.isFollowingBottom,
                            coordinator: structuredSessionAutoScrollCoordinator,
                            draftGrowthThrottle: structuredSessionDraftGrowthScrollThrottle,
                            scrollPosition: $structuredSessionFeedScrollPosition,
                            scrollPositionUsesBottomEdge: structuredSessionFeedUsesBottomEdgeScrollPositionBinding(
                                for: presentation
                            )
                        )
                }
                .onChange(of: presentation.feed.feedScrollItemCount) { _, total in
                    let synced = StructuredSessionFeedSegmentRevealPolicy.synchronizedVisibleTailSegmentCount(
                        currentVisibleCount: structuredSessionFeedVisibleTailRowCount,
                        totalFeedSegmentCount: total
                    )
                    if synced != structuredSessionFeedVisibleTailRowCount {
                        structuredSessionFeedVisibleTailRowCount = synced
                    }
                }
            }
            .sheet(item: $presentedStructuredSessionAssistantFullResponse) { presentation in
                NavigationStack {
                    StructuredSessionAssistantFullResponseReader(markdown: presentation.markdown)
                        .navigationTitle("Assistant response")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    presentedStructuredSessionAssistantFullResponse = nil
                                }
                            }
                        }
                }
            }
        }

        @ViewBuilder
        private func structuredSessionHistoryPagingControls() -> some View {
            if model.canLoadOlderFocusedStructuredSessionHistory
                || model.isLoadingOlderFocusedStructuredSessionHistory
                || model.focusedStructuredSessionHistoryErrorMessage != nil
            {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task {
                            await model.loadOlderFocusedStructuredSessionHistory()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isLoadingOlderFocusedStructuredSessionHistory {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(
                                model.isLoadingOlderFocusedStructuredSessionHistory
                                    ? "Loading older activity…" : "Load older activity"
                            )
                            .font(NexusIOSTheme.bodyFont(14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NexusIOSSecondaryButtonStyle())
                    .disabled(
                        model.isLoadingOlderFocusedStructuredSessionHistory
                            || model.canLoadOlderFocusedStructuredSessionHistory == false)

                    if let errorMessage = model.focusedStructuredSessionHistoryErrorMessage {
                        Text(errorMessage)
                            .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(NexusIOSTheme.coral)
                    }
                }
            }
        }

        @ViewBuilder
        private func structuredSessionSupplementaryContent(
            presentation: FocusedStructuredSessionPresentation,
            approvalRequestPresentation: StructuredSessionApprovalRequestPresentation
        ) -> some View {
            if let extensionUI, extensionUI.pendingDialogs.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(extensionUI.pendingDialogs) { dialog in
                        structuredSessionExtensionDialogView(dialog)
                    }
                }
            }

            if presentation.feed.pendingApprovalRequests.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(presentation.feed.pendingApprovalRequests) { request in
                        structuredSessionApprovalRequestView(request, presentation: approvalRequestPresentation)
                    }
                }
            }

            if let extensionUI, shouldShowStructuredSessionExtensionSummary(extensionUI) {
                structuredSessionExtensionSummaryView(extensionUI)
            }
        }

        private func structuredSessionScheduleFeedActivityRowsIfNeeded() {
            guard StructuredSessionFeedProgressiveRevealPolicy.usesProgressiveActivityRowReveal else {
                structuredSessionFeedVisibleTailRowCount = Int.max
                return
            }
            guard structuredSessionFeedVisibleTailRowCount == 0 else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                structuredSessionRevealFeedActivityRowsProgressively()
            }
        }

        private func structuredSessionRevealFeedActivityRowsProgressively() {
            guard let feed = structuredFeedPresentation else {
                return
            }
            let total = feed.feedScrollItemCount
            guard total > 0 else {
                structuredSessionFeedVisibleTailRowCount = 0
                return
            }
            let initial = min(StructuredSessionFeedProgressiveRevealPolicy.initialVisibleTailRowCount, total)
            structuredSessionFeedVisibleTailRowCount = initial
            guard initial < total else {
                return
            }
            Task { @MainActor in
                var visible = initial
                while visible < total {
                    await Task.yield()
                    visible = StructuredSessionFeedProgressiveRevealPolicy.nextVisibleTailRowCount(
                        currentVisibleCount: visible,
                        totalRowCount: total
                    )
                    structuredSessionFeedVisibleTailRowCount = visible
                }
            }
        }

        @ViewBuilder
        private func structuredSessionActivityFeed(
            feedPresentation: StructuredSessionFeedPresentation,
            providerDisplayName: String
        ) -> some View {
            if feedPresentation.activityRowChunks.isEmpty {
                RemoteUnavailableInsetCard(
                    title: feedPresentation.copy.emptyStateTitle,
                    detail: feedPresentation.copy.emptyStateDescription,
                    accent: NexusIOSTheme.gold
                )
            } else if feedPresentation.activityRows.isEmpty {
                EmptyView()
            } else if feedPresentation.feedSegments != nil {
                if let segments = feedPresentation.feedSegments,
                    let visibleIndices = structuredSessionVisibleFeedSegmentIndices(
                        in: feedPresentation,
                        visibleTailItemCount: structuredSessionFeedVisibleTailRowCount
                    )
                {
                    ForEach(visibleIndices, id: \.self) { index in
                        let segment = segments[index]
                        if structuredSessionShouldRenderFeedSegment(
                            segment,
                            hiddenStandaloneFeedSegmentIDs: feedPresentation.hiddenStandaloneFeedSegmentIDs
                        ) {
                            StructuredSessionPiFeedSegmentView(
                                segment: segment,
                                providerDisplayName: providerDisplayName,
                                style: iosPiStructuredSessionFeedSegmentStyle(
                                    feedReaderIsScrollIdle: structuredSessionFeedScrollIsIdle
                                ),
                                disclosureState: structuredSessionAgentTurnDisclosureState,
                                standaloneRow: { row in
                                    AnyView(structuredSessionActivityRowView(row))
                                },
                                onShowFullAssistantResponse: { presentation in
                                    presentedStructuredSessionAssistantFullResponse = presentation
                                },
                                artifactActions: { artifact in
                                    structuredSessionFeedArtifactActionPresentation(
                                        for: artifact,
                                        hasWriterAuthority: model.focusedSessionIsController,
                                        usesHostArtifactFetch: true
                                    )
                                },
                                onArtifactDownload: { artifact in
                                    Task {
                                        await model.downloadFocusedStructuredSessionArtifact(artifact)
                                    }
                                }
                            )
                            .id(segment.id)
                        }
                    }
                }

                if StructuredSessionFeedProgressiveRevealPolicy.shouldShowThinkingIndicator(
                    in: feedPresentation,
                    visibleTailRowCount: structuredSessionFeedVisibleTailRowCount
                ), let thinkingIndicator = feedPresentation.thinkingIndicator {
                    structuredSessionThinkingIndicatorView(thinkingIndicator)
                        .id("structured-session-thinking-indicator")
                }
            } else {
                let visibleRows = StructuredSessionFeedProgressiveRevealPolicy.visibleActivityRows(
                    in: feedPresentation,
                    visibleTailRowCount: structuredSessionFeedVisibleTailRowCount
                )
                ForEach(visibleRows) { row in
                    IOSEquatableStructuredSessionActivityRow(row: row) {
                        structuredSessionActivityRowView(row)
                    }
                    .equatable()
                    .id(row.id)
                }

                if StructuredSessionFeedProgressiveRevealPolicy.shouldShowThinkingIndicator(
                    in: feedPresentation,
                    visibleTailRowCount: structuredSessionFeedVisibleTailRowCount
                ), let thinkingIndicator = feedPresentation.thinkingIndicator {
                    structuredSessionThinkingIndicatorView(thinkingIndicator)
                        .id("structured-session-thinking-indicator")
                }
            }
        }

        private func shouldShowStructuredSessionExtensionSummary(_ extensionUI: SessionExtensionUIState) -> Bool {
            extensionUI.title != nil || extensionUI.statuses.isEmpty == false
                || extensionUI.notifications.isEmpty == false
        }

        private func structuredSessionThinkingIndicatorView(_ indicator: StructuredSessionThinkingIndicator)
            -> some View
        {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(NexusIOSTheme.gold)
                    Text(indicator.text)
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NexusIOSTheme.overlay(0.05), in: Capsule())
                Spacer()
            }
        }

        @ViewBuilder
        private func structuredSessionActivityRowView(_ row: StructuredSessionActivityRow) -> some View {
            let accentColor = structuredSessionActivityColor(for: row.emphasis)
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
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(conversation.text)
                            .font(NexusIOSTheme.bodyFont(15))
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                            .structuredSessionFeedTextSelection()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(NexusIOSTheme.gold, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .frame(maxWidth: 420, alignment: .trailing)
                    .contextMenu {
                        Button("Copy") {
                            structuredSessionFeedMarkdownCopyToPasteboard(conversation.text)
                        }
                    }
                }
                .structuredSessionFeedRowCompositing()
            case .assistant(let label):
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label)
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                            .foregroundStyle(NexusIOSTheme.mutedText)

                        structuredSessionAssistantResponseView(
                            conversation,
                            rowID: row.id,
                            font: NexusIOSTheme.bodyFont(15),
                            color: NexusIOSTheme.terminalText.opacity(0.94)
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 420, alignment: .leading)
                    .background(NexusIOSTheme.overlay(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contextMenu {
                        Button("Copy") {
                            structuredSessionFeedMarkdownCopyToPasteboard(conversation.text)
                        }
                    }
                    Spacer(minLength: 48)
                }
                .structuredSessionFeedRowCompositing()
            case .command:
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title)
                            .font(NexusIOSTheme.monoFont(10, relativeTo: .caption))
                            .foregroundStyle(accentColor)
                        Text(conversation.text)
                            .font(NexusIOSTheme.monoFont(12, relativeTo: .callout))
                            .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                            .structuredSessionFeedTextSelection()
                            .fixedSize(horizontal: false, vertical: true)
                        if let detailText = row.detailText {
                            structuredSessionDetailTextView(
                                detailText,
                                isTruncated: row.isDetailTextTruncated,
                                font: NexusIOSTheme.monoFont(12, relativeTo: .callout)
                            )
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(NexusIOSTheme.overlay(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer(minLength: 48)
                }
                .structuredSessionFeedRowCompositing()
            case .error:
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Error")
                            .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .semibold))
                            .foregroundStyle(accentColor)
                        Text(conversation.text)
                            .font(NexusIOSTheme.bodyFont(14))
                            .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.94))
                            .structuredSessionFeedTextSelection()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer(minLength: 48)
                }
                .structuredSessionFeedRowCompositing()
            case .system:
                HStack {
                    if row.showsExpandedSystemCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.title)
                                .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                            Text(verbatim: conversation.text)
                                .font(NexusIOSTheme.bodyFont(14))
                                .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                                .structuredSessionFeedTextSelection()
                                .fixedSize(horizontal: false, vertical: true)
                            if let detailText = row.detailText {
                                structuredSessionDetailTextView(
                                    detailText,
                                    isTruncated: row.isDetailTextTruncated,
                                    font: NexusIOSTheme.monoFont(12, relativeTo: .callout)
                                )
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: 520, alignment: .leading)
                        .background(
                            NexusIOSTheme.overlay(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Spacer(minLength: 48)
                    } else {
                        Spacer()
                        Text(conversation.text)
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NexusIOSTheme.overlay(0.05), in: Capsule())
                        Spacer()
                    }
                }
                .structuredSessionFeedRowCompositing()
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
                    charactersPerLine: 56
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
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                    }
                }
            } else {
                let policy = structuredSessionFeedAssistantMarkdownDisplayPolicy(
                    for: conversation.text,
                    charactersPerLine: 56
                )
                let isLatestFinalizedAssistantRow = latestFinalizedAssistantRowID == rowID
                let prefersPlainText = structuredSessionFeedAssistantAutoExpandedLatestResponsePrefersPlainText(
                    policy: policy,
                    isLatestFinalizedAssistantRow: isLatestFinalizedAssistantRow,
                    isExplicitlyExpanded: false
                )
                let allowsInlineMarkdownHydration = structuredSessionFeedAllowsLatestAssistantInlineMarkdownHydration(
                    prefersPlainTextInitialRender: prefersPlainText,
                    feedReaderIsScrollIdle: structuredSessionFeedScrollIsIdle,
                    feedTailIsStableForInlineMarkdown: isStructuredSessionFeedTailStableForInlineMarkdown
                )
                if policy.showsCollapsedPreview, isLatestFinalizedAssistantRow == false {
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
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                            .foregroundStyle(NexusIOSTheme.mutedText)

                        Button(policy.showFullResponseTitle) {
                            presentedStructuredSessionAssistantFullResponse =
                                structuredSessionAssistantFullResponsePresentation(
                                    rowID: rowID,
                                    markdown: conversation.text
                                )
                        }
                        .buttonStyle(.plain)
                        .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                        .foregroundStyle(NexusIOSTheme.gold)
                    }
                } else if prefersPlainText {
                    StructuredSessionIdleGatedAssistantFeedMarkdownText(
                        markdown: conversation.text,
                        font: font,
                        color: color,
                        prefersPlainTextUntilIdle: true,
                        allowsInlineMarkdownHydration: allowsInlineMarkdownHydration
                    )
                } else {
                    structuredSessionMarkdownText(conversation.text, font: font, color: color)
                }
            }
        }

        @ViewBuilder
        private func structuredSessionDetailTextView(_ text: String, isTruncated: Bool, font: Font) -> some View {
            let showsCollapsedPreview = structuredSessionShouldCollapseDetailPreview(text, charactersPerLine: 60)

            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if showsCollapsedPreview {
                        Text(verbatim: text)
                            .font(font)
                            .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.84))
                            .structuredSessionFeedTextSelection()
                            .frame(
                                height: structuredSessionFeedCollapsedDetailViewportHeight,
                                alignment: .top
                            )
                            .clipped()
                    } else {
                        Text(verbatim: text)
                            .font(font)
                            .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.84))
                            .structuredSessionFeedTextSelection()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isTruncated {
                    Text("Output preview truncated for smoother scrolling.")
                        .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                } else if showsCollapsedPreview {
                    Text("Long output preview truncated for smoother scrolling.")
                        .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(NexusIOSTheme.terminalOverlay, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        private func structuredSessionApprovalRequestView(
            _ request: SessionApprovalRequest,
            presentation: StructuredSessionApprovalRequestPresentation
        ) -> some View {
            let isApproving = activeApprovalRequestID == request.id

            return VStack(alignment: .leading, spacing: 12) {
                Label("Approval Request", systemImage: "hand.raised.fill")
                    .font(NexusIOSTheme.bodyFont(14, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.gold)

                Text(request.title)
                    .font(NexusIOSTheme.bodyFont(15, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.textPrimary)

                Text(request.text)
                    .font(NexusIOSTheme.bodyFont(14))
                    .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if presentation.actionsAreEnabled {
                    HStack(spacing: 10) {
                        Button(isApproving ? "Denying…" : "Deny") {
                            respondToStructuredApprovalRequest(request.id, decision: .deny)
                        }
                        .buttonStyle(NexusIOSDangerButtonStyle())
                        .disabled(isPerformingAction)

                        Button(isApproving ? "Approving…" : "Approve") {
                            respondToStructuredApprovalRequest(request.id, decision: .approve)
                        }
                        .buttonStyle(NexusIOSPrimaryButtonStyle())
                        .disabled(isPerformingAction)
                    }
                } else {
                    HStack {
                        Text(presentation.disabledReason ?? "Take over to respond.")
                            .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                        Spacer(minLength: 0)
                        Button(controllerActionTitle) {
                            toggleControllerState()
                        }
                        .buttonStyle(NexusIOSPrimaryButtonStyle())
                        .disabled(isPerformingAction)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusIOSTheme.overlay(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NexusIOSTheme.gold.opacity(0.22))
            }
        }

        private func structuredSessionExtensionDialogView(_ dialog: SessionExtensionUIDialog) -> some View {
            RemoteStructuredSessionExtensionDialogCard(
                dialog: dialog,
                actionsAreEnabled: model.focusedSessionIsController,
                isPerformingAction: isPerformingAction,
                actionTitle: controllerActionTitle,
                onTakeOver: toggleControllerState,
                onRespond: { response in
                    respondToStructuredSessionExtensionDialog(dialog.id, response: response)
                }
            )
        }

        private func structuredSessionExtensionSummaryView(_ extensionUI: SessionExtensionUIState) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                if let title = extensionUI.title, title.isEmpty == false {
                    Text(title)
                        .font(NexusIOSTheme.bodyFont(15, weight: .semibold))
                        .foregroundStyle(NexusIOSTheme.textPrimary)
                }

                if extensionUI.statuses.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.mutedText)

                        ForEach(extensionUI.statuses) { status in
                            Text(status.text)
                                .font(NexusIOSTheme.bodyFont(12))
                                .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(NexusIOSTheme.overlay(0.05), in: Capsule())
                        }
                    }
                }

                if extensionUI.notifications.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications")
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.mutedText)

                        ForEach(extensionUI.notifications.suffix(5)) { notification in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notification.kind.rawValue.capitalized)
                                    .font(NexusIOSTheme.bodyFont(10, relativeTo: .caption, weight: .semibold))
                                    .foregroundStyle(structuredSessionExtensionNotificationColor(notification.kind))
                                Text(notification.message)
                                    .font(NexusIOSTheme.bodyFont(12))
                                    .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                NexusIOSTheme.overlay(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusIOSTheme.overlay(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NexusIOSTheme.teal.opacity(0.22))
            }
        }

        private func structuredSessionExtensionWidgetsView(_ widgets: [SessionExtensionUIWidget]) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(widgets) { widget in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(widget.key)
                            .font(NexusIOSTheme.bodyFont(10, relativeTo: .caption, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                        ForEach(Array(widget.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(NexusIOSTheme.bodyFont(12))
                                .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NexusIOSTheme.overlay(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NexusIOSTheme.overlay(0.08), lineWidth: 1)
                    }
                }
            }
        }

        private func structuredSessionExtensionNotificationColor(_ kind: SessionExtensionUINotificationKind) -> Color {
            switch kind {
            case .info:
                NexusIOSTheme.teal
            case .warning:
                NexusIOSTheme.gold
            case .error:
                NexusIOSTheme.coral
            }
        }

        private func structuredSessionActivityColor(for emphasis: StructuredSessionActivityEmphasis) -> Color {
            switch emphasis {
            case .neutral:
                NexusIOSTheme.mutedText
            case .accent:
                NexusIOSTheme.gold
            case .critical:
                NexusIOSTheme.coral
            case .success:
                NexusIOSTheme.teal
            }
        }

        private func structuredSessionWorkspaceLocation(for session: Session) -> String {
            if model.focusedSessionID == session.id,
                let focusedSessionWorkspaceLocation = model.focusedSessionWorkspaceLocation
            {
                return focusedSessionWorkspaceLocation
            }

            return "Workspace unavailable"
        }

        @ViewBuilder
        private func iosStructuredSessionStatusBar(_ presentation: StructuredSessionStatusBarPresentation) -> some View
        {
            HStack(spacing: 10) {
                Label {
                    Text(presentation.workspaceLocation)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "folder")
                }

                Spacer(minLength: 8)

                Label(presentation.tokenUsageText, systemImage: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(iosStructuredSessionTokenUsageColor(presentation.tokenUsagePercent))
            }
            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
            .foregroundStyle(NexusIOSTheme.mutedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NexusIOSTheme.overlay(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NexusIOSTheme.overlay(0.08), lineWidth: 1)
            }
        }

        private func iosStructuredSessionTokenUsageColor(_ percent: Int?) -> Color {
            guard let percent else {
                return NexusIOSTheme.mutedText
            }

            switch percent {
            case 85...:
                return NexusIOSTheme.coral
            case 60...:
                return NexusIOSTheme.gold
            default:
                return NexusIOSTheme.teal
            }
        }

        private var terminalCellWidth: CGFloat { 8.5 }

        private var terminalCellHeight: CGFloat { 20 }

        private func sendStructuredPrompt() {
            let prompt = structuredPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard prompt.isEmpty == false else {
                return
            }

            structuredPrompt = ""
            Task {
                do {
                    try await model.sendInputToFocusedRemoteSession(prompt)
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                    structuredPrompt = prompt
                }
            }
        }

        private func respondToStructuredApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) {
            activeApprovalRequestID = approvalRequestID
            Task {
                defer { activeApprovalRequestID = nil }
                do {
                    try await model.respondToFocusedRemoteSessionApprovalRequest(approvalRequestID, decision: decision)
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                }
            }
        }

        private func respondToStructuredSessionExtensionDialog(
            _ dialogID: String, response: SessionExtensionUIDialogResponse
        ) {
            activeExtensionDialogID = dialogID
            Task {
                defer { activeExtensionDialogID = nil }
                do {
                    try await model.respondToFocusedRemoteSessionExtensionDialog(dialogID, response: response)
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                }
            }
        }

        private func terminalViewport() -> (columns: Int, rows: Int) {
            if terminalViewportSize != .zero {
                let columns = max(20, Int((terminalViewportSize.width - 24) / terminalCellWidth))
                let rows = max(8, Int((terminalViewportSize.height - 24) / terminalCellHeight))
                return (columns, rows)
            }

            return (screen?.terminalColumns ?? 80, screen?.terminalRows ?? 24)
        }

        @ViewBuilder
        private func terminalLineView(_ line: TerminalLine, row: Int, screen: SessionScreen) -> some View {
            let segments = renderedRemoteTerminalDisplaySegments(for: line, row: row, screen: screen)

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    terminalSegmentView(segment)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }

        @ViewBuilder
        private func terminalSegmentView(_ segment: RemoteTerminalDisplaySegment) -> some View {
            let colors = resolvedTerminalColors(for: segment.style)
            let foreground = segment.isCursor ? NexusIOSTheme.backgroundTop : colors.foreground
            let background = segment.isCursor ? NexusIOSTheme.terminalText : colors.background
            let text = Text(segment.renderedText)
                .font(.system(size: 17, design: .monospaced))
                .fontWeight(segment.style.isBold ? .bold : .regular)
                .foregroundStyle(foreground)
                .opacity(segment.style.isDim ? 0.65 : 1)
                .frame(
                    width: terminalCellWidth * CGFloat(segment.columnCount),
                    height: terminalCellHeight,
                    alignment: .leading
                )
                .background(background)
                .lineLimit(1)

            if segment.style.isItalic {
                text.italic()
            } else {
                text
            }
        }

        private func resolvedTerminalColors(for style: TerminalStyle) -> (foreground: Color, background: Color) {
            let defaultForeground = NexusIOSTheme.terminalText
            let defaultBackground = NexusIOSTheme.terminalSurface
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
    }

    private struct RemoteStructuredSessionExtensionDialogCard: View {
        let dialog: SessionExtensionUIDialog
        let actionsAreEnabled: Bool
        let isPerformingAction: Bool
        let actionTitle: String
        let onTakeOver: () -> Void
        let onRespond: (SessionExtensionUIDialogResponse) -> Void

        @State private var selectedOption: String
        @State private var textValue: String

        init(
            dialog: SessionExtensionUIDialog,
            actionsAreEnabled: Bool,
            isPerformingAction: Bool,
            actionTitle: String,
            onTakeOver: @escaping () -> Void,
            onRespond: @escaping (SessionExtensionUIDialogResponse) -> Void
        ) {
            self.dialog = dialog
            self.actionsAreEnabled = actionsAreEnabled
            self.isPerformingAction = isPerformingAction
            self.actionTitle = actionTitle
            self.onTakeOver = onTakeOver
            self.onRespond = onRespond
            _selectedOption = State(initialValue: dialog.options.first ?? "")
            _textValue = State(initialValue: dialog.prefill ?? "")
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("Extension UI", systemImage: "puzzlepiece.extension.fill")
                    .font(NexusIOSTheme.bodyFont(14, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.teal)

                Text(dialog.title)
                    .font(NexusIOSTheme.bodyFont(15, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.textPrimary)

                if let message = dialog.message, message.isEmpty == false {
                    Text(message)
                        .font(NexusIOSTheme.bodyFont(14))
                        .foregroundStyle(NexusIOSTheme.textPrimary.opacity(0.92))
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

                    actionRow(
                        primaryTitle: "Select",
                        primaryRole: .value(selectedOption),
                        primaryDisabled: selectedOption.isEmpty
                    )
                case .confirm:
                    actionRow(
                        cancelTitle: "Cancel",
                        cancelRole: .confirmed(false),
                        primaryTitle: "Confirm",
                        primaryRole: .confirmed(true),
                        primaryDisabled: false
                    )
                case .input:
                    TextField(dialog.placeholder ?? dialog.title, text: $textValue, axis: .vertical)
                        .lineLimit(1...4)
                        .nexusIOSTextField(tint: NexusIOSTheme.teal)

                    actionRow(
                        primaryTitle: "Submit",
                        primaryRole: .value(textValue),
                        primaryDisabled: false
                    )
                case .editor:
                    TextEditor(text: $textValue)
                        .font(NexusIOSTheme.bodyFont(14))
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(
                            NexusIOSTheme.overlay(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(NexusIOSTheme.softLine, lineWidth: 1)
                        }

                    actionRow(
                        primaryTitle: "Submit",
                        primaryRole: .value(textValue),
                        primaryDisabled: false
                    )
                }

                if let timeoutMilliseconds = dialog.timeoutMilliseconds {
                    Text("Auto-cancels after \(timeoutMilliseconds / 1000)s")
                        .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusIOSTheme.overlay(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NexusIOSTheme.teal.opacity(0.22))
            }
        }

        @ViewBuilder
        private func actionRow(
            cancelTitle: String = "Cancel",
            cancelRole: SessionExtensionUIDialogResponse = .cancelled,
            primaryTitle: String,
            primaryRole: SessionExtensionUIDialogResponse,
            primaryDisabled: Bool
        ) -> some View {
            if actionsAreEnabled {
                HStack(spacing: 10) {
                    Button(cancelTitle) {
                        onRespond(cancelRole)
                    }
                    .buttonStyle(NexusIOSSecondaryButtonStyle())
                    .disabled(isPerformingAction)

                    Button(primaryTitle) {
                        onRespond(primaryRole)
                    }
                    .buttonStyle(NexusIOSPrimaryButtonStyle())
                    .disabled(isPerformingAction || primaryDisabled)
                }
            } else {
                HStack {
                    Text("Take Controller to respond to Extension UI dialogs from this iPhone.")
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                    Spacer(minLength: 0)
                    Button(actionTitle) {
                        onTakeOver()
                    }
                    .buttonStyle(NexusIOSPrimaryButtonStyle())
                    .disabled(isPerformingAction)
                }
            }
        }
    }

    private struct RemoteProviderSessionSummaryCard: View {
        let session: Session
        let accent: Color
        let openAction: () -> Void
        let deleteAction: () -> Void
        var deleteDisabled = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: session.isDefault ? "message.fill" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.isDefault ? "Default chat" : (session.name ?? "Chat"))
                            .font(NexusIOSTheme.bodyFont(16, weight: .semibold))
                            .foregroundStyle(NexusIOSTheme.textPrimary)
                        Text(session.failureMessage ?? session.state.rawValue.capitalized)
                            .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                            .foregroundStyle(deleteDisabled ? NexusIOSTheme.mutedText : accent)
                    }

                    Spacer(minLength: 0)
                    NexusIOSStatusPill(text: session.state.rawValue.capitalized, color: accent)
                }

                HStack(spacing: 10) {
                    Button("Open") {
                        openAction()
                    }
                    .buttonStyle(NexusIOSSecondaryButtonStyle())

                    Button("Delete") {
                        deleteAction()
                    }
                    .buttonStyle(NexusIOSDangerButtonStyle())
                    .disabled(deleteDisabled)
                }
            }
            .padding(16)
            .nexusIOSPanel(tint: accent, radius: 20)
        }

        func disabledDelete(_ isDisabled: Bool) -> RemoteProviderSessionSummaryCard {
            var copy = self
            copy.deleteDisabled = isDisabled
            return copy
        }
    }

    private struct RemoteUnavailableCard: View {
        let title: String
        let detail: String

        var body: some View {
            ZStack {
                NexusIOSBackdrop()
                VStack(alignment: .leading, spacing: 12) {
                    NexusIOSSectionHeader(eyebrow: "Unavailable", title: title, detail: detail)
                }
                .padding(22)
                .nexusIOSPanel(tint: NexusIOSTheme.coral, radius: 28)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private struct RemoteUnavailableInsetCard: View {
        let title: String
        let detail: String
        let accent: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(NexusIOSTheme.bodyFont(14, weight: .semibold))
                    .foregroundStyle(NexusIOSTheme.textPrimary)
                Text(detail)
                    .font(NexusIOSTheme.bodyFont(13))
                    .foregroundStyle(NexusIOSTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexusIOSPanel(tint: accent, radius: 18)
        }
    }

    private struct RemoteClientHomePresentedError: Identifiable {
        let id = UUID()
        let message: String
    }
#endif
