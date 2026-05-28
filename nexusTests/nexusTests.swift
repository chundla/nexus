import AppKit
import Foundation
import NexusDomain
import SwiftUI
import NexusIPC
@testable import NexusService
import Testing
@testable import nexus

struct nexusTests {

    @Test func terminalKeyMappingConvertsControlTIntoTerminalControlText() {
        let input = mapSessionTerminalInput(
            modifierFlags: [.control],
            keyCode: 17,
            characters: "t",
            charactersIgnoringModifiers: "t"
        )

        #expect(input == .text("\u{0014}"))
    }

    @Test func terminalKeyMappingMapsForwardDeleteToDeleteKey() {
        let input = mapSessionTerminalInput(
            modifierFlags: [],
            keyCode: 117,
            characters: nil,
            charactersIgnoringModifiers: nil
        )

        #expect(input == .key(.deleteForward))
    }

    @Test func terminalKeyMappingMapsHomeAndEndKeys() {
        let homeInput = mapSessionTerminalInput(
            modifierFlags: [],
            keyCode: 115,
            characters: nil,
            charactersIgnoringModifiers: nil
        )
        let endInput = mapSessionTerminalInput(
            modifierFlags: [],
            keyCode: 119,
            characters: nil,
            charactersIgnoringModifiers: nil
        )

        #expect(homeInput == .key(.home))
        #expect(endInput == .key(.end))
    }

    @Test func utf8StreamDecoderBuffersSplitMultibyteTerminalGlyphs() {
        var decoder = UTF8StreamDecoder()

        let firstChunk = decoder.decode(Data([0xE2, 0x95]))
        let secondChunk = decoder.decode(Data([0xAD, 0xE2, 0x94]))
        let thirdChunk = decoder.decode(Data([0x80, 0xE2, 0x9D]))
        let fourthChunk = decoder.decode(Data([0xAF]))

        #expect(firstChunk.isEmpty)
        #expect(secondChunk == "╭")
        #expect(thirdChunk == "─")
        #expect(fourthChunk == "❯")
    }

    @Test func terminalRendererPreservesClaudeAnsiColorsAndInverseVideo() {
        let renderState = TerminalRenderer.renderState(
            from: "\u{001B}[38;5;153m/add-dir\u{001B}[39m\n/\u{001B}[7m \u{001B}[27m",
            terminalColumns: 40,
            terminalRows: 4
        )

        #expect(renderState.visibleLines == ["/add-dir", "/ "])
        #expect(renderState.styledVisibleLines[0].cells.allSatisfy { $0.style.foregroundColor == .ansi256(153) })
        #expect(renderState.styledVisibleLines[1].cells[0].style.isInverse == false)
        #expect(renderState.styledVisibleLines[1].cells[1].style.isInverse == true)
    }

    @Test func terminalRendererWrapsSequentialTextAtTerminalWidth() {
        let renderState = TerminalRenderer.renderState(
            from: "123456789",
            terminalColumns: 5,
            terminalRows: 3
        )

        #expect(renderState.visibleLines == ["12345", "6789"])
        #expect(renderState.cursorRow == 1)
        #expect(renderState.cursorColumn == 4)
    }

    @Test func terminalRendererDoesNotSoftWrapAbsolutePositionedOffscreenCells() {
        let renderState = TerminalRenderer.renderState(
            from: "a\u{001B}[143G|",
            terminalColumns: 139,
            terminalRows: 10
        )

        #expect(renderState.styledVisibleLines.count == 1)
        #expect(renderState.visibleLines[0].hasPrefix("a"))
    }

    @Test func terminalViewportLayoutUsesContentAreaInsteadOfOuterFrame() {
        let layout = TerminalViewportLayout(
            font: .system(size: 13, design: .monospaced),
            cellWidth: 8,
            cellHeight: 16,
            contentPadding: CGSize(width: 12, height: 12),
            minimumColumns: 40,
            minimumRows: 12
        )

        let gridSize = layout.gridSize(fitting: CGSize(width: 1_148, height: 344))

        #expect(gridSize.columns == 140)
        #expect(gridSize.rows == 20)
    }

