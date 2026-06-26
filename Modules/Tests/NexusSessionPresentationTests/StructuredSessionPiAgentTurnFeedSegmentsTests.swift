import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

/// Regression suite for Pi **Agent Turn** composite feed segments (#236, ADR 0037).
struct StructuredSessionPiAgentTurnFeedSegmentsTests {
    private func piSession() -> Session {
        Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
    }

    @Test func piFeedSegmentsEmitUserAgentTurnAndStandaloneRows() throws {
        let userID = UUID()
        let thoughtsID = UUID()
        let commandID = UUID()
        let subagentMessageID = UUID()
        let answerID = UUID()
        let connectedID = UUID()

        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(id: connectedID, kind: .status, text: "Pi shared Session stream connected"),
                SessionActivityItem(
                    id: userID,
                    kind: .message,
                    text: "You: hello",
                    prompt: SessionPrompt(text: "hello")
                ),
                SessionActivityItem(
                    id: thoughtsID,
                    kind: .status,
                    text: "thoughts:",
                    detailText: "Plan the change."
                ),
                SessionActivityItem(id: commandID, kind: .command, text: "subagent reviewer: Review diff"),
                SessionActivityItem(id: subagentMessageID, kind: .message, text: "reviewer: Looks good overall."),
                SessionActivityItem(id: answerID, kind: .message, text: "Pi: Done"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))

        #expect(segments.count == 3)
        guard case .standalone(let connected) = segments[0] else {
            Issue.record("Expected standalone session status")
            return
        }
        #expect(connected.id == connectedID)

        guard case .userMessage(let user) = segments[1] else {
            Issue.record("Expected user message segment")
            return
        }
        #expect(user.activityItemID == userID)
        #expect(user.text == "hello")

