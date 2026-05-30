#if os(iOS)
import NexusDomain
import SwiftUI

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

    private var catalog: RemoteWorkspaceCatalog? {
        model.catalog
    }

    private var availableWorkspaceGroups: [WorkspaceGroup] {
        guard let catalog else {
            return []
        }

        return catalog.workspaceGroups
            .filter { group in
                catalog.workspaceOverviews.contains { $0.workspace.primaryGroupID == group.id }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var workspaceRecencyRanking: [UUID: Int] {
        guard let catalog else {
            return [:]
        }

        var workspaceIDs: [UUID] = []

        if let workspaceID = model.focusedSessionScreen?.session.workspaceID {
            workspaceIDs.append(workspaceID)
        }

        for item in catalog.recentNavigation {
            switch item.target.kind {
            case .workspace, .provider:
                if let workspaceID = item.target.workspaceID {
                    workspaceIDs.append(workspaceID)
                }
            case .session:
                if let sessionID = item.target.sessionID,
                   let workspaceID = workspaceID(forSessionID: sessionID, catalog: catalog) {
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

    private var sortedWorkspaceOverviews: [WorkspaceOverview] {
        guard let catalog else {
            return []
        }

        let ranking = workspaceRecencyRanking
        return catalog.workspaceOverviews.sorted { lhs, rhs in
            let lhsRank = ranking[lhs.workspace.id] ?? Int.max
            let rhsRank = ranking[rhs.workspace.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.workspace.name.localizedCaseInsensitiveCompare(rhs.workspace.name) == .orderedAscending
        }
    }

    private var filteredWorkspaceOverviews: [WorkspaceOverview] {
        switch workspaceBrowseMode {
        case .all:
            return sortedWorkspaceOverviews
        case .groups:
            guard let selectedWorkspaceGroupID else {
                return sortedWorkspaceOverviews
            }
            return sortedWorkspaceOverviews.filter { $0.workspace.primaryGroupID == selectedWorkspaceGroupID }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NexusIOSBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                        heroCard

                        if let pairingRecoveryMessage = model.pairingRecoveryMessage {
                            messageCard(
                                eyebrow: "Pairing required",
                                title: "Reconnect this iPhone.",
                                detail: pairingRecoveryMessage,
                                accent: NexusIOSTheme.coral
                            )
                        }

                        if let activePairedMac = model.activePairedMac {
                            activePairedMacCard(activePairedMac)
                        }

                        if model.pairedMacs.isEmpty == false {
                            pairedMacsSection
                        }

                        catalogSection
                        pairingSection
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
        .preferredColorScheme(.dark)
        .tint(NexusIOSTheme.gold)
        .onAppear {
            if model.pairedMacs.isEmpty {
                isShowingPairingForm = true
            }
        }
        .onChange(of: availableWorkspaceGroups.map(\.id)) { _, groupIDs in
            if let selectedWorkspaceGroupID, groupIDs.contains(selectedWorkspaceGroupID) == false {
                self.selectedWorkspaceGroupID = nil
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("Nexus Remote"), message: Text(error.message))
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nexus")
                        .font(NexusIOSTheme.displayFont(horizontalSizeClass == .regular ? 34 : 30, relativeTo: .largeTitle))
                        .foregroundStyle(.white)

                    Text("Simple remote chats for your workspaces.")
                        .font(NexusIOSTheme.bodyFont(15))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }

                Spacer(minLength: 0)

                if let activePairedMac = model.activePairedMac {
                    NexusIOSStatusPill(
                        text: availabilityTitle(for: activePairedMac),
                        color: availabilityColor(for: activePairedMac)
                    )
                }
            }

            Text(model.pairedMacs.isEmpty
                 ? "Pair your Mac, then jump straight into workspace conversations."
                 : "Workspaces float to the top when you use them, and groups stay tucked away until you need a filter.")
                .font(NexusIOSTheme.bodyFont(14))
                .foregroundStyle(NexusIOSTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(isRefreshingAvailability ? "Refreshing…" : "Refresh") {
                    Task {
                        await refreshAvailability()
                    }
                }
                .buttonStyle(NexusIOSSecondaryButtonStyle())
                .disabled(isRefreshingAvailability)

                Button(model.pairedMacs.isEmpty ? "Pair a Mac" : "Add Mac") {
                    isShowingPairingForm = true
                }
                .buttonStyle(NexusIOSPrimaryButtonStyle())
            }
        }
        .padding(horizontalSizeClass == .regular ? 24 : 20)
        .nexusIOSPanel(tint: NexusIOSTheme.gold, radius: 26, raised: true)
    }

    private func activePairedMacCard(_ pairedMac: PairedMac) -> some View {
        let availability = model.availability(for: pairedMac)
        let accent = availabilityColor(for: pairedMac)

        return Button {
            withAnimation {
                isShowingPairedMacs.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: availability == .available ? "laptopcomputer.and.iphone" : "wifi.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(pairedMac.name)
                        .font(NexusIOSTheme.bodyFont(17, weight: .semibold))
                        .foregroundStyle(.white)
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
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(18)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .nexusIOSPanel(tint: accent, radius: 22)
    }

    @ViewBuilder
    private var pairedMacsSection: some View {
        if isShowingPairedMacs || model.pairedMacs.count == 1 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Paired Macs")
                        .font(NexusIOSTheme.bodyFont(16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(model.pairedMacs.count)")
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
                .padding(.horizontal, 4)

                ForEach(model.pairedMacs) { pairedMac in
                    pairedMacCard(pairedMac)
                }
            }
        }
    }

    private func pairedMacCard(_ pairedMac: PairedMac) -> some View {
        let isActive = model.activePairedMac?.id == pairedMac.id
        let accent = isActive ? availabilityColor(for: pairedMac) : Color.white.opacity(0.72)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(pairedMac.name)
                            .font(NexusIOSTheme.bodyFont(16, weight: .semibold))
                            .foregroundStyle(.white)
                        if isActive {
                            NexusIOSStatusPill(text: "Current", color: availabilityColor(for: pairedMac))
                        }
                    }

                    Text(model.availability(for: pairedMac).summary)
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(isActive ? availabilityColor(for: pairedMac) : NexusIOSTheme.mutedText)
                }

                Spacer(minLength: 0)

                Text("\(pairedMac.host):\(pairedMac.port)")
                    .font(NexusIOSTheme.monoFont(11, relativeTo: .caption))
                    .foregroundStyle(NexusIOSTheme.mutedText)
            }

            HStack(spacing: 10) {
                if isActive == false {
                    Button("Use This Mac") {
                        selectActivePairedMac(pairedMac)
                    }
                    .buttonStyle(NexusIOSPrimaryButtonStyle())
                }

                Button("Forget") {
                    forgetPairedMac(pairedMac)
                }
                .buttonStyle(NexusIOSDangerButtonStyle())
            }
        }
        .padding(16)
        .nexusIOSPanel(tint: accent, radius: 20)
    }

    @ViewBuilder
    private var catalogSection: some View {
        if catalog != nil {
            VStack(alignment: .leading, spacing: 14) {
                if filteredWorkspaceOverviews.isEmpty {
                    messageCard(
                        eyebrow: workspaceBrowseMode == .groups ? "No workspaces in this filter" : "No workspaces yet",
                        title: workspaceBrowseMode == .groups ? "Try another group." : "Nothing remote is ready yet.",
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
                                    .foregroundStyle(.white)
                                Text("Your most recently used workspaces rise to the top.")
                                    .font(NexusIOSTheme.bodyFont(13))
                                    .foregroundStyle(NexusIOSTheme.mutedText)
                            }

                            Spacer(minLength: 0)

                            Text("\(filteredWorkspaceOverviews.count)")
                                .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                        }
                        .padding(.horizontal, 4)

                        if availableWorkspaceGroups.isEmpty == false {
                            Picker("Browse", selection: $workspaceBrowseMode) {
                                ForEach(RemoteWorkspaceBrowseMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if workspaceBrowseMode == .groups {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        groupFilterChip(title: "All Groups", groupID: nil)
                                        ForEach(availableWorkspaceGroups) { group in
                                            groupFilterChip(title: group.name, groupID: group.id)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }

                    ForEach(filteredWorkspaceOverviews, id: \.workspace.id) { overview in
                        NavigationLink {
                            RemoteWorkspaceDetailView(model: model, overview: overview)
                        } label: {
                            RemoteWorkspaceSummaryCard(
                                overview: overview,
                                groupName: groupName(for: overview.workspace.primaryGroupID),
                                showsGroupName: workspaceBrowseMode == .groups && selectedWorkspaceGroupID == nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if let activePairedMac = model.activePairedMac,
                  model.availability(for: activePairedMac) == .available {
            messageCard(
                eyebrow: "Workspace catalog",
                title: model.catalogErrorMessage == nil ? "Loading your workspaces…" : "Catalog unavailable right now.",
                detail: model.catalogErrorMessage ?? "Nexus is fetching workspace conversations from \(activePairedMac.name).",
                accent: model.catalogErrorMessage == nil ? NexusIOSTheme.gold : NexusIOSTheme.coral
            )
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
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
                    completePairing()
                }
                .buttonStyle(NexusIOSPrimaryButtonStyle())
                .disabled(isPairing)
            }
            .padding(20)
            .nexusIOSPanel(tint: NexusIOSTheme.gold, radius: 24, raised: true)
        }
    }

    private func groupFilterChip(title: String, groupID: UUID?) -> some View {
        Button {
            selectedWorkspaceGroupID = groupID
        } label: {
            Text(title)
                .font(NexusIOSTheme.bodyFont(13, relativeTo: .callout, weight: .medium))
                .foregroundStyle(selectedWorkspaceGroupID == groupID ? .white : NexusIOSTheme.mutedText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background((selectedWorkspaceGroupID == groupID ? NexusIOSTheme.gold : Color.white.opacity(0.06)), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(selectedWorkspaceGroupID == groupID ? NexusIOSTheme.gold.opacity(0.3) : NexusIOSTheme.softLine, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func messageCard(eyebrow: String, title: String, detail: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NexusIOSCardTitle(eyebrow: eyebrow, title: title, detail: detail, accent: accent)
        }
        .padding(18)
        .nexusIOSPanel(tint: accent, radius: 22)
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

        if let activePairedMac = model.activePairedMac,
           model.availability(for: activePairedMac) == .available {
            await model.refreshActivePairedMacCatalog()
        } else {
            model.catalog = nil
            model.catalogErrorMessage = nil
        }
    }

    private func workspaceID(forSessionID sessionID: UUID, catalog: RemoteWorkspaceCatalog) -> UUID? {
        for overview in catalog.workspaceOverviews {
            if overview.providerCards.contains(where: { $0.defaultSession.sessionID == sessionID }) {
                return overview.workspace.id
            }
        }
        return nil
    }

    private func groupName(for groupID: UUID?) -> String? {
        guard let groupID else {
            return nil
        }
        return availableWorkspaceGroups.first(where: { $0.id == groupID })?.name
    }

    private func availabilityColor(for pairedMac: PairedMac) -> Color {
        switch model.availability(for: pairedMac) {
        case .available:
            NexusIOSTheme.teal
        case .unavailablePairedMac, .remoteAccessDisabled:
            NexusIOSTheme.coral
        case .unknown:
            NexusIOSTheme.gold
        }
    }

    private func availabilityTitle(for pairedMac: PairedMac) -> String {
        switch model.availability(for: pairedMac) {
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
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let groupName, showsGroupName {
                            Text(groupName)
                                .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                                .foregroundStyle(NexusIOSTheme.mutedText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(NexusIOSTheme.bodyFont(13))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                        .lineLimit(2)

                    if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability,
                       workspaceAvailability.state != .available {
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
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
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
                    .foregroundStyle(.white)
                Text(item.subtitle)
                    .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption))
                    .foregroundStyle(NexusIOSTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.44))
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
                       workspaceAvailability.state != .available || workspaceAvailability.diagnostics.isEmpty == false {
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
                        .font(NexusIOSTheme.displayFont(horizontalSizeClass == .regular ? 32 : 28, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
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
                    .nexusIOSPanel(tint: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state), radius: 16)
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
                        .foregroundStyle(.white)
                    Text(overview.providerCards.isEmpty ? "Nothing is available yet." : "Choose who you want to talk to.")
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
            RemoteUnavailableCard(title: "Workspace unavailable", detail: "Reconnect to the paired Mac and refresh the Workspace catalog.")
        }
    }
}

private struct RemoteProviderDestinationView: View {
    @Bindable var model: RemoteClientPairingModel
    let workspaceID: UUID
    let providerID: ProviderID

    var body: some View {
        if let overview = model.workspaceOverview(id: workspaceID),
           let providerCard = model.providerCard(workspaceID: workspaceID, providerID: providerID) {
            RemoteProviderDetailView(model: model, overview: overview, providerCard: providerCard)
        } else {
            RemoteUnavailableCard(title: "Provider unavailable", detail: "Refresh this Workspace on the paired Mac and try again.")
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
            if let session = model.resolvedSession(workspaceID: workspaceID, providerID: providerID, sessionID: sessionID) {
                RemoteSessionScreenView(model: model, session: session)
            } else if let errorMessage = model.providerDetailErrorMessage(for: workspaceID, providerID: providerID) {
                RemoteUnavailableCard(title: "Session unavailable", detail: errorMessage)
            } else {
                RemoteUnavailableCard(title: "Loading Session…", detail: "Nexus is resolving the Session from the paired Mac.")
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
        providerHealthColor(providerCard.health.state)
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
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(NexusIOSTheme.bodyFont(13))
                    .foregroundStyle(NexusIOSTheme.mutedText)
                    .lineLimit(2)

                if providerCard.alternateSessionCount > 0 {
                    Text("\(providerCard.alternateSessionCount) other chat\(providerCard.alternateSessionCount == 1 ? "" : "s")")
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .medium))
                        .foregroundStyle(accent)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(16)
        .nexusIOSPanel(tint: accent, radius: 20)
    }
}

private func remoteWorkspaceTargetSummary(for overview: WorkspaceOverview) -> String {
    overview.remoteTarget.map { "\($0.host.name) • \(overview.workspace.folderPath)" } ?? overview.workspace.folderPath
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
        providerHealthColor(detail?.health.state ?? providerCard.health.state)
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    private var showsProviderIssues: Bool {
        if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability,
           workspaceAvailability.state != .available || workspaceAvailability.diagnostics.isEmpty == false {
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
                await model.loadProviderDetail(workspaceID: overview.workspace.id, providerID: providerCard.provider.id)
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
                        .font(NexusIOSTheme.displayFont(horizontalSizeClass == .regular ? 32 : 28, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                    Text(overview.workspace.name)
                        .font(NexusIOSTheme.bodyFont(14, weight: .medium))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                }
                Spacer(minLength: 0)
                NexusIOSStatusPill(text: (detail?.health.state ?? providerCard.health.state).rawValue.capitalized, color: accent)
            }

            Text(providerCard.defaultSession.state == .ready
                 ? "Jump straight back into the main chat."
                 : "Start or resume a conversation with \(providerCard.provider.displayName).")
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
                RemoteProviderSessionSummaryCard(session: session, accent: remoteSessionStateColor(session.state)) {
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
               defaultSessionActionState.isEnabled == false {
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
                        .foregroundStyle(.white)
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
                    RemoteProviderSessionSummaryCard(session: session, accent: remoteSessionStateColor(session.state)) {
                        openedSession = session
                    } deleteAction: {
                        if namedSessionsSection.deletableSessionIDs.contains(session.id) {
                            pendingDeleteSessionRecord = session
                        }
                    }
                    .disabledDelete(namedSessionsSection.deletableSessionIDs.contains(session.id) == false)
                }
            case .loading:
                RemoteUnavailableInsetCard(title: "Loading chats…", detail: "Nexus is fetching the rest of this provider’s conversations.", accent: NexusIOSTheme.teal)
            case .none:
                EmptyView()
            }

            Button(isCreatingNamedSession ? "Creating…" : "New chat") {
                createNamedSession()
            }
            .buttonStyle(NexusIOSSecondaryButtonStyle())
            .disabled(isCreatingNamedSession || createNamedSessionActionState.isEnabled == false)

            if let disabledReason = createNamedSessionActionState.disabledReason,
               createNamedSessionActionState.isEnabled == false {
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
               workspaceAvailability.state != .available || workspaceAvailability.diagnostics.isEmpty == false {
                providerAvailabilityCard(workspaceAvailability)
            }

            if let detail, detail.health.state != .available || detail.health.diagnostics.isEmpty == false {
                providerHealthCard
            }

            if let errorMessage {
                RemoteUnavailableInsetCard(title: "Provider detail issue", detail: errorMessage, accent: NexusIOSTheme.coral)
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
                    .nexusIOSPanel(tint: remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state), radius: 16)
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
    @State private var terminalViewportSize: CGSize = .zero
    @State private var isShowingStopConfirmation = false
    @State private var activeAction: RemoteSessionAction?
    @State private var activeApprovalRequestID: UUID?
    @State private var presentedError: RemoteClientHomePresentedError?
    @FocusState private var isStructuredPromptFocused: Bool
    @FocusState private var isTerminalInputFocused: Bool

    private let conversationBottomID = "conversation-bottom"

    private var screen: SessionScreen? {
        guard model.focusedSessionID == session.id else {
            return nil
        }
        return model.focusedSessionScreen
    }

    private var currentSession: Session {
        screen?.session ?? session
    }

    private var isReady: Bool {
        currentSession.state == .ready
    }

    private var surfacePresentation: RemoteSessionSurfacePresentation? {
        guard let screen else {
            return nil
        }

        return remoteSessionSurfacePresentation(
            for: screen,
            isReady: isReady
        )
    }

    private var structuredPresentation: StructuredSessionPresentation? {
        guard let screen else {
            return nil
        }

        return structuredSessionPresentation(
            for: screen,
            isController: model.focusedSessionIsController,
            draft: structuredPrompt,
            isPerformingAction: isPerformingAction || screen.isAgentTurnInProgress
        )
    }

    private var supportsFocusedSessionSurface: Bool {
        surfacePresentation?.surfaceSupport == .supported
    }

    private var isPerformingAction: Bool {
        activeAction != nil || activeApprovalRequestID != nil
    }

    private var accent: Color {
        remoteSessionStateColor(currentSession.state)
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
                if model.focusedSessionIsStale, screen != nil {
                    RemoteUnavailableInsetCard(
                        title: "Connection is stale",
                        detail: model.focusedSessionErrorMessage ?? "Reconnecting… showing the last known conversation.",
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
            await model.focusRemoteSession(sessionID: session.id)
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
            Text("Stop terminates the live Session runtime and keeps the Session record for inspection or relaunch.")
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("Nexus Remote"), message: Text(error.message))
        }
        .onChange(of: terminalViewportSize) { _, _ in
            guard isReady, supportsFocusedSessionSurface, model.focusedSessionIsController else {
                return
            }

            let viewport = terminalViewport()
            Task {
                await model.updateFocusedRemoteSessionViewport(columns: viewport.columns, rows: viewport.rows)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await model.handleFocusedSessionBackgrounded()
                }
            }
        }
        .onDisappear {
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
                    .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
            }
        }
    }

    private var structuredConversationView: some View {
        Group {
            if let screen, let presentation = structuredPresentation {
                structuredSessionContent(screen, presentation: presentation)
            } else if let errorMessage = model.focusedSessionErrorMessage {
                ScrollView {
                    RemoteUnavailableInsetCard(title: "Conversation unavailable", detail: errorMessage, accent: NexusIOSTheme.coral)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 14)
                }
            } else {
                ScrollView {
                    RemoteUnavailableInsetCard(title: "Loading conversation…", detail: "Nexus is connecting to the paired Mac.", accent: NexusIOSTheme.gold)
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
                    .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text("Live terminal")
                            .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                            .foregroundStyle(NexusIOSTheme.mutedText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
                    RemoteUnavailableInsetCard(title: "Session screen unavailable", detail: errorMessage, accent: NexusIOSTheme.coral)
                } else {
                    RemoteUnavailableInsetCard(title: "Loading terminal…", detail: "Nexus is connecting to the paired Mac.", accent: NexusIOSTheme.gold)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private var structuredComposerBar: some View {
        if let screen, let presentation = structuredPresentation {
            VStack(spacing: 8) {
                if presentation.composer.isEnabled {
                    if presentation.slashCommandMenu.isVisible {
                        iosStructuredSessionSlashCommandMenu(presentation.slashCommandMenu.commands)
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        TextField(presentation.composer.placeholder, text: $structuredPrompt, axis: .vertical)
                            .focused($isStructuredPromptFocused)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                            .lineLimit(1 ... 6)
                            .disabled(isPerformingAction || screen.isAgentTurnInProgress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .nexusIOSTextField(tint: NexusIOSTheme.gold)

                        if presentation.sendAffordance.isVisible {
                            Button {
                                sendStructuredPrompt()
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        presentation.sendAffordance.isEnabled
                                            ? NexusIOSTheme.gold
                                            : NexusIOSTheme.gold.opacity(0.32),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(presentation.sendAffordance.isEnabled == false)
                            .accessibilityLabel("Send")
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.16), value: presentation.sendAffordance.isVisible)
                } else {
                    HStack(spacing: 12) {
                        Text(presentation.composer.disabledReason ?? "Take over to reply from this iPhone.")
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
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func iosStructuredSessionSlashCommandMenu(_ commands: [StructuredSessionSlashCommand]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(commands) { command in
                    Button {
                        structuredPrompt = applyStructuredSessionSlashCommand(command, to: structuredPrompt)
                        isStructuredPromptFocused = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(command.displayText)
                                .font(NexusIOSTheme.monoFont(13, relativeTo: .callout))
                                .foregroundStyle(.white)
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
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
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
                .fill(Color.white.opacity(0.08))
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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
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
        _ screen: SessionScreen,
        presentation: StructuredSessionPresentation
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if presentation.feed.pendingApprovalRequests.isEmpty == false {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(presentation.feed.pendingApprovalRequests) { request in
                                structuredSessionApprovalRequestView(request, presentation: presentation.approvalRequest)
                            }
                        }
                    }

                    if presentation.feed.activityRows.isEmpty {
                        RemoteUnavailableInsetCard(
                            title: presentation.feed.copy.emptyStateTitle,
                            detail: presentation.feed.copy.emptyStateDescription,
                            accent: NexusIOSTheme.gold
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(presentation.feed.activityRows) { row in
                                structuredSessionActivityRowView(row, screen: screen)
                                    .id(row.id)
                            }

                            if let thinkingIndicator = presentation.feed.thinkingIndicator {
                                structuredSessionThinkingIndicatorView(thinkingIndicator)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(conversationBottomID)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 120)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(conversationBottomID, anchor: .bottom)
                }
            }
            .onChange(of: presentation.feed.activityRows.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(conversationBottomID, anchor: .bottom)
                }
            }
            .onChange(of: presentation.feed.pendingApprovalRequests.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(conversationBottomID, anchor: .bottom)
                }
            }
        }
    }

    private func structuredSessionThinkingIndicatorView(_ indicator: StructuredSessionThinkingIndicator) -> some View {
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
            .background(Color.white.opacity(0.05), in: Capsule())
            Spacer()
        }
    }

    @ViewBuilder
    private func structuredSessionActivityRowView(
        _ row: StructuredSessionActivityRow,
        screen: SessionScreen
    ) -> some View {
        let accentColor = structuredSessionActivityColor(for: row.emphasis)
        let conversation = structuredSessionConversationPresentation(for: row, screen: screen)

        switch conversation.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(conversation.text)
                        .font(NexusIOSTheme.bodyFont(15))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(NexusIOSTheme.gold, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .frame(maxWidth: 420, alignment: .trailing)
            }
        case .assistant(let label):
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption, weight: .medium))
                        .foregroundStyle(NexusIOSTheme.mutedText)
                    Text(conversation.text)
                        .font(NexusIOSTheme.bodyFont(15))
                        .foregroundStyle(.white.opacity(0.94))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(NexusIOSTheme.softLine, lineWidth: 1)
                }
                Spacer(minLength: 48)
            }
        case .command:
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label(row.title, systemImage: row.systemImage)
                        .font(NexusIOSTheme.monoFont(10, relativeTo: .caption))
                        .foregroundStyle(accentColor)
                    Text(conversation.text)
                        .font(NexusIOSTheme.monoFont(12, relativeTo: .callout))
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accentColor.opacity(0.22), lineWidth: 1)
                }
                Spacer(minLength: 48)
            }
        case .error:
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Error", systemImage: row.systemImage)
                        .font(NexusIOSTheme.bodyFont(12, relativeTo: .caption, weight: .semibold))
                        .foregroundStyle(accentColor)
                    Text(conversation.text)
                        .font(NexusIOSTheme.bodyFont(14))
                        .foregroundStyle(.white.opacity(0.94))
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accentColor.opacity(0.28), lineWidth: 1)
                }
                Spacer(minLength: 48)
            }
        case .system:
            HStack {
                Spacer()
                Label(conversation.text, systemImage: row.systemImage)
                    .font(NexusIOSTheme.bodyFont(11, relativeTo: .caption))
                    .foregroundStyle(NexusIOSTheme.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: Capsule())
                Spacer()
            }
        }
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
                .foregroundStyle(.white)

            Text(request.text)
                .font(NexusIOSTheme.bodyFont(14))
                .foregroundStyle(.white.opacity(0.92))
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NexusIOSTheme.gold.opacity(0.22))
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
        let cells = renderedTerminalCells(for: line, row: row, screen: screen)

        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                terminalCellView(cell)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func terminalCellView(_ cell: RemoteTerminalDisplayCell) -> some View {
        let colors = resolvedTerminalColors(for: cell.style)
        let foreground = cell.isCursor ? Color.black : colors.foreground
        let background = cell.isCursor ? Color.white : colors.background
        let text = Text(cell.renderedText)
            .font(.system(size: 17, design: .monospaced))
            .fontWeight(cell.style.isBold ? .bold : .regular)
            .foregroundStyle(foreground)
            .opacity(cell.style.isDim ? 0.65 : 1)
            .frame(width: terminalCellWidth, height: terminalCellHeight)
            .background(background)
            .lineLimit(1)

        if cell.style.isItalic {
            text.italic()
        } else {
            text
        }
    }

    private func renderedTerminalCells(for line: TerminalLine, row: Int, screen: SessionScreen) -> [RemoteTerminalDisplayCell] {
        let targetColumnCount = max(1, screen.terminalColumns)
        var cells = Array(line.cells.prefix(targetColumnCount)).map {
            RemoteTerminalDisplayCell(text: $0.text, style: $0.style)
        }

        if cells.count < targetColumnCount {
            cells.append(contentsOf: repeatElement(
                RemoteTerminalDisplayCell(text: " ", style: TerminalStyle()),
                count: targetColumnCount - cells.count
            ))
        }

        if screen.cursorVisible, row == screen.cursorRow {
            let cursorIndex = max(0, min(screen.cursorColumn, targetColumnCount - 1))
            let cursorCell = cells[cursorIndex]
            cells[cursorIndex] = RemoteTerminalDisplayCell(
                text: cursorCell.text,
                style: cursorCell.style,
                isCursor: true
            )
        }

        return cells
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
                        .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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

private func providerHealthColor(_ state: ProviderHealthSummary.State) -> Color {
    switch state {
    case .available:
        NexusIOSTheme.teal
    case .unavailable, .blocked:
        NexusIOSTheme.gold
    case .misconfigured:
        NexusIOSTheme.coral
    case .notChecked:
        Color.white.opacity(0.7)
    }
}

private func remoteSessionStateColor(_ state: Session.State) -> Color {
    switch state {
    case .ready:
        NexusIOSTheme.teal
    case .interrupted:
        NexusIOSTheme.gold
    case .exited, .failed:
        NexusIOSTheme.coral
    }
}

private struct RemoteTerminalDisplayCell {
    let text: String
    let style: TerminalStyle
    var isCursor = false

    var renderedText: String {
        if text.isEmpty || text == " " {
            return "\u{00A0}"
        }

        return text
    }
}

private struct RemoteClientHomePresentedError: Identifiable {
    let id = UUID()
    let message: String
}
#endif