    @MainActor
    @Test func focusedSessionSurfaceUsesExplicitPrimarySurfaceInsteadOfProviderIdentity() {
        let piScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .terminal,
            transcript: "Pi can still expose a terminal surface"
        )
        let claudeScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .claude,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Structured Claude session")
            ]
        )

        #expect(focusedSessionSurface(for: piScreen) == .terminal)
        #expect(focusedSessionSurface(for: claudeScreen) == .structuredActivityFeed)
    }

    @MainActor
    @Test func structuredSessionActivityRowsDescribeSharedSessionActivityKinds() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Connected"),
                SessionActivityItem(kind: .message, text: "Pi: hello"),
                SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy to production?"),
                SessionActivityItem(kind: .approvalDecision, text: "Approved: Deploy to production?"),
                SessionActivityItem(kind: .progress, text: "Gathering context"),
                SessionActivityItem(kind: .command, text: "git status"),
                SessionActivityItem(kind: .diff, text: "Edited ContentView.swift"),
                SessionActivityItem(kind: .error, text: "Provider request failed"),
                SessionActivityItem(kind: .completion, text: "Turn complete")
            ]
        )

        #expect(structuredSessionActivityRows(for: screen) == [
            StructuredSessionActivityRow(id: screen.activityItems[0].id, title: "Status", systemImage: "dot.radiowaves.left.and.right", text: "Connected", emphasis: .neutral),
            StructuredSessionActivityRow(id: screen.activityItems[1].id, title: "Message", systemImage: "message", text: "Pi: hello", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[2].id, title: "Approval Request", systemImage: "hand.raised", text: "Approval Request: Deploy to production?", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[3].id, title: "Approval Decision", systemImage: "checkmark.shield", text: "Approved: Deploy to production?", emphasis: .success),
            StructuredSessionActivityRow(id: screen.activityItems[4].id, title: "Progress", systemImage: "hourglass", text: "Gathering context", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[5].id, title: "Command", systemImage: "terminal", text: "git status", emphasis: .neutral),
            StructuredSessionActivityRow(id: screen.activityItems[6].id, title: "Diff", systemImage: "square.and.pencil", text: "Edited ContentView.swift", emphasis: .accent),
            StructuredSessionActivityRow(id: screen.activityItems[7].id, title: "Error", systemImage: "exclamationmark.triangle", text: "Provider request failed", emphasis: .critical),
            StructuredSessionActivityRow(id: screen.activityItems[8].id, title: "Completion", systemImage: "checkmark.circle", text: "Turn complete", emphasis: .success)
        ])
    }

    @MainActor
    @Test func structuredSessionPresentationCopyUsesProviderDisplayName() {
        let codexScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(structuredSessionPresentationCopy(for: codexScreen) == StructuredSessionPresentationCopy(
            emptyStateTitle: "No Session activity yet",
            emptyStateDescription: "Send a prompt to start the Codex Session.",
            composerPlaceholder: "Send a prompt to Codex"
        ))
    }

    @MainActor
    @Test func structuredSessionFeedPresentationKeepsSharedRowsCopyAndPendingApprovalRequestsAligned() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let pendingRequest = SessionApprovalRequest(title: "Deploy", text: "Deploy to production?", state: .pending)
        let approvedRequest = SessionApprovalRequest(title: "Cleanup", text: "Delete temp files?", state: .approved)
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .progress, text: "Gathering context")],
            approvalRequests: [pendingRequest, approvedRequest]
        )

        #expect(structuredSessionFeedPresentation(for: screen) == StructuredSessionFeedPresentation(
            copy: StructuredSessionPresentationCopy(
                emptyStateTitle: "No Session activity yet",
                emptyStateDescription: "Send a prompt to start the Codex Session.",
                composerPlaceholder: "Send a prompt to Codex"
            ),
            activityRows: [
                StructuredSessionActivityRow(
                    id: screen.activityItems[0].id,
                    title: "Progress",
                    systemImage: "hourglass",
                    text: "Gathering context",
                    emphasis: .accent
                )
            ],
            pendingApprovalRequests: [pendingRequest]
        ))
    }

    @MainActor
    @Test func structuredSessionComposerPresentationKeepsViewerPromptVisibleButDisabledUntilControllerTaken() {
        let codexScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(structuredSessionComposerPresentation(for: codexScreen, isController: false) == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
    }

    @MainActor
    @Test func structuredSessionApprovalRequestPresentationKeepsViewerActionsVisibleButDisabledUntilControllerTaken() {
        #expect(structuredSessionApprovalRequestPresentation(isController: false) == StructuredSessionApprovalRequestPresentation(
            actionsAreEnabled: false,
            disabledReason: "Take Controller to respond to Approval Requests from this iPhone."
        ))
    }

    @MainActor
    @Test func remoteSessionSurfacePresentationSupportsExistingStructuredCodexSessionsOnIPhone() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Codex shared Session stream connected")]
        )

        #expect(remoteSessionSurfacePresentation(for: screen, isReady: true, workspaceKind: .remote) == RemoteSessionSurfacePresentation(
            surfaceSupport: .supported,
            showsTerminal: false,
            showsStructuredActivity: true,
            showsAttachment: true,
            showsInput: false,
            relaunchIsEnabled: true,
            relaunchDisabledReason: nil,
            unsupportedCopy: nil
        ))
    }

    @MainActor
    @Test func remoteSessionSurfacePresentationSupportsExistingStructuredLocalPiSessionsOnIPhone() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
        )

        #expect(remoteSessionSurfacePresentation(for: screen, isReady: true, workspaceKind: .local) == RemoteSessionSurfacePresentation(
            surfaceSupport: .supported,
            showsTerminal: false,
            showsStructuredActivity: true,
            showsAttachment: true,
            showsInput: false,
            relaunchIsEnabled: true,
            relaunchDisabledReason: nil,
            unsupportedCopy: nil
        ))
    }

    @MainActor
    @Test func remoteSessionSurfacePresentationKeepsTerminalAffordancesForTerminalBackedCodexOnIPhone() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .terminal,
            transcript: "Codex remote ready"
        )

        #expect(remoteSessionSurfacePresentation(for: screen, isReady: true, workspaceKind: .remote) == RemoteSessionSurfacePresentation(
            surfaceSupport: .supported,
            showsTerminal: true,
            showsStructuredActivity: false,
            showsAttachment: true,
            showsInput: true,
            relaunchIsEnabled: true,
            relaunchDisabledReason: nil,
            unsupportedCopy: nil
        ))
    }

    @MainActor
    @Test func remoteProviderActionStateEnablesSupportedStructuredDefaultLaunchOnIPhone() {
        let launchState = RemoteProviderActionState(
            capability: ProviderCapability(
                action: .launchDefaultSession,
                isSupported: true,
                isEnabled: true
            ),
            provider: Provider(id: .pi),
            prelaunchPrimarySurface: .structuredActivityFeed,
            workspaceKind: .local
        )

        #expect(launchState == RemoteProviderActionState(
            isEnabled: true,
            disabledReason: nil
        ))
    }

    @MainActor
    @Test func remoteProviderActionStateEnablesSupportedStructuredNamedSessionCreationOnIPhone() {
        let createState = RemoteProviderActionState(
            capability: ProviderCapability(
                action: .createNamedSession,
                isSupported: true,
                isEnabled: true
            ),
            provider: Provider(id: .codex),
            prelaunchPrimarySurface: .structuredActivityFeed,
            workspaceKind: .remote
        )

        #expect(createState == RemoteProviderActionState(
            isEnabled: true,
            disabledReason: nil
        ))
    }

    @MainActor
    @Test func remoteProviderActionStateKeepsUnsupportedStructuredDefaultLaunchBlockedOnIPhone() {
        let launchState = RemoteProviderActionState(
            capability: ProviderCapability(
                action: .launchDefaultSession,
                isSupported: true,
                isEnabled: true
            ),
            provider: Provider(id: .pi),
            prelaunchPrimarySurface: .structuredActivityFeed,
            workspaceKind: .remote
        )

        #expect(launchState == RemoteProviderActionState(
            isEnabled: false,
            disabledReason: "Open this Workspace on the paired Mac to launch Pi because this iPhone cannot operate its primary Session surface yet."
        ))
    }

    @MainActor
    @Test func remoteProviderActionStateUsesProviderHealthGuidanceWhenStructuredLaunchIsNotLaunchable() {
        let launchState = RemoteProviderActionState(
            capability: ProviderCapability(
                action: .launchDefaultSession,
                isSupported: true,
                isEnabled: false,
                disabledReason: "Codex requires signing in on the paired Mac before launch."
            ),
            provider: Provider(id: .codex),
            prelaunchPrimarySurface: .structuredActivityFeed,
            workspaceKind: .remote
        )

        #expect(launchState == RemoteProviderActionState(
            isEnabled: false,
            disabledReason: "Codex requires signing in on the paired Mac before launch."
        ))
    }

    @MainActor
    @Test func remoteSessionSurfacePresentationKeepsRemotePiStructuredSessionsUnsupportedOnIPhone() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .interrupted,
                failureMessage: "Remote Pi remains unsupported"
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(remoteSessionSurfacePresentation(for: screen, isReady: false, workspaceKind: .remote) == RemoteSessionSurfacePresentation(
            surfaceSupport: .unsupported,
            showsTerminal: false,
            showsStructuredActivity: false,
            showsAttachment: false,
            showsInput: false,
            relaunchIsEnabled: false,
            relaunchDisabledReason: "Open this Session on the paired Mac to relaunch it because this iPhone cannot operate its primary Session surface yet.",
            unsupportedCopy: UnsupportedRemoteSessionSurfaceCopy(
                title: "Unsupported Session Surface",
                summary: "This iPhone can inspect this Pi Session, but it cannot present or operate its primary Session surface yet.",
                recovery: "Open this Session on the paired Mac to use its primary Session surface."
            )
        ))
    }

    @Test func workspaceProviderCardNamedSessionSummaryUsesNamedSessionCopy() {
        let zero = WorkspaceProviderCard(
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Ready"),
            defaultSession: ProviderDefaultSessionSummary(state: .ready, summary: "Running", actionTitle: "Open")
        )
        let singular = WorkspaceProviderCard(
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Ready"),
            defaultSession: ProviderDefaultSessionSummary(state: .ready, summary: "Running", actionTitle: "Open"),
            alternateSessionCount: 1
        )
        let plural = WorkspaceProviderCard(
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Ready"),
            defaultSession: ProviderDefaultSessionSummary(state: .ready, summary: "Running", actionTitle: "Open"),
            alternateSessionCount: 2
        )

        #expect(zero.namedSessionSummary == nil)
        #expect(singular.namedSessionSummary == "1 named session")
        #expect(plural.namedSessionSummary == "2 named sessions")
    }

    @Test func embeddedServiceBootstrapStartsBackgroundServiceReachableOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let status = try await client.getServiceStatus()

        #expect(status.state == .running)
        #expect(status.store.kind == .sqlite)
        #expect(status.store.owner == .backgroundService)
        #expect(status.store.location.path(percentEncoded: false).hasSuffix("Nexus.sqlite"))
    }

    @Test func backgroundServiceCreatesAndListsWorkspaceGroupsOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let createdGroup = try await client.createWorkspaceGroup(name: "Client Work")
        let groups = try await client.listWorkspaceGroups()

        #expect(createdGroup.name == "Client Work")
        #expect(groups == [createdGroup])
    }

    @Test func remoteAccessStartsDisabledAndCanBeEnabledOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let initialState = try await client.getRemoteAccessState()

        #expect(initialState.isEnabled == false)
        #expect(initialState.activePairing == nil)

        await #expect(throws: (any Error).self) {
            _ = try await client.startPairing()
        }

        let enabledState = try await client.setRemoteAccessEnabled(true)
        let pairing = try await client.startPairing()

        #expect(enabledState.isEnabled)
        #expect(enabledState.activePairing == nil)
        #expect(pairing.code.isEmpty == false)
        #expect(pairing.qrPayload.contains(pairing.code))
    }

    @Test func remoteAccessPairingPersistsPairedDevicesAndAllowsRevokeOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let firstService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        _ = try await firstClient.setRemoteAccessEnabled(true)
        let pairing = try await firstClient.startPairing()
        let pairedDevice = try await firstClient.completePairing(pairingCode: pairing.code, deviceName: "Chris’s iPhone")
        let firstDevices = try await firstClient.listPairedDevices()

        #expect(firstDevices == [pairedDevice])

        let secondService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let secondState = try await secondClient.getRemoteAccessState()
        let persistedDevices = try await secondClient.listPairedDevices()

        #expect(secondState.isEnabled)
        #expect(persistedDevices == [pairedDevice])

        _ = try await secondClient.revokePairedDevice(deviceID: pairedDevice.id)
        let remainingDevices = try await secondClient.listPairedDevices()

        #expect(remainingDevices.isEmpty)
    }

    @Test func localWorkspaceInheritsOnlyWorkspaceGroupAndPersistsAcrossServiceBootstrap() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let firstService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: "/tmp/example-workspace",
            primaryGroupID: nil
        )

        let secondService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedGroups = try await secondClient.listWorkspaceGroups()
        let persistedWorkspaces = try await secondClient.listWorkspaces()

        #expect(workspace.name == "example-workspace")
        #expect(workspace.primaryGroupID == group.id)
        #expect(persistedGroups == [group])
        #expect(persistedWorkspaces == [workspace])
    }

    @Test func localWorkspaceRequiresExplicitPrimaryWorkspaceGroupWhenMultipleGroupsExist() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        _ = try await client.createWorkspaceGroup(name: "Alpha")
        _ = try await client.createWorkspaceGroup(name: "Beta")

        await #expect(throws: (any Error).self) {
            _ = try await client.createLocalWorkspace(
                name: nil,
                folderPath: "/tmp/multi-group-workspace",
                primaryGroupID: nil
            )
        }
    }

    @Test func remoteWorkspaceCreatesAndPersistsHostTargetOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let firstService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let secondService = try NexusEmbeddedServiceBootstrap.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedWorkspaces = try await secondClient.listWorkspaces()

        #expect(workspace.name == "api")
        #expect(workspace.kind == .remote)
        #expect(workspace.folderPath == "/srv/api")
        #expect(workspace.remoteHostID == host.id)
        #expect(workspace.primaryGroupID == group.id)
        #expect(persistedWorkspaces == [workspace])
    }

    @Test func remoteWorkspaceTargetUniquenessIsGlobalAndDoesNotBlockFailingHostValidation() async throws {
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .unavailable,
                    summary: "SSH connection timed out",
                    diagnostics: [
                        HostValidationDiagnostic(
                            severity: .error,
                            code: "sshTimedOut",
                            message: "ssh build-box timed out while validating the Host."
                        )
                    ]
                )
            ])
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let primaryGroup = try await client.createWorkspaceGroup(name: "Primary")
        let secondaryGroup = try await client.createWorkspaceGroup(name: "Secondary")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        let validation = try await client.validateHost(hostID: host.id)

        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: primaryGroup.id
        )

        #expect(validation.state == .unavailable)
        #expect(workspace.remoteHostID == host.id)

        await #expect(throws: (any Error).self) {
            _ = try await client.createRemoteWorkspace(
                name: "Duplicate API",
                hostID: host.id,
                remotePath: "/srv/api",
                primaryGroupID: secondaryGroup.id
            )
        }
    }

    @Test func remoteWorkspaceOverviewSurfacesWorkspaceAwareClaudeAndCodexProviderHealth() async throws {
        let sshRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n"),
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteCodexProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/codex\n1.2.3\n")
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: [
                        HostValidationDiagnostic(severity: .info, code: "sshTarget", message: "Validated build-box")
                    ]
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: sshRunner)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let remoteTarget = try #require(overview.remoteTarget)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))

        #expect(remoteTarget.host == host)
        #expect(remoteTarget.hostValidation?.state == .available)
        #expect(remoteTarget.workspaceAvailability.state == .available)
        #expect(remoteTarget.workspaceAvailability.summary == "Workspace is available")
        let remotePathDiagnostic = remoteTarget.workspaceAvailability.diagnostics.first(where: { $0.code == "remotePath" })
        #expect(remotePathDiagnostic?.message == "Validated remote path /srv/api on Build Server.")
        #expect(claudeCard.health.state == .available)
        #expect(claudeCard.health.summary == "Claude 9.9.9 (Claude Code) is available")
        #expect(claudeCard.health.resolvedExecutable == "/usr/local/bin/claude")
        #expect(claudeCard.health.version == "9.9.9 (Claude Code)")
        #expect(claudeCard.health.launchability == .launchable)
        #expect(codexCard.health.state == .available)
        #expect(codexCard.health.summary == "Codex 1.2.3 is available")
        #expect(codexCard.health.resolvedExecutable == "/usr/local/bin/codex")
        #expect(codexCard.health.version == "1.2.3")
        #expect(codexCard.health.launchability == .launchable)
        #expect(codexCard.capabilities.launchDefaultSession.isSupported)
        #expect(codexCard.capabilities.createNamedSession.isSupported)
    }

    @Test func workspaceOverviewAndProviderDetailExposeProviderCapabilities() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [
                    "claude": "/tmp/fake-claude",
                    "codex": "/tmp/fake-codex"
                ]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ]),
                codexReadinessProbe: NoOpCodexReadinessProbe()
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))
        let claudeDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let codexDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

        #expect(claudeCard.capabilities.launchDefaultSession.isSupported)
        #expect(claudeCard.capabilities.launchDefaultSession.isEnabled)
        #expect(claudeCard.capabilities.launchDefaultSession.disabledReason == nil)
        #expect(claudeCard.capabilities.createNamedSession.isSupported)
        #expect(claudeCard.capabilities.createNamedSession.isEnabled)
        #expect(claudeDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(claudeDetail.capabilities.createNamedSession.isEnabled)

        #expect(codexCard.capabilities.launchDefaultSession.isSupported)
        #expect(codexCard.capabilities.launchDefaultSession.isEnabled)
        #expect(codexCard.capabilities.launchDefaultSession.disabledReason == nil)
        #expect(codexCard.capabilities.createNamedSession.isSupported)
        #expect(codexCard.capabilities.createNamedSession.isEnabled)
        #expect(codexCard.capabilities.createNamedSession.disabledReason == nil)
        #expect(codexDetail.capabilities.launchDefaultSession == codexCard.capabilities.launchDefaultSession)
        #expect(codexDetail.capabilities.createNamedSession == codexCard.capabilities.createNamedSession)
    }

    @Test func existingDefaultSessionKeepsLaunchCapabilityEnabledWhenProviderHealthBecomesUnavailable() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let resolver = MutableExecutableResolver(executables: ["claude": "/tmp/fake-claude"])
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: resolver,
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        resolver.executables = [:]

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))
        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(session.state == .ready)
        #expect(claudeCard.health.launchability == .notLaunchable)
        #expect(claudeCard.capabilities.launchDefaultSession.isEnabled)
        #expect(claudeCard.capabilities.launchDefaultSession.disabledReason == nil)
        #expect(claudeCard.capabilities.createNamedSession.isEnabled == false)
        #expect(claudeCard.capabilities.createNamedSession.disabledReason == claudeCard.health.summary)
        #expect(detail.capabilities.launchDefaultSession.isEnabled)
        #expect(detail.capabilities.createNamedSession.isEnabled == false)
        #expect(detail.capabilities.createNamedSession.disabledReason == detail.health.summary)
    }

    @Test func remoteClaudeProviderHealthPersistsAcrossServiceBootstrap() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let firstOverview = try await firstClient.getWorkspaceOverview(workspaceID: workspace.id)
        let firstHealth = try #require(firstOverview.providerCards.first(where: { $0.provider.id == .claude })?.health)
        #expect(firstHealth.checkedAt != nil)

        let secondService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedDetail = try await secondClient.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(persistedDetail.health.checkedAt == firstHealth.checkedAt)
        #expect(persistedDetail.health == firstHealth)
    }

    @Test func remoteClaudeProviderHealthExplainsMissingExecutableInCheckedRemoteShells() async throws {
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "", stderr: "NEXUS_REMOTE_CLAUDE_NOT_FOUND\n", exitStatus: 1)
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let diagnostic = try #require(detail.health.diagnostics.first(where: { $0.code == "remoteExecutableNotFound" }))

        #expect(detail.health.state == .unavailable)
        #expect(detail.health.summary == "Claude is unavailable on the Remote Workspace")
        #expect(detail.health.launchability == .notLaunchable)
        #expect(diagnostic.message == "Claude executable was not found in the remote shell environments Nexus checked.")
    }

    @Test func remoteClaudeLaunchRefreshesStaleFailedProviderHealthSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let failedHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "", stderr: "NEXUS_REMOTE_CLAUDE_NOT_FOUND\n", exitStatus: 1)
        ])
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: failedHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let failedDetail = try await firstClient.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(failedDetail.health.state == .unavailable)
        #expect(failedDetail.health.summary == "Claude is unavailable on the Remote Workspace")

        let recoveredHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, _, _ in
                "\(configuration.executable) @ \(configuration.workingDirectory)"
            }
        )
        let secondService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: recoveredHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager
        )
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)

        let session = try await secondClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await secondClient.getSessionScreen(sessionID: session.id)
        let refreshedDetail = try await secondClient.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(session.state == .ready)
        #expect(screen.transcript == "/usr/local/bin/claude @ /srv/api")
        #expect(refreshedDetail.health.state == .available)
        #expect(refreshedDetail.health.resolvedExecutable == "/usr/local/bin/claude")
        #expect(refreshedDetail.defaultSession?.id == session.id)
        #expect(refreshedDetail.defaultSession?.state == .ready)
    }

    @Test func remoteWorkspaceOverviewBlocksProviderHealthBehindHostValidation() async throws {
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/home/chundla/.openclaw",
            primaryGroupID: group.id
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let remoteTarget = try #require(overview.remoteTarget)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(remoteTarget.hostValidation == nil)
        #expect(remoteTarget.workspaceAvailability.state == .blocked)
        #expect(remoteTarget.workspaceAvailability.summary == "Workspace Availability is blocked by Host Validation")
        let availabilityDiagnostic = remoteTarget.workspaceAvailability.diagnostics.first(where: { $0.code == "hostValidationBlocked" })
        #expect(availabilityDiagnostic?.message == "Workspace Availability is blocked until Host Validation runs for Build Server.")
        #expect(claudeCard.health.state == .blocked)
        #expect(claudeCard.health.summary == "Provider Health is blocked by Host Validation")
        let healthDiagnostic = claudeCard.health.diagnostics.first(where: { $0.code == "hostValidationBlocked" })
        #expect(healthDiagnostic?.message == "Provider Health for Claude is blocked until Host Validation runs.")
    }

    @Test func remoteWorkspaceOverviewBlocksProviderHealthBehindBrokenWorkspaceAvailability() async throws {
        let sshRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/missing' && pwd"
                ]
            ): .success(stdout: "", stderr: "bash: cd: /srv/missing: No such file or directory\n", exitStatus: 1)
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: sshRunner)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/missing",
            primaryGroupID: group.id
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let remoteTarget = try #require(overview.remoteTarget)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(remoteTarget.workspaceAvailability.state == .broken)
        #expect(remoteTarget.workspaceAvailability.summary == "Workspace requires repair")
        let availabilityDiagnostic = remoteTarget.workspaceAvailability.diagnostics.first
        #expect(availabilityDiagnostic?.code == "workspaceTargetBroken")
        #expect(availabilityDiagnostic?.message == "bash: cd: /srv/missing: No such file or directory")
        #expect(claudeCard.health.state == .blocked)
        #expect(claudeCard.health.summary == "Provider Health is blocked by Workspace Availability")
        let healthDiagnostic = claudeCard.health.diagnostics.first(where: { $0.code == "workspaceAvailabilityBlocked" })
        #expect(healthDiagnostic?.message == "Provider Health for Claude is blocked by Workspace Availability: Workspace requires repair.")
    }

    @Test func remoteWorkspaceOverviewClassifiesTransientWorkspaceAvailabilityFailuresAsUnavailable() async throws {
        let sshRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "", stderr: "ssh: connect to host build-box port 22: Operation timed out\n", exitStatus: 255)
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: sshRunner)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let remoteTarget = try #require(overview.remoteTarget)

        #expect(remoteTarget.workspaceAvailability.state == .unavailable)
        #expect(remoteTarget.workspaceAvailability.summary == "Workspace is currently unavailable")
        let availabilityDiagnostic = remoteTarget.workspaceAvailability.diagnostics.first
        #expect(availabilityDiagnostic?.code == "workspaceUnavailable")
        #expect(availabilityDiagnostic?.message == "ssh: connect to host build-box port 22: Operation timed out")
    }

    @Test func workspaceOverviewShowsAllSupportedProvidersOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(name: nil, folderPath: "/tmp/provider-overview-workspace", primaryGroupID: nil)

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)

        #expect(overview.workspace == workspace)
        #expect(overview.providerCards.map(\.provider.id) == [.codex, .claude, .ibmBob, .pi])
        #expect(overview.providerCards.map(\.defaultSession.state) == [.notCreated, .notCreated, .notCreated, .notCreated])
        #expect(overview.providerCards.filter { [.ibmBob, .pi].contains($0.provider.id) }.map(\.health.state) == [.notChecked, .notChecked])
    }

    @Test func workspaceOverviewShowsLaunchableClaudeHealthFromServiceOwnedAdapter() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager()
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(claudeCard.health.state == .available)
        #expect(claudeCard.health.summary == "Claude 9.9.9 (Claude Code) is available")
        #expect(claudeCard.health.resolvedExecutable == "/tmp/fake-claude")
        #expect(claudeCard.health.version == "9.9.9 (Claude Code)")
        #expect(claudeCard.health.launchability == .launchable)
        #expect(claudeCard.health.diagnostics.isEmpty)
    }

    @Test func workspaceOverviewShowsLaunchableCodexHealthFromServiceOwnedAdapter() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ]),
                codexReadinessProbe: NoOpCodexReadinessProbe()
            ),
            sessionRuntimeManager: StubSessionRuntimeManager()
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))

        #expect(codexCard.health.state == .available)
        #expect(codexCard.health.summary == "Codex 1.2.3 is available")
        #expect(codexCard.health.resolvedExecutable == "/tmp/fake-codex")
        #expect(codexCard.health.version == "1.2.3")
        #expect(codexCard.health.launchability == .launchable)
        #expect(codexCard.health.diagnostics.isEmpty)
    }

    @Test func workspaceOverviewShowsUnavailableClaudeHealthWhenExecutableCannotBeResolved() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(claudeCard.health.state == .unavailable)
        #expect(claudeCard.health.summary == "Claude executable was not found")
        #expect(claudeCard.health.resolvedExecutable == nil)
        #expect(claudeCard.health.version == nil)
        #expect(claudeCard.health.launchability == .notLaunchable)
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0 == ProviderHealthDiagnostic(
                severity: .error,
                code: "executableNotFound",
                message: "Claude executable was not found in the service search paths."
            )
        }))
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0.code == "searchedDirectories" && $0.message.contains("/tmp/search-a")
        }))
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0.code == "homeDirectories" && $0.message.contains("/tmp/home")
        }))
        #expect(claudeCard.health.diagnostics.contains(where: {
            $0.code == "pathEnvironment" && $0.message.contains("/tmp/search-a:/tmp/search-b")
        }))
    }

    @Test func launchOrResumeDefaultSessionCreatesAndReusesCodexSessionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ]),
                codexReadinessProbe: NoOpCodexReadinessProbe()
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Codex ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let firstSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let secondSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))

        #expect(firstSession.state == .ready)
        #expect(firstSession.providerID == .codex)
        #expect(firstSession.workspaceID == workspace.id)
        #expect(firstSession.isDefault)
        #expect(secondSession == firstSession)
        #expect(codexCard.defaultSession.state == .ready)
        #expect(codexCard.defaultSession.actionTitle == "Resume")
        #expect(codexCard.defaultSession.sessionID == firstSession.id)
    }

    @Test func launchOrResumeDefaultSessionCreatesAndReusesClaudeSessionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager()
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let firstSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let secondSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(firstSession.state == .ready)
        #expect(firstSession.providerID == .claude)
        #expect(firstSession.workspaceID == workspace.id)
        #expect(firstSession.isDefault)
        #expect(secondSession == firstSession)
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
        #expect(claudeCard.defaultSession.sessionID == firstSession.id)
    }

    @Test func launchOrResumeDefaultSessionUsesInjectedClaudeAdapterHealthOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let adapterExecutable = "/tmp/adapter-claude"
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { $0 }),
            providerAdapters: [
                .claude: ServiceProviderAdapter(
                    providerID: .claude,
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { workspace, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Claude adapter available for \(workspace.name)",
                            resolvedExecutable: adapterExecutable,
                            launchability: .launchable
                        )
                    }
                )
            ]
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: session.id)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(session.state == .ready)
        #expect(screen.transcript == adapterExecutable)
        #expect(claudeCard.health.summary == "Claude adapter available for \(workspace.name)")
        #expect(claudeCard.health.resolvedExecutable == adapterExecutable)
    }

    @Test func launchOrResumeDefaultSessionUsesInjectedClaudeAdapterLaunchCopyOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    configuration.initialTranscript
                }
            ),
            providerAdapters: [
                .claude: ServiceProviderAdapter(
                    providerID: .claude,
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { workspace, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Claude adapter available for \(workspace.name)",
                            resolvedExecutable: "/tmp/adapter-claude",
                            launchability: .launchable
                        )
                    },
                    initialTranscriptBuilder: { workspace, _, _ in
                        "Adapter launch copy for \(workspace.name)"
                    }
                )
            ]
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: session.id)

        #expect(session.state == .ready)
        #expect(screen.transcript == "Adapter launch copy for \(workspace.name)")
    }

    @Test func createNamedSessionUsesInjectedClaudeAdapterHealthOnRemoteWorkspaceOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let adapterExecutable = "/usr/local/bin/adapter-claude"
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, session, _ in
                let runtimeIdentifier = configuration.remoteRuntimeIdentifier ?? "missing"
                let sessionName = session.name ?? "default"
                return "\(configuration.executable) @ \(configuration.workingDirectory) session:\(runtimeIdentifier) named:\(sessionName)"
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager,
            providerAdapters: [
                .claude: ServiceProviderAdapter(
                    providerID: .claude,
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { _, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Claude adapter available on the Remote Workspace",
                            resolvedExecutable: adapterExecutable,
                            launchability: .launchable
                        )
                    }
                )
            ]
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Review")
        let screen = try await client.getSessionScreen(sessionID: namedSession.id)
        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(namedSession.state == .ready)
        #expect(namedSession.name == "Review")
        #expect(screen.transcript == "\(adapterExecutable) @ /srv/api session:nexus-\(namedSession.id.uuidString.lowercased())-runtime-1 named:Review")
        #expect(detail.health.summary == "Claude adapter available on the Remote Workspace")
        #expect(detail.alternateSessions.map(\.id) == [namedSession.id])
    }

    @Test func remoteClaudeDefaultSessionLaunchesThroughWorkspaceAwareSSHTmuxRuntimeOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-p", "2222",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-p", "2222",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, session, _ in
                let hostTarget = configuration.remoteHost.map { "\($0.sshTarget):\($0.port ?? 22)" } ?? "local"
                return "ssh \(hostTarget) \(configuration.workingDirectory) \(configuration.executable) session:\(configuration.remoteRuntimeIdentifier ?? "missing")"
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: session.id)
        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(session.state == .ready)
        #expect(screen.session.state == .ready)
        #expect(screen.transcript == "ssh build-box:2222 /srv/api /usr/local/bin/claude session:nexus-\(session.id.uuidString.lowercased())-runtime-1")
        #expect(detail.defaultSession?.id == session.id)
        #expect(detail.defaultSession?.state == .ready)
    }

    @Test func remoteCodexDefaultSessionLaunchesThroughWorkspaceAwareSSHTmuxRuntimeOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-p", "2222",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-p", "2222",
                    "build-box",
                    remoteCodexProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/codex\n1.2.3\n")
        ])
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, session, _ in
                let hostTarget = configuration.remoteHost.map { "\($0.sshTarget):\($0.port ?? 22)" } ?? "local"
                return "ssh \(hostTarget) \(configuration.workingDirectory) \(configuration.executable) session:\(configuration.remoteRuntimeIdentifier ?? "missing")"
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let firstSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let secondSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let screen = try await client.getSessionScreen(sessionID: firstSession.id)
        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

        #expect(firstSession.state == .ready)
        #expect(secondSession == firstSession)
        #expect(screen.session.state == .ready)
        #expect(screen.transcript == "ssh build-box:2222 /srv/api /usr/local/bin/codex session:nexus-\(firstSession.id.uuidString.lowercased())-runtime-1")
        #expect(detail.defaultSession?.id == firstSession.id)
        #expect(detail.defaultSession?.state == .ready)
    }

    @Test func remoteCodexNamedSessionLaunchesThroughWorkspaceAwareSSHTmuxRuntimeOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteCodexProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/codex\n1.2.3\n")
        ])
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, session, _ in
                "\(configuration.executable) @ \(configuration.workingDirectory) session:\(configuration.remoteRuntimeIdentifier ?? "missing") named:\(session.name ?? "default")"
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try await client.createNamedSession(workspaceID: workspace.id, providerID: .codex, name: "Review")
        let screen = try await client.getSessionScreen(sessionID: session.id)
        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

        #expect(session.state == .ready)
        #expect(session.name == "Review")
        #expect(screen.transcript == "/usr/local/bin/codex @ /srv/api session:nexus-\(session.id.uuidString.lowercased())-runtime-1 named:Review")
        #expect(detail.alternateSessions.map(\.id) == [session.id])
    }

    @Test func failedNamedRemoteCodexSessionRemainsInspectableAndCanBeRelaunched() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let failedHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteCodexProbeScript("/srv/api")
                ]
            ): .success(stdout: "", stderr: "NEXUS_REMOTE_CODEX_NOT_FOUND\n", exitStatus: 1)
        ])
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: failedHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let failedSession = try await firstClient.createNamedSession(workspaceID: workspace.id, providerID: .codex, name: "Review")
        let failedDetail = try await firstClient.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
        let failedScreen = try await firstClient.getSessionScreen(sessionID: failedSession.id)

        #expect(failedSession.state == .failed)
        #expect(failedDetail.failedSessions.map(\.id) == [failedSession.id])
        #expect(failedScreen.session.state == .failed)
        #expect(failedScreen.transcript == "Codex executable was not found in the remote shell environments Nexus checked.")

        let recoveredHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteCodexProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/codex\n1.2.3\n")
        ])
        let secondService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: recoveredHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            )
        )
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)

        let relaunchedSession = try await secondClient.launchOrResumeSession(sessionID: failedSession.id)
        let relaunchedDetail = try await secondClient.getProviderDetail(workspaceID: workspace.id, providerID: .codex)
        let relaunchedScreen = try await secondClient.getSessionScreen(sessionID: failedSession.id)

        #expect(relaunchedSession.id == failedSession.id)
        #expect(relaunchedDetail.failedSessions.isEmpty)
        #expect(relaunchedDetail.alternateSessions.map(\.id) == [failedSession.id])
        #expect(relaunchedScreen.transcript == "runtime:nexus-\(failedSession.id.uuidString.lowercased())-runtime-1")
    }

    @Test func remoteClaudeDefaultSessionLaunchesWhenExecutableIsOnlyInFallbackRemoteShellPath() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    legacyRemoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "", stderr: "NEXUS_REMOTE_CLAUDE_NOT_FOUND\n", exitStatus: 1),
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/home/chundla/.local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, session, _ in
                "\(configuration.executable) @ \(configuration.workingDirectory) session:\(configuration.remoteRuntimeIdentifier ?? "missing")"
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: session.id)
        let detail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(session.state == .ready)
        #expect(screen.transcript == "/home/chundla/.local/bin/claude @ /srv/api session:nexus-\(session.id.uuidString.lowercased())-runtime-1")
        #expect(detail.health.state == .available)
        #expect(detail.health.resolvedExecutable == "/home/chundla/.local/bin/claude")
    }

    @Test func remoteSessionCommandBuilderUsesPortPathAndRuntimeIdentifier() throws {
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let configuration = SessionRuntimeLaunchConfiguration(
            executable: "/usr/local/bin/claude",
            workingDirectory: "/srv/api",
            remoteHost: host,
            remoteRuntimeIdentifier: "nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2"
        )
        let builder = RemoteSessionCommandBuilder()

        let launchArguments = builder.launchArguments(configuration: configuration)
        #expect(launchArguments.prefix(8) == [
            "-tt",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-p", "2222",
            "build-box"
        ])
        let remoteLaunchCommand = try #require(launchArguments.last)
        #expect(remoteLaunchCommand.contains("cd '/srv/api'"))
        #expect(remoteLaunchCommand.contains("NEXUS_REMOTE_SHELL=\"$(for shell in \"${SHELL:-}\""))
        #expect(remoteLaunchCommand.contains("case \"${NEXUS_REMOTE_SHELL##*/}\" in csh|tcsh)"))
        #expect(remoteLaunchCommand.contains("fish) exec tmux new-session -s 'nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2' \"$NEXUS_REMOTE_SHELL\" -i -c"))
        #expect(remoteLaunchCommand.contains("*) exec tmux new-session -s 'nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2' \"$NEXUS_REMOTE_SHELL\" -lic"))
        #expect(remoteLaunchCommand.contains("/usr/local/bin/claude"))
        #expect(builder.recoverArguments(configuration: configuration) == [
            "-tt",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-p", "2222",
            "build-box",
            "tmux has-session -t 'nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2' 2>/dev/null || { echo 'NEXUS_REMOTE_RUNTIME_NOT_FOUND' >&2; exit 1; }; exec tmux attach-session -t 'nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2'"
        ])
        #expect(builder.stopArguments(runtimeIdentifier: "nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2", host: host) == [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-p", "2222",
            "build-box",
            "tmux kill-session -t 'nexus-01234567-89ab-cdef-0123-456789abcdef-runtime-2'"
        ])
    }

    @Test func remoteDefaultSessionRelaunchesWithFreshRuntimeIdentifierWhileKeepingSessionLane() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let runtimeManager = StubSessionRuntimeManager(
            launchTranscriptForConfiguration: { configuration, _, _ in
                "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
            }
        )
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let firstSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let firstScreen = try await client.getSessionScreen(sessionID: firstSession.id)
        _ = try await client.stopSession(sessionID: firstSession.id)

        let relaunchedSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await client.getSessionScreen(sessionID: relaunchedSession.id)

        #expect(firstSession.id == relaunchedSession.id)
        #expect(firstScreen.transcript == "runtime:nexus-\(firstSession.id.uuidString.lowercased())-runtime-1")
        #expect(relaunchedScreen.transcript == "runtime:nexus-\(firstSession.id.uuidString.lowercased())-runtime-2")
    }

    @Test func remoteDefaultSessionRecoversPersistedRuntimeAfterServiceRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            )
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            )
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)

        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)
        let recoveredSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let recoveredScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(interruptedScreen.session.state == .interrupted)
        #expect(recoveredSession.id == launchedSession.id)
        #expect(recoveredSession.state == .ready)
        #expect(recoveredScreen.session.state == .ready)
        #expect(recoveredScreen.transcript == "runtime:nexus-\(launchedSession.id.uuidString.lowercased())-runtime-1")
    }

    @Test func recoveredRemoteClaudeSessionUsesInjectedAdapterReconnectCopyOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let adapterOverride = ServiceProviderAdapter(
            providerID: .claude,
            supportsDefaultSessionLaunch: true,
            supportsNamedSessions: true,
            healthSummaryEvaluator: { _, _, _ in
                ProviderHealthSummary(
                    state: .available,
                    summary: "Claude adapter available on the Remote Workspace",
                    resolvedExecutable: "/usr/local/bin/adapter-claude",
                    launchability: .launchable
                )
            },
            initialTranscriptBuilder: { _, remoteHost, launchMode in
                switch launchMode {
                case .launchNew:
                    return "Adapter connect copy"
                case .attachExisting:
                    return "Adapter reconnect copy for \(remoteHost?.name ?? "unknown host")"
                }
            }
        )
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    configuration.initialTranscript
                }
            ),
            providerAdapters: [.claude: adapterOverride]
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    configuration.initialTranscript
                }
            ),
            providerAdapters: [.claude: adapterOverride]
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)

        let recoveredSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let recoveredScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(recoveredSession.id == launchedSession.id)
        #expect(recoveredScreen.transcript == "Adapter reconnect copy for Build Server")
    }

    @Test func missingRecoveredRemoteRuntimeStaysInspectableAndRelaunchesFresh() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            )
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchBehavior: { configuration, _, _ in
                    if configuration.remoteRuntimeLaunchMode == .attachExisting {
                        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "NEXUS_REMOTE_RUNTIME_NOT_FOUND"])
                    }
                },
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            )
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)

        let recoveryAttempt = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let failedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)
        let relaunchedSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(recoveryAttempt.id == launchedSession.id)
        #expect(recoveryAttempt.state == .failed)
        #expect(recoveryAttempt.failureMessage == "Known remote runtime 'nexus-\(launchedSession.id.uuidString.lowercased())-runtime-1' is no longer available on Build Server. Relaunch to create a new remote runtime.")
        #expect(failedScreen.session.state == .failed)
        #expect(relaunchedSession.id == launchedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(relaunchedScreen.transcript == "runtime:nexus-\(launchedSession.id.uuidString.lowercased())-runtime-2")
    }

    @Test func missingRecoveredRemoteRuntimeUsesInjectedClaudeAdapterRecoveryFailureOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let adapterOverride: ServiceProviderAdapter = ServiceProviderAdapter(
            providerID: .claude,
            supportsDefaultSessionLaunch: true,
            supportsNamedSessions: true,
            healthSummaryEvaluator: { _, _, _ in
                ProviderHealthSummary(
                    state: .available,
                    summary: "Claude adapter available on the Remote Workspace",
                    resolvedExecutable: "/usr/local/bin/adapter-claude",
                    launchability: .launchable
                )
            },
            remoteRuntimeRecoveryFailureEvaluator: { context in
                (
                    state: .failed,
                    message: "Adapter recovery failure for \(context.runtimeIdentifier) on \(context.hostName)."
                )
            }
        )
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            ),
            providerAdapters: [.claude: adapterOverride]
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchBehavior: { configuration, _, _ in
                    if configuration.remoteRuntimeLaunchMode == .attachExisting {
                        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "NEXUS_REMOTE_RUNTIME_NOT_FOUND"])
                    }
                }
            ),
            providerAdapters: [.claude: adapterOverride]
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)

        let recoveryAttempt = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        #expect(recoveryAttempt.id == launchedSession.id)
        #expect(recoveryAttempt.state == .failed)
        #expect(recoveryAttempt.failureMessage == "Adapter recovery failure for nexus-\(launchedSession.id.uuidString.lowercased())-runtime-1 on Build Server.")
    }

    @Test func failedNamedRemoteSessionRemainsInspectableAndCanBeRelaunched() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let failedHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "", stderr: "NEXUS_REMOTE_CLAUDE_NOT_FOUND\n", exitStatus: 1)
        ])
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: failedHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner)
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let group = try await firstClient.createWorkspaceGroup(name: "Remote")
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await firstClient.validateHost(hostID: host.id)
        let workspace = try await firstClient.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        let failedSession = try await firstClient.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Review")
        let failedDetail = try await firstClient.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let failedScreen = try await firstClient.getSessionScreen(sessionID: failedSession.id)

        #expect(failedSession.state == .failed)
        #expect(failedDetail.failedSessions.map(\.id) == [failedSession.id])
        #expect(failedScreen.session.state == .failed)
        #expect(failedScreen.transcript == "Claude executable was not found in the remote shell environments Nexus checked.")

        let recoveredHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let secondService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: recoveredHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(
                launchTranscriptForConfiguration: { configuration, _, _ in
                    "runtime:\(configuration.remoteRuntimeIdentifier ?? "missing")"
                }
            )
        )
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)

        let relaunchedSession = try await secondClient.launchOrResumeSession(sessionID: failedSession.id)
        let relaunchedDetail = try await secondClient.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await secondClient.getSessionScreen(sessionID: failedSession.id)

        #expect(relaunchedSession.id == failedSession.id)
        #expect(relaunchedDetail.failedSessions.isEmpty)
        #expect(relaunchedDetail.alternateSessions.map(\.id) == [failedSession.id])
        #expect(relaunchedScreen.transcript == "runtime:nexus-\(failedSession.id.uuidString.lowercased())-runtime-1")
    }

    @Test func quickSwitchPrioritizesWorkspaceMatchesBeforeProviderAndSessionMatchesOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: "Claude Lab",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        _ = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let results = try await client.searchNavigation(query: "claude")

        #expect(results.map(\.kind).prefix(3).elementsEqual([.workspace, .provider, .session]))
        #expect(results.first?.title == "Claude Lab")
        #expect(results.dropFirst().first?.subtitle.contains("Claude Lab") == true)
    }

    @Test func recentNavigationPersistsWorkspaceAndSessionContextsOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: "Recents Workspace",
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let session = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        try await firstClient.recordNavigation(target: .workspace(workspace.id))
        try await Task.sleep(nanoseconds: 20_000_000)
        try await firstClient.recordNavigation(target: .session(session.id))

        let initialRecents = try await firstClient.listRecentNavigation(limit: 10)
        #expect(initialRecents.map(\.kind).prefix(2).elementsEqual([.session, .workspace]))
        #expect(initialRecents.first?.title == "Default Session")
        #expect(initialRecents.dropFirst().first?.title == "Recents Workspace")

        let secondService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedRecents = try await secondClient.listRecentNavigation(limit: 10)

        #expect(persistedRecents.map(\.kind).prefix(2).elementsEqual([.session, .workspace]))
        #expect(persistedRecents.first?.subtitle.contains("Recents Workspace") == true)
        #expect(persistedRecents.dropFirst().first?.title == "Recents Workspace")
    }

    @Test func remoteWorkspaceNavigationUsesHostAndRemotePathMetadataOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        let workspace = try await client.createRemoteWorkspace(
            name: "Remote API",
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        try await client.recordNavigation(target: .workspace(workspace.id))

        let recents = try await client.listRecentNavigation(limit: 10)
        let results = try await client.searchNavigation(query: "build server")

        #expect(recents.first?.title == "Remote API")
        #expect(recents.first?.subtitle == "Build Server • /srv/api")
        #expect(results.first?.title == "Remote API")
        #expect(results.first?.subtitle == "Build Server • /srv/api")
    }

    @Test func createNamedSessionAddsAlternateSessionToProviderDetailOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let defaultSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(defaultSession.isDefault)
        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Session 1")
        #expect(providerDetail.defaultSession?.id == defaultSession.id)
        #expect(providerDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(providerDetail.alternateSessions.first?.name == "Session 1")
        #expect(providerDetail.failedSessions.isEmpty)
        #expect(claudeCard.alternateSessionCount == 1)
    }

    @Test func codexNamedSessionCanBeStoppedInspectedRelaunchedAndDeletedOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["codex": "/tmp/fake-codex"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--version"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-codex", arguments: ["--help"]): .success(stdout: "Usage: codex\n")
                ]),
                codexReadinessProbe: NoOpCodexReadinessProbe()
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Codex ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .codex, name: nil)
        let stoppedSession = try await client.stopSession(sessionID: namedSession.id)
        let stoppedScreen = try await client.getSessionScreen(sessionID: namedSession.id)
        let relaunchedSession = try await client.launchOrResumeSession(sessionID: namedSession.id)
        let relaunchedScreen = try await client.getSessionScreen(sessionID: namedSession.id)
        _ = try await client.stopSession(sessionID: namedSession.id)
        let deleted = try await client.deleteSessionRecord(sessionID: namedSession.id)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .codex)

        #expect(namedSession.providerID == .codex)
        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Session 1")
        #expect(stoppedSession.id == namedSession.id)
        #expect(stoppedSession.state == .exited)
        #expect(stoppedScreen.session.state == .exited)
        #expect(stoppedScreen.transcript == "Codex ready")
        #expect(relaunchedSession.id == namedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(relaunchedScreen.session.state == .ready)
        #expect(relaunchedScreen.transcript == "Codex ready")
        #expect(deleted)
        #expect(providerDetail.alternateSessions.isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await client.getSessionScreen(sessionID: namedSession.id)
        }
    }

    @Test func stopSessionKeepsAlternateSessionRecordInspectableOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)
        let stoppedSession = try await client.stopSession(sessionID: namedSession.id)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: namedSession.id)

        #expect(stoppedSession.id == namedSession.id)
        #expect(stoppedSession.state == .exited)
        #expect(providerDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(providerDetail.alternateSessions.first?.state == .exited)
        #expect(providerDetail.failedSessions.isEmpty)
        #expect(screen.session.state == .exited)
        #expect(screen.transcript == "Claude ready")
    }

    @Test func deleteStoppedSessionRecordRemovesItFromProviderDetailOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)
        _ = try await client.stopSession(sessionID: namedSession.id)
        let deleted = try await client.deleteSessionRecord(sessionID: namedSession.id)
        let providerDetail = try await client.getProviderDetail(workspaceID: workspace.id, providerID: .claude)

        #expect(deleted)
        #expect(providerDetail.alternateSessions.isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await client.getSessionScreen(sessionID: namedSession.id)
        }
    }

    @Test func deleteRunningSessionRecordIsRejectedOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let namedSession = try await client.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: nil)

        await #expect(throws: (any Error).self) {
            _ = try await client.deleteSessionRecord(sessionID: namedSession.id)
        }
    }

    @Test func launchedSessionReturnsFocusedTranscriptAndAcceptsInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "Claude ready")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let firstScreen = try await client.getSessionScreen(sessionID: session.id)
        let updatedScreen = try await client.sendSessionInput(sessionID: session.id, text: "help")

        #expect(firstScreen.session == session)
        #expect(firstScreen.transcript == "Claude ready")
        #expect(firstScreen.terminalColumns == 80)
        #expect(firstScreen.terminalRows == 24)
        #expect(updatedScreen.transcript.contains("> help"))
        #expect(updatedScreen.transcript.contains("Claude acknowledged: help"))
    }

    @Test func launchedSessionNormalizesTerminalControlTranscriptOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "progress 0%\rprogress 100%\n\u{001B}[32mClaude ready\u{001B}[0m\n")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.getSessionScreen(sessionID: session.id)

        #expect(screen.transcript.contains("progress 100%"))
        #expect(screen.transcript.contains("Claude ready"))
        #expect(screen.transcript.contains("progress 0%") == false)
        #expect(screen.transcript.contains("\u{001B}") == false)
        #expect(screen.transcript.contains("\r") == false)
    }

    @Test func launchedSessionTreatsCRLFAsLineBreakOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\r\r\nbeta")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "alpha\nbeta")
        #expect(screen.visibleLines == ["alpha", "beta"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 4)
    }

    @Test func launchedSessionCanBeResizedOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "Claude ready")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let resizedScreen = try await client.resizeSession(sessionID: session.id, columns: 132, rows: 40)

        #expect(resizedScreen.session == session)
        #expect(resizedScreen.transcript == "Claude ready")
        #expect(resizedScreen.terminalColumns == 132)
        #expect(resizedScreen.terminalRows == 40)
    }

    @Test func sessionScreenExposesVisibleTerminalLinesOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\n123456789\nomega")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.visibleLines == ["12345", "6789", "omega"])
    }

    @Test func sessionScreenExposesViewportCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\n123456789\nom")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.visibleLines == ["12345", "6789", "om"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenTracksCursorLeftControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abc\u{001B}[2D")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.transcript == "abc")
        #expect(screen.visibleLines == ["abc"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenTracksCursorUpOverwriteOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1A\u{001B}[2DXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.transcript == "alXYa\nbeta")
        #expect(screen.visibleLines == ["alXYa", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenClearsLineSuffixWithEraseInLineControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "loading...\rdone\u{001B}[K")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "done")
        #expect(screen.visibleLines == ["done"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenClearsDisplayPrefixWithoutShiftingTextOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[3G\u{001B}[1J")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "   de")
        #expect(screen.visibleLines == ["   de"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenTracksAbsoluteCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1;3HXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 5, rows: 3)

        #expect(screen.transcript == "alXYa\nbeta")
        #expect(screen.visibleLines == ["alXYa", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenTracksVerticalAbsoluteCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1dXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "alphXY\nbeta")
        #expect(screen.visibleLines == ["alphXY", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 6)
    }

    @Test func sessionScreenTracksHorizontalAbsoluteCursorAliasOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[3`XY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "alpha\nbeXY")
        #expect(screen.visibleLines == ["alpha", "beXY"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenTracksHorizontalRelativeCursorAliasOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "ab\u{001B}[2aXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "ab  XY")
        #expect(screen.visibleLines == ["ab  XY"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 6)
    }

    @Test func sessionScreenTracksVerticalRelativeCursorAliasOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nmid\nbot\u{001B}[1;1H\u{001B}[2eXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 4)

        #expect(screen.transcript == "top\nmid\nXYt")
        #expect(screen.visibleLines == ["top", "mid", "XYt"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenSwitchesToAlternateBufferOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "main\u{001B}[?1049halt")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "alt")
        #expect(screen.visibleLines == ["alt"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenRestoresPrimaryScrollStateAfterAlternateBufferExitOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[?6h\u{001B}[?1049halt\u{001B}[?6l\u{001B}[r\u{001B}[?1049l\u{001B}[1;1HX")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 4)

        #expect(screen.transcript == "top\nXlpha\nbeta\nbottom")
        #expect(screen.visibleLines == ["top", "Xlpha", "beta", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 1)
    }

    @Test func alternateBufferRestoresPrimaryApplicationCursorModeForInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "main\u{001B}[?1049halt\u{001B}[?1h\u{001B}[?1049l")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.sendSessionInputKey(sessionID: session.id, key: .upArrow)

        #expect(screen.transcript.contains("[key: upArrow]"))
        #expect(screen.transcript.contains("[key: upArrow:application]") == false)
    }

    @Test func sessionScreenClearsEntireDisplayOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[2J\u{001B}[Hdone")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "done")
        #expect(screen.visibleLines == ["done"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenDeletesCharacterAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[2D\u{001B}[P")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "abce")
        #expect(screen.visibleLines == ["abce"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenInsertsCharacterAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abde\u{001B}[2D\u{001B}[@c")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "abcde")
        #expect(screen.visibleLines == ["abcde"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenDeletesCurrentLineOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[2;1H\u{001B}[M")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 4)

        #expect(screen.transcript == "alpha\ngamma")
        #expect(screen.visibleLines == ["alpha", "gamma"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenInsertsBlankLineAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[2;1H\u{001B}[L")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 5)

        #expect(screen.transcript == "alpha\n\nbeta\ngamma")
        #expect(screen.visibleLines == ["alpha", "", "beta", "gamma"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenErasesCharacterAtCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[2D\u{001B}[X")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "abc e")
        #expect(screen.visibleLines == ["abc e"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
    }

    @Test func sessionScreenClearsEntireLineWithoutMovingCursorOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[2D\u{001B}[2KZ")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "   Z")
        #expect(screen.visibleLines == ["   Z"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenExpandsHorizontalTabsOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "ab\tc")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "ab      c")
        #expect(screen.visibleLines == ["ab      c"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 9)
    }

    @Test func sessionScreenTracksCursorNextLineControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\u{001B}[Ec")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "alpha\nc")
        #expect(screen.visibleLines == ["alpha", "c"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenHidesCursorWhenTerminalRequestsItOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abc\u{001B}[?25l")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "abc")
        #expect(screen.visibleLines == ["abc"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 3)
        #expect(screen.cursorVisible == false)
    }

    @Test func sessionScreenRestoresSavedCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1;1H\u{001B}[sXY\u{001B}[uZ")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "ZYpha\nbeta")
        #expect(screen.visibleLines == ["ZYpha", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenRestoresDecSavedCursorPositionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\u{001B}[1;1H\u{001B}7\u{001B}[2;1HXY\u{001B}8Z")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "Zlpha\nXYta")
        #expect(screen.visibleLines == ["Zlpha", "XYta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenStripsOscWindowTitleControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{001B}]0;Claude working\u{0007}world")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "helloworld")
        #expect(screen.visibleLines == ["helloworld"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 10)
    }

    @Test func sessionScreenStripsOscHyperlinkControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "pre\u{001B}]8;;https://example.com\u{001B}\\link\u{001B}]8;;\u{001B}\\post")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 10, rows: 3)

        #expect(screen.transcript == "prelinkpost")
        #expect(screen.visibleLines == ["prelinkpos", "t"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 1)
    }

    @Test func sessionScreenIgnoresKittyKeyboardProtocolControlsOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{001B}[<uworld\u{001B}[>1u!")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "helloworld!")
        #expect(screen.visibleLines == ["helloworld!"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 11)
    }

    @Test func sessionScreenStripsDeviceControlStringOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{001B}P$qm\u{001B}\\world")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "helloworld")
        #expect(screen.visibleLines == ["helloworld"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 10)
    }

    @Test func sessionScreenStripsBellControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "hello\u{0007}world")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "helloworld")
        #expect(screen.visibleLines == ["helloworld"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 10)
    }

    @Test func sessionScreenRendersVt100LineDrawingCharactersOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "\u{001B}(0lqqk\u{001B}(B")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "┌──┐")
        #expect(screen.visibleLines == ["┌──┐"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenRepeatsPreviousCharacterOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "q\u{001B}[3b")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "qqqq")
        #expect(screen.visibleLines == ["qqqq"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func sessionScreenScrollsDisplayUpOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[S")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "beta\ngamma\n")
        #expect(screen.visibleLines == ["beta", "gamma", ""])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 5)
    }

    @Test func sessionScreenMovesCursorToScrollingRegionOriginOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[?6h\u{001B}[HXY")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nXYpha\nbeta\nbottom")
        #expect(screen.visibleLines == ["top", "XYpha", "beta", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenScrollsDisplayUpWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[S")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nbeta\n\nbottom")
        #expect(screen.visibleLines == ["top", "beta", "", "bottom"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenScrollsDisplayDownWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[T")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\n\nalpha\nbottom")
        #expect(screen.visibleLines == ["top", "", "alpha", "bottom"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenScrollsDisplayDownWithinScrollingRegionWithReverseIndexOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[3;1H\u{001B}D")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nbeta\n\nbottom")
        #expect(screen.visibleLines == ["top", "beta", "", "bottom"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenInsertsBlankLineWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[2;1H\u{001B}[L")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\n\nalpha\nbottom")
        #expect(screen.visibleLines == ["top", "", "alpha", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenDeletesLineWithinScrollingRegionOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "top\nalpha\nbeta\nbottom\u{001B}[2;3r\u{001B}[2;1H\u{001B}[M")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 4)

        #expect(screen.transcript == "top\nbeta\n\nbottom")
        #expect(screen.visibleLines == ["top", "beta", "", "bottom"])
        #expect(screen.cursorRow == 1)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenScrollsDisplayDownOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[T")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "\nalpha\nbeta")
        #expect(screen.visibleLines == ["", "alpha", "beta"])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 5)
    }

    @Test func sessionScreenReverseIndexesDisplayDownOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[1;1H\u{001B}M")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "\nalpha\nbeta")
        #expect(screen.visibleLines == ["", "alpha", "beta"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenIndexesDisplayUpOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[3;3H\u{001B}D")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "beta\ngamma\n")
        #expect(screen.visibleLines == ["beta", "gamma", ""])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenMovesToNextLineAndScrollsOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\nbeta\ngamma\u{001B}[3;3H\u{001B}E")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "beta\ngamma\n")
        #expect(screen.visibleLines == ["beta", "gamma", ""])
        #expect(screen.cursorRow == 2)
        #expect(screen.cursorColumn == 0)
    }

    @Test func sessionScreenBackspaceOnlyMovesCursorLeftOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abc\u{0008}")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "abc")
        #expect(screen.visibleLines == ["abc"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenErasesLinePrefixWithoutShiftingTextOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "abcde\u{001B}[3D\u{001B}[1K")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "   de")
        #expect(screen.visibleLines == ["   de"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 2)
    }

    @Test func sessionScreenResetsDisplayWithFullResetControlOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let runtimeManager = StubSessionRuntimeManager(initialTranscript: "alpha\u{001B}cdone")
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: runtimeManager
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await client.resizeSession(sessionID: session.id, columns: 20, rows: 3)

        #expect(screen.transcript == "done")
        #expect(screen.visibleLines == ["done"])
        #expect(screen.cursorRow == 0)
        #expect(screen.cursorColumn == 4)
    }

    @Test func liveClaudeRuntimeStartsOnPseudoTerminalOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import fcntl
        import struct
        import sys
        import termios
        
        try:
            rows, cols, _, _ = struct.unpack(
                "HHHH",
                fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
            )
            print(f"TTY {rows} {cols}", flush=True)
        except OSError:
            print("TTY no-tty", flush=True)

        while True:
            line = sys.stdin.readline()
            if not line:
                break
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("TTY 24 80") || currentScreen.transcript.contains("TTY no-tty")
        }

        #expect(screen.terminalColumns == 80)
        #expect(screen.terminalRows == 24)
        #expect(screen.transcript.contains("TTY 24 80"))
    }

    @Test func liveClaudeRuntimeNormalizesTerminalControlOutputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import sys
        import time

        sys.stdout.write("progress 0%")
        sys.stdout.flush()
        time.sleep(0.05)
        sys.stdout.write("\\rprogress 100%\\n")
        sys.stdout.write("\\x1b[32mClaude ready\\x1b[0m\\n")
        sys.stdout.flush()
        time.sleep(2)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("progress 100%") && currentScreen.transcript.contains("Claude ready")
        }

        #expect(screen.transcript.contains("progress 100%"))
        #expect(screen.transcript.contains("Claude ready"))
        #expect(screen.transcript.contains("progress 0%") == false)
        #expect(screen.transcript.contains("\u{001B}") == false)
    }

    @Test func liveClaudeRuntimeStreamsSessionScreenUpdatesOverXPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import time

        print("Claude ready", flush=True)
        time.sleep(0.2)
        print("Claude streamed update", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let collector = SessionScreenCollector()
        let observation = try await client.observeSessionScreen(sessionID: session.id) { screen in
            Task {
                await collector.record(screen)
            }
        }

        let streamedScreen = try await collector.waitForScreen { screen in
            screen.transcript.contains("Claude streamed update") && screen.session.state == .exited
        }

        #expect(streamedScreen.transcript.contains("Claude ready"))
        #expect(streamedScreen.transcript.contains("Claude streamed update"))
        #expect(streamedScreen.session.state == .exited)
        await observation.cancel()
    }

    @Test func liveClaudeRuntimeAcceptsEmptyInputAsEnterOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import sys

        print("Press enter to continue", flush=True)
        line = sys.stdin.readline()
        if line == "\\n":
            print("Enter received", flush=True)
        else:
            print(f"Unexpected input: {line!r}", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("Press enter to continue")
        }

        _ = try await client.sendSessionInput(sessionID: session.id, text: "")
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("Enter received")
        }

        #expect(screen.transcript.contains("Enter received"))
    }

    @Test func liveClaudeRuntimeSendsCarriageReturnForEnterKeyOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 1)
        if data == b'\r':
            print("CR", flush=True)
        elif data == b'\n':
            print("LF", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }

        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .enter)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("CR") || currentScreen.transcript.contains("LF")
        }

        #expect(screen.transcript.contains("CR"))
        #expect(screen.transcript.contains("LF") == false)
    }

    @Test func liveClaudeRuntimeAcceptsSpecialArrowKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 3)
        if data == b'\x1b[A':
            print("UP", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .upArrow)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("UP")
        }

        #expect(screen.transcript.contains("UP"))
    }

    @Test func liveClaudeRuntimeAcceptsEndOfTransmissionKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 1)
        if data == b'\x04':
            print("EOT", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .endOfTransmission)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("EOT")
        }

        #expect(screen.transcript.contains("EOT"))
    }

    @Test func liveClaudeRuntimeAcceptsInterruptKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 1)
        if data == b'\x03':
            print("INTERRUPT", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .interrupt)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("INTERRUPT")
        }

        #expect(screen.transcript.contains("INTERRUPT"))
    }

    @Test func liveClaudeRuntimeUsesApplicationCursorKeysWhenTerminalRequestsThemOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        sys.stdout.write("\x1b[?1h")
        print("READY", flush=True)
        data = os.read(sys.stdin.fileno(), 3)
        if data == b'\x1bOA':
            print("APPLICATION-UP", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .upArrow)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("APPLICATION-UP") || currentScreen.transcript.contains("\\x1b[A")
        }

        #expect(screen.transcript.contains("APPLICATION-UP"))
    }

    @Test func liveClaudeRuntimeRespondsToCursorPositionReportQueryOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        sys.stdout.write('abc\r\x1b[2B\x1b[5C\x1b[6n')
        sys.stdout.flush()

        data = b''
        while not data.endswith(b'R'):
            data += os.read(sys.stdin.fileno(), 1)

        if data == b'\x1b[3;6R':
            print('CPR', flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("CPR") || currentScreen.transcript.contains("\\x1b[3;6R")
        }

        #expect(screen.transcript.contains("CPR"))
        #expect(screen.transcript.contains("\\x1b[3;6R") == false)
    }

    @Test func liveClaudeRuntimeReceivesTypedTextAndBackspaceOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = b''
        while len(data) < 3:
            data += os.read(sys.stdin.fileno(), 3 - len(data))
        if data == b'ab\x7f':
            print("BACKSPACE", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionText(sessionID: session.id, text: "ab")
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .backspace)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("BACKSPACE")
        }

        #expect(screen.transcript.contains("BACKSPACE"))
    }

    @Test func liveClaudeRuntimeAcceptsForwardDeleteKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        data = b''
        while len(data) < 4:
            data += os.read(sys.stdin.fileno(), 4 - len(data))
        if data == b'\x1b[3~':
            print("DELETE", flush=True)
        else:
            print(repr(data), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .deleteForward)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("DELETE")
        }

        #expect(screen.transcript.contains("DELETE"))
    }

    @Test func liveClaudeRuntimeAcceptsHomeAndEndKeyInputOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try #"""
        #!/usr/bin/env python3
        import os
        import sys
        import tty

        tty.setraw(sys.stdin.fileno())
        print("READY", flush=True)
        first = os.read(sys.stdin.fileno(), 3)
        second = os.read(sys.stdin.fileno(), 3)
        if first == b'\x1b[H' and second == b'\x1b[F':
            print("HOME-END", flush=True)
        else:
            print(repr((first, second)), flush=True)
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("READY")
        }
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .home)
        _ = try await client.sendSessionInputKey(sessionID: session.id, key: .end)
        let screen = try await waitForSessionScreen(client: client, sessionID: session.id) { currentScreen in
            currentScreen.transcript.contains("HOME-END")
        }

        #expect(screen.transcript.contains("HOME-END"))
    }

    @Test func exitedClaudeRuntimeUsesInjectedAdapterExitCopyOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            providerAdapters: [
                .claude: ServiceProviderAdapter(
                    providerID: .claude,
                    supportsDefaultSessionLaunch: true,
                    supportsNamedSessions: true,
                    healthSummaryEvaluator: { workspace, _, _ in
                        ProviderHealthSummary(
                            state: .available,
                            summary: "Claude adapter available for \(workspace.name)",
                            resolvedExecutable: executableURL.path(percentEncoded: false),
                            launchability: .launchable
                        )
                    },
                    terminationStatusMessageBuilder: { status in
                        "\n[Adapter exit status \(status)]\n"
                    }
                )
            ]
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let exitedScreen = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.session.state == .exited
        }

        #expect(exitedScreen.transcript.contains("Claude finished work"))
        #expect(exitedScreen.transcript.contains("[Adapter exit status 0]"))
        #expect(exitedScreen.transcript.contains("Claude exited") == false)
    }

    @Test func exitedClaudeRuntimeBecomesInspectableAndRelaunchableOverIPC() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let exitedScreen = try await waitForSessionScreen(client: client, sessionID: session.id) { screen in
            screen.session.state == .exited
        }
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(exitedScreen.session.id == session.id)
        #expect(exitedScreen.session.state == .exited)
        #expect(exitedScreen.transcript.contains("Claude finished work"))
        #expect(exitedScreen.transcript.contains("Claude exited"))
        #expect(claudeCard.defaultSession.state == .exited)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(claudeCard.defaultSession.sessionID == session.id)
    }

    @Test func persistedReadySessionBecomesRelaunchableAfterServiceRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let healthEvaluator = ProviderHealthEvaluator(
            executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
            commandRunner: StubCommandRunner(results: [
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
            ])
        )

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let overviewAfterRestart = try await restartedClient.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overviewAfterRestart.providerCards.first(where: { $0.provider.id == .claude }))
        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(claudeCard.defaultSession.state == .interrupted)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(claudeCard.defaultSession.sessionID == launchedSession.id)
        #expect(interruptedScreen.session.id == launchedSession.id)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.transcript.contains("service restarted"))
    }

    @Test func interruptedSessionRetainsLastTerminalSizeAfterServiceRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let healthEvaluator = ProviderHealthEvaluator(
            executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
            commandRunner: StubCommandRunner(results: [
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
            ])
        )

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let resizedScreen = try await firstClient.resizeSession(sessionID: launchedSession.id, columns: 132, rows: 40)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(resizedScreen.terminalColumns == 132)
        #expect(resizedScreen.terminalRows == 40)
        #expect(interruptedScreen.session.state == .interrupted)
        #expect(interruptedScreen.terminalColumns == 132)
        #expect(interruptedScreen.terminalRows == 40)
    }

    @Test func interruptedDefaultSessionCanBeRelaunchedAfterServiceRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let healthEvaluator = ProviderHealthEvaluator(
            executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
            commandRunner: StubCommandRunner(results: [
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
            ])
        )

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: healthEvaluator,
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        _ = try await restartedClient.getWorkspaceOverview(workspaceID: workspace.id)

        let relaunchedSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(relaunchedSession.id == launchedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(relaunchedScreen.session.state == .ready)
        #expect(relaunchedScreen.transcript == "Claude ready")
    }

    @Test func interruptedDefaultSessionRelaunchesFromPersistedLaunchSnapshotWhenCurrentHealthIsUnavailable() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let firstRuntimeManager = StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
            "launched with \(executable)"
        })
        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/claude-a"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: firstRuntimeManager
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
                "launched with \(executable)"
            })
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let interruptedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(interruptedScreen.session.state == .interrupted)

        let relaunchedSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let relaunchedScreen = try await restartedClient.getSessionScreen(sessionID: launchedSession.id)

        #expect(relaunchedSession.id == launchedSession.id)
        #expect(relaunchedScreen.session.state == .ready)
        #expect(relaunchedScreen.transcript == "launched with /tmp/claude-a")
    }

    @Test func newSessionsUseUpdatedLaunchConfigWithoutMutatingPersistedLaunchSnapshots() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/claude-a"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/claude-a", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
                "launched with \(executable)"
            })
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        _ = try await firstClient.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await firstClient.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let defaultSession = try await firstClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let restartedService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/claude-b"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/claude-b", arguments: ["--version"]): .success(stdout: "9.9.10 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/claude-b", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForExecutable: { executable in
                "launched with \(executable)"
            })
        )
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)

        let relaunchedDefaultSession = try await restartedClient.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let defaultSessionScreen = try await restartedClient.getSessionScreen(sessionID: defaultSession.id)
        let namedSession = try await restartedClient.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Fresh Session")
        let namedSessionScreen = try await restartedClient.getSessionScreen(sessionID: namedSession.id)

        #expect(relaunchedDefaultSession.id == defaultSession.id)
        #expect(defaultSessionScreen.transcript == "launched with /tmp/claude-a")
        #expect(namedSessionScreen.transcript == "launched with /tmp/claude-b")
    }

    @Test func launchOrResumeDefaultSessionPersistsFailedClaudeSessionWhenLaunchabilityFails() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )

        let session = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let overview = try await client.getWorkspaceOverview(workspaceID: workspace.id)
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(session.state == .failed)
        #expect(session.failureMessage == "Claude executable was not found in the service search paths.")
        #expect(claudeCard.defaultSession.state == .failed)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(claudeCard.defaultSession.summary == "Claude executable was not found in the service search paths.")
        #expect(claudeCard.defaultSession.sessionID == session.id)
    }

    @MainActor
    @Test func appModelLoadsWorkspaceCatalogFromIPCClient() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        _ = try await client.createLocalWorkspace(name: nil, folderPath: "/tmp/app-model-workspace", primaryGroupID: nil)
        let model = NexusAppModel(client: client)

        await model.refresh()

        #expect(model.serviceStatus?.state == .running)
        #expect(model.workspaceGroups.map(\.name) == ["Solo Group"])
        #expect(model.workspaces.map(\.name) == ["app-model-workspace"])
        #expect(model.workspaceOverview(for: try #require(model.workspaces.first).id)?.providerCards.map(\.provider.displayName) == ["Codex", "Claude", "IBM Bob", "Pi"])
    }

    @MainActor
    @Test func appModelLoadsRemoteAccessStateAndPairedDevices() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let pairing = PairingCeremony(
            id: UUID(),
            code: "123456",
            qrPayload: "nexus://pair?code=123456",
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 610)
        )
        let pairedDevice = PairedDevice(id: UUID(), name: "Chris’s iPhone", pairedAt: Date(timeIntervalSince1970: 20))
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            remoteAccessState: RemoteAccessState(isEnabled: true, activePairing: pairing),
            pairedDevices: [pairedDevice]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()

        #expect(model.remoteAccessState == RemoteAccessState(isEnabled: true, activePairing: pairing))
        #expect(model.pairedDevices == [pairedDevice])
    }

    @MainActor
    @Test func appModelLoadsHostsAndCachesHostDetailOnDemand() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let snapshot = HostValidationSnapshot(
            hostID: host.id,
            state: .unavailable,
            summary: "SSH connection timed out",
            checkedAt: Date(timeIntervalSince1970: 123),
            diagnostics: [HostValidationDiagnostic(severity: .error, code: "sshTimedOut", message: "ssh build-box timed out while validating the Host.")]
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            hosts: [host],
            hostDetails: [host.id: HostDetail(host: host, latestValidation: snapshot)]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()

        #expect(model.hosts == [host])
        #expect(model.hostDetail(for: host.id) == nil)

        try await model.loadHostDetail(hostID: host.id)

        #expect(model.hostDetail(for: host.id)?.host == host)
        #expect(model.hostDetail(for: host.id)?.latestValidation == snapshot)
    }

    @MainActor
    @Test func appModelCreateUpdateAndValidateHostRefreshesCachedHostState() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready")
        )
        let model = NexusAppModel(client: client)

        let createdHost = try await model.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)

        #expect(model.hosts == [createdHost])
        #expect(model.hostDetail(for: createdHost.id) == HostDetail(host: createdHost, latestValidation: nil))

        let updatedHost = try await model.updateHost(hostID: createdHost.id, name: "Primary Build Server", sshTarget: "build-box-2", port: nil)

        #expect(model.hosts == [updatedHost])
        #expect(model.hostDetail(for: updatedHost.id) == HostDetail(host: updatedHost, latestValidation: nil))

        let snapshot = try await model.validateHost(hostID: updatedHost.id)

        #expect(snapshot.hostID == updatedHost.id)
        #expect(snapshot.state == .available)
        #expect(snapshot.summary == "Host is available")
        #expect(model.hostDetail(for: updatedHost.id) == HostDetail(host: updatedHost, latestValidation: snapshot))
    }

    @MainActor
    @Test func appModelValidateHostRefreshesRemoteWorkspaceOverview() async throws {
        let sshRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: sshRunner)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let model = NexusAppModel(client: client)

        await model.refresh()

        #expect(model.workspaceOverview(for: workspace.id)?.remoteTarget?.workspaceAvailability.state == .blocked)

        _ = try await model.validateHost(hostID: host.id)

        #expect(model.workspaceOverview(for: workspace.id)?.remoteTarget?.workspaceAvailability.state == .available)
        #expect(model.workspaceOverview(for: workspace.id)?.remoteTarget?.hostValidation?.state == .available)
    }

    @MainActor
    @Test func appModelCreatesRemoteWorkspaceAndFormatsWorkspaceTargetSummary() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Remote")
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let workspace = Workspace(
            id: UUID(),
            name: "Remote API",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: group.id,
            remoteHostID: host.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            hosts: [host]
        )
        let model = NexusAppModel(client: client)

        try await model.refreshHosts()

        let createdWorkspace = try await model.createRemoteWorkspace(
            name: nil,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )

        #expect(createdWorkspace == workspace)
        #expect(model.workspaces == [workspace])
        #expect(model.workspaceOverview(for: workspace.id)?.workspace == workspace)
        #expect(model.workspaceTargetSummary(for: workspace) == "Build Server • /srv/api")
    }

    @MainActor
    @Test func appModelFocusedRemoteSessionContextShowsHostAndRemotePath() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let workspace = Workspace(
            id: UUID(),
            name: "Remote API",
            kind: .remote,
            folderPath: "/srv/api",
            primaryGroupID: group.id,
            remoteHostID: host.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            hosts: [host]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        try await model.focusSession(sessionID: session.id)

        let context = try #require(model.focusedSessionPresentationContext)
        #expect(context.workspace == workspace)
        #expect(context.host == host)
        #expect(context.remotePath == "/srv/api")
        #expect(context.targetSummary == "Build Server • /srv/api")
    }

    @MainActor
    @Test func appModelDetachFocusedSessionClearsScreenAndStopsObservation() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready")
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        try await model.focusSession(sessionID: session.id)
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(client.observedScreenHandlerCount == 1)

        let detachedSession = await model.detachFocusedSession()

        #expect(detachedSession?.id == session.id)
        #expect(model.focusedSessionScreen == nil)
        #expect(client.observedScreenHandlerCount == 0)

        await client.emitObservedScreen(SessionScreen(session: session, transcript: "Detached update"))
        #expect(model.focusedSessionScreen == nil)
    }

    @MainActor
    @Test func appModelFocusedSessionControllerSummaryNamesRemoteController() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let pairedDevice = PairedDevice(id: UUID(), name: "Chris’s iPhone", pairedAt: Date(timeIntervalSince1970: 600))
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, controller: .pairedDevice(pairedDevice.id), transcript: "Claude ready"),
            pairedDevices: [pairedDevice]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        try await model.focusSession(sessionID: session.id)

        #expect(model.focusedSessionControllerSummary == SessionControllerSummary(
            label: "Chris’s iPhone",
            message: "Chris’s iPhone is the Controller. Input on this Mac reclaims Controller."
        ))
    }

    @MainActor
    @Test func appModelDeleteHostRemovesCachedHostState() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let host = NexusDomain.Host(id: UUID(), name: "Build Server", sshTarget: "build-box", port: 2222)
        let snapshot = HostValidationSnapshot(
            hostID: host.id,
            state: .available,
            summary: "Host is available",
            checkedAt: Date(timeIntervalSince1970: 456),
            diagnostics: [HostValidationDiagnostic(severity: .info, code: "sshTarget", message: "Validated build-box")]
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            hosts: [host],
            hostDetails: [host.id: HostDetail(host: host, latestValidation: snapshot)]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        try await model.loadHostDetail(hostID: host.id)

        let deleted = try await model.deleteHost(hostID: host.id)

        #expect(deleted)
        #expect(model.hosts.isEmpty)
        #expect(model.hostDetail(for: host.id) == nil)
    }

    @MainActor
    @Test func appModelLoadsAndUpdatesRecentNavigation() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let workspaceItem = NavigationItem(
            target: .workspace(workspace.id),
            title: workspace.name,
            subtitle: workspace.folderPath
        )
        let sessionItem = NavigationItem(
            target: .session(session.id),
            title: "Default Session",
            subtitle: "\(workspace.name) • Claude"
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: SessionScreen(session: session, transcript: "Claude ready"),
            recentNavigation: [workspaceItem],
            searchResults: [sessionItem]
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        #expect(model.recentNavigation == [workspaceItem])

        try await model.recordNavigation(.session(session.id))
        #expect(model.recentNavigation == [sessionItem, workspaceItem])
        #expect(client.recordedNavigationTargets == [.session(session.id)])

        let searchResults = try await model.searchNavigation(query: "claude")
        #expect(searchResults == [sessionItem])
    }

    @MainActor
    @Test func appModelLaunchOrResumePiSessionFocusesStructuredActivityFeed() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let launcher = ProcessSessionRuntimeLauncher(localProtocolNativeRuntimeFactories: [.pi: { launchConfiguration, _, _ in
            try PiRPCSessionRuntime(
                executable: launchConfiguration.executable,
                workingDirectory: launchConfiguration.workingDirectory,
                terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                transportFactory: { _, _, _ in
                    NexusTestsPiRPCTransport(promptResponseText: "world")
                }
            )
        }])

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        try await model.sendInputToFocusedSession("hello")

        let screen = try #require(model.focusedSessionScreen)
        #expect(focusedSessionSurface(for: screen) == .structuredActivityFeed)
        #expect(screen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: world"
        ])
    }

    @MainActor
    @Test func appModelKeepsTerminalBackedProvidersOnTerminalSurfacesAlongsidePiSessionSurfaces() async throws {
        final class CompatibilityStaticSessionRuntime: SessionRuntime, @unchecked Sendable {
            var state: Session.State = .ready
            var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { nil }

            private let primarySurface: SessionSurface
            private let transcript: String
            private let activityItems: [SessionActivityItem]

            init(primarySurface: SessionSurface = .terminal, transcript: String, activityItems: [SessionActivityItem] = []) {
                self.primarySurface = primarySurface
                self.transcript = transcript
                self.activityItems = activityItems
            }

            func sessionScreen(for session: Session) -> SessionScreen {
                SessionScreen(
                    session: Session(
                        id: session.id,
                        workspaceID: session.workspaceID,
                        providerID: session.providerID,
                        name: session.name,
                        isDefault: session.isDefault,
                        state: state,
                        failureMessage: session.failureMessage
                    ),
                    primarySurface: primarySurface,
                    transcript: transcript,
                    activityItems: activityItems
                )
            }

            func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
            func stop() throws { state = .exited }
            func sendInput(_ text: String) throws {}
            func sendText(_ text: String) throws {}
            func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
            func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}
            func resize(columns: Int, rows: Int) throws {}
        }

        struct CompatibilitySessionRuntimeLauncher: SessionRuntimeLaunching {
            func makeRuntime(
                session: Session,
                workspace: Workspace,
                launchConfiguration: SessionRuntimeLaunchConfiguration
            ) throws -> any SessionRuntime {
                switch session.providerID {
                case .claude:
                    CompatibilityStaticSessionRuntime(transcript: "Claude ready")
                case .codex:
                    CompatibilityStaticSessionRuntime(primarySurface: .structuredActivityFeed, transcript: "Codex ready")
                case .pi:
                    CompatibilityStaticSessionRuntime(
                        transcript: "",
                        activityItems: [SessionActivityItem(kind: .status, text: "Pi shared Session stream connected")]
                    )
                case .ibmBob:
                    CompatibilityStaticSessionRuntime(transcript: "")
                }
            }
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [
                    "claude": "/tmp/fake-claude",
                    "codex": "/tmp/fake-codex",
                    "pi": "/tmp/fake-pi"
                ]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-claude' '--version'"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-claude' '--help'"]): .success(stdout: "Usage: claude\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-codex' '--version'"]): .success(stdout: "1.2.3\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-codex' '--help'"]): .success(stdout: "Usage: codex\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"]),
                codexReadinessProbe: NoOpCodexReadinessProbe()
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: CompatibilitySessionRuntimeLauncher())
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .codex)
        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .pi)

        let claudeSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let initialClaudeScreen = try #require(model.focusedSessionScreen)
        #expect(initialClaudeScreen.session.id == claudeSession.id)
        #expect(focusedSessionSurface(for: initialClaudeScreen) == .terminal)
        #expect(initialClaudeScreen.transcript == "Claude ready")

        let piSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)
        let piScreen = try #require(model.focusedSessionScreen)
        #expect(piScreen.session.id == piSession.id)
        #expect(focusedSessionSurface(for: piScreen) == .structuredActivityFeed)
        #expect(piScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])

        try await model.focusSession(sessionID: claudeSession.id)
        try await model.loadSessionScreen(sessionID: claudeSession.id)
        let resumedClaudeScreen = try #require(model.focusedSessionScreen)
        #expect(resumedClaudeScreen.session.id == claudeSession.id)
        #expect(focusedSessionSurface(for: resumedClaudeScreen) == .terminal)
        #expect(resumedClaudeScreen.transcript == "Claude ready")

        let codexSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .codex)
        let codexScreen = try #require(model.focusedSessionScreen)
        #expect(codexScreen.session.id == codexSession.id)
        #expect(focusedSessionSurface(for: codexScreen) == .structuredActivityFeed)
        #expect(codexScreen.transcript == "Codex ready")

        try await model.focusSession(sessionID: piSession.id)
        try await model.loadSessionScreen(sessionID: piSession.id)
        let refocusedPiScreen = try #require(model.focusedSessionScreen)
        #expect(refocusedPiScreen.session.id == piSession.id)
        #expect(focusedSessionSurface(for: refocusedPiScreen) == .structuredActivityFeed)
        #expect(refocusedPiScreen.activityItems.map(\.text) == ["Pi shared Session stream connected"])

        let overview = try #require(model.workspaceOverview(for: workspace.id))
        let claudeCard = try #require(overview.providerCards.first(where: { $0.provider.id == .claude }))
        let codexCard = try #require(overview.providerCards.first(where: { $0.provider.id == .codex }))
        let piCard = try #require(overview.providerCards.first(where: { $0.provider.id == .pi }))
        let claudeDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        let codexDetail = try #require(model.providerDetail(for: workspace.id, providerID: .codex))
        let piDetail = try #require(model.providerDetail(for: workspace.id, providerID: .pi))

        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
        #expect(codexCard.defaultSession.state == .ready)
        #expect(codexCard.defaultSession.actionTitle == "Resume")
        #expect(piCard.defaultSession.state == .ready)
        #expect(piCard.defaultSession.actionTitle == "Resume")

        #expect(claudeDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(claudeDetail.capabilities.createNamedSession.isEnabled)
        #expect(claudeDetail.defaultSession?.id == claudeSession.id)
        #expect(codexDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(codexDetail.capabilities.createNamedSession.isEnabled)
        #expect(codexDetail.defaultSession?.id == codexSession.id)
        #expect(piDetail.capabilities.launchDefaultSession.isEnabled)
        #expect(piDetail.capabilities.createNamedSession.isEnabled)
        #expect(piDetail.defaultSession?.id == piSession.id)
    }

    @MainActor
    @Test func appModelShowsInterruptedPiRestartCopyForInspectableLostRuntimeSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        func makeService() throws -> NexusService {
            let launcher = ProcessSessionRuntimeLauncher(localProtocolNativeRuntimeFactories: [.pi: { launchConfiguration, _, _ in
                try PiRPCSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.piSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    transportFactory: { _, _, _ in
                        NexusTestsPiRPCTransport(promptResponseText: "world")
                    }
                )
            }])

            return try NexusService.bootstrapForTests(
                rootURL: rootURL,
                providerHealthEvaluator: ProviderHealthEvaluator(
                    executableResolver: StubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                    commandRunner: StubCommandRunner(results: [
                        StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                        StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                    ]),
                    localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
                ),
                sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
            )
        }

        let service = try makeService()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let launchedSession = try await client.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .pi)

        let restartedService = try makeService()
        let restartedClient = try NexusIPCClient.connect(to: restartedService.listenerEndpoint)
        let model = NexusAppModel(client: restartedClient)
        let expectedMessage = "Pi Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."

        await model.refresh()
        try await model.focusSession(sessionID: launchedSession.id)

        let piCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .pi }))
        let screen = try #require(model.focusedSessionScreen)

        #expect(piCard.defaultSession.state == .interrupted)
        #expect(piCard.defaultSession.summary == expectedMessage)
        #expect(focusedSessionSurface(for: screen) == .structuredActivityFeed)
        #expect(screen.session.state == .interrupted)
        #expect(screen.activityItems.map(\.kind) == [.error])
        #expect(screen.activityItems.map(\.text) == [expectedMessage])
        #expect(structuredSessionActivityRows(for: screen).map(\.title) == ["Error"])
        #expect(structuredSessionActivityRows(for: screen).map(\.text) == [expectedMessage])
    }

    @MainActor
    @Test func appModelPiNamedSessionLifecycleRefreshesProviderDetailAndClearsFocusAfterDelete() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let launcher = ProcessSessionRuntimeLauncher(localProtocolNativeRuntimeFactories: [.pi: { launchConfiguration, _, _ in
            try PiRPCSessionRuntime(
                executable: launchConfiguration.executable,
                workingDirectory: launchConfiguration.workingDirectory,
                sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.piSessionLinkage,
                terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                transportFactory: { _, _, _ in
                    NexusTestsPiRPCTransport(promptResponseText: "world")
                }
            )
        }])

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["pi": "/tmp/fake-pi"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--version'"]): .success(stdout: "0.9.0\n"),
                    StubCommandRunner.Invocation(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-pi' '--help'"]): .success(stdout: "Usage: pi\n")
                ]),
                localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
            ),
            sessionRuntimeManager: InMemorySessionRuntimeManager(launcher: launcher)
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let namedSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .pi, name: "Review")
        try await model.sendInputToFocusedSession("hello")

        let stoppedSession = try await model.stopSession(
            sessionID: namedSession.id,
            workspaceID: workspace.id,
            providerID: .pi
        )
        let stoppedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .pi))
        let stoppedScreen = try #require(model.focusedSessionScreen)

        let relaunchedSession = try await model.relaunchFocusedSession()
        let relaunchedScreen = try #require(model.focusedSessionScreen)
        _ = try await model.stopSession(sessionID: namedSession.id, workspaceID: workspace.id, providerID: .pi)
        let deleted = try await model.deleteSessionRecord(
            sessionID: namedSession.id,
            workspaceID: workspace.id,
            providerID: .pi
        )
        let deletedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .pi))
        let piCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .pi }))

        #expect(namedSession.providerID == .pi)
        #expect(namedSession.name == "Review")
        #expect(namedSession.isDefault == false)
        #expect(focusedSessionSurface(for: stoppedScreen) == .structuredActivityFeed)
        #expect(stoppedSession.state == .exited)
        #expect(stoppedDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(stoppedDetail.alternateSessions.first?.state == .exited)
        #expect(stoppedScreen.session.state == .exited)
        #expect(stoppedScreen.activityItems.map(\.text) == [
            "Pi shared Session stream connected",
            "You: hello",
            "Pi: world"
        ])
        #expect(relaunchedSession.id == namedSession.id)
        #expect(relaunchedSession.state == .ready)
        #expect(focusedSessionSurface(for: relaunchedScreen) == .structuredActivityFeed)
        #expect(deleted)
        #expect(model.focusedSessionScreen == nil)
        #expect(deletedDetail.alternateSessions.isEmpty)
        #expect(piCard.alternateSessionCount == 0)
    }

    @MainActor
    @Test func appModelLaunchOrResumeDefaultSessionRefreshesWorkspaceOverview() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let session = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.transcript == "Claude ready")
    }

    @MainActor
    @Test func appModelCreateNamedSessionRefreshesProviderDetailAndFocusesNewSession() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let defaultSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let workspaceOverview = WorkspaceOverview(
            workspace: workspace,
            providerCards: [
                WorkspaceProviderCard(
                    provider: Provider(id: .claude),
                    health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .ready,
                        summary: "Default session ready",
                        actionTitle: "Resume",
                        sessionID: defaultSession.id
                    )
                )
            ]
        )
        let providerDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: defaultSession,
            alternateSessions: [],
            failedSessions: []
        )
        let client = TrackingServiceClient(
            workspaceOverview: workspaceOverview,
            session: defaultSession,
            screen: SessionScreen(session: defaultSession, transcript: "Claude ready"),
            providerDetail: providerDetail
        )
        let model = NexusAppModel(client: client)

        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let namedSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude)

        let refreshedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first)
        #expect(namedSession.isDefault == false)
        #expect(namedSession.name == "Session 1")
        #expect(model.focusedSessionScreen?.session.id == namedSession.id)
        #expect(refreshedDetail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(claudeCard.alternateSessionCount == 1)
    }

    @MainActor
    @Test func appModelStopSessionRefreshesProviderDetail() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let defaultSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let namedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .ready
        )
        let workspaceOverview = WorkspaceOverview(
            workspace: workspace,
            providerCards: [
                WorkspaceProviderCard(
                    provider: Provider(id: .claude),
                    health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .ready,
                        summary: "Default session ready",
                        actionTitle: "Resume",
                        sessionID: defaultSession.id
                    ),
                    alternateSessionCount: 1
                )
            ]
        )
        let providerDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: defaultSession,
            alternateSessions: [namedSession],
            failedSessions: []
        )
        let client = TrackingServiceClient(
            workspaceOverview: workspaceOverview,
            session: namedSession,
            screen: SessionScreen(session: namedSession, transcript: "Claude ready"),
            providerDetail: providerDetail
        )
        let model = NexusAppModel(client: client)

        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let stoppedSession = try await model.stopSession(sessionID: namedSession.id, workspaceID: workspace.id, providerID: .claude)

        let refreshedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        #expect(stoppedSession.state == .exited)
        #expect(refreshedDetail.alternateSessions.first?.id == namedSession.id)
        #expect(refreshedDetail.alternateSessions.first?.state == .exited)
    }

    @MainActor
    @Test func appModelDeleteSessionRecordRefreshesProviderDetailAndWorkspaceOverview() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let defaultSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let stoppedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Session 1",
            isDefault: false,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        let workspaceOverview = WorkspaceOverview(
            workspace: workspace,
            providerCards: [
                WorkspaceProviderCard(
                    provider: Provider(id: .claude),
                    health: ProviderHealthSummary(state: .available, summary: "Claude available"),
                    defaultSession: ProviderDefaultSessionSummary(
                        state: .ready,
                        summary: "Default session ready",
                        actionTitle: "Resume",
                        sessionID: defaultSession.id
                    ),
                    alternateSessionCount: 1
                )
            ]
        )
        let providerDetail = ProviderDetail(
            workspace: workspace,
            provider: Provider(id: .claude),
            health: ProviderHealthSummary(state: .available, summary: "Claude available"),
            defaultSession: defaultSession,
            alternateSessions: [stoppedSession],
            failedSessions: []
        )
        let client = TrackingServiceClient(
            workspaceOverview: workspaceOverview,
            session: stoppedSession,
            screen: SessionScreen(session: stoppedSession, transcript: "Claude ready"),
            providerDetail: providerDetail
        )
        let model = NexusAppModel(client: client)

        try await model.loadProviderDetail(workspaceID: workspace.id, providerID: .claude)
        let deleted = try await model.deleteSessionRecord(sessionID: stoppedSession.id, workspaceID: workspace.id, providerID: .claude)

        let refreshedDetail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        let refreshedCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first)
        #expect(deleted)
        #expect(refreshedDetail.alternateSessions.isEmpty)
        #expect(refreshedCard.alternateSessionCount == 0)
    }

    @MainActor
    @Test func appModelLaunchOrResumeFailedSessionShowsInspectableFailureScreen() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: [:]),
                commandRunner: StubCommandRunner(results: [:])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let session = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(session.state == .failed)
        #expect(claudeCard.defaultSession.state == .failed)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
        #expect(model.focusedSessionScreen?.session.id == session.id)
        #expect(model.focusedSessionScreen?.session.state == .failed)
        #expect(model.focusedSessionScreen?.transcript == "Claude executable was not found in the service search paths.")
    }

    @MainActor
    @Test func appModelRefreshesExitedFocusedSessionAndWorkspaceOverview() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import time
        time.sleep(0.2)
        print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let session = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let readyCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(readyCard.defaultSession.state == .ready)

        let exitedScreen = try await waitForFocusedSessionScreen(model: model, sessionID: session.id) { screen in
            screen.session.state == .exited
        }

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(exitedScreen.session.id == session.id)
        #expect(exitedScreen.session.state == .exited)
        #expect(exitedScreen.transcript.contains("Claude finished work"))
        #expect(claudeCard.defaultSession.state == .exited)
        #expect(claudeCard.defaultSession.actionTitle == "Relaunch")
    }

    @MainActor
    @Test func appModelCanRelaunchExitedFocusedSession() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try """
        #!/usr/bin/env python3
        import os
        import pathlib
        import time

        state_path = pathlib.Path(os.environ["NEXUS_RELAUNCH_STATE_FILE"])
        if state_path.exists():
            print("Claude relaunched", flush=True)
            time.sleep(2)
        else:
            state_path.write_text("relaunched")
            print("Claude finished work", flush=True)
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path(percentEncoded: false))

        setenv("NEXUS_RELAUNCH_STATE_FILE", stateFileURL.path(percentEncoded: false), 1)
        defer { unsetenv("NEXUS_RELAUNCH_STATE_FILE") }

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": executableURL.path(percentEncoded: false)]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: executableURL.path(percentEncoded: false), arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            )
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let firstSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForFocusedSessionScreen(model: model, sessionID: firstSession.id) { screen in
            screen.session.state == .exited
        }

        let relaunchedSession = try await model.relaunchFocusedSession()
        let readyScreen = try await waitForFocusedSessionScreen(model: model, sessionID: relaunchedSession.id) { screen in
            screen.session.state == .ready && screen.transcript.contains("Claude relaunched")
        }

        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))
        #expect(relaunchedSession.id == firstSession.id)
        #expect(readyScreen.session.state == .ready)
        #expect(readyScreen.transcript.contains("Claude relaunched"))
        #expect(claudeCard.defaultSession.state == .ready)
        #expect(claudeCard.defaultSession.actionTitle == "Resume")
    }

    @MainActor
    @Test func appModelCanRelaunchExitedFocusedRemoteNamedSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let availabilityRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    "cd '/srv/api' && pwd"
                ]
            ): .success(stdout: "/srv/api\n")
        ])
        let providerHealthRunner = StubCommandRunner(results: [
            StubCommandRunner.Invocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "build-box",
                    remoteClaudeProbeScript("/srv/api")
                ]
            ): .success(stdout: "/usr/local/bin/claude\n9.9.9 (Claude Code)\n")
        ])
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: providerHealthRunner
            ),
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: [
                "build-box": HostValidationResult(
                    state: .available,
                    summary: "Host is available",
                    diagnostics: []
                )
            ]),
            workspaceAvailabilityEvaluator: WorkspaceAvailabilityEvaluator(commandRunner: availabilityRunner),
            sessionRuntimeManager: StubSessionRuntimeManager(launchTranscriptForConfiguration: { _, session, _ in
                "session:\(session.id.uuidString.lowercased())"
            })
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let group = try await client.createWorkspaceGroup(name: "Remote")
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: nil as Int?)
        _ = try await client.validateHost(hostID: host.id)
        let workspace = try await client.createRemoteWorkspace(
            name: nil as String?,
            hostID: host.id,
            remotePath: "/srv/api",
            primaryGroupID: group.id
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        let defaultSession = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        let namedSession = try await model.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Review")
        _ = try await model.stopSession(sessionID: namedSession.id, workspaceID: workspace.id, providerID: .claude)
        _ = try await waitForFocusedSessionScreen(model: model, sessionID: namedSession.id) { screen in
            screen.session.state == .exited
        }

        let relaunchedSession = try await model.relaunchFocusedSession()
        let readyScreen = try await waitForFocusedSessionScreen(model: model, sessionID: namedSession.id) { screen in
            screen.session.state == .ready
        }
        let detail = try #require(model.providerDetail(for: workspace.id, providerID: .claude))
        let claudeCard = try #require(model.workspaceOverview(for: workspace.id)?.providerCards.first(where: { $0.provider.id == .claude }))

        #expect(relaunchedSession.id == namedSession.id)
        #expect(relaunchedSession.id != defaultSession.id)
        #expect(readyScreen.session.id == namedSession.id)
        #expect(readyScreen.transcript == "session:\(namedSession.id.uuidString.lowercased())")
        #expect(detail.defaultSession?.id == defaultSession.id)
        #expect(detail.alternateSessions.map(\.id) == [namedSession.id])
        #expect(claudeCard.alternateSessionCount == 1)
    }

    @MainActor
    @Test func appModelSendInputUpdatesFocusedSessionTranscript() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        try await model.sendInputToFocusedSession("status")

        #expect(model.focusedSessionScreen?.transcript.contains("> status") == true)
        #expect(model.focusedSessionScreen?.transcript.contains("Claude acknowledged: status") == true)
    }

    @MainActor
    @Test func appModelSendInputKeyUpdatesFocusedSessionTranscript() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        try await model.sendInputKeyToFocusedSession(.tab)

        #expect(model.focusedSessionScreen?.transcript.contains("[key: tab]") == true)
    }

    @MainActor
    @Test func appModelSendTypedTextUpdatesFocusedSessionTranscript() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        try await model.sendTypedTextToFocusedSession("abc")

        #expect(model.focusedSessionScreen?.transcript.contains("[typed: abc]") == true)
    }

    @MainActor
    @Test func appModelFocusSessionStreamRefreshesWorkspaceOverviewOnlyOnStateChanges() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let readySession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let initialScreen = SessionScreen(session: readySession, transcript: "Claude ready")
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: readySession,
            screen: initialScreen
        )
        let model = NexusAppModel(client: client)

        try await model.focusSession(sessionID: readySession.id)
        #expect(model.focusedSessionScreen == initialScreen)
        #expect(client.workspaceOverviewRequestCount == 0)

        await client.emitObservedScreen(SessionScreen(session: readySession, transcript: "Claude ready[typed: abc]"))
        let readyScreen = try await waitForObservedFocusedSessionScreen(model: model) { screen in
            screen.transcript.contains("[typed: abc]")
        }

        #expect(readyScreen.session.state == .ready)
        #expect(client.workspaceOverviewRequestCount == 0)

        let exitedSession = Session(
            id: readySession.id,
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        await client.emitObservedScreen(SessionScreen(session: exitedSession, transcript: "Claude streamed update"))
        let exitedScreen = try await waitForObservedFocusedSessionScreen(model: model) { screen in
            screen.session.state == .exited
        }
        try await waitUntil {
            client.workspaceOverviewRequestCount == 1
        }

        #expect(exitedScreen.transcript == "Claude streamed update")
        #expect(client.workspaceOverviewRequestCount == 1)
    }

    @MainActor
    @Test func appModelLoadSessionScreenDoesNotRefreshWorkspaceOverviewDuringTerminalPolling() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(session: session, transcript: "Claude ready")
        let client = TrackingServiceClient(workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []), session: session, screen: screen)
        let model = NexusAppModel(client: client)

        try await model.loadSessionScreen(sessionID: session.id)

        #expect(model.focusedSessionScreen == screen)
        #expect(client.workspaceOverviewRequestCount == 0)
    }

    @MainActor
    @Test func appModelSendTypedTextDoesNotRefreshWorkspaceOverviewWhileTyping() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        let initialScreen = SessionScreen(session: session, transcript: "Claude ready")
        let client = TrackingServiceClient(workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []), session: session, screen: initialScreen)
        let model = NexusAppModel(client: client)
        model.focusedSessionScreen = initialScreen

        try await model.sendTypedTextToFocusedSession("abc")

        #expect(model.focusedSessionScreen?.transcript == "Claude ready[typed: abc]")
        #expect(client.workspaceOverviewRequestCount == 0)
    }

    @MainActor
    @Test func appModelRespondsToFocusedSessionApprovalRequestThroughServiceClient() async throws {
        let group = WorkspaceGroup(id: UUID(), name: "Group")
        let workspace = Workspace(
            id: UUID(),
            name: "Workspace",
            kind: .local,
            folderPath: "/tmp/workspace",
            primaryGroupID: group.id
        )
        let session = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let approvalRequest = SessionApprovalRequest(
            id: UUID(),
            title: "Deploy to production?",
            text: "Pi wants to run deploy --prod.",
            state: .pending
        )
        let initialScreen = SessionScreen(
            session: session,
            transcript: "> deploy",
            activityItems: [SessionActivityItem(kind: .approvalRequest, text: "Approval Request: Deploy to production?")],
            approvalRequests: [approvalRequest]
        )
        let client = TrackingServiceClient(
            workspaceOverview: WorkspaceOverview(workspace: workspace, providerCards: []),
            session: session,
            screen: initialScreen
        )
        let model = NexusAppModel(client: client)
        model.focusedSessionScreen = initialScreen

        try await model.respondToFocusedSessionApprovalRequest(approvalRequest.id, decision: .approve)

        #expect(client.respondedApprovalRequests.count == 1)
        #expect(client.respondedApprovalRequests[0].sessionID == session.id)
        #expect(client.respondedApprovalRequests[0].approvalRequestID == approvalRequest.id)
        #expect(client.respondedApprovalRequests[0].decision == .approve)
        #expect(model.focusedSessionScreen?.approvalRequests == [
            SessionApprovalRequest(
                id: approvalRequest.id,
                title: approvalRequest.title,
                text: approvalRequest.text,
                state: .approved
            )
        ])
    }

    @MainActor
    @Test func appModelResizeFocusedSessionUpdatesTerminalDimensions() async throws {
        let workspaceFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolderURL, withIntermediateDirectories: true)

        let service = try NexusService.bootstrapForTests(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("NexusTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            providerHealthEvaluator: ProviderHealthEvaluator(
                executableResolver: StubExecutableResolver(executables: ["claude": "/tmp/fake-claude"]),
                commandRunner: StubCommandRunner(results: [
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--version"]): .success(stdout: "9.9.9 (Claude Code)\n"),
                    StubCommandRunner.Invocation(executable: "/tmp/fake-claude", arguments: ["--help"]): .success(stdout: "Usage: claude\n")
                ])
            ),
            sessionRuntimeManager: StubSessionRuntimeManager(initialTranscript: "Claude ready")
        )
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        _ = try await client.createWorkspaceGroup(name: "Solo Group")
        let workspace = try await client.createLocalWorkspace(
            name: nil,
            folderPath: workspaceFolderURL.path(percentEncoded: false),
            primaryGroupID: nil
        )
        let model = NexusAppModel(client: client)

        await model.refresh()
        _ = try await model.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)
        try await model.resizeFocusedSession(columns: 100, rows: 30)

        #expect(model.focusedSessionScreen?.terminalColumns == 100)
        #expect(model.focusedSessionScreen?.terminalRows == 30)
        #expect(model.focusedSessionScreen?.transcript == "Claude ready")
    }

    @MainActor
    @Test func appModelReportsUnavailableServiceWhenStatusRefreshFails() async {
        let model = NexusAppModel(client: FailingServiceClient())

        await model.refreshServiceStatus()

        #expect(model.serviceStatus == nil)
        #expect(model.serviceErrorMessage == "Background Service unavailable")
        #expect(model.workspaceGroups.isEmpty)
        #expect(model.workspaces.isEmpty)
        #expect(model.hosts.isEmpty)
        #expect(model.workspaceOverviews.isEmpty)
    }

    @MainActor
    @Test func liveAppModelBootstrapsEmbeddedBackgroundServiceAndLoadsStatus() async throws {
        let model = try NexusAppModel.live(listeningPort: nil)

        await model.refreshServiceStatus()

        let status = try #require(model.serviceStatus)
        #expect(status.state == .running)
        #expect(status.store.kind == .sqlite)
        #expect(status.store.owner == .backgroundService)
        #expect(status.store.location.path(percentEncoded: false).contains("Application Support"))
        #expect(status.store.location.lastPathComponent == "Nexus.sqlite")
        #expect(model.serviceErrorMessage == nil)
    }

    @Test func hostManagementCreatesListsAndPersistsHostsOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let firstService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)

        let createdHost = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        let listedHosts = try await firstClient.listHosts()

        #expect(createdHost.name == "Build Server")
        #expect(createdHost.sshTarget == "build-box")
        #expect(createdHost.port == 2222)
        #expect(listedHosts == [createdHost])

        let secondService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedHosts = try await secondClient.listHosts()
        let detail = try await secondClient.getHostDetail(hostID: createdHost.id)

        #expect(persistedHosts == [createdHost])
        #expect(detail.host == createdHost)
        #expect(detail.latestValidation == nil)
    }

    @Test func hostValidationPersistsLatestSnapshotAndDiagnosticsOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let validation = HostValidationResult(
            state: .unavailable,
            summary: "SSH connection timed out",
            diagnostics: [
                HostValidationDiagnostic(
                    severity: .error,
                    code: "sshTimedOut",
                    message: "ssh build-box timed out while validating the Host."
                )
            ]
        )

        let firstService = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            hostValidationEvaluator: StubHostValidationEvaluator(resultsByTarget: ["build-box": validation])
        )
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)

        let snapshot = try await firstClient.validateHost(hostID: host.id)
        let detail = try await firstClient.getHostDetail(hostID: host.id)

        #expect(snapshot.hostID == host.id)
        #expect(snapshot.state == .unavailable)
        #expect(snapshot.summary == "SSH connection timed out")
        #expect(snapshot.diagnostics == validation.diagnostics)
        #expect(detail.latestValidation == snapshot)

        let secondService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedDetail = try await secondClient.getHostDetail(hostID: host.id)

        #expect(persistedDetail.latestValidation == snapshot)
    }

    @Test func hostEditingUpdatesPersistedFieldsAndClearsStaleValidationOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let service = try NexusService.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let host = try await client.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try await client.validateHost(hostID: host.id)

        let updatedHost = try await client.updateHost(
            hostID: host.id,
            name: "Primary Build Server",
            sshTarget: "build-box-2",
            port: nil
        )
        let detail = try await client.getHostDetail(hostID: host.id)

        #expect(updatedHost.id == host.id)
        #expect(updatedHost.name == "Primary Build Server")
        #expect(updatedHost.sshTarget == "build-box-2")
        #expect(updatedHost.port == nil)
        #expect(detail.host == updatedHost)
        #expect(detail.latestValidation == nil)

        let secondService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)
        let persistedDetail = try await secondClient.getHostDetail(hostID: host.id)

        #expect(persistedDetail.host == updatedHost)
        #expect(persistedDetail.latestValidation == nil)
    }

    @Test func hostDeletionRemovesPersistedHostAndValidationOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let firstService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let firstClient = try NexusIPCClient.connect(to: firstService.listenerEndpoint)
        let host = try await firstClient.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try await firstClient.validateHost(hostID: host.id)

        let deleted = try await firstClient.deleteHost(hostID: host.id)
        let listedHosts = try await firstClient.listHosts()

        #expect(deleted)
        #expect(listedHosts.isEmpty)

        let secondService = try NexusService.bootstrapForTests(rootURL: rootURL)
        let secondClient = try NexusIPCClient.connect(to: secondService.listenerEndpoint)

        #expect(try await secondClient.listHosts().isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await secondClient.getHostDetail(hostID: host.id)
        }
    }

    @Test func hostDeletionShowsBlockingRemoteWorkspaceDependenciesOverIPC() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        FileManager.default.createFile(atPath: storeURL.path, contents: Data())
        let store = try NexusMetadataStore(storeURL: storeURL)
        let group = try store.createWorkspaceGroup(name: "Remote")
        let host = try store.createHost(name: "Build Server", sshTarget: "build-box", port: 2222)
        _ = try store.createRemoteWorkspace(name: "Remote API", hostID: host.id, remotePath: "/srv/api", primaryGroupID: group.id)

        let service = try NexusService.bootstrapForTests(rootURL: rootURL)
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        do {
            _ = try await client.deleteHost(hostID: host.id)
            Issue.record("Expected Host deletion to be blocked by a Remote Workspace reference")
        } catch {
            #expect(error.localizedDescription == "Host is still referenced by Remote Workspaces: Remote API (/srv/api)")
        }

        #expect(try await client.listHosts() == [host])
    }
}

private func waitForSessionScreen(
    client: any NexusServiceClient,
    sessionID: UUID,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    var latestScreen = try await client.getSessionScreen(sessionID: sessionID)

    while predicate(latestScreen) == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for session screen update: \(latestScreen.transcript)"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        latestScreen = try await client.getSessionScreen(sessionID: sessionID)
    }

    return latestScreen
}

@MainActor
private func waitForFocusedSessionScreen(
    model: NexusAppModel,
    sessionID: UUID,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    try await model.loadSessionScreen(sessionID: sessionID)
    var latestScreen = try #require(model.focusedSessionScreen)

    while predicate(latestScreen) == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for focused session screen update: \(latestScreen.transcript)"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        try await model.loadSessionScreen(sessionID: sessionID)
        latestScreen = try #require(model.focusedSessionScreen)
    }

    return latestScreen
}

@MainActor
private func waitForObservedFocusedSessionScreen(
    model: NexusAppModel,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping (SessionScreen) -> Bool
) async throws -> SessionScreen {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    var latestScreen = try #require(model.focusedSessionScreen)

    while predicate(latestScreen) == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for observed focused session update: \(latestScreen.transcript)"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        latestScreen = try #require(model.focusedSessionScreen)
    }

    return latestScreen
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    until predicate: @escaping @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

    while predicate() == false {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition"])
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

private func legacyRemoteClaudeProbeScript(_ workspacePath: String) -> String {
    "cd \(testShellQuoted(workspacePath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; command -v tmux >/dev/null 2>&1 || { echo 'NEXUS_REMOTE_TMUX_UNAVAILABLE' >&2; exit 1; }; CLAUDE_PATH=\"$(command -v claude)\" || { echo 'NEXUS_REMOTE_CLAUDE_NOT_FOUND' >&2; exit 1; }; printf '%s\\n' \"$CLAUDE_PATH\"; \"$CLAUDE_PATH\" --version; \"$CLAUDE_PATH\" --help >/dev/null 2>&1"
}

func remoteClaudeProbeScript(_ workspacePath: String) -> String {
    remoteCLIProbeScript(workspacePath, commandName: "claude")
}

func remoteCodexProbeScript(_ workspacePath: String) -> String {
    remoteCLIProbeScript(workspacePath, commandName: "codex")
}

private func remoteCLIProbeScript(_ workspacePath: String, commandName: String) -> String {
    let commandPathVariable = "\(commandName.uppercased())_PATH"
    let resolveFunctionName = "resolve_\(commandName)_path"
    let notFoundMarker = "NEXUS_REMOTE_\(commandName.uppercased())_NOT_FOUND"
    let shellCommand = testShellQuoted("command -v \(commandName)")
    let fallbackCandidates = [
        "$HOME/.local/bin/\(commandName)",
        "$HOME/bin/\(commandName)",
        "$HOME/.volta/bin/\(commandName)",
        "$HOME/.asdf/shims/\(commandName)",
        "$HOME/.local/share/mise/shims/\(commandName)",
        "$HOME/.nix-profile/bin/\(commandName)",
        "$HOME/.bun/bin/\(commandName)",
        "$HOME/.nvm/current/bin/\(commandName)",
        "/opt/homebrew/bin/\(commandName)",
        "/usr/local/bin/\(commandName)",
        "/usr/bin/\(commandName)",
        "/bin/\(commandName)"
    ].map { "\"\($0)\"" }.joined(separator: " ")
    let shellCandidates = ["\"${SHELL:-}\"", "\"/bin/zsh\"", "\"/usr/bin/zsh\"", "\"/bin/bash\"", "\"/usr/bin/bash\"", "\"/bin/sh\"", "\"/usr/bin/sh\"", "\"/bin/ksh\"", "\"/usr/bin/ksh\"", "\"/bin/dash\"", "\"/usr/bin/dash\"", "\"/bin/csh\"", "\"/usr/bin/csh\"", "\"/bin/tcsh\"", "\"/usr/bin/tcsh\"", "\"/opt/homebrew/bin/fish\"", "\"/usr/local/bin/fish\"", "\"/usr/bin/fish\"", "\"/bin/fish\"", "$(grep '^/' /etc/shells 2>/dev/null)"]
        .joined(separator: " ")

    return "cd \(testShellQuoted(workspacePath)) || { echo 'NEXUS_REMOTE_WORKSPACE_UNAVAILABLE' >&2; exit 1; }; command -v tmux >/dev/null 2>&1 || { echo 'NEXUS_REMOTE_TMUX_UNAVAILABLE' >&2; exit 1; }; \(resolveFunctionName)() { for shell in \(shellCandidates); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; case \"${shell##*/}\" in csh|tcsh) CANDIDATE=\"$(\"$shell\" -i -c \"if ( -f ~/.login ) source ~/.login; command -v \(commandName)\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"if ( -f ~/.login ) source ~/.login; command -v \(commandName)\" 2>/dev/null)\" || continue ;; fish) CANDIDATE=\"$(\"$shell\" -i -c \"command -v \(commandName)\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -l -c \"command -v \(commandName)\" 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -c \"command -v \(commandName)\" 2>/dev/null)\" || continue ;; *) CANDIDATE=\"$(\"$shell\" -lic \(shellCommand) 2>/dev/null)\" || CANDIDATE=\"$(\"$shell\" -lc \(shellCommand) 2>/dev/null)\" || continue ;; esac; [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; for CANDIDATE in \(fallbackCandidates); do [ -x \"$CANDIDATE\" ] || continue; printf '%s\\n' \"$CANDIDATE\"; return 0; done; return 1; }; \(commandPathVariable)=\"$(\(resolveFunctionName))\" || { echo '\(notFoundMarker)' >&2; exit 1; }; [ -n \"$\(commandPathVariable)\" ] || { echo '\(notFoundMarker)' >&2; exit 1; }; printf '%s\\n' \"$\(commandPathVariable)\"; \"$\(commandPathVariable)\" --version; \"$\(commandPathVariable)\" --help >/dev/null 2>&1"
}

private func testShellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private actor SessionScreenCollector {
    private var screens: [SessionScreen] = []

    func record(_ screen: SessionScreen) {
        screens.append(screen)
    }

    func waitForScreen(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        until predicate: @escaping (SessionScreen) -> Bool
    ) async throws -> SessionScreen {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

        while true {
            if let matchingScreen = screens.last(where: predicate) {
                return matchingScreen
            }

            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "nexusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for streamed session screen update"])
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }
}

struct StubExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]
    var searchedDirectories: [String] = ["/tmp/search-a", "/tmp/search-b"]
    var homeDirectories: [String] = ["/tmp/home"]
    var pathEnvironment: String? = "/tmp/search-a:/tmp/search-b"

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: searchedDirectories,
            homeDirectories: homeDirectories,
            pathEnvironment: pathEnvironment
        )
    }
}

final class MutableExecutableResolver: ProviderExecutableResolving {
    var executables: [String: String]
    var searchedDirectories: [String] = ["/tmp/search-a", "/tmp/search-b"]
    var homeDirectories: [String] = ["/tmp/home"]
    var pathEnvironment: String? = "/tmp/search-a:/tmp/search-b"

    init(executables: [String: String]) {
        self.executables = executables
    }

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: searchedDirectories,
            homeDirectories: homeDirectories,
            pathEnvironment: pathEnvironment
        )
    }
}

struct StubCommandRunner: ProviderCommandRunning {
    struct Invocation: Hashable {
        let executable: String
        let arguments: [String]
    }

    enum StubbedResult {
        case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
    }

    let results: [Invocation: StubbedResult]

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
            throw NSError(domain: "StubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(arguments)"])
        }

        switch result {
        case .success(let stdout, let stderr, let exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private struct NoOpCodexReadinessProbe: CodexReadinessProbing {
    func probe(executable: String, workingDirectory: String) throws {}
}

private final class NexusTestsPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private let promptResponseText: String
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(promptResponseText: String = "") {
        self.promptResponseText = promptResponseText
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": [
                    "sessionId": "pi-session-1"
                ]
            ])
        case "prompt":
            emit([
                "type": "response",
                "command": "prompt",
                "success": true
            ])
            guard promptResponseText.isEmpty == false else {
                return
            }
            emit([
                "type": "message_update",
                "assistantMessageEvent": [
                    "type": "text_delta",
                    "delta": promptResponseText
                ]
            ])
            emit([
                "type": "turn_end",
                "message": [
                    "content": [
                        [
                            "type": "text",
                            "text": promptResponseText
                        ]
                    ]
                ]
            ])
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}

struct StubHostValidationEvaluator: HostValidationEvaluating {
    let resultsByTarget: [String: HostValidationResult]

    func validate(host: NexusDomain.Host) -> HostValidationResult {
        resultsByTarget[host.sshTarget] ?? HostValidationResult(
            state: .available,
            summary: "Host is available",
            diagnostics: []
        )
    }
}

private final class StubSessionRuntimeManager: SessionRuntimeManaging {
    private let initialTranscript: String
    private let launchBehavior: ((SessionRuntimeLaunchConfiguration, Session, Workspace) throws -> Void)?
    private let launchTranscriptForExecutable: ((String) -> String)?
    private let launchTranscriptForConfiguration: ((SessionRuntimeLaunchConfiguration, Session, Workspace) -> String)?
    private var transcripts: [UUID: String] = [:]
    private var states: [UUID: Session.State] = [:]
    private var sizes: [UUID: (columns: Int, rows: Int)] = [:]
    private var updateObservers: [UUID: [UUID: @Sendable () -> Void]] = [:]
    private var observedSessionIDs: [UUID: UUID] = [:]

    init(
        initialTranscript: String = "",
        launchBehavior: ((SessionRuntimeLaunchConfiguration, Session, Workspace) throws -> Void)? = nil,
        launchTranscriptForExecutable: ((String) -> String)? = nil,
        launchTranscriptForConfiguration: ((SessionRuntimeLaunchConfiguration, Session, Workspace) -> String)? = nil
    ) {
        self.initialTranscript = initialTranscript
        self.launchBehavior = launchBehavior
        self.launchTranscriptForExecutable = launchTranscriptForExecutable
        self.launchTranscriptForConfiguration = launchTranscriptForConfiguration
    }

    func launchOrResume(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) throws {
        try launchBehavior?(launchConfiguration, session, workspace)
        if let launchTranscriptForConfiguration {
            transcripts[session.id] = launchTranscriptForConfiguration(launchConfiguration, session, workspace)
        } else if let launchTranscriptForExecutable {
            transcripts[session.id] = launchTranscriptForExecutable(launchConfiguration.executable)
        } else if transcripts[session.id] == nil {
            transcripts[session.id] = initialTranscript
        }
        states[session.id] = .ready
        if sizes[session.id] == nil {
            sizes[session.id] = (80, 24)
        }
        notifyObservers(for: session.id)
    }

    func stop(session: Session) throws {
        transcripts[session.id] = transcripts[session.id, default: initialTranscript]
        states[session.id] = .exited
        notifyObservers(for: session.id)
    }

    func remove(session: Session) {
        transcripts.removeValue(forKey: session.id)
        states.removeValue(forKey: session.id)
        sizes.removeValue(forKey: session.id)
        updateObservers.removeValue(forKey: session.id)
        observedSessionIDs = observedSessionIDs.filter { $0.value != session.id }
    }

    func hasRuntime(for session: Session) -> Bool {
        transcripts[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        states[session.id]
    }

    func sessionRecordAdapterMetadata(for session: Session) -> SessionRecordAdapterMetadata? {
        nil
    }

    func sessionScreen(for session: Session) throws -> SessionScreen {
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id, default: initialTranscript],
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func addUpdateObserver(id observationID: UUID, for session: Session, observer: @escaping @Sendable () -> Void) {
        updateObservers[session.id, default: [:]][observationID] = observer
        observedSessionIDs[observationID] = session.id
    }

    func removeUpdateObserver(id: UUID) {
        guard let sessionID = observedSessionIDs.removeValue(forKey: id) else {
            return
        }
        updateObservers[sessionID]?.removeValue(forKey: id)
        if updateObservers[sessionID]?.isEmpty == true {
            updateObservers.removeValue(forKey: sessionID)
        }
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        let separator = prefix.isEmpty ? "" : "\n"
        transcripts[session.id] = prefix + separator + "> \(text)\nClaude acknowledged: \(text)"
        notifyObservers(for: session.id)
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id] ?? "",
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func sendText(_ text: String, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        transcripts[session.id] = prefix + "[typed: \(text)]"
        notifyObservers(for: session.id)
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id] ?? "",
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen {
        let prefix = transcripts[session.id, default: initialTranscript]
        let separator = prefix.isEmpty ? "" : "\n"
        let modeSuffix = applicationCursorMode ? ":application" : ""
        transcripts[session.id] = prefix + separator + "[key: \(key.rawValue)\(modeSuffix)]"
        notifyObservers(for: session.id)
        let size = sizes[session.id] ?? (80, 24)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id] ?? "",
            terminalColumns: size.columns,
            terminalRows: size.rows
        )
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision, to session: Session) throws -> SessionScreen {
        throw NexusSessionApprovalError.approvalRequestsUnavailable
    }

    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen {
        sizes[session.id] = (columns, rows)
        notifyObservers(for: session.id)
        return SessionScreen(
            session: session,
            transcript: transcripts[session.id, default: initialTranscript],
            terminalColumns: columns,
            terminalRows: rows
        )
    }

    private func notifyObservers(for sessionID: UUID) {
        for observer in updateObservers[sessionID, default: [:]].values {
            observer()
        }
    }
}

private final class TrackingServiceClient: NexusServiceClient {
    private var workspaceOverviewValue: WorkspaceOverview
    private var providerDetailValue: ProviderDetail
    private var sessionValue: Session
    private var screenValue: SessionScreen
    private var hostsValue: [NexusDomain.Host]
    private var hostDetailsValue: [UUID: HostDetail]
    private var recentNavigationValue: [NavigationItem]
    private var searchResultsValue: [NavigationItem]
    private var remoteAccessStateValue: RemoteAccessState
    private var pairedDevicesValue: [PairedDevice]
    private var observedScreenHandlers: [UUID: @Sendable (SessionScreen) -> Void] = [:]

    var workspaceOverviewRequestCount = 0
    var recordedNavigationTargets: [NavigationTarget] = []
    var respondedApprovalRequests: [(sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision)] = []
    var observedScreenHandlerCount: Int {
        observedScreenHandlers.count
    }

    init(
        workspaceOverview: WorkspaceOverview,
        session: Session,
        screen: SessionScreen,
        providerDetail: ProviderDetail? = nil,
        hosts: [NexusDomain.Host] = [],
        hostDetails: [UUID: HostDetail] = [:],
        recentNavigation: [NavigationItem] = [],
        searchResults: [NavigationItem] = [],
        remoteAccessState: RemoteAccessState = RemoteAccessState(isEnabled: false, activePairing: nil),
        pairedDevices: [PairedDevice] = []
    ) {
        self.workspaceOverviewValue = workspaceOverview
        self.providerDetailValue = providerDetail ?? ProviderDetail(
            workspace: workspaceOverview.workspace,
            provider: Provider(id: session.providerID),
            health: workspaceOverview.providerCards.first(where: { $0.provider.id == session.providerID })?.health
                ?? ProviderHealthSummary(state: .notChecked, summary: "Not checked"),
            defaultSession: session.isDefault ? session : nil,
            alternateSessions: session.isDefault ? [] : [session],
            failedSessions: session.state == .failed && session.isDefault == false ? [session] : []
        )
        self.sessionValue = session
        self.screenValue = screen
        self.hostsValue = hosts
        self.hostDetailsValue = hostDetails
        self.recentNavigationValue = recentNavigation
        self.searchResultsValue = searchResults
        self.remoteAccessStateValue = remoteAccessState
        self.pairedDevicesValue = pairedDevices
    }

    func getServiceStatus() async throws -> NexusServiceStatus {
        NexusServiceStatus(state: .running, store: .init(kind: .sqlite, owner: .backgroundService, location: URL(fileURLWithPath: "/tmp/Nexus.sqlite")))
    }

    func listWorkspaceGroups() async throws -> [WorkspaceGroup] {
        [WorkspaceGroup(id: workspaceOverviewValue.workspace.primaryGroupID, name: "Group")]
    }

    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        WorkspaceGroup(id: UUID(), name: name)
    }

    func listWorkspaces() async throws -> [Workspace] {
        [workspaceOverviewValue.workspace]
    }

    func listHosts() async throws -> [NexusDomain.Host] {
        hostsValue
    }

    func getHostDetail(hostID: UUID) async throws -> NexusDomain.HostDetail {
        if let detail = hostDetailsValue[hostID] {
            return detail
        }
        guard let host = hostsValue.first(where: { $0.id == hostID }) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Host not found"])
        }
        return HostDetail(host: host, latestValidation: nil)
    }

    func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        let host = NexusDomain.Host(id: UUID(), name: name, sshTarget: sshTarget, port: port)
        hostsValue.append(host)
        hostDetailsValue[host.id] = HostDetail(host: host, latestValidation: nil)
        return host
    }

    func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        let host = NexusDomain.Host(id: hostID, name: name, sshTarget: sshTarget, port: port)
        if let index = hostsValue.firstIndex(where: { $0.id == hostID }) {
            hostsValue[index] = host
        } else {
            hostsValue.append(host)
        }
        hostDetailsValue[hostID] = HostDetail(host: host, latestValidation: nil)
        return host
    }

    func validateHost(hostID: UUID) async throws -> HostValidationSnapshot {
        guard let host = hostsValue.first(where: { $0.id == hostID }) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Host not found"])
        }
        let snapshot = HostValidationSnapshot(
            hostID: hostID,
            state: .available,
            summary: "Host is available",
            checkedAt: Date(timeIntervalSince1970: 456),
            diagnostics: [HostValidationDiagnostic(severity: .info, code: "sshTarget", message: "Validated \(host.sshTarget)")]
        )
        hostDetailsValue[hostID] = HostDetail(host: host, latestValidation: snapshot)
        return snapshot
    }

    func deleteHost(hostID: UUID) async throws -> Bool {
        guard hostsValue.contains(where: { $0.id == hostID }) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Host not found"])
        }
        hostsValue.removeAll { $0.id == hostID }
        hostDetailsValue.removeValue(forKey: hostID)
        return true
    }

    func listRecentNavigation(limit: Int) async throws -> [NavigationItem] {
        Array(recentNavigationValue.prefix(limit))
    }

    func recordNavigation(target: NavigationTarget) async throws {
        recordedNavigationTargets.append(target)
        switch target.kind {
        case .workspace:
            if let workspaceID = target.workspaceID, workspaceID == workspaceOverviewValue.workspace.id {
                recentNavigationValue.removeAll { $0.target == target }
                recentNavigationValue.insert(
                    NavigationItem(
                        target: .workspace(workspaceID),
                        title: workspaceOverviewValue.workspace.name,
                        subtitle: workspaceOverviewValue.workspace.folderPath
                    ),
                    at: 0
                )
            }
        case .session:
            if let sessionID = target.sessionID, sessionID == sessionValue.id {
                recentNavigationValue.removeAll { $0.target == target }
                recentNavigationValue.insert(
                    NavigationItem(
                        target: .session(sessionID),
                        title: sessionValue.isDefault ? "Default Session" : (sessionValue.name ?? "Session"),
                        subtitle: "\(workspaceOverviewValue.workspace.name) • \(sessionValue.providerID.displayName)"
                    ),
                    at: 0
                )
            }
        case .provider:
            if let workspaceID = target.workspaceID, let providerID = target.providerID {
                recentNavigationValue.removeAll { $0.target == target }
                recentNavigationValue.insert(
                    NavigationItem(
                        target: .provider(workspaceID: workspaceID, providerID: providerID),
                        title: providerID.displayName,
                        subtitle: workspaceOverviewValue.workspace.name
                    ),
                    at: 0
                )
            }
        }
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        searchResultsValue
    }

    func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) async throws {}

    func getRemoteAccessState() async throws -> RemoteAccessState {
        remoteAccessStateValue
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState {
        remoteAccessStateValue = RemoteAccessState(isEnabled: isEnabled, activePairing: isEnabled ? remoteAccessStateValue.activePairing : nil)
        return remoteAccessStateValue
    }

    func startPairing() async throws -> PairingCeremony {
        let pairing = PairingCeremony(
            id: UUID(),
            code: "123456",
            qrPayload: "nexus://pair?code=123456",
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 600)
        )
        remoteAccessStateValue = RemoteAccessState(isEnabled: remoteAccessStateValue.isEnabled, activePairing: pairing)
        return pairing
    }

    func completePairing(pairingCode: String, deviceName: String) async throws -> PairedDevice {
        let device = PairedDevice(id: UUID(), name: deviceName, pairedAt: Date(timeIntervalSince1970: 600))
        pairedDevicesValue.append(device)
        remoteAccessStateValue = RemoteAccessState(isEnabled: remoteAccessStateValue.isEnabled, activePairing: nil)
        return device
    }

    func listPairedDevices() async throws -> [PairedDevice] {
        pairedDevicesValue
    }

    func revokePairedDevice(deviceID: UUID) async throws -> Bool {
        let priorCount = pairedDevicesValue.count
        pairedDevicesValue.removeAll { $0.id == deviceID }
        return pairedDevicesValue.count != priorCount
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        workspaceOverviewRequestCount += 1
        return workspaceOverviewValue
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        providerDetailValue
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        workspaceOverviewValue.workspace
    }

    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace {
        workspaceOverviewValue.workspace
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        sessionValue
    }

    func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        guard sessionValue.id == sessionID else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }

        let relaunchedSession = Session(
            id: sessionValue.id,
            workspaceID: sessionValue.workspaceID,
            providerID: sessionValue.providerID,
            name: sessionValue.name,
            isDefault: sessionValue.isDefault,
            state: .ready
        )
        sessionValue = relaunchedSession
        screenValue = SessionScreen(session: relaunchedSession, transcript: screenValue.transcript)
        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: relaunchedSession.isDefault ? relaunchedSession : providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions.map { $0.id == relaunchedSession.id ? relaunchedSession : $0 },
            failedSessions: providerDetailValue.failedSessions.filter { $0.id != relaunchedSession.id }
        )
        return relaunchedSession
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        let namedSession = Session(
            id: UUID(),
            workspaceID: workspaceID,
            providerID: providerID,
            name: name ?? "Session 1",
            isDefault: false,
            state: .ready
        )
        sessionValue = namedSession
        screenValue = SessionScreen(session: namedSession, transcript: screenValue.transcript)
        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions + [namedSession],
            failedSessions: providerDetailValue.failedSessions
        )
        if let index = workspaceOverviewValue.providerCards.firstIndex(where: { $0.provider.id == providerID }) {
            let card = workspaceOverviewValue.providerCards[index]
            var providerCards = workspaceOverviewValue.providerCards
            providerCards[index] = WorkspaceProviderCard(
                provider: card.provider,
                health: card.health,
                defaultSession: card.defaultSession,
                alternateSessionCount: card.alternateSessionCount + 1
            )
            workspaceOverviewValue = WorkspaceOverview(
                workspace: workspaceOverviewValue.workspace,
                providerCards: providerCards,
                remoteTarget: workspaceOverviewValue.remoteTarget
            )
        }
        return namedSession
    }

    func stopSession(sessionID: UUID) async throws -> Session {
        let stoppedSession = Session(
            id: sessionValue.id,
            workspaceID: sessionValue.workspaceID,
            providerID: sessionValue.providerID,
            name: sessionValue.name,
            isDefault: sessionValue.isDefault,
            state: .exited,
            failureMessage: "Session exited. Relaunch to start a new live runtime."
        )
        sessionValue = stoppedSession
        screenValue = SessionScreen(session: stoppedSession, transcript: screenValue.transcript)
        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: stoppedSession.isDefault ? stoppedSession : providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions.map { $0.id == stoppedSession.id ? stoppedSession : $0 },
            failedSessions: providerDetailValue.failedSessions
        )
        return stoppedSession
    }

    func deleteSessionRecord(sessionID: UUID) async throws -> Bool {
        guard sessionValue.id == sessionID, sessionValue.state != .ready else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stop the session before deleting its record"])
        }

        providerDetailValue = ProviderDetail(
            workspace: providerDetailValue.workspace,
            provider: providerDetailValue.provider,
            health: providerDetailValue.health,
            defaultSession: sessionValue.isDefault ? nil : providerDetailValue.defaultSession,
            alternateSessions: providerDetailValue.alternateSessions.filter { $0.id != sessionID },
            failedSessions: providerDetailValue.failedSessions.filter { $0.id != sessionID }
        )
        if let index = workspaceOverviewValue.providerCards.firstIndex(where: { $0.provider.id == sessionValue.providerID }) {
            let card = workspaceOverviewValue.providerCards[index]
            var providerCards = workspaceOverviewValue.providerCards
            providerCards[index] = WorkspaceProviderCard(
                provider: card.provider,
                health: card.health,
                defaultSession: card.defaultSession,
                alternateSessionCount: max(0, card.alternateSessionCount - 1)
            )
            workspaceOverviewValue = WorkspaceOverview(
                workspace: workspaceOverviewValue.workspace,
                providerCards: providerCards,
                remoteTarget: workspaceOverviewValue.remoteTarget
            )
        }
        return true
    }

    func getSessionRecord(sessionID: UUID) async throws -> Session {
        guard sessionValue.id == sessionID else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        return sessionValue
    }

    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        guard sessionValue.id == sessionID else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        return screenValue
    }

    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation {
        let observationID = UUID()
        observedScreenHandlers[observationID] = onUpdate
        onUpdate(screenValue)
        return TestSessionScreenObservation { [weak self] in
            self?.observedScreenHandlers.removeValue(forKey: observationID)
        }
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        screenValue = SessionScreen(session: sessionValue, transcript: screenValue.transcript + "\n> \(text)")
        return screenValue
    }

    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        screenValue = SessionScreen(session: sessionValue, transcript: screenValue.transcript + "[typed: \(text)]")
        return screenValue
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        screenValue = SessionScreen(session: sessionValue, transcript: screenValue.transcript + "[key: \(key.rawValue)]")
        return screenValue
    }

    func respondToApprovalRequest(sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
        respondedApprovalRequests.append((sessionID: sessionID, approvalRequestID: approvalRequestID, decision: decision))
        let updatedApprovalRequests = screenValue.approvalRequests.map { request in
            guard request.id == approvalRequestID else {
                return request
            }

            return SessionApprovalRequest(
                id: request.id,
                title: request.title,
                text: request.text,
                state: decision == .approve ? .approved : .denied
            )
        }
        screenValue = SessionScreen(
            session: sessionValue,
            controller: screenValue.controller,
            transcript: screenValue.transcript,
            terminalColumns: screenValue.terminalColumns,
            terminalRows: screenValue.terminalRows,
            activityItems: screenValue.activityItems + [
                SessionActivityItem(
                    kind: .approvalDecision,
                    text: "\(decision == .approve ? "Approved" : "Denied"): \(screenValue.approvalRequests.first(where: { $0.id == approvalRequestID })?.title ?? "Approval Request")"
                )
            ],
            approvalRequests: updatedApprovalRequests
        )
        return screenValue
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            controller: screenValue.controller,
            transcript: screenValue.transcript,
            terminalColumns: columns,
            terminalRows: rows
        )
        return screenValue
    }

    func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            controller: .pairedDevice(pairedDeviceID),
            transcript: screenValue.transcript,
            terminalColumns: columns,
            terminalRows: rows
        )
        return screenValue
    }

    func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            controller: .mac,
            transcript: screenValue.transcript,
            terminalColumns: 80,
            terminalRows: 24
        )
        return screenValue
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            controller: .pairedDevice(pairedDeviceID),
            transcript: screenValue.transcript + "\n> \(text)",
            terminalColumns: screenValue.terminalColumns,
            terminalRows: screenValue.terminalRows
        )
        return screenValue
    }

    func respondToRemoteApprovalRequest(
        sessionID: UUID,
        pairedDeviceID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        respondedApprovalRequests.append((sessionID: sessionID, approvalRequestID: approvalRequestID, decision: decision))
        let updatedApprovalRequests = screenValue.approvalRequests.map { request in
            guard request.id == approvalRequestID else {
                return request
            }

            return SessionApprovalRequest(
                id: request.id,
                title: request.title,
                text: request.text,
                state: decision == .approve ? .approved : .denied
            )
        }
        screenValue = SessionScreen(
            session: sessionValue,
            controller: .pairedDevice(pairedDeviceID),
            transcript: screenValue.transcript,
            terminalColumns: screenValue.terminalColumns,
            terminalRows: screenValue.terminalRows,
            activityItems: screenValue.activityItems + [
                SessionActivityItem(
                    kind: .approvalDecision,
                    text: "\(decision == .approve ? "Approved" : "Denied"): \(screenValue.approvalRequests.first(where: { $0.id == approvalRequestID })?.title ?? "Approval Request")"
                )
            ],
            approvalRequests: updatedApprovalRequests
        )
        return screenValue
    }

    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            controller: .pairedDevice(pairedDeviceID),
            transcript: screenValue.transcript + "[typed: \(text)]",
            terminalColumns: screenValue.terminalColumns,
            terminalRows: screenValue.terminalRows
        )
        return screenValue
    }

    func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        screenValue = SessionScreen(
            session: sessionValue,
            controller: .pairedDevice(pairedDeviceID),
            transcript: screenValue.transcript + "[key: \(key.rawValue)]",
            terminalColumns: screenValue.terminalColumns,
            terminalRows: screenValue.terminalRows
        )
        return screenValue
    }

    func emitObservedScreen(_ screen: SessionScreen) async {
        sessionValue = screen.session
        screenValue = screen
        let handlers = observedScreenHandlers.values
        for handler in handlers {
            handler(screen)
        }
    }
}

private struct FailingServiceClient: NexusServiceClient {
    func getServiceStatus() async throws -> NexusServiceStatus {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func listWorkspaceGroups() async throws -> [WorkspaceGroup] {
        []
    }

    func createWorkspaceGroup(name: String) async throws -> WorkspaceGroup {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func listWorkspaces() async throws -> [Workspace] {
        []
    }

    func listHosts() async throws -> [NexusDomain.Host] {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getHostDetail(hostID: UUID) async throws -> NexusDomain.HostDetail {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createHost(name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) async throws -> NexusDomain.Host {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func validateHost(hostID: UUID) async throws -> HostValidationSnapshot {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func deleteHost(hostID: UUID) async throws -> Bool {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func listRecentNavigation(limit: Int) async throws -> [NavigationItem] {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func recordNavigation(target: NavigationTarget) async throws {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func searchNavigation(query: String) async throws -> [NavigationItem] {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) async throws {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getRemoteAccessState() async throws -> RemoteAccessState {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) async throws -> RemoteAccessState {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func startPairing() async throws -> PairingCeremony {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func completePairing(pairingCode: String, deviceName: String) async throws -> PairedDevice {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func listPairedDevices() async throws -> [PairedDevice] {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func revokePairedDevice(deviceID: UUID) async throws -> Bool {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) async throws -> Workspace {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) async throws -> Workspace {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func stopSession(sessionID: UUID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func deleteSessionRecord(sessionID: UUID) async throws -> Bool {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getSessionRecord(sessionID: UUID) async throws -> Session {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func getSessionScreen(sessionID: UUID) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func observeSessionScreen(sessionID: UUID, onUpdate: @escaping @Sendable (SessionScreen) -> Void) async throws -> any SessionScreenObservation {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func respondToApprovalRequest(sessionID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func respondToRemoteApprovalRequest(sessionID: UUID, pairedDeviceID: UUID, approvalRequestID: UUID, decision: ApprovalRequestDecision) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }

    func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }
}

private final class TestSessionScreenObservation: SessionScreenObservation, @unchecked Sendable {
    private let onCancel: @Sendable () -> Void
    private let cancellationState = TestObservationCancellationState()

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() async {
        guard await cancellationState.beginCancellation() else {
            return
        }

        onCancel()
    }
}

private actor TestObservationCancellationState {
    private var isCancelled = false

    func beginCancellation() -> Bool {
        guard isCancelled == false else {
            return false
        }

        isCancelled = true
        return true
    }
}