        guard case .agentTurn(let turn) = segments[2] else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.isOpen == false)
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Plan the change."])
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].callPreview == "subagent reviewer: Review diff")
        #expect(turn.toolStackItems[0].subagentOutputs == ["Looks good overall."])
        #expect(turn.finalAnswer?.text == "Done")
        #expect(turn.finalAnswer?.isStreaming == false)
    }

    @Test func piFeedSegmentsEmitSeparateReasoningBlocksPerThoughtsStatus() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(
                    kind: .message,
                    text: "You: go",
                    prompt: SessionPrompt(text: "go")
                ),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "First thought."),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Second thought."),
                SessionActivityItem(kind: .message, text: "Pi: ok"),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["First thought.", "Second thought."])
    }

    @Test func piFeedSegmentsNestSubagentAssistantTextUnderParentToolCall() throws {
        let commandID = UUID()
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: run", prompt: SessionPrompt(text: "run")),
                SessionActivityItem(
                    id: commandID, kind: .command, text: "subagent reviewer: Task", detailText: "step 1"),
                SessionActivityItem(kind: .message, text: "reviewer: Summary output"),
                SessionActivityItem(kind: .message, text: "Pi: final"),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].activityItemID == commandID)
        #expect(turn.toolStackItems[0].detailText == "step 1")
        #expect(turn.toolStackItems[0].subagentOutputs == ["Summary output"])
        #expect(turn.finalAnswer?.text == "final")
    }

    @Test func piOpenTurnAbsorbsPostInterimPiWorkIntoContinuationTurn() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: review", prompt: SessionPrompt(text: "review")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Plan."),
                SessionActivityItem(kind: .command, text: "read: CONTEXT.md"),
                SessionActivityItem(
                    kind: .message, text: "Pi: Gathering recent changes and project context for the review"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "More planning."),
                SessionActivityItem(kind: .command, text: "bash: ls"),
            ],
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .userMessage = segments[0],
            case .agentTurn(let turn) = segments[1]
        else {
            Issue.record("Expected user and single open turn absorbing work after hidden interim Pi")
            return
        }
        #expect(segments.count == 2)
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Plan.", "More planning."])
        #expect(turn.toolStackItems.count == 2)
    }

    @Test func piHidesStandalonePiWhenClosedTurnFinalAnswerMatches() throws {
        let finalText = "Done with a long enough answer for the test."
        let turnID = UUID()
        let dupID = UUID()
        let segments: [StructuredSessionFeedSegment] = [
            .userMessage(StructuredSessionFeedUserMessageSegment(activityItemID: UUID(), text: "hi")),
            .agentTurn(
                StructuredSessionFeedAgentTurnSegment(
                    id: turnID,
                    isOpen: false,
                    stackItems: [],
                    finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment(text: finalText)
                )),
            .standalone(
                SessionActivityItem(id: dupID, kind: .message, text: "Pi: \(finalText)")),
        ]
        guard case .standalone(let dup) = segments[2] else {
            Issue.record("Expected standalone Pi")
            return
        }
        let duplicateFinalAnswerBodies = structuredSessionPiFinalAnswerBodies(in: segments)
        #expect(
            structuredSessionPiShouldRenderStandaloneFeedSegment(
                item: dup,
                duplicateFinalAnswerBodies: duplicateFinalAnswerBodies
            ) == false
        )
    }

    /// The old `in segments:` overload rescanned every segment per standalone item (O(visible * total)
    /// per render). Callers must build this set once and reuse it across all standalone items in a render.
    @Test func finalAnswerBodiesCollectsOnlyClosedTurnFinalAnswers() throws {
        let openTurnID = UUID()
        let closedTurnID = UUID()
        let segments: [StructuredSessionFeedSegment] = [
            .agentTurn(
                StructuredSessionFeedAgentTurnSegment(
                    id: openTurnID,
                    isOpen: true,
                    finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment(text: "still streaming")
                )),
            .agentTurn(
                StructuredSessionFeedAgentTurnSegment(
                    id: closedTurnID,
                    isOpen: false,
                    finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment(text: "  done answer  ")
                )),
        ]
        let bodies = structuredSessionPiFinalAnswerBodies(in: segments)
        #expect(bodies == ["done answer"])
    }

    @Test func piOpenTurnPostInterimPiCommandsLiveInContinuationTurn() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: review", prompt: SessionPrompt(text: "review")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Scan."),
                SessionActivityItem(
                    kind: .message,
                    text: "Pi: Reviewing Nexus: checking recent changes and key architecture."
                ),
                SessionActivityItem(kind: .command, text: "cd /Users/ck/source/repos/nexus"),
            ],
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected single open turn with thoughts, hidden interim Pi, and cd")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].callPreview == "cd /Users/ck/source/repos/nexus")
    }

    @Test func piOpenTurnDoesNotAttachLiveAssistantDraftAsFinalAnswerPlaceholder() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi", prompt: SessionPrompt(text: "hi")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Thinking through it."),
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: "partial"),
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn without draft Pi bubble")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.finalAnswer == nil)
    }

    @Test func piFeedPresentationIncludesCompositeFeedSegments() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: hi", prompt: SessionPrompt(text: "hi")),
                SessionActivityItem(kind: .message, text: "Pi: hey"),
            ]
        )

        let feed = structuredSessionFeedPresentation(for: screen)
        let segments = try #require(feed.feedSegments)
        #expect(segments.count == 2)
        guard case .userMessage = segments[0],
            case .agentTurn = segments[1]
        else {
            Issue.record("Expected user then agent turn segments")
            return
        }
    }

    @Test func nonPiSessionsDoNotEmitPiCompositeFeedSegments() {
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
                SessionActivityItem(kind: .message, text: "You: hi")
            ]
        )

        #expect(structuredSessionPiFeedSegments(for: screen) == nil)
    }

    @Test func piClosedTurnAbsorbsThoughtsAndToolsAfterInterimPiMessage() throws {
        // Matches macOS hybrid feed bug: composite card from early slice, then flat thoughts/commands after turn_end.
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: review", prompt: SessionPrompt(text: "review")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Early plan."),
                SessionActivityItem(kind: .command, text: "read: A.swift"),
                SessionActivityItem(kind: .command, text: "read: B.swift"),
                SessionActivityItem(
                    kind: .message,
                    text: "Pi: Scope unclear — checking recent changes and repo state to focus the review."
                ),
                SessionActivityItem(
                    kind: .status,
                    text: "thoughts:",
                    detailText: "The user asked for a code review on Nexus…"
                ),
                SessionActivityItem(kind: .command, text: "read: StructuredSessionPiFeedSegmentStyle.swift"),
                SessionActivityItem(kind: .command, text: "read: NexusSessionPresentation/foo.swift"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected single composite agent turn")
            return
        }
        #expect(
            turn.reasoningStackItems.map(\.markdownBody) == [
                "Early plan.",
                "The user asked for a code review on Nexus…",
            ])
        #expect(turn.toolStackItems.count == 4)
        #expect(turn.finalAnswer?.text == "Scope unclear — checking recent changes and repo state to focus the review.")
    }

    @Test func piProgressDoesNotSplitTurnIntoLegacyRows() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: run", prompt: SessionPrompt(text: "run")),
                SessionActivityItem(kind: .command, text: "/bash ls"),
                SessionActivityItem(kind: .progress, text: "Running bash: ls"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Still working."),
                SessionActivityItem(kind: .message, text: "Pi: done"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected composite agent turn")
            return
        }
        #expect(turn.turnNotices == [.progress("Running bash: ls")])
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Still working."])
        #expect(turn.finalAnswer?.text == "done")
    }

    @Test func piMidTurnSessionStatusStaysInTurnNoticesWithoutSplitting() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: work", prompt: SessionPrompt(text: "work")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Plan."),
                SessionActivityItem(kind: .status, text: "Auto-compacting the session context"),
                SessionActivityItem(kind: .command, text: "read: x.swift"),
                SessionActivityItem(kind: .message, text: "Pi: done"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.turnNotices.contains(.progress("Auto-compacting the session context")))
        #expect(turn.toolStackItems.count == 1)
    }

    @Test func piBashOutputMergesIntoOpenBashToolWithoutStandaloneRow() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: ls", prompt: SessionPrompt(text: "ls")),
                SessionActivityItem(kind: .command, text: "/bash ls -la"),
                SessionActivityItem(kind: .progress, text: "Running bash: ls -la"),
                SessionActivityItem(kind: .message, text: "bash: total 8\ndrwxr-xr-x"),
                SessionActivityItem(kind: .message, text: "Pi: listed"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].detailText?.contains("total 8") == true)
        #expect(turn.finalAnswer?.text == "listed")
    }

    @Test func piOrphanTurnErrorSurfacesInTurnNoticesWithoutSplitting() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .message, text: "Pi: partial answer"),
                SessionActivityItem(kind: .error, text: "Operation aborted"),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Recovering."),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.turnNotices == [.error("Operation aborted")])
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Recovering."])
        #expect(turn.finalAnswer?.text == "partial answer")
    }

    @Test func piLastAssistantMessageStaysInTurnWithoutStandaloneRow() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: /last", prompt: SessionPrompt(text: "/last")),
                SessionActivityItem(kind: .command, text: "/get-last-assistant-text"),
                SessionActivityItem(kind: .message, text: "Last assistant message: prior reply text"),
                SessionActivityItem(kind: .message, text: "Pi: noted"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.turnNotices.contains(.progress("Last assistant message: prior reply text")))
        #expect(turn.finalAnswer?.text == "noted")
    }

    @Test func piCompletionAndDiffRowsStayInTurnNoticesWithoutSplitting() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: edit", prompt: SessionPrompt(text: "edit")),
                SessionActivityItem(kind: .diff, text: "Edited ContentView.swift"),
                SessionActivityItem(kind: .completion, text: "Turn complete"),
                SessionActivityItem(kind: .message, text: "Pi: saved"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.turnNotices.contains(.progress("Edited ContentView.swift")))
        #expect(turn.turnNotices.contains(.progress("Turn complete")))
    }

    @Test func piMultipleErrorsOnSameToolMergeInChronologicalOrder() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: read", prompt: SessionPrompt(text: "read")),
                SessionActivityItem(kind: .command, text: "read: x.swift", detailText: "partial output"),
                SessionActivityItem(kind: .error, text: "first failure"),
                SessionActivityItem(kind: .error, text: "second failure"),
                SessionActivityItem(kind: .message, text: "Pi: stopped"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].detailText == "partial output\nfirst failure\nsecond failure")
    }

    @Test func piErrorsAttachToMostRecentlyOpenedTool() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .command, text: "read: a.swift"),
                SessionActivityItem(kind: .error, text: "err-a"),
                SessionActivityItem(kind: .command, text: "read: b.swift"),
                SessionActivityItem(kind: .error, text: "err-b"),
                SessionActivityItem(kind: .message, text: "Pi: ok"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 2)
        #expect(turn.toolStackItems[0].detailText == "err-a")
        #expect(turn.toolStackItems[1].detailText == "err-b")
    }

    @Test func piErrorAfterInterimPiBeforeNextCommandUsesLastOpenTool() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .command, text: "read: skill.md"),
                SessionActivityItem(kind: .message, text: "Pi: still checking"),
                SessionActivityItem(kind: .error, text: "ENOENT: skill.md"),
                SessionActivityItem(kind: .command, text: "read: fallback.swift"),
                SessionActivityItem(kind: .message, text: "Pi: done"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 2)
        #expect(turn.toolStackItems[0].detailText == "ENOENT: skill.md")
        #expect(turn.toolStackItems[1].detailText == nil)
    }

    @Test func piRawAssistantMessagesThatOnlyEchoToolOutputStayInsideToolAccordion() throws {
        let shellOutput = "a865ced fix(Modules): surface Pi tool output"
        let readOutput = "# Nexus\n\nWorkspace-first control center"
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(
                    kind: .message,
                    text: "You: Lets perform a code review on nexus",
                    prompt: SessionPrompt(text: "Lets perform a code review on nexus")
                ),
                SessionActivityItem(kind: .command, text: "Shell: git log", detailText: shellOutput),
                SessionActivityItem(kind: .command, text: "Read: ARCHITECTURE.md", detailText: readOutput),
                SessionActivityItem(kind: .message, text: shellOutput),
                SessionActivityItem(kind: .message, text: readOutput),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 2)
        #expect(turn.toolStackItems[0].detailText == shellOutput)
        #expect(turn.toolStackItems[1].detailText == readOutput)
        #expect(turn.finalAnswer == nil)
    }

    @Test func piToolErrorDoesNotSplitTurnIntoLegacyRows() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: review", prompt: SessionPrompt(text: "review")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Scoping the review."),
                SessionActivityItem(kind: .command, text: "read: first.swift"),
                SessionActivityItem(
                    kind: .message, text: "Pi: Scoping the review: repo layout, recent changes, and critical modules."),
                SessionActivityItem(kind: .error, text: "ENOENT: no such file or directory, access '/tmp/missing'"),
                SessionActivityItem(
                    kind: .status, text: "thoughts:", detailText: "Let me dive into recent Pi/agent-turn changes."),
                SessionActivityItem(kind: .command, text: "read: second.swift"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected single composite agent turn")
            return
        }
        #expect(
            turn.reasoningStackItems.map(\.markdownBody) == [
                "Scoping the review.",
                "Let me dive into recent Pi/agent-turn changes.",
            ])
        #expect(turn.toolStackItems.count == 2)
        #expect(turn.toolStackItems[0].detailText?.contains("ENOENT") == true)
        #expect(turn.finalAnswer?.text == "Scoping the review: repo layout, recent changes, and critical modules.")
    }

    @Test func piClosedTurnUsesLastPiMessageAsFinalAnswerWhenMultipleAssistantLines() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .message, text: "Pi: interim status"),
                SessionActivityItem(kind: .command, text: "read: x"),
                SessionActivityItem(kind: .message, text: "Pi: final report"),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        guard case .agentTurn(let turn) = segments.last else {
            Issue.record("Expected agent turn")
            return
        }
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.finalAnswer?.text == "final report")
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
    }

    @Test func piAgentTurnRegressionThoughtsAndCommandRowsNeverLeakAsStandaloneSegments() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: ship it", prompt: SessionPrompt(text: "ship it")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Checklist."),
                SessionActivityItem(kind: .command, text: "read: AGENTS.md"),
                SessionActivityItem(kind: .message, text: "Pi: Shipped."),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        #expect(
            segments.contains {
                if case .standalone = $0 { return true }
                return false
            } == false)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected composite agent turn")
            return
        }
        #expect(turn.reasoningStackItems.map(\.markdownBody) == ["Checklist."])
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.toolStackItems[0].callPreview == "read: AGENTS.md")
        #expect(turn.finalAnswer?.text == "Shipped.")
    }

    @Test func piAgentTurnRegressionCompositeTurnUsesFewerFeedSegmentsThanFlatActivityRows() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Plan."),
                SessionActivityItem(kind: .command, text: "bash: true"),
                SessionActivityItem(kind: .command, text: "read: README.md", detailText: "{\"path\":\"README.md\"}"),
                SessionActivityItem(kind: .message, text: "Pi: done"),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(screen.activityItems.count == 5)
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected agent turn segment")
            return
        }
        #expect(turn.toolStackItems.count == 2)
        #expect(turn.toolStackItems[1].detailText == "{\"path\":\"README.md\"}")
    }

    @Test func piAgentTurnRegressionOutsideStackRowsStayStandaloneNotInsideTurn() throws {
        let approvalID = UUID()
        let retryID = UUID()
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: deploy", prompt: SessionPrompt(text: "deploy")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Verify."),
                SessionActivityItem(kind: .message, text: "Pi: ok"),
                SessionActivityItem(
                    id: approvalID,
                    kind: .approvalRequest,
                    text: "Approval Request: Deploy to production?"
                ),
                SessionActivityItem(
                    id: retryID,
                    kind: .status,
                    text: "Retrying after rate limit"
                ),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 4)
        guard case .userMessage = segments[0],
            case .agentTurn = segments[1],
            case .standalone(let approval) = segments[2],
            case .standalone(let retry) = segments[3]
        else {
            Issue.record("Expected user, agent turn, then outside-stack standalone rows")
            return
        }
        #expect(approval.id == approvalID)
        #expect(approval.kind == .approvalRequest)
        #expect(retry.id == retryID)
        #expect(retry.text == "Retrying after rate limit")
    }

    @Test func piSecondOpenTurnKeepsPreviousFinalAnswerInClosedTurn() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: one", prompt: SessionPrompt(text: "one")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "First thought."),
                SessionActivityItem(kind: .message, text: "Pi: **first final**"),
                SessionActivityItem(kind: .message, text: "You: two", prompt: SessionPrompt(text: "two")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Second thought."),
                SessionActivityItem(kind: .command, text: "read: file.swift"),
                SessionActivityItem(kind: .message, text: "Pi: Still checking tools."),
            ],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "turn_end",
                    family: .turn,
                    rawPayload: #"{"type":"turn_end"}"#
                ),
                SessionProviderEvent(
                    sequence: 1,
                    providerID: .pi,
                    type: "message_update",
                    family: .message,
                    rawPayload: #"{"type":"message_update"}"#
                ),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 4)
        guard case .agentTurn(let firstTurn) = segments[1],
            case .agentTurn(let secondTurn) = segments[3]
        else {
            Issue.record("Expected closed first turn and open second turn without interim Pi bubble")
            return
        }
        #expect(firstTurn.isOpen == false)
        #expect(firstTurn.finalAnswer?.text == "**first final**")
        #expect(secondTurn.isOpen == true)
        #expect(secondTurn.finalAnswer == nil)
    }

    @Test func piSecondClosedTurnFormatsBothFinalAnswers() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: one", prompt: SessionPrompt(text: "one")),
                SessionActivityItem(kind: .message, text: "Pi: **first final**"),
                SessionActivityItem(kind: .message, text: "You: two", prompt: SessionPrompt(text: "two")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Second thought."),
                SessionActivityItem(kind: .message, text: "Pi: # second final"),
            ],
            providerEvents: [
                SessionProviderEvent(
                    sequence: 0,
                    providerID: .pi,
                    type: "turn_end",
                    family: .turn,
                    rawPayload: #"{"type":"turn_end"}"#
                ),
                SessionProviderEvent(
                    sequence: 1,
                    providerID: .pi,
                    type: "turn_end",
                    family: .turn,
                    rawPayload: #"{"type":"turn_end"}"#
                ),
            ],
            isAgentTurnInProgress: false
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 4)
        guard case .agentTurn(let firstTurn) = segments[1],
            case .agentTurn(let secondTurn) = segments[3]
        else {
            Issue.record("Expected two closed agent turns")
            return
        }
        #expect(firstTurn.finalAnswer?.text == "**first final**")
        #expect(secondTurn.finalAnswer?.text == "# second final")
        #expect(firstTurn.isOpen == false)
        #expect(secondTurn.isOpen == false)
    }

    @Test func piAgentTurnRegressionMultipleTurnsProduceSegmentListShape() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: one", prompt: SessionPrompt(text: "one")),
                SessionActivityItem(kind: .message, text: "Pi: first"),
                SessionActivityItem(kind: .message, text: "You: two", prompt: SessionPrompt(text: "two")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Again."),
                SessionActivityItem(kind: .message, text: "Pi: second"),
            ]
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 4)
        let kinds = segments.map { segment -> String in
            switch segment {
            case .userMessage: "user"
            case .agentTurn: "agentTurn"
            case .standalone: "standalone"
            }
        }
        #expect(kinds == ["user", "agentTurn", "user", "agentTurn"])
    }

    @Test func piAgentTurnRegressionOpenTurnWithoutThoughtsStillEmitsAgentTurnSegment() throws {
        let screen = SessionScreen(
            session: piSession(),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: wait", prompt: SessionPrompt(text: "wait")),
                SessionActivityItem(kind: .command, text: "bash: sleep 1"),
            ],
            providerFacts: StructuredSessionProviderFacts(liveAssistantDraftText: nil),
            isAgentTurnInProgress: true
        )

        let segments = try #require(structuredSessionPiFeedSegments(for: screen))
        #expect(segments.count == 2)
        guard case .agentTurn(let turn) = segments[1] else {
            Issue.record("Expected open agent turn with in-flight tool only")
            return
        }
        #expect(turn.isOpen == true)
        #expect(turn.reasoningStackItems.isEmpty)
        #expect(turn.toolStackItems.count == 1)
        #expect(turn.finalAnswer == nil)
    }
}
