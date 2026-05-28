#if os(iOS)
import NexusDomain
import SwiftUI

struct RemoteClientHomeView: View {
    @Bindable var model: RemoteClientPairingModel

    @State private var isShowingPairingForm = false
    @State private var isPairing = false
    @State private var isRefreshingAvailability = false
    @State private var recentDestination: RemoteBrowseDestination?
    @State private var presentedError: RemoteClientHomePresentedError?

    var body: some View {
        NavigationStack {
            List {
                if let activePairedMac = model.activePairedMac {
                    Section("Active Paired Mac") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activePairedMac.name)
                                .font(.headline)
                            Text(model.availability(for: activePairedMac).summary)
                                .font(.subheadline)
                                .foregroundStyle(availabilityColor(for: activePairedMac))
                            Text("\(activePairedMac.host):\(activePairedMac.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if model.pairedMacs.isEmpty == false {
                    Section("Paired Macs") {
                        ForEach(model.pairedMacs) { pairedMac in
                            Button {
                                selectActivePairedMac(pairedMac)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pairedMac.name)
                                            .fontWeight(.medium)
                                        Text(model.availability(for: pairedMac).summary)
                                            .font(.caption)
                                            .foregroundStyle(availabilityColor(for: pairedMac))
                                        Text("\(pairedMac.host):\(pairedMac.port)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Paired \(pairedMac.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 12)

                                    if model.activePairedMac?.id == pairedMac.id {
                                        Label("Current", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Forget", role: .destructive) {
                                    forgetPairedMac(pairedMac)
                                }
                            }
                        }
                    }
                }

                if let catalog = model.catalog {
                    if catalog.recentNavigation.isEmpty == false {
                        Section("Recent") {
                            ForEach(catalog.recentNavigation) { item in
                                Button {
                                    openRecent(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .fontWeight(.medium)
                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ForEach(catalog.workspaceGroups) { group in
                        let overviews = workspaceOverviews(in: group, catalog: catalog)
                        if overviews.isEmpty == false {
                            Section(group.name) {
                                ForEach(overviews, id: \.workspace.id) { overview in
                                    NavigationLink {
                                        RemoteWorkspaceDetailView(model: model, overview: overview)
                                    } label: {
                                        RemoteWorkspaceSummaryRow(overview: overview)
                                    }
                                }
                            }
                        }
                    }
                } else if let activePairedMac = model.activePairedMac,
                          model.availability(for: activePairedMac) == .available {
                    Section("Workspace Catalog") {
                        Text(model.catalogErrorMessage ?? "Loading Workspaces…")
                            .font(.footnote)
                            .foregroundStyle(model.catalogErrorMessage == nil ? Color.secondary : .orange)
                    }
                }

                if let pairingRecoveryMessage = model.pairingRecoveryMessage {
                    Section("Pairing Required") {
                        Text(pairingRecoveryMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if model.pairedMacs.isEmpty || isShowingPairingForm {
                    Section("Pair a Mac") {
                        TextField("Mac Address", text: $model.macHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Port", text: $model.macPort)
                            .keyboardType(.numberPad)
                        TextField("Pairing Code", text: $model.pairingCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("This iPhone's Name", text: $model.deviceName)

                        Button(isPairing ? "Pairing…" : "Complete Pairing") {
                            completePairing()
                        }
                        .disabled(isPairing)
                    }
                } else {
                    Section {
                        Button("Pair Another Mac") {
                            isShowingPairingForm = true
                        }
                    }
                }

                Section("What’s Next") {
                    Text("Take Controller from a Session to send terminal input from this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .refreshable {
                await refreshAvailability()
            }
            .task(id: availabilityRefreshID) {
                await refreshAvailability()
            }
            .navigationDestination(item: $recentDestination) { destination in
                recentDestinationView(destination)
            }
            .navigationTitle("Nexus Remote")
            .toolbar {
                if model.pairedMacs.isEmpty == false, isShowingPairingForm {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingPairingForm = false
                        }
                    }
                }
            }
        }
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

    private func openRecent(_ item: NavigationItem) {
        Task {
            do {
                let destination = try await model.browseDestination(for: item.target)
                recentDestination = nil
                recentDestination = destination
            } catch {
                presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private func recentDestinationView(_ destination: RemoteBrowseDestination) -> some View {
        switch destination {
        case .workspace(let workspaceID):
            RemoteWorkspaceDestinationView(model: model, workspaceID: workspaceID)
        case .provider(let workspaceID, let providerID):
            RemoteProviderDestinationView(model: model, workspaceID: workspaceID, providerID: providerID)
        case .session(let workspaceID, let providerID, let sessionID):
            RemoteSessionDestinationView(
                model: model,
                workspaceID: workspaceID,
                providerID: providerID,
                sessionID: sessionID
            )
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

    private func workspaceOverviews(in group: WorkspaceGroup, catalog: RemoteWorkspaceCatalog) -> [WorkspaceOverview] {
        catalog.workspaceOverviews.filter { $0.workspace.primaryGroupID == group.id }
    }

    private func availabilityColor(for pairedMac: PairedMac) -> Color {
        switch model.availability(for: pairedMac) {
        case .available:
            .green
        case .unavailablePairedMac, .remoteAccessDisabled:
            .orange
        case .unknown:
            .secondary
        }
    }
}

private struct RemoteWorkspaceSummaryRow: View {
    let overview: WorkspaceOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(overview.workspace.name)
                    .font(.headline)
                Spacer()
                Text("\(overview.providerCards.count) provider\(overview.providerCards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(remoteWorkspaceTargetSummary(for: overview))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability {
                Text(workspaceAvailability.summary)
                    .font(.caption)
                    .foregroundStyle(remoteWorkspaceAvailabilityColor(for: workspaceAvailability.state))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RemoteWorkspaceDetailView: View {
    @Bindable var model: RemoteClientPairingModel
    let overview: WorkspaceOverview

    var body: some View {
        List {
            Section("Workspace") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(overview.workspace.name)
                        .font(.headline)
                    Text(remoteWorkspaceTargetSummary(for: overview))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability {
                Section("Workspace Availability") {
                    Text(workspaceAvailability.summary)
                    if workspaceAvailability.diagnostics.isEmpty == false {
                        ForEach(Array(workspaceAvailability.diagnostics.enumerated()), id: \.offset) { entry in
                            Text(entry.element.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Providers") {
                if overview.providerCards.isEmpty {
                    Text("No Providers available yet.")
                        .foregroundStyle(.secondary)
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
                    }
                }
            }
        }
        .navigationTitle(overview.workspace.name)
    }
}

private struct RemoteWorkspaceDestinationView: View {
    @Bindable var model: RemoteClientPairingModel
    let workspaceID: UUID

    var body: some View {
        if let overview = model.workspaceOverview(id: workspaceID) {
            RemoteWorkspaceDetailView(model: model, overview: overview)
        } else {
            ContentUnavailableView("Workspace Unavailable", systemImage: "exclamationmark.triangle")
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
            ContentUnavailableView("Provider Unavailable", systemImage: "exclamationmark.triangle")
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
                Text(errorMessage)
                    .foregroundStyle(.orange)
            } else {
                Text("Loading Session…")
                    .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(providerCard.provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if providerCard.alternateSessionCount > 0 {
                    Text("\(providerCard.alternateSessionCount) named")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(providerCard.health.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(providerCard.defaultSession.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private func remoteWorkspaceTargetSummary(for overview: WorkspaceOverview) -> String {
    overview.remoteTarget.map { "\($0.host.name) • \(overview.workspace.folderPath)" } ?? overview.workspace.folderPath
}

private func remoteWorkspaceAvailabilityColor(for state: WorkspaceAvailabilitySnapshot.State) -> Color {
    switch state {
    case .available:
        .green
    case .unavailable, .broken, .blocked:
        .orange
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

    private var isDeletingSessionRecord: Bool {
        if case .deleteSessionRecord = activeAction {
            return true
        }
        return false
    }

    private var defaultSessionActionTitle: String {
        if let session = detail?.defaultSession {
            return session.state == .ready ? "Resume Default Session" : "Relaunch Default Session"
        }

        return "\(providerCard.defaultSession.actionTitle) Default Session"
    }

    private var providerHealth: ProviderHealthSummary {
        detail?.health ?? providerCard.health
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

    var body: some View {
        List {
            Section("Provider") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(providerCard.provider.displayName)
                        .font(.headline)
                    Text(overview.workspace.name)
                        .font(.subheadline)
                    Text(overview.remoteTarget.map { "\($0.host.name) • \(overview.workspace.folderPath)" } ?? overview.workspace.folderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let workspaceAvailability = overview.remoteTarget?.workspaceAvailability {
                Section("Workspace Availability") {
                    Text(workspaceAvailability.summary)
                    if workspaceAvailability.diagnostics.isEmpty == false {
                        ForEach(Array(workspaceAvailability.diagnostics.enumerated()), id: \.offset) { entry in
                            Text(entry.element.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Health") {
                Text(detail?.health.summary ?? providerCard.health.summary)
                if let detail, detail.health.diagnostics.isEmpty == false {
                    ForEach(Array(detail.health.diagnostics.enumerated()), id: \.offset) { entry in
                        Text(entry.element.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Default Session") {
                if let session = defaultSessionSection.session {
                    NavigationLink {
                        RemoteSessionScreenView(model: model, session: session)
                    } label: {
                        RemoteProviderSessionSummaryRow(session: session)
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        if defaultSessionSection.canDeleteSessionRecord {
                            Button("Delete", role: .destructive) {
                                pendingDeleteSessionRecord = session
                            }
                            .disabled(isDeletingSessionRecord)
                        }
                    }
                } else {
                    Text(detail == nil && errorMessage == nil ? "Loading Session details…" : providerCard.defaultSession.summary)
                        .foregroundStyle(.secondary)
                }

                Button(isLaunchingDefaultSession ? "Working…" : defaultSessionActionTitle) {
                    launchDefaultSession()
                }
                .disabled(isLaunchingDefaultSession || defaultSessionActionState.isEnabled == false)

                if let disabledReason = defaultSessionActionState.disabledReason,
                   defaultSessionActionState.isEnabled == false {
                    Text(disabledReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Named Sessions") {
                switch namedSessionsSection.content {
                case .empty:
                    Text("No Named Sessions yet.")
                        .foregroundStyle(.secondary)
                case .sessions(let sessions):
                    ForEach(sessions) { session in
                        NavigationLink {
                            RemoteSessionScreenView(model: model, session: session)
                        } label: {
                            RemoteProviderSessionSummaryRow(session: session)
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            if namedSessionsSection.deletableSessionIDs.contains(session.id) {
                                Button("Delete", role: .destructive) {
                                    pendingDeleteSessionRecord = session
                                }
                                .disabled(isDeletingSessionRecord)
                            }
                        }
                    }
                case .loading:
                    Text("Loading Named Sessions…")
                        .foregroundStyle(.secondary)
                case .none:
                    EmptyView()
                }

                Button(isCreatingNamedSession ? "Creating…" : "Create Session") {
                    createNamedSession()
                }
                .disabled(isCreatingNamedSession || createNamedSessionActionState.isEnabled == false)

                if let disabledReason = createNamedSessionActionState.disabledReason,
                   createNamedSessionActionState.isEnabled == false {
                    Text(disabledReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let detail, detail.failedSessions.isEmpty == false {
                Section("Failed Session Records") {
                    ForEach(detail.failedSessions) { session in
                        NavigationLink {
                            RemoteSessionScreenView(model: model, session: session)
                        } label: {
                            RemoteProviderSessionSummaryRow(session: session)
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                pendingDeleteSessionRecord = session
                            }
                            .disabled(isDeletingSessionRecord)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(providerCard.provider.displayName)
        .task(id: providerCard.id) {
            await model.loadProviderDetail(workspaceID: overview.workspace.id, providerID: providerCard.provider.id)
        }
        .refreshable {
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
    @State private var terminalDraft = ""
    @State private var terminalViewportSize: CGSize = .zero
    @State private var isShowingStopConfirmation = false
    @State private var activeAction: RemoteSessionAction?
    @State private var presentedError: RemoteClientHomePresentedError?
    @FocusState private var isTerminalInputFocused: Bool

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
            isReady: isReady,
            workspaceKind: model.workspaceKind(
                for: currentSession.workspaceID,
                providerID: currentSession.providerID
            )
        )
    }

    private var supportsFocusedSessionSurface: Bool {
        surfacePresentation?.surfaceSupport == .supported
    }

    private var isPerformingAction: Bool {
        activeAction != nil
    }

    private var controllerActionTitle: String {
        switch activeAction {
        case .takeController:
            "Taking Controller…"
        case .returnToViewer:
            "Returning to Viewer…"
        default:
            model.focusedSessionIsController ? "Return to Viewer" : "Take Controller"
        }
    }

    private var controllerDescription: String {
        guard screen?.primarySurface == .structuredActivityFeed else {
            return model.focusedSessionIsController
                ? "This iPhone is the Controller for terminal input and terminal size."
                : "Take Controller to send terminal input from this iPhone."
        }

        return model.focusedSessionIsController
            ? "This iPhone is the Controller for Session-writing actions."
            : "Viewer mode keeps this iPhone attached without Session-writing authority."
    }

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("State", value: currentSession.state.rawValue.capitalized)
                if let failureMessage = currentSession.failureMessage {
                    Text(failureMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                if isReady {
                    Button(isPerformingAction ? "Stopping…" : "Stop Session", role: .destructive) {
                        isShowingStopConfirmation = true
                    }
                    .disabled(isPerformingAction)
                } else {
                    Button(isPerformingAction ? "Relaunching…" : "Relaunch Session") {
                        relaunchSession()
                    }
                    .disabled(isPerformingAction || surfacePresentation?.relaunchIsEnabled == false)

                    if let disabledReason = surfacePresentation?.relaunchDisabledReason,
                       surfacePresentation?.relaunchIsEnabled == false {
                        Text(disabledReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if surfacePresentation?.showsAttachment == true {
                Section("Attachment") {
                    LabeledContent("Mode", value: model.focusedSessionIsController ? "Controller" : "Viewer")
                    Text(controllerDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(controllerActionTitle) {
                        toggleControllerState()
                    }
                    .disabled(isPerformingAction)
                }
            }

            if model.focusedSessionIsStale, screen != nil {
                Section {
                    Text(model.focusedSessionErrorMessage ?? "Reconnecting… showing the last known Session screen.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if let unsupportedCopy = surfacePresentation?.unsupportedCopy {
                Section(unsupportedCopy.title) {
                    Text(unsupportedCopy.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(unsupportedCopy.recovery)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if surfacePresentation?.showsStructuredActivity == true {
                Section("Shared Activity") {
                    if let screen {
                        structuredSessionContent(screen)
                    } else if let errorMessage = model.focusedSessionErrorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Loading Session screen…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Terminal") {
                    if let screen {
                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(screen.styledVisibleLines.enumerated()), id: \.offset) { row, line in
                                    terminalLineView(line, row: row, screen: screen)
                                }
                            }
                            .padding(12)
                        }
                        .listRowInsets(EdgeInsets())
                        .frame(minHeight: 260)
                        .background(Color.black.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        Text(errorMessage)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Loading Session screen…")
                            .foregroundStyle(.secondary)
                    }
                }

                if surfacePresentation?.showsInput == true {
                    Section("Input") {
                        TextField("Type into the terminal", text: $terminalDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .focused($isTerminalInputFocused)
                            .onSubmit {
                                prepareAndSendDraftText()
                            }

                        Button("Send Text") {
                            prepareAndSendDraftText()
                        }
                        .disabled(model.focusedSessionIsController == false || terminalDraft.isEmpty || isPerformingAction)

                        HStack {
                            quickKeyButton("Return", key: .enter)
                            quickKeyButton("Backspace", key: .backspace)
                            quickKeyButton("Ctrl-C", key: .interrupt)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.isDefault ? "Default Session" : (session.name ?? "Session"))
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

    @ViewBuilder
    private func quickKeyButton(_ title: String, key: SessionInputKey) -> some View {
        Button(title) {
            Task {
                do {
                    try await model.sendInputKeyToFocusedRemoteSession(key)
                } catch {
                    presentedError = RemoteClientHomePresentedError(message: error.localizedDescription)
                }
            }
        }
        .disabled(model.focusedSessionIsController == false || isPerformingAction)
    }

    @ViewBuilder
    private func structuredSessionContent(_ screen: SessionScreen) -> some View {
        let copy = structuredSessionPresentationCopy(for: screen)
        let rows = structuredSessionActivityRows(for: screen)
        let pendingApprovalRequests = screen.approvalRequests.filter { $0.state == .pending }

        VStack(alignment: .leading, spacing: 12) {
            if pendingApprovalRequests.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pendingApprovalRequests) { request in
                        structuredSessionApprovalRequestView(request)
                    }
                }
            }

            if rows.isEmpty {
                ContentUnavailableView(
                    copy.emptyStateTitle,
                    systemImage: "sparkles.rectangle.stack",
                    description: Text(copy.emptyStateDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        structuredSessionActivityRowView(row)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func structuredSessionActivityRowView(_ row: StructuredSessionActivityRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.systemImage)
                .foregroundStyle(structuredSessionActivityColor(for: row.emphasis))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(row.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(structuredSessionActivityColor(for: row.emphasis).opacity(0.15))
        }
    }

    private func structuredSessionApprovalRequestView(_ request: SessionApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Approval Request", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(.accent)

            Text(request.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(request.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.2))
        }
    }

    private func structuredSessionActivityColor(for emphasis: StructuredSessionActivityEmphasis) -> Color {
        switch emphasis {
        case .neutral:
            .secondary
        case .accent:
            .accentColor
        case .critical:
            .red
        case .success:
            .green
        }
    }

    private var terminalCellWidth: CGFloat { 8.5 }

    private var terminalCellHeight: CGFloat { 20 }

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

private struct RemoteProviderSessionSummaryRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.isDefault ? "Default Session" : (session.name ?? "Session"))
                .fontWeight(.medium)
            Text(session.failureMessage ?? session.state.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
