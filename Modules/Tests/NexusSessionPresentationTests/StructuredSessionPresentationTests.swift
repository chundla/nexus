import Foundation
import NexusDomain
@testable import NexusSessionPresentation
import Testing

struct StructuredSessionPresentationTests {
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

    @Test func structuredSessionDetailTextPreviewLeavesShortOutputUnchanged() {
        let text = "first line\nsecond line"

        #expect(structuredSessionDetailTextPreview(for: text) == StructuredSessionDetailTextPreview(
            text: text,
            isTruncated: false
        ))
    }

    @Test func structuredSessionDetailTextPreviewTruncatesLongOutputByLineCount() {
        let text = (1 ... 16).map { "line \($0)" }.joined(separator: "\n")

        #expect(structuredSessionDetailTextPreview(for: text, maximumLines: 12) == StructuredSessionDetailTextPreview(
            text: (1 ... 12).map { "line \($0)" }.joined(separator: "\n"),
            isTruncated: true
        ))
    }

    @Test func structuredSessionActivityRowsStoreDetailPreviewsInsteadOfFullOutput() throws {
        let fullDetail = (1 ... 16).map { "line \($0)" }.joined(separator: "\n")
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
                SessionActivityItem(kind: .command, text: "git status", detailText: fullDetail)
            ]
        )

        let row = try #require(structuredSessionActivityRows(for: screen).first)
        #expect(row.detailText == (1 ... 12).map { "line \($0)" }.joined(separator: "\n"))
        #expect(row.isDetailTextTruncated)
    }

    @Test func structuredSessionActivityRowsKeepShortSystemUpdatesCompact() throws {
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
                SessionActivityItem(kind: .status, text: "Connected")
            ]
        )

        let row = try #require(structuredSessionActivityRows(for: screen).first)
        #expect(row.showsExpandedSystemCard == false)
    }

    @Test func structuredSessionActivityRowsPrecomputeExpandedSystemCardsForLongOrDetailedUpdates() {
        let longStatus = String(repeating: "A", count: 81)
        let rows = structuredSessionActivityRows(for: [
            SessionActivityItem(kind: .status, text: longStatus),
            SessionActivityItem(kind: .progress, text: "Planning", detailText: "step 1\nstep 2")
        ])

        #expect(rows.map(\.showsExpandedSystemCard) == [true, true])
    }

    @Test func structuredSessionAutoScrollTriggerTracksStableFeedIdentity() {
        let pendingApprovalID = UUID()
        let notificationID = UUID()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: Ship it"),
                SessionActivityItem(kind: .message, text: "Pi: On it")
            ],
            approvalRequests: [
                SessionApprovalRequest(id: pendingApprovalID, title: "Deploy", text: "Deploy now?", state: .pending),
                SessionApprovalRequest(title: "Cleanup", text: "Delete temp files?", state: .approved)
            ],
            extensionUI: SessionExtensionUIState(
                title: "Plan",
                pendingDialogs: [
                    SessionExtensionUIDialog(id: "dialog-1", kind: .input, title: "Name")
                ],
                notifications: [
                    SessionExtensionUINotification(id: notificationID, kind: .info, message: "Saved")
                ],
                statuses: [SessionExtensionUIStatus(key: "sync", text: "Synced")],
                widgets: [SessionExtensionUIWidget(key: "summary", lines: ["Ready"])],
                editorText: "draft"
            ),
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "response",
                    family: .response,
                    rawPayload: "{}"
                )
            ],
            isAgentTurnInProgress: true
        )

        #expect(structuredSessionAutoScrollTrigger(for: screen) == StructuredSessionAutoScrollTrigger(
            lastActivityRowID: screen.activityItems.last?.id,
            pendingApprovalRequestIDs: [pendingApprovalID],
            pendingDialogIDs: ["dialog-1"]
        ))
    }

    @Test func structuredSessionAutoScrollTriggerIgnoresExtensionNotificationChurn() {
        let activityID = UUID()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let base = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(id: activityID, kind: .message, text: "Pi: hi")],
            extensionUI: SessionExtensionUIState(
                notifications: [SessionExtensionUINotification(id: UUID(), kind: .info, message: "a")]
            ),
            isAgentTurnInProgress: false
        )
        let churnedNotifications = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(id: activityID, kind: .message, text: "Pi: hi")],
            extensionUI: SessionExtensionUIState(
                notifications: [SessionExtensionUINotification(id: UUID(), kind: .warning, message: "b")]
            ),
            isAgentTurnInProgress: false
        )

        #expect(structuredSessionAutoScrollTrigger(for: base) == structuredSessionAutoScrollTrigger(for: churnedNotifications))
    }

    @Test func structuredSessionAutoScrollTriggerIgnoresNonFeedPresentationChanges() {
        let activityID = UUID()
        let approvalID = UUID()
        let notificationID = UUID()
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let baseScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "base transcript",
            activityItems: [SessionActivityItem(id: activityID, kind: .message, text: "Codex: Ready")],
            approvalRequests: [SessionApprovalRequest(id: approvalID, title: "Deploy", text: "Deploy?", state: .pending)],
            extensionUI: SessionExtensionUIState(
                title: "Base",
                pendingDialogs: [SessionExtensionUIDialog(id: "dialog-1", kind: .confirm, title: "Continue")],
                notifications: [SessionExtensionUINotification(id: notificationID, kind: .info, message: "Saved")],
                statuses: [SessionExtensionUIStatus(key: "base", text: "Idle")],
                widgets: [SessionExtensionUIWidget(key: "base", lines: ["One"])],
                editorText: "draft"
            ),
            providerEvents: [],
            isAgentTurnInProgress: false
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "updated transcript",
            activityItems: [SessionActivityItem(id: activityID, kind: .message, text: "Codex: Updated body")],
            approvalRequests: [
                SessionApprovalRequest(id: approvalID, title: "Deploy", text: "Deploy later?", state: .pending),
                SessionApprovalRequest(title: "Cleanup", text: "Delete temp files?", state: .approved)
            ],
            extensionUI: SessionExtensionUIState(
                title: "Updated",
                pendingDialogs: [SessionExtensionUIDialog(id: "dialog-1", kind: .input, title: "Reason")],
                notifications: [SessionExtensionUINotification(id: notificationID, kind: .warning, message: "Changed")],
                statuses: [SessionExtensionUIStatus(key: "updated", text: "Busy")],
                widgets: [SessionExtensionUIWidget(key: "updated", lines: ["Two"])],
                editorText: "new draft"
            ),
            providerEvents: [
                SessionProviderEvent(
                    sequence: 99,
                    providerID: .codex,
                    type: "response",
                    family: .response,
                    rawPayload: "{}"
                )
            ],
            isAgentTurnInProgress: true
        )

        #expect(structuredSessionAutoScrollTrigger(for: baseScreen) == structuredSessionAutoScrollTrigger(for: updatedScreen))
    }

    @Test func structuredSessionAutoScrollAnimationUsesImmediateScrollForAppendedActivityRows() {
        let firstActivityID = UUID()
        let secondActivityID = UUID()
        let previous = StructuredSessionAutoScrollTrigger(
            lastActivityRowID: firstActivityID,
            pendingApprovalRequestIDs: [],
            pendingDialogIDs: []
        )
        let current = StructuredSessionAutoScrollTrigger(
            lastActivityRowID: secondActivityID,
            pendingApprovalRequestIDs: [],
            pendingDialogIDs: []
        )

        #expect(structuredSessionAutoScrollAnimation(previous: previous, current: current) == .immediate)
    }

    @Test func structuredSessionAutoScrollAnimationKeepsAnimatedScrollForNewPendingApprovals() {
        let activityID = UUID()
        let previous = StructuredSessionAutoScrollTrigger(
            lastActivityRowID: activityID,
            pendingApprovalRequestIDs: [],
            pendingDialogIDs: []
        )
        let current = StructuredSessionAutoScrollTrigger(
            lastActivityRowID: activityID,
            pendingApprovalRequestIDs: [UUID()],
            pendingDialogIDs: []
        )

        #expect(structuredSessionAutoScrollAnimation(previous: previous, current: current) == .animated)
    }

    @Test func structuredSessionAutoScrollCoordinatorCoalescesRapidRequestsIntoOneScroll() {
        var scheduled: [() -> Void] = []
        let coordinator = StructuredSessionAutoScrollCoordinator { work in
            scheduled.append(work)
        }
        var performed: [StructuredSessionAutoScrollAnimation] = []

        coordinator.request(.immediate) { animation in
            performed.append(animation)
        }
        coordinator.request(.animated) { animation in
            performed.append(animation)
        }

        #expect(scheduled.count == 1)
        #expect(performed.isEmpty)

        let flush = try! #require(scheduled.first)
        flush()

        #expect(performed == [.animated])
    }

    @Test func structuredSessionAutoScrollCoordinatorSchedulesAnotherFlushAfterRunningPendingScroll() {
        var scheduled: [() -> Void] = []
        let coordinator = StructuredSessionAutoScrollCoordinator { work in
            scheduled.append(work)
        }
        var performed: [StructuredSessionAutoScrollAnimation] = []

        coordinator.request(.immediate) { animation in
            performed.append(animation)
        }
        let firstFlush = try! #require(scheduled.first)
        firstFlush()

        coordinator.request(.animated) { animation in
            performed.append(animation)
        }

        #expect(scheduled.count == 2)
        let secondFlush = try! #require(scheduled.last)
        secondFlush()

        #expect(performed == [.immediate, .animated])
    }

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

    @Test func structuredSessionStatusBarPresentationFormatsTokenUsageFromProviderEvents() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "response",
                    family: .response,
                    command: "get_session_stats",
                    rawPayload: #"{"type":"response","command":"get_session_stats","success":true,"data":{"contextUsage":{"tokens":60000,"contextWindow":200000,"percent":30}}}"#
                )
            ]
        )

        #expect(structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus") == StructuredSessionStatusBarPresentation(
            workspaceLocation: "/tmp/nexus",
            tokenUsage: StructuredSessionTokenUsagePresentation(usedTokens: 60000, totalTokens: 200000, percent: 30)
        ))
    }

    @Test func structuredSessionStatusBarPresentationFallsBackToKnownContextWindowForPiModels() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "response",
                    family: .response,
                    command: "get_state",
                    rawPayload: #"{"type":"response","command":"get_state","success":true,"data":{"model":{"provider":"openai","id":"gpt-5.1-codex-max","name":"GPT-5.1 Codex Max"}}}"#
                )
            ]
        )

        let presentation = structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus")

        #expect(presentation.workspaceLocation == "/tmp/nexus")
        #expect(presentation.tokenUsage == StructuredSessionTokenUsagePresentation(usedTokens: 0, totalTokens: 272000, percent: 0))
        #expect(presentation.tokenUsageText == "0/272k 0%")
    }

    @Test func structuredSessionStatusBarPresentationFallsBackToKnownContextWindowForCodexModels() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .codex,
                    type: "response",
                    family: .response,
                    rawPayload: #"{"id":"nexus-codex-thread-start","result":{"thread":{"id":"codex-thread-1"},"model":"gpt-5.5"}}"#
                )
            ]
        )

        #expect(structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus").tokenUsageText == "0/272k 0%")
    }

    @Test func structuredSessionStatusBarPresentationUsesProviderFactsWithoutReparsingRawEvents() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "response",
                    family: .response,
                    command: "get_session_stats",
                    rawPayload: #"{"type":"response","command":"get_session_stats","success":true,"data":{"contextUsage":{"tokens":1,"contextWindow":2,"percent":50}}}"#
                )
            ],
            providerFacts: StructuredSessionProviderFacts(
                providerEventCount: 1,
                lastProviderEventSequence: 0,
                lastProviderEventType: "response",
                tokenUsage: StructuredSessionProviderTokenUsage(usedTokens: 60000, totalTokens: 200000, percent: 30)
            )
        )

        #expect(structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus").tokenUsage == StructuredSessionTokenUsagePresentation(
            usedTokens: 60000,
            totalTokens: 200000,
            percent: 30
        ))
    }

    @Test func structuredSessionStatusBarPresentationInfersContextWindowFromProviderFactsModelIdentifier() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerFacts: StructuredSessionProviderFacts(modelIdentifier: "openai/gpt-5.1-codex-max")
        )

        #expect(structuredSessionStatusBarPresentation(for: screen, workspaceLocation: "/tmp/nexus").tokenUsageText == "0/272k 0%")
    }

    @Test func structuredSessionTokenUsagePresenterOnlyParsesNewProviderEventsAcrossAppendOnlyUpdates() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let usage = StructuredSessionTokenUsagePresentation(usedTokens: 60000, totalTokens: 200000, percent: 30)
        let usageEvent = SessionProviderEvent(
            sequence: 0,
            providerID: .pi,
            type: "response",
            family: .response,
            rawPayload: "usage"
        )
        let appendedEvent = SessionProviderEvent(
            sequence: 1,
            providerID: .pi,
            type: "response",
            family: .response,
            rawPayload: "noop"
        )
        var parsedPayloads: [String] = []
        let presenter = StructuredSessionTokenUsagePresenter(
            providerEventUsageParser: { event in
                parsedPayloads.append(event.rawPayload)
                return event.rawPayload == "usage"
                    ? StructuredSessionTokenUsagePresentation(usedTokens: 60000, totalTokens: 200000, percent: 30)
                    : nil
            },
            activityItemUsageParser: { _ in
                Issue.record("Expected append-only provider event updates to avoid reparsing activity items")
                return nil
            },
            inferredContextWindowResolver: { _ in
                Issue.record("Expected append-only provider event updates to avoid falling back to inferred context windows")
                return nil
            }
        )

        let initialPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [usageEvent]
        ))
        let updatedPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [usageEvent, appendedEvent]
        ))

        #expect(initialPresentation == usage)
        #expect(updatedPresentation == usage)
        #expect(parsedPayloads == ["usage", "noop"])
    }

    @Test func structuredSessionTokenUsagePresenterOnlyParsesNewActivityItemsAcrossAppendOnlyUpdates() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let usage = StructuredSessionTokenUsagePresentation(usedTokens: 40000, totalTokens: 200000, percent: 20)
        let usageItem = SessionActivityItem(kind: .progress, text: "usage")
        let appendedItem = SessionActivityItem(kind: .message, text: "noop")
        var parsedTexts: [String] = []
        let presenter = StructuredSessionTokenUsagePresenter(
            providerEventUsageParser: { _ in
                Issue.record("Expected append-only activity updates to avoid reparsing provider events")
                return nil
            },
            activityItemUsageParser: { item in
                parsedTexts.append(item.text)
                return item.text == "usage"
                    ? StructuredSessionTokenUsagePresentation(usedTokens: 40000, totalTokens: 200000, percent: 20)
                    : nil
            },
            inferredContextWindowResolver: { _ in
                Issue.record("Expected append-only activity updates to avoid falling back to inferred context windows")
                return nil
            }
        )

        let initialPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [usageItem]
        ))
        let updatedPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [usageItem, appendedItem]
        ))

        #expect(initialPresentation == usage)
        #expect(updatedPresentation == usage)
        #expect(parsedTexts == ["usage", "noop"])
    }

    @Test func structuredSessionTokenUsagePresenterRebuildsWhenProviderEventsChangeInPlace() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let initialEvent = SessionProviderEvent(
            sequence: 0,
            providerID: .pi,
            type: "response",
            family: .response,
            rawPayload: "usage-1"
        )
        let updatedEvent = SessionProviderEvent(
            sequence: 0,
            providerID: .pi,
            type: "response",
            family: .response,
            rawPayload: "usage-2"
        )
        var parsedPayloads: [String] = []
        let presenter = StructuredSessionTokenUsagePresenter(
            providerEventUsageParser: { event in
                parsedPayloads.append(event.rawPayload)
                switch event.rawPayload {
                case "usage-1":
                    return StructuredSessionTokenUsagePresentation(usedTokens: 10000, totalTokens: 200000, percent: 5)
                case "usage-2":
                    return StructuredSessionTokenUsagePresentation(usedTokens: 60000, totalTokens: 200000, percent: 30)
                default:
                    return nil
                }
            },
            activityItemUsageParser: { _ in
                Issue.record("Expected provider event rebuilds to avoid activity-item fallback when usage still exists in provider events")
                return nil
            },
            inferredContextWindowResolver: { _ in
                Issue.record("Expected provider event rebuilds to avoid inferred-context fallback when usage still exists in provider events")
                return nil
            }
        )

        let initialPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [initialEvent]
        ))
        let updatedPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            providerEvents: [updatedEvent]
        ))

        #expect(initialPresentation == StructuredSessionTokenUsagePresentation(usedTokens: 10000, totalTokens: 200000, percent: 5))
        #expect(updatedPresentation == StructuredSessionTokenUsagePresentation(usedTokens: 60000, totalTokens: 200000, percent: 30))
        #expect(parsedPayloads == ["usage-1", "usage-2"])
    }

    @Test func structuredSessionPresentationBuildsSharedFeedAndComposerStateFromSessionScreenAndDraft() {
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

        let presentation = StructuredSessionPresentation(
            screen: screen,
            hasWriterAuthority: false,
            draft: "Ship it",
            isPerformingAction: false
        )

        #expect(presentation.feed == StructuredSessionFeedPresentation(
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
                    emphasis: .accent,
                    conversationPresentation: StructuredSessionConversationPresentation(
                        role: .system,
                        text: "Gathering context"
                    )
                )
            ],
            pendingApprovalRequests: [pendingRequest],
            thinkingIndicator: nil
        ))
        #expect(presentation.composer == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
        #expect(presentation.sendAffordance == StructuredSessionComposerSendAffordance(
            isVisible: false,
            isEnabled: false
        ))
        #expect(presentation.approvalRequest == StructuredSessionApprovalRequestPresentation(
            actionsAreEnabled: false,
            disabledReason: "Take Controller to respond to Approval Requests from this iPhone."
        ))
        #expect(presentation.slashCommandMenu == StructuredSessionSlashCommandMenuPresentation(
            isVisible: false,
            commands: []
        ))
    }

    @Test func structuredSessionFeedPresenterAppendsOnlyNewStructuredSessionRowsAcrossLiveUpdates() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let pendingRequest = SessionApprovalRequest(title: "Deploy", text: "Deploy to production?", state: .pending)
        let firstActivity = SessionActivityItem(kind: .message, text: "You: Ship it")
        let secondActivity = SessionActivityItem(kind: .progress, text: "Gathering context")
        let thirdActivity = SessionActivityItem(kind: .completion, text: "Done")
        var builtItemIDs: [[UUID]] = []
        let presenter = StructuredSessionFeedPresenter { items in
            builtItemIDs.append(items.map(\.id))
            return items.map { item in
                StructuredSessionActivityRow(
                    id: item.id,
                    title: item.kind.rawValue,
                    systemImage: item.kind.rawValue,
                    text: item.text,
                    detailText: item.detailText,
                    isDetailTextTruncated: false,
                    emphasis: .neutral
                )
            }
        }

        let firstPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity],
            approvalRequests: [pendingRequest]
        ))
        let secondPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity],
            approvalRequests: [pendingRequest],
            isAgentTurnInProgress: true
        ))

        #expect(firstPresentation.activityRows.map(\.id) == [firstActivity.id, secondActivity.id])
        #expect(secondPresentation.activityRows.map(\.id) == [firstActivity.id, secondActivity.id, thirdActivity.id])
        #expect(secondPresentation.pendingApprovalRequests == [pendingRequest])
        #expect(secondPresentation.thinkingIndicator == nil)
        #expect(builtItemIDs == [[firstActivity.id, secondActivity.id], [thirdActivity.id]])
    }

    @Test func structuredSessionFeedPresenterStreamsLivePiAssistantDraftAndReusesItsRowIdentityWhenTurnFinalizes() throws {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let userPrompt = SessionActivityItem(kind: .message, text: "You: hello")
        let finalizedAssistantMessage = SessionActivityItem(kind: .message, text: "Pi: world")
        let presenter = StructuredSessionFeedPresenter()

        let firstDraftPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [userPrompt],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"wor"}}"#
                )
            ],
            isAgentTurnInProgress: true
        ))
        let streamedDraftPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [userPrompt],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"wor"}}"#
                ),
                SessionProviderEvent(
                    sequence: 1,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"ld"}}"#
                )
            ],
            isAgentTurnInProgress: true
        ))
        let finalizedPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [userPrompt, finalizedAssistantMessage],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"wor"}}"#
                ),
                SessionProviderEvent(
                    sequence: 1,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"ld"}}"#
                ),
                SessionProviderEvent(
                    sequence: 2,
                    providerID: .pi,
                    type: "turn_end",
                    family: .turn,
                    rawPayload: #"{"type":"turn_end","message":{"content":[{"type":"text","text":"world"}]}}"#
                )
            ],
            isAgentTurnInProgress: false
        ))

        #expect(firstDraftPresentation.activityRows.map(\.text) == ["You: hello", "Pi: wor"])
        #expect(firstDraftPresentation.activityRows.last?.conversationPresentation?.isStreaming == true)
        let draftRowID = try #require(firstDraftPresentation.activityRows.last?.id)
        #expect(streamedDraftPresentation.activityRows.map(\.text) == ["You: hello", "Pi: world"])
        #expect(streamedDraftPresentation.activityRows.last?.id == draftRowID)
        #expect(streamedDraftPresentation.activityRows.last?.conversationPresentation?.isStreaming == true)
        let sealedChunkCount = firstDraftPresentation.activityRowChunks.count
        #expect(streamedDraftPresentation.activityRowChunks.count == sealedChunkCount)
        #expect(
            zip(firstDraftPresentation.activityRowChunks, streamedDraftPresentation.activityRowChunks).allSatisfy {
                $0.id == $1.id && $0.rows.count == $1.rows.count
            }
        )
        #expect(finalizedPresentation.activityRows.map(\.text) == ["You: hello", "Pi: world"])
        #expect(finalizedPresentation.activityRows.last?.id == draftRowID)
        #expect(finalizedPresentation.activityRows.last?.conversationPresentation?.isStreaming == false)
        #expect(finalizedPresentation.activityRows.filter { $0.text == "Pi: world" }.count == 1)
    }

    @Test func structuredSessionFeedPresenterUsesProviderFactsForLivePiDraftsWithoutReparsingRawEvents() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let presenter = StructuredSessionFeedPresenter()
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .message, text: "You: hello")],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"stale"}}"#
                )
            ],
            providerFacts: StructuredSessionProviderFacts(
                providerEventCount: 1,
                lastProviderEventSequence: 0,
                lastProviderEventType: "message_update",
                liveAssistantDraftText: "fresh"
            ),
            isAgentTurnInProgress: true
        )

        #expect(presenter.presentation(for: screen).activityRows.map(\.text) == ["You: hello", "Pi: fresh"])
    }

    @Test func structuredSessionFeedPresentationUsesChunksAsCanonicalActivityRowStorage() {
        let firstRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "Pi: One",
            emphasis: .accent
        )
        let secondRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Command",
            systemImage: "terminal",
            text: "git status",
            emphasis: .neutral
        )

        let presentation = StructuredSessionFeedPresentation(
            copy: StructuredSessionPresentationCopy(
                emptyStateTitle: "Empty",
                emptyStateDescription: "Nothing yet",
                composerPlaceholder: "Prompt"
            ),
            activityRows: [firstRow],
            activityRowChunks: [StructuredSessionActivityRowChunk(id: 0, rows: [firstRow, secondRow])],
            pendingApprovalRequests: [],
            thinkingIndicator: nil
        )

        #expect(presentation.activityRows == [firstRow, secondRow])
    }

    @Test func structuredSessionFeedPresenterKeepsEarlierChunksStableAcrossLongAppendOnlyBursts() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let firstActivity = SessionActivityItem(kind: .message, text: "You: One")
        let secondActivity = SessionActivityItem(kind: .progress, text: "Two")
        let thirdActivity = SessionActivityItem(kind: .command, text: "three")
        let fourthActivity = SessionActivityItem(kind: .completion, text: "Four")
        let fifthActivity = SessionActivityItem(kind: .message, text: "Codex: Five")
        let presenter = StructuredSessionFeedPresenter(chunkSize: 2) { items in
            items.map { item in
                StructuredSessionActivityRow(
                    id: item.id,
                    title: item.kind.rawValue,
                    systemImage: item.kind.rawValue,
                    text: item.text,
                    detailText: item.detailText,
                    isDetailTextTruncated: false,
                    emphasis: .neutral
                )
            }
        }

        let firstPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity]
        ))
        let secondPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity, fourthActivity]
        ))
        let thirdPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity, fourthActivity, fifthActivity]
        ))

        #expect(firstPresentation.activityRowChunks.map(\.id) == [0, 2])
        #expect(firstPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id],
            [thirdActivity.id]
        ])
        #expect(secondPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id],
            [thirdActivity.id, fourthActivity.id]
        ])
        #expect(thirdPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id],
            [thirdActivity.id, fourthActivity.id],
            [fifthActivity.id]
        ])
        #expect(secondPresentation.activityRowChunks[0] == firstPresentation.activityRowChunks[0])
        #expect(thirdPresentation.activityRowChunks[0] == secondPresentation.activityRowChunks[0])
        #expect(thirdPresentation.activityRowChunks[1] == secondPresentation.activityRowChunks[1])
    }

    @Test func structuredSessionFeedPresenterSealsFullLiveTailChunkBeforeContinuingAppendBurst() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let firstActivity = SessionActivityItem(kind: .message, text: "One")
        let secondActivity = SessionActivityItem(kind: .message, text: "Two")
        let thirdActivity = SessionActivityItem(kind: .message, text: "Three")
        let fourthActivity = SessionActivityItem(kind: .message, text: "Four")
        let fifthActivity = SessionActivityItem(kind: .message, text: "Five")
        let sixthActivity = SessionActivityItem(kind: .message, text: "Six")
        let seventhActivity = SessionActivityItem(kind: .message, text: "Seven")
        let eighthActivity = SessionActivityItem(kind: .message, text: "Eight")
        let presenter = StructuredSessionFeedPresenter(chunkSize: 4, liveTailChunkSize: 2) { items in
            items.map { item in
                StructuredSessionActivityRow(
                    id: item.id,
                    title: item.kind.rawValue,
                    systemImage: item.kind.rawValue,
                    text: item.text,
                    detailText: item.detailText,
                    isDetailTextTruncated: false,
                    emphasis: .neutral
                )
            }
        }

        let firstPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity, fourthActivity, fifthActivity, sixthActivity]
        ))
        let secondPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity, fourthActivity, fifthActivity, sixthActivity, seventhActivity]
        ))
        let thirdPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, thirdActivity, fourthActivity, fifthActivity, sixthActivity, seventhActivity, eighthActivity]
        ))

        #expect(firstPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id, thirdActivity.id, fourthActivity.id],
            [fifthActivity.id, sixthActivity.id]
        ])
        #expect(secondPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id, thirdActivity.id, fourthActivity.id],
            [fifthActivity.id, sixthActivity.id],
            [seventhActivity.id]
        ])
        #expect(thirdPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id, thirdActivity.id, fourthActivity.id],
            [fifthActivity.id, sixthActivity.id],
            [seventhActivity.id, eighthActivity.id]
        ])
        #expect(secondPresentation.activityRowChunks[0] == firstPresentation.activityRowChunks[0])
        #expect(secondPresentation.activityRowChunks[1] == firstPresentation.activityRowChunks[1])
        #expect(thirdPresentation.activityRowChunks[0] == secondPresentation.activityRowChunks[0])
        #expect(thirdPresentation.activityRowChunks[1] == secondPresentation.activityRowChunks[1])
    }

    @Test func structuredSessionFeedPresenterOnlyRebuildsAffectedTailChunkForInPlaceLastItemUpdates() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let firstActivity = SessionActivityItem(kind: .message, text: "Pi: First")
        let secondActivity = SessionActivityItem(kind: .progress, text: "Thinking")
        let thirdActivityID = UUID()
        let originalThirdActivity = SessionActivityItem(
            id: thirdActivityID,
            kind: .command,
            text: "git diff",
            detailText: "line 1"
        )
        let updatedThirdActivity = SessionActivityItem(
            id: thirdActivityID,
            kind: .command,
            text: "git diff",
            detailText: "line 1\nline 2"
        )
        var builtItems: [[String]] = []
        let presenter = StructuredSessionFeedPresenter(chunkSize: 2, liveTailChunkSize: 2) { items in
            builtItems.append(items.map { "\($0.text)|\($0.detailText ?? "")" })
            return items.map { item in
                StructuredSessionActivityRow(
                    id: item.id,
                    title: item.kind.rawValue,
                    systemImage: item.kind.rawValue,
                    text: item.text,
                    detailText: item.detailText,
                    isDetailTextTruncated: false,
                    emphasis: .neutral
                )
            }
        }

        let initialPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, originalThirdActivity]
        ))
        let updatedPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [firstActivity, secondActivity, updatedThirdActivity]
        ))

        #expect(initialPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id],
            [thirdActivityID]
        ])
        #expect(updatedPresentation.activityRowChunks.map { $0.rows.map(\.id) } == [
            [firstActivity.id, secondActivity.id],
            [thirdActivityID]
        ])
        #expect(updatedPresentation.activityRows.last?.detailText == "line 1\nline 2")
        #expect(builtItems == [
            ["Pi: First|", "Thinking|", "git diff|line 1"],
            ["git diff|line 1\nline 2"]
        ])
    }

    @Test func structuredSessionFeedPresenterRebuildsWhenStructuredSessionHistoryChangesInPlace() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let activityID = UUID()
        let originalActivity = SessionActivityItem(id: activityID, kind: .message, text: "Pi: First draft")
        let unchangedActivity = SessionActivityItem(kind: .progress, text: "Thinking")
        let updatedActivity = SessionActivityItem(id: activityID, kind: .message, text: "Pi: Revised draft")
        var builtItemTexts: [[String]] = []
        let presenter = StructuredSessionFeedPresenter { items in
            builtItemTexts.append(items.map(\.text))
            return items.map { item in
                StructuredSessionActivityRow(
                    id: item.id,
                    title: item.kind.rawValue,
                    systemImage: item.kind.rawValue,
                    text: item.text,
                    detailText: item.detailText,
                    isDetailTextTruncated: false,
                    emphasis: .neutral
                )
            }
        }

        _ = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [originalActivity, unchangedActivity]
        ))
        let updatedPresentation = presenter.presentation(for: SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [updatedActivity, unchangedActivity]
        ))

        #expect(updatedPresentation.activityRows.map(\.text) == ["Pi: Revised draft", "Thinking"])
        #expect(builtItemTexts == [["Pi: First draft", "Thinking"], ["Pi: Revised draft", "Thinking"]])
    }

    @Test func structuredSessionFeedPresenterPrecomputesConversationRowsForUIAdapters() {
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
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: Ship it"),
                SessionActivityItem(kind: .message, text: "Planner: Check git status"),
                SessionActivityItem(kind: .message, text: "Still working"),
                SessionActivityItem(kind: .command, text: "git status")
            ]
        )

        let presentation = StructuredSessionFeedPresenter().presentation(for: screen)

        #expect(presentation.activityRows.map(\.conversationPresentation) == [
            StructuredSessionConversationPresentation(role: .user, text: "Ship it"),
            StructuredSessionConversationPresentation(role: .assistant(label: "Planner"), text: "Check git status"),
            StructuredSessionConversationPresentation(role: .assistant(label: "Codex"), text: "Still working"),
            StructuredSessionConversationPresentation(role: .command, text: "git status")
        ])
    }

    @Test func focusedStructuredSessionPresenterKeepsFeedStableDuringChromeOnlyExtensionUpdates() throws {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let activity = SessionActivityItem(kind: .message, text: "Pi: Ready")
        let initialScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [activity],
            extensionUI: SessionExtensionUIState(
                title: "Plan",
                statuses: [SessionExtensionUIStatus(key: "status", text: "Planning")],
                widgets: [SessionExtensionUIWidget(key: "summary", lines: ["One"])],
                editorText: "draft"
            )
        )
        let updatedScreen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "Pi shared Session stream connected",
            activityItems: [activity],
            extensionUI: SessionExtensionUIState(
                title: "Plan updated",
                statuses: [SessionExtensionUIStatus(key: "status", text: "Ready")],
                widgets: [SessionExtensionUIWidget(key: "summary", lines: ["Two"])],
                editorText: "draft updated"
            )
        )
        let presenter = FocusedStructuredSessionPresenter()

        let initialPresentation = try #require(presenter.presentation(for: initialScreen))
        let updatedPresentation = try #require(presenter.presentation(for: updatedScreen))

        #expect(initialPresentation == updatedPresentation)
        #expect(focusedStructuredSessionChromePresentation(for: initialScreen) != focusedStructuredSessionChromePresentation(for: updatedScreen))
    }

    @Test func structuredSessionConversationPresentationClassifiesSharedMessageRowsAndFallsBackToProviderLabel() {
        let screen = SessionScreen(
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
        let userRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "You: Ship it",
            emphasis: .accent
        )
        let assistantRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "Planner: Check git status",
            emphasis: .accent
        )
        let fallbackRow = StructuredSessionActivityRow(
            id: UUID(),
            title: "Message",
            systemImage: "message",
            text: "Still working",
            emphasis: .accent
        )

        #expect(structuredSessionConversationPresentation(for: userRow, screen: screen) == StructuredSessionConversationPresentation(
            role: .user,
            text: "Ship it"
        ))
        #expect(structuredSessionConversationPresentation(for: assistantRow, screen: screen) == StructuredSessionConversationPresentation(
            role: .assistant(label: "Planner"),
            text: "Check git status"
        ))
        #expect(structuredSessionConversationPresentation(for: fallbackRow, screen: screen) == StructuredSessionConversationPresentation(
            role: .assistant(label: "Codex"),
            text: "Still working"
        ))
    }

    @Test func structuredSessionFeedPresentationShowsThinkingIndicatorWhileAgentTurnIsInProgress() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .codex,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [SessionActivityItem(kind: .message, text: "You: Ship it")],
            isAgentTurnInProgress: true
        )

        #expect(structuredSessionFeedPresentation(for: screen).thinkingIndicator == StructuredSessionThinkingIndicator(text: "Thinking…"))
    }

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

        #expect(structuredSessionComposerPresentation(for: codexScreen, hasWriterAuthority: false) == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
    }

    @Test func structuredSessionComposerPresentationUsesPiCopyWhileKeepingViewerPromptVisibleButDisabledUntilControllerTaken() {
        let piScreen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            transcript: ""
        )

        #expect(structuredSessionComposerPresentation(for: piScreen, hasWriterAuthority: false) == StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Pi",
            isEnabled: false,
            disabledReason: "Take Controller to send a prompt from this iPhone."
        ))
    }

    @Test func structuredSessionComposerSendAffordanceAppearsAfterTheFirstSendableCharacter() {
        let composer = StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Codex",
            isEnabled: true,
            disabledReason: nil
        )

        #expect(structuredSessionComposerSendAffordance(
            for: "H",
            composer: composer,
            isPerformingAction: false
        ) == StructuredSessionComposerSendAffordance(
            isVisible: true,
            isEnabled: true
        ))
    }

    @Test func structuredSessionComposerSendAffordanceStaysHiddenForWhitespaceOnlyDrafts() {
        let composer = StructuredSessionComposerPresentation(
            placeholder: "Send a prompt to Pi",
            isEnabled: true,
            disabledReason: nil
        )

        #expect(structuredSessionComposerSendAffordance(
            for: " \n ",
            composer: composer,
            isPerformingAction: false
        ) == StructuredSessionComposerSendAffordance(
            isVisible: false,
            isEnabled: false
        ))
    }

    @Test func structuredSessionApprovalRequestPresentationKeepsViewerActionsVisibleButDisabledUntilControllerTaken() {
        #expect(structuredSessionApprovalRequestPresentation(hasWriterAuthority: false) == StructuredSessionApprovalRequestPresentation(
            actionsAreEnabled: false,
            disabledReason: "Take Controller to respond to Approval Requests from this iPhone."
        ))
    }

    @Test func structuredSessionSlashCommandMenuAppearsAsSoonAsSlashIsTyped() {
        let menu = structuredSessionSlashCommandMenuPresentation(
            for: "/",
            screen: SessionScreen(
                session: Session(
                    id: UUID(),
                    workspaceID: UUID(),
                    providerID: .codex,
                    isDefault: true,
                    state: .ready
                ),
                transcript: ""
            )
        )

        #expect(menu.isVisible)
        #expect(menu.commands.first?.displayText == "/model")
    }

    @Test func structuredSessionSlashCommandMenuNarrowsUsingTypedPrefixAndSupportsArgumentCommands() {
        let codexMenu = structuredSessionSlashCommandMenuPresentation(
            for: "/go",
            screen: SessionScreen(
                session: Session(
                    id: UUID(),
                    workspaceID: UUID(),
                    providerID: .codex,
                    isDefault: true,
                    state: .ready
                ),
                transcript: ""
            )
        )
        let bobMenu = structuredSessionSlashCommandMenuPresentation(
            for: "/mode a",
            screen: SessionScreen(
                session: Session(
                    id: UUID(),
                    workspaceID: UUID(),
                    providerID: .ibmBob,
                    isDefault: true,
                    state: .ready
                ),
                transcript: ""
            )
        )

        #expect(codexMenu.commands.map(\.displayText) == ["/goal <objective>"])
        #expect(bobMenu.commands.map(\.displayText) == ["/mode advanced", "/mode ask"])
    }

    @Test func structuredSessionSlashCommandMenuUsesLivePiSkillCommandsFromSessionScreen() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "skill:create-cli",
                    description: "CLI UX/spec: args, flags, help, output, errors, config, dry-run.",
                    source: .skill,
                    location: .user,
                    path: "/Users/tester/.pi/agent/skills/create-cli/SKILL.md"
                ),
                SessionSlashCommand(
                    name: "skill:tdd",
                    description: "Test-driven development with red-green-refactor loop.",
                    source: .skill,
                    location: .project,
                    path: "/tmp/project/.pi/skills/tdd/SKILL.md"
                )
            ]
        )
        let menu = structuredSessionSlashCommandMenuPresentation(for: "/skill:", screen: screen)

        #expect(menu.isVisible)
        #expect(menu.commands.map(\.displayText) == ["/skill:create-cli [u]", "/skill:tdd [p]"])
        #expect(menu.commands.first?.summary == "CLI UX/spec: args, flags, help, output, errors, config, dry-run.")
    }

    @Test func structuredSessionSlashCommandMenuUsesStaticPiModelCommandAndLiveModelSuggestions() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "model anthropic/claude-sonnet-4-20250514",
                    displayName: "model anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4",
                    insertionText: "model anthropic/claude-sonnet-4-20250514",
                    suggestionQueryPrefix: "model ",
                    description: "Switch to anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4.",
                    source: .builtIn
                ),
                SessionSlashCommand(
                    name: "skill:tdd",
                    description: "Test-driven development with red-green-refactor loop.",
                    source: .skill,
                    location: .project,
                    path: "/tmp/project/.pi/skills/tdd/SKILL.md"
                )
            ]
        )

        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText).contains("/model <provider>/<model>"))
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.contains(where: { $0.displayText.contains("Claude Sonnet 4") }) == false)
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/model anth", screen: screen).commands.map(\.displayText) == ["/model anthropic/claude-sonnet-4-20250514 — Claude Sonnet 4"])
    }

    @Test func structuredSessionSlashCommandMenuUsesLivePiThinkingCommandsOnlyAfterThinkingPrefix() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "thinking high",
                    displayName: "thinking high",
                    insertionText: "thinking high",
                    suggestionQueryPrefix: "thinking ",
                    description: "Set Pi thinking level to high.",
                    source: .builtIn
                )
            ]
        )

        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText).contains("/thinking <level>"))
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.contains(where: { $0.displayText == "/thinking high" }) == false)
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/thinking h", screen: screen).commands.map(\.displayText) == ["/thinking high"])
    }

    @Test func structuredSessionSlashCommandMenuUsesStaticPiQueueControlsAndLiveModeSuggestions() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "steering-mode one-at-a-time",
                    displayName: "steering-mode one-at-a-time",
                    insertionText: "steering-mode one-at-a-time",
                    suggestionQueryPrefix: "steering-mode ",
                    description: "Current Pi steering mode.",
                    source: .builtIn
                )
            ]
        )

        let rootCommands = structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText)

        #expect(rootCommands.contains("/steer <message>"))
        #expect(rootCommands.contains("/follow-up <message>"))
        #expect(rootCommands.contains("/abort"))
        #expect(rootCommands.contains("/steering-mode <mode>"))
        #expect(rootCommands.contains("/follow-up-mode <mode>"))
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/steering-mode o", screen: screen).commands.map(\.displayText) == ["/steering-mode one-at-a-time"])
    }

    @Test func structuredSessionSlashCommandMenuUsesStaticPiCompactionAndRetryControls() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            transcript: ""
        )

        let rootCommands = structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.map(\.displayText)

        #expect(rootCommands.contains("/cycle-model"))
        #expect(rootCommands.contains("/cycle-thinking-level"))
        #expect(rootCommands.contains("/compact [instructions]"))
        #expect(rootCommands.contains("/auto-compaction <on|off>"))
        #expect(rootCommands.contains("/auto-retry <on|off>"))
        #expect(rootCommands.contains("/abort-retry"))
    }

    @Test func structuredSessionSlashCommandMenuUsesLiveCodexModelCommandsOnlyAfterModelPrefix() {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "model gpt-5.5",
                    displayName: "model gpt-5.5 — GPT-5.5",
                    insertionText: "model gpt-5.5",
                    suggestionQueryPrefix: "model ",
                    description: "Default model. Frontier coding model.",
                    source: .builtIn
                )
            ]
        )

        #expect(structuredSessionSlashCommandMenuPresentation(for: "/", screen: screen).commands.contains(where: { $0.displayText.contains("GPT-5.5") }) == false)
        #expect(structuredSessionSlashCommandMenuPresentation(for: "/model g", screen: screen).commands.map(\.displayText) == ["/model gpt-5.5 — GPT-5.5"])
    }

    @Test func structuredSessionSlashCommandMenuUsesLiveBobCommandArgumentHintsFromSessionScreen() throws {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .ibmBob,
                isDefault: true,
                state: .ready
            ),
            transcript: "",
            slashCommands: [
                SessionSlashCommand(
                    name: "api-endpoint",
                    displayName: "api-endpoint <endpoint-name> <http-method>",
                    insertionText: "api-endpoint ",
                    description: "Create a new API endpoint.",
                    source: .prompt,
                    location: .project,
                    path: "/tmp/project/.bob/commands/api-endpoint.md"
                )
            ]
        )
        let menu = structuredSessionSlashCommandMenuPresentation(for: "/api", screen: screen)

        #expect(menu.commands.map(\.displayText) == ["/api-endpoint <endpoint-name> <http-method> [p]"])
        let command = try #require(menu.commands.first)
        #expect(applyStructuredSessionSlashCommand(command, to: "/api") == "/api-endpoint ")
    }

    @Test func structuredSessionSlashCommandMenuAppliesSelectedCommandThroughSharedMenuPolicy() throws {
        let screen = SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .codex,
                isDefault: true,
                state: .ready
            ),
            transcript: ""
        )
        let menu = structuredSessionSlashCommandMenuPresentation(for: "  /go", screen: screen)
        let command = try #require(menu.commands.first)

        #expect(menu.applying(command, to: "  /go") == "  /goal ")
    }

    @Test func applyStructuredSessionSlashCommandReplacesSlashDraftWhilePreservingLeadingWhitespace() {
        let command = StructuredSessionSlashCommand(
            matchText: "goal",
            displayText: "/goal <objective>",
            insertionText: "/goal ",
            summary: "Set or view the goal for a long-running task.",
            acceptsArguments: true
        )

        #expect(applyStructuredSessionSlashCommand(command, to: "  /go") == "  /goal ")
    }

    // Collapse decision regression tests for #205.
    // These unit-test the pure bounding logic that keeps structured feed row content
    // (assistant streaming previews + long detail/command output) from growing unbounded
    // during live draft appends. They are the "new regression test for row geometry stability
    // under burst" (the decisions are what stop the 200 ms fixture bursts from thrashing
    // layout in the tail). Thresholds/captions match the original view implementations exactly
    // so finalize behavior and visuals are preserved. The views now delegate here.
    @Test func structuredSessionShouldCollapseStreamingMarkdownPreviewRespectsLineAndCharThresholds() {
        // Short content: never collapse (both platform widths)
        #expect(structuredSessionShouldCollapseStreamingMarkdownPreview("short reply", charactersPerLine: 72) == false)
        #expect(structuredSessionShouldCollapseStreamingMarkdownPreview("Pi: hi", charactersPerLine: 56) == false)

        // Char count bomb (> 6_000) collapses regardless of wrapping
        let charBomb = String(repeating: "x", count: 6_001)
        #expect(structuredSessionShouldCollapseStreamingMarkdownPreview(charBomb, charactersPerLine: 72) == true)

        // Wrapped lines at macOS width (72 chars/line, >18 lines)
        let macLong = (0 ..< 20).map { _ in String(repeating: "m", count: 70) }.joined(separator: "\n")
        #expect(structuredSessionShouldCollapseStreamingMarkdownPreview(macLong, charactersPerLine: 72) == true)

        // Wrapped lines at iOS width (56 chars/line)
        let iosLong = (0 ..< 20).map { _ in String(repeating: "i", count: 50) }.joined(separator: "\n")
        #expect(structuredSessionShouldCollapseStreamingMarkdownPreview(iosLong, charactersPerLine: 56) == true)

        // Boundary: exactly 18 lines at width does not trigger (strict > 18)
        let macBoundary = (0 ..< 18).map { _ in String(repeating: "b", count: 72) }.joined(separator: "\n")
        #expect(structuredSessionShouldCollapseStreamingMarkdownPreview(macBoundary, charactersPerLine: 72) == false)
    }

    @Test func structuredSessionShouldCollapseDetailPreviewRespectsDetailThreshold() {
        #expect(structuredSessionShouldCollapseDetailPreview("short output", charactersPerLine: 84) == false)
        #expect(structuredSessionShouldCollapseDetailPreview("short output", charactersPerLine: 60) == false)

        // >10 wrapped lines triggers (mac 84 or iOS 60)
        let detailLong = (0 ..< 12).map { "line \($0)" }.joined(separator: "\n")
        #expect(structuredSessionShouldCollapseDetailPreview(detailLong, charactersPerLine: 84) == true)
        #expect(structuredSessionShouldCollapseDetailPreview(detailLong, charactersPerLine: 60) == true)
    }

    // MARK: - Feed scroll policy (#211)

    @Test func structuredSessionFeedScrollTargetUsesLiveDraftRowWhileStreaming() throws {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let userItem = SessionActivityItem(kind: .message, text: "You: hi")
        let presenter = StructuredSessionFeedPresenter()
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [userItem],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "draft"),
            isAgentTurnInProgress: true
        )
        let feed = presenter.presentation(for: screen)
        let presentation = FocusedStructuredSessionPresentation(
            session: session,
            feed: feed,
            autoScrollTrigger: structuredSessionAutoScrollTrigger(for: screen)
        )

        let draftRowID = try #require(feed.activityRows.last?.id)
        #expect(structuredSessionFeedScrollTarget(for: presentation) == .activityRow(draftRowID))
    }

    @Test func structuredSessionFeedScrollTargetFallsBackToBottomSentinelWhenFeedEmpty() {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let presentation = FocusedStructuredSessionPresentation(
            session: session,
            feed: StructuredSessionFeedPresentation(
                copy: structuredSessionPresentationCopy(for: SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "")),
                activityRows: [],
                pendingApprovalRequests: [],
                thinkingIndicator: nil
            ),
            autoScrollTrigger: StructuredSessionAutoScrollTrigger(
                lastActivityRowID: nil,
                pendingApprovalRequestIDs: [],
                pendingDialogIDs: []
            )
        )

        #expect(structuredSessionFeedScrollTarget(for: presentation) == .bottomSentinel)
    }

    @Test func structuredSessionBottomScrollIntentIgnoresDwellAndMetadataChurnWhenPinned() {
        let activityID = UUID()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let row = StructuredSessionActivityRow(
            id: activityID,
            title: "Message",
            systemImage: "message",
            text: "Pi: stable",
            emphasis: .accent
        )
        let feed = StructuredSessionFeedPresentation(
            copy: structuredSessionPresentationCopy(for: SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "")),
            activityRows: [row],
            pendingApprovalRequests: [],
            thinkingIndicator: nil
        )
        let trigger = StructuredSessionAutoScrollTrigger(
            lastActivityRowID: activityID,
            pendingApprovalRequestIDs: [],
            pendingDialogIDs: []
        )
        let presentation = FocusedStructuredSessionPresentation(session: session, feed: feed, autoScrollTrigger: trigger)
        let snapshot = structuredSessionFeedScrollSnapshot(for: presentation)

        // Dwell-stable feed: same rows and trigger as live metadata churn (#208) would still publish.
        #expect(
            structuredSessionBottomScrollIntent(
                previous: snapshot,
                current: snapshot,
                isPinnedToBottom: true
            ) == .none
        )
        #expect(structuredSessionShouldRequestBottomScroll(
            previous: snapshot,
            current: snapshot,
            isPinnedToBottom: true
        ) == false)
    }

    @Test func structuredSessionBottomScrollIntentRequestsAnimatedScrollWhenPendingChromeChangesWhilePinned() {
        let activityID = UUID()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let feed = StructuredSessionFeedPresentation(
            copy: structuredSessionPresentationCopy(for: SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "")),
            activityRows: [
                StructuredSessionActivityRow(
                    id: activityID,
                    title: "Message",
                    systemImage: "message",
                    text: "Pi: stable",
                    emphasis: .accent
                )
            ],
            pendingApprovalRequests: [],
            thinkingIndicator: nil
        )
        let previous = structuredSessionFeedScrollSnapshot(for: FocusedStructuredSessionPresentation(
            session: session,
            feed: feed,
            autoScrollTrigger: StructuredSessionAutoScrollTrigger(
                lastActivityRowID: activityID,
                pendingApprovalRequestIDs: [],
                pendingDialogIDs: []
            )
        ))
        let current = structuredSessionFeedScrollSnapshot(for: FocusedStructuredSessionPresentation(
            session: session,
            feed: feed,
            autoScrollTrigger: StructuredSessionAutoScrollTrigger(
                lastActivityRowID: activityID,
                pendingApprovalRequestIDs: [UUID()],
                pendingDialogIDs: ["dialog-1"]
            )
        ))

        #expect(
            structuredSessionBottomScrollIntent(previous: previous, current: current, isPinnedToBottom: true)
                == .animated
        )
    }

    @Test func structuredSessionBottomScrollIntentRequestsImmediateScrollWhenLastActivityRowAppendsWhilePinned() {
        let firstID = UUID()
        let secondID = UUID()
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        func presentation(lastRowID: UUID) -> FocusedStructuredSessionPresentation {
            let row = StructuredSessionActivityRow(
                id: lastRowID,
                title: "Message",
                systemImage: "message",
                text: "Pi: row",
                emphasis: .accent
            )
            return FocusedStructuredSessionPresentation(
                session: session,
                feed: StructuredSessionFeedPresentation(
                    copy: structuredSessionPresentationCopy(for: SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "")),
                    activityRows: [row],
                    pendingApprovalRequests: [],
                    thinkingIndicator: nil
                ),
                autoScrollTrigger: StructuredSessionAutoScrollTrigger(
                    lastActivityRowID: lastRowID,
                    pendingApprovalRequestIDs: [],
                    pendingDialogIDs: []
                )
            )
        }

        let previous = structuredSessionFeedScrollSnapshot(for: presentation(lastRowID: firstID))
        let current = structuredSessionFeedScrollSnapshot(for: presentation(lastRowID: secondID))

        #expect(
            structuredSessionBottomScrollIntent(previous: previous, current: current, isPinnedToBottom: true) == .immediate
        )
        #expect(structuredSessionShouldRequestBottomScroll(previous: previous, current: current, isPinnedToBottom: true))
        #expect(structuredSessionShouldRequestBottomScroll(previous: previous, current: current, isPinnedToBottom: false) == false)
    }

    @Test func structuredSessionBottomScrollIntentCoalescesLiveDraftGrowthWithoutChangingRowIDWhilePinned() throws {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let draftRowID = UUID()
        let sealedActivityRowID = UUID()
        func snapshot(text: String) -> StructuredSessionFeedScrollSnapshot {
            let row = StructuredSessionActivityRow(
                id: draftRowID,
                title: "Message",
                systemImage: "message",
                text: text,
                emphasis: .accent,
                conversationPresentation: StructuredSessionConversationPresentation(
                    role: .assistant(label: "Pi"),
                    text: text,
                    isStreaming: true
                )
            )
            let presentation = FocusedStructuredSessionPresentation(
                session: session,
                feed: StructuredSessionFeedPresentation(
                    copy: structuredSessionPresentationCopy(for: SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "")),
                    activityRows: [row],
                    pendingApprovalRequests: [],
                    thinkingIndicator: nil
                ),
                autoScrollTrigger: StructuredSessionAutoScrollTrigger(
                    lastActivityRowID: sealedActivityRowID,
                    pendingApprovalRequestIDs: [],
                    pendingDialogIDs: []
                )
            )
            return structuredSessionFeedScrollSnapshot(for: presentation)
        }

        let previous = snapshot(text: "Pi: hel")
        let current = snapshot(text: "Pi: hello")

        #expect(previous.feedScrollTarget == .activityRow(draftRowID))

        #expect(
            structuredSessionBottomScrollIntent(previous: previous, current: current, isPinnedToBottom: true)
                == .draftGrowthCoalesced
        )
    }

    @Test func structuredSessionDraftGrowthScrollThrottleBucketsRapidCoalescedRequests() {
        var now = 0.0
        let throttle = StructuredSessionDraftGrowthScrollThrottle(minimumInterval: 0.12, now: { now })
        var performed = 0

        #expect(throttle.requestIfDue { performed += 1 })
        #expect(performed == 1)

        now = 0.05
        #expect(throttle.requestIfDue { performed += 1 } == false)
        #expect(performed == 1)

        now = 0.13
        #expect(throttle.requestIfDue { performed += 1 })
        #expect(performed == 2)
    }

    @Test func structuredSessionIsPinnedToBottomFromBottomDistanceTreatsNearBottomAsPinned() {
        #expect(structuredSessionIsPinnedToBottomFromBottomDistance(0))
        #expect(structuredSessionIsPinnedToBottomFromBottomDistance(24))
        #expect(structuredSessionIsPinnedToBottomFromBottomDistance(48))
        #expect(structuredSessionIsPinnedToBottomFromBottomDistance(49) == false)
        #expect(structuredSessionIsPinnedToBottomFromBottomDistance(120) == false)
    }

    @Test func structuredSessionFeedPinStateKeepsFollowingWhenContentGrowsAtTopOffset() {
        let initial = StructuredSessionFeedPinState()
        let afterGrowth = structuredSessionFeedPinState(
            previous: initial,
            distanceFromBottom: 800,
            contentOffsetY: 0
        )
        #expect(afterGrowth.isFollowingBottom)
        #expect(afterGrowth.userHasDetachedFromBottom == false)
    }

    @Test func structuredSessionFeedPinStateDetachesWhenUserScrollsUp() {
        let initial = StructuredSessionFeedPinState()
        let detached = structuredSessionFeedPinState(
            previous: initial,
            distanceFromBottom: 400,
            contentOffsetY: 120
        )
        #expect(detached.isFollowingBottom == false)
        #expect(detached.userHasDetachedFromBottom)
    }

    @Test func structuredSessionFeedPinStateReattachesAtBottom() {
        let detached = StructuredSessionFeedPinState(isFollowingBottom: false, userHasDetachedFromBottom: true)
        let reattached = structuredSessionFeedPinState(
            previous: detached,
            distanceFromBottom: 12,
            contentOffsetY: 500
        )
        #expect(reattached.isFollowingBottom)
        #expect(reattached.userHasDetachedFromBottom == false)
    }

    @Test func structuredSessionFeedPinStateIfChangedSkipsRedundantGeometrySamples() {
        let initial = StructuredSessionFeedPinState()
        let sample = StructuredSessionScrollGeometrySample(distanceFromBottom: 400, contentOffsetY: 0)
        #expect(structuredSessionFeedPinStateIfChanged(previous: initial, sample: sample) == nil)
    }

    @Test func structuredSessionFeedFollowScrollTokenChangesWhenDraftGrows() {
        let session = Session(id: UUID(), workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready)
        let rowID = UUID()
        func presentation(text: String) -> FocusedStructuredSessionPresentation {
            let row = StructuredSessionActivityRow(
                id: rowID,
                title: "Message",
                systemImage: "message",
                text: text,
                emphasis: .accent,
                conversationPresentation: StructuredSessionConversationPresentation(
                    role: .assistant(label: "Pi"),
                    text: text,
                    isStreaming: true
                )
            )
            let feed = StructuredSessionFeedPresentation(
                copy: structuredSessionPresentationCopy(for: SessionScreen(session: session, primarySurface: .structuredActivityFeed, transcript: "")),
                activityRows: [row],
                pendingApprovalRequests: [],
                thinkingIndicator: nil
            )
            return FocusedStructuredSessionPresentation(
                session: session,
                feed: feed,
                autoScrollTrigger: StructuredSessionAutoScrollTrigger(lastActivityRowID: rowID, pendingApprovalRequestIDs: [], pendingDialogIDs: [])
            )
        }
        let short = structuredSessionFeedFollowScrollToken(for: presentation(text: "a"))
        let long = structuredSessionFeedFollowScrollToken(for: presentation(text: "abcdef"))
        #expect(short != long)
    }

    @Test func structuredSessionRequestBottomScrollUsesThrottleOnlyForDraftGrowthCoalescedIntent() {
        var now = 0.0
        let throttle = StructuredSessionDraftGrowthScrollThrottle(minimumInterval: 0.12, now: { now })
        var scheduled: [() -> Void] = []
        let coordinator = StructuredSessionAutoScrollCoordinator { work in
            scheduled.append(work)
        }
        var performed: [StructuredSessionAutoScrollAnimation] = []
        let scroll: (StructuredSessionAutoScrollAnimation) -> Void = { animation in
            performed.append(animation)
        }

        structuredSessionRequestBottomScroll(
            intent: .immediate,
            coordinator: coordinator,
            draftGrowthThrottle: throttle,
            performScroll: scroll
        )
        #expect(scheduled.count == 1)
        scheduled.first?()
        #expect(performed == [.immediate])

        structuredSessionRequestBottomScroll(
            intent: .draftGrowthCoalesced,
            coordinator: coordinator,
            draftGrowthThrottle: throttle,
            performScroll: scroll
        )
        #expect(scheduled.count == 2)
        scheduled.last?()
        #expect(performed == [.immediate, .immediate])

        now = 0.05
        structuredSessionRequestBottomScroll(
            intent: .draftGrowthCoalesced,
            coordinator: coordinator,
            draftGrowthThrottle: throttle,
            performScroll: scroll
        )
        #expect(scheduled.count == 2)

        now = 0.13
        structuredSessionRequestBottomScroll(
            intent: .draftGrowthCoalesced,
            coordinator: coordinator,
            draftGrowthThrottle: throttle,
            performScroll: scroll
        )
        #expect(scheduled.count == 3)
        scheduled.last?()
        #expect(performed == [.immediate, .immediate, .immediate])
    }
}
