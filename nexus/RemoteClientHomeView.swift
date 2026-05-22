#if os(iOS)
import NexusDomain
import SwiftUI

struct RemoteClientHomeView: View {
    @Bindable var model: RemoteClientPairingModel

    @State private var isShowingPairingForm = false
    @State private var isPairing = false
    @State private var isRefreshingAvailability = false
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .fontWeight(.medium)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    ForEach(catalog.workspaceGroups) { group in
                        let overviews = workspaceOverviews(in: group, catalog: catalog)
                        if overviews.isEmpty == false {
                            Section(group.name) {
                                ForEach(overviews, id: \.workspace.id) { overview in
                                    workspaceOverviewRow(overview)
                                }
                            }
                        }
                    }
                } else if let activePairedMac = model.activePairedMac,
                          model.availability(for: activePairedMac) == .available {
                    Section("Workspace Catalog") {
                        Text(model.catalogErrorMessage ?? "Loading Workspaces…")
                            .font(.footnote)
                            .foregroundStyle(model.catalogErrorMessage == nil ? .secondary : .orange)
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

    @ViewBuilder
    private func workspaceOverviewRow(_ overview: WorkspaceOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(overview.workspace.name)
                .font(.headline)
            Text(workspaceTargetSummary(for: overview))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(overview.providerCards) { providerCard in
                NavigationLink {
                    RemoteProviderDetailView(
                        model: model,
                        overview: overview,
                        providerCard: providerCard
                    )
                } label: {
                    providerCardRow(providerCard)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func providerCardRow(_ providerCard: WorkspaceProviderCard) -> some View {
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

    private func workspaceOverviews(in group: WorkspaceGroup, catalog: RemoteWorkspaceCatalog) -> [WorkspaceOverview] {
        catalog.workspaceOverviews.filter { $0.workspace.primaryGroupID == group.id }
    }

    private func workspaceTargetSummary(for overview: WorkspaceOverview) -> String {
        overview.remoteTarget.map { "\($0.host.name) • \(overview.workspace.folderPath)" } ?? overview.workspace.folderPath
    }

    private func availabilityColor(for pairedMac: PairedMac) -> Color {
        switch model.availability(for: pairedMac) {
        case .available:
            .green
        case .unavailable:
            .orange
        case .unknown:
            .secondary
        }
    }
}

private struct RemoteProviderDetailView: View {
    @Bindable var model: RemoteClientPairingModel
    let overview: WorkspaceOverview
    let providerCard: WorkspaceProviderCard

    private var detail: ProviderDetail? {
        model.providerDetail(for: overview.workspace.id, providerID: providerCard.provider.id)
    }

    private var errorMessage: String? {
        model.providerDetailErrorMessage(for: overview.workspace.id, providerID: providerCard.provider.id)
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
                if let session = detail?.defaultSession {
                    NavigationLink {
                        RemoteSessionScreenView(model: model, session: session)
                    } label: {
                        RemoteProviderSessionSummaryRow(session: session)
                    }
                } else {
                    Text(detail == nil && errorMessage == nil ? "Loading Session details…" : providerCard.defaultSession.summary)
                        .foregroundStyle(.secondary)
                }
            }

            if let detail {
                if detail.alternateSessions.isEmpty == false {
                    Section("Named Sessions") {
                        ForEach(detail.alternateSessions) { session in
                            NavigationLink {
                                RemoteSessionScreenView(model: model, session: session)
                            } label: {
                                RemoteProviderSessionSummaryRow(session: session)
                            }
                        }
                    }
                }

                if detail.failedSessions.isEmpty == false {
                    Section("Failed Sessions") {
                        ForEach(detail.failedSessions) { session in
                            NavigationLink {
                                RemoteSessionScreenView(model: model, session: session)
                            } label: {
                                RemoteProviderSessionSummaryRow(session: session)
                            }
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
    }
}

private struct RemoteSessionScreenView: View {
    @Bindable var model: RemoteClientPairingModel
    let session: Session

    @Environment(\.scenePhase) private var scenePhase
    @State private var terminalDraft = ""
    @State private var terminalViewportSize: CGSize = .zero

    private var screen: SessionScreen? {
        guard model.focusedSessionID == session.id else {
            return nil
        }
        return model.focusedSessionScreen
    }

    var body: some View {
        List {
            Section("Attachment") {
                LabeledContent("Mode", value: model.focusedSessionIsController ? "Controller" : "Viewer")
                Text(model.focusedSessionIsController
                     ? "This iPhone is the Controller for terminal input and terminal size."
                     : "Take Controller to send terminal input from this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(model.focusedSessionIsController ? "Return to Viewer" : "Take Controller") {
                    toggleControllerState()
                }
            }

            if model.focusedSessionIsStale, screen != nil {
                Section {
                    Text(model.focusedSessionErrorMessage ?? "Reconnecting… showing the last known Session screen.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

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

            Section("Input") {
                TextField("Type into the terminal", text: $terminalDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Send Text") {
                    sendDraftText()
                }
                .disabled(model.focusedSessionIsController == false || terminalDraft.isEmpty)

                HStack {
                    quickKeyButton("Return", key: .enter)
                    quickKeyButton("Backspace", key: .backspace)
                    quickKeyButton("Ctrl-C", key: .interrupt)
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
        .onChange(of: terminalViewportSize) { _, _ in
            guard model.focusedSessionIsController else {
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
                    await model.releaseFocusedRemoteSessionControl()
                    model.stopFocusingRemoteSession()
                }
            }
        }
    }

    private func toggleControllerState() {
        Task {
            if model.focusedSessionIsController {
                await model.releaseFocusedRemoteSessionControl()
            } else {
                let viewport = terminalViewport()
                try? await model.takeFocusedRemoteSessionControl(columns: viewport.columns, rows: viewport.rows)
            }
        }
    }

    private func sendDraftText() {
        let text = terminalDraft
        guard text.isEmpty == false else {
            return
        }

        terminalDraft = ""
        Task {
            try? await model.sendTextToFocusedRemoteSession(text)
        }
    }

    @ViewBuilder
    private func quickKeyButton(_ title: String, key: SessionInputKey) -> some View {
        Button(title) {
            Task {
                try? await model.sendInputKeyToFocusedRemoteSession(key)
            }
        }
        .disabled(model.focusedSessionIsController == false)
    }

    private func terminalViewport() -> (columns: Int, rows: Int) {
        if terminalViewportSize != .zero {
            let columns = max(20, Int((terminalViewportSize.width - 24) / 8.5))
            let rows = max(8, Int((terminalViewportSize.height - 24) / 20))
            return (columns, rows)
        }

        return (screen?.terminalColumns ?? 80, screen?.terminalRows ?? 24)
    }

    @ViewBuilder
    private func terminalLineView(_ line: TerminalLine, row: Int, screen: SessionScreen) -> some View {
        let segments = renderedTerminalSegments(for: line, row: row, screen: screen)

        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                terminalSegmentView(segment)
            }
        }
        .font(.system(.body, design: .monospaced))
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func terminalSegmentView(_ segment: RemoteTerminalLineSegment) -> some View {
        let colors = resolvedTerminalColors(for: segment.style)
        let text = Text(segment.text)
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

    private func renderedTerminalSegments(for line: TerminalLine, row: Int, screen: SessionScreen) -> [RemoteTerminalLineSegment] {
        var cells = line.cells

        if screen.cursorVisible, row == screen.cursorRow {
            let cursorIndex = max(0, min(screen.cursorColumn, cells.count))
            cells.insert(TerminalCell(text: "█"), at: cursorIndex)
        }

        if cells.isEmpty {
            cells = [TerminalCell(text: " ")]
        }

        var segments: [RemoteTerminalLineSegment] = []
        for cell in cells {
            if let lastIndex = segments.indices.last, segments[lastIndex].style == cell.style {
                segments[lastIndex].text.append(cell.text)
            } else {
                segments.append(RemoteTerminalLineSegment(text: cell.text, style: cell.style))
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

private struct RemoteTerminalLineSegment {
    var text: String
    let style: TerminalStyle
}

private struct RemoteClientHomePresentedError: Identifiable {
    let id = UUID()
    let message: String
}
#endif
