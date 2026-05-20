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

        return VStack(alignment: .leading, spacing: 16) {
            Text(workspace?.name ?? "Workspace")
                .font(.title2)
                .fontWeight(.semibold)

            if let workspace {
                LabeledContent("Kind", value: workspace.kind.rawValue)
                LabeledContent("Folder", value: workspace.folderPath)
                LabeledContent("Primary Group", value: appModel.workspaceGroupName(for: workspace.primaryGroupID) ?? workspace.primaryGroupID.uuidString)
            } else {
                Text("Workspace not found.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}

private enum SidebarSelection: Hashable {
    case workspaceGroup(UUID)
    case workspace(UUID)
}

private struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    ContentView(appModel: try! .live())
}
