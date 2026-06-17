import Foundation
import NexusDomain
import Testing

@testable import nexus

struct RemoteClientAgentTurnCompletionHapticsTests {
    private func session(isAgentTurnInProgress: Bool) -> SessionScreen {
        SessionScreen(
            session: Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            ),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: isAgentTurnInProgress
        )
    }

    @Test func playsWhenLiveTurnCompletesAndUserIsController() {
        let id = UUID()
        let inProgress = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: true
        )
        let completed = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: false
        )

        #expect(
            shouldPlayAgentTurnCompletionHaptic(
                previousScreen: inProgress,
                newScreen: completed,
                isController: true,
                isLoadingOlderStructuredSessionHistory: false
            ))
    }

    @Test func doesNotPlayWhenUserIsViewer() {
        let id = UUID()
        let inProgress = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: true
        )
        let completed = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: false
        )

        #expect(
            shouldPlayAgentTurnCompletionHaptic(
                previousScreen: inProgress,
                newScreen: completed,
                isController: false,
                isLoadingOlderStructuredSessionHistory: false
            ) == false)
    }

    @Test func doesNotPlayOnInitialAttachWithoutPriorInProgressScreen() {
        let completed = session(isAgentTurnInProgress: false)

        #expect(
            shouldPlayAgentTurnCompletionHaptic(
                previousScreen: nil,
                newScreen: completed,
                isController: true,
                isLoadingOlderStructuredSessionHistory: false
            ) == false)
    }

    @Test func doesNotPlayWhileLoadingOlderStructuredSessionHistory() {
        let id = UUID()
        let inProgress = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: true
        )
        let completed = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: false
        )

        #expect(
            shouldPlayAgentTurnCompletionHaptic(
                previousScreen: inProgress,
                newScreen: completed,
                isController: true,
                isLoadingOlderStructuredSessionHistory: true
            ) == false)
    }

    @Test func doesNotPlayWhenTurnWasNotPreviouslyInProgress() {
        let id = UUID()
        let idle = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            isAgentTurnInProgress: false
        )
        let stillIdle = SessionScreen(
            session: Session(id: id, workspaceID: UUID(), providerID: .pi, isDefault: true, state: .ready),
            primarySurface: .structuredActivityFeed,
            activityItems: [SessionActivityItem(kind: .message, text: "delta")],
            isAgentTurnInProgress: false
        )

        #expect(
            shouldPlayAgentTurnCompletionHaptic(
                previousScreen: idle,
                newScreen: stillIdle,
                isController: true,
                isLoadingOlderStructuredSessionHistory: false
            ) == false)
    }
}

#if os(iOS)
    @MainActor
    struct RemoteClientPairingModelAgentTurnCompletionHapticsTests {
        @Test func modelPlaysHapticOnceWhenObservedTurnCompletesAsController() async throws {
            let suiteName = "RemoteClientPairingModelHapticsTests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)

            let pairedDeviceID = UUID()
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let pairedMac = PairedMac(
                name: "Studio Mac",
                host: "studio.local",
                port: 9234,
                pairedAt: Date(timeIntervalSince1970: 600),
                pairedDeviceID: pairedDeviceID
            )
            let inProgress = SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .pairedDevice(pairedDeviceID),
                isAgentTurnInProgress: true
            )
            let completed = SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .pairedDevice(pairedDeviceID),
                activityItems: [SessionActivityItem(kind: .message, text: "Pi: Done")],
                isAgentTurnInProgress: false
            )

            let store = UserDefaultsPairedMacStore(defaults: defaults)
            try store.savePairedMacs([pairedMac])
            store.saveActivePairedMacID(pairedMac.id)

            let haptic = RecordingAgentTurnCompletionHapticFeedback()
            let client = StubRemotePairingClient(result: pairedMac, sessionScreen: inProgress)
            let model = RemoteClientPairingModel(
                client: client,
                store: store,
                agentTurnCompletionHapticFeedback: haptic
            )

            await model.focusRemoteSession(sessionID: session.id)
            for _ in 0..<20 where model.focusedSessionScreen != inProgress {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            #expect(haptic.successCount == 0)

            await client.emitObservedScreen(completed)
            for _ in 0..<20 where model.focusedSessionScreen != completed {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            #expect(haptic.successCount == 1)
        }

        @Test func modelDoesNotPlayHapticWhenViewerObservesTurnCompletion() async throws {
            let suiteName = "RemoteClientPairingModelHapticsTests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)

            let pairedDeviceID = UUID()
            let session = Session(
                id: UUID(),
                workspaceID: UUID(),
                providerID: .pi,
                isDefault: true,
                state: .ready
            )
            let pairedMac = PairedMac(
                name: "Studio Mac",
                host: "studio.local",
                port: 9234,
                pairedAt: Date(timeIntervalSince1970: 600),
                pairedDeviceID: pairedDeviceID
            )
            let inProgress = SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .mac,
                isAgentTurnInProgress: true
            )
            let completed = SessionScreen(
                session: session,
                primarySurface: .structuredActivityFeed,
                controller: .mac,
                isAgentTurnInProgress: false
            )

            let store = UserDefaultsPairedMacStore(defaults: defaults)
            try store.savePairedMacs([pairedMac])
            store.saveActivePairedMacID(pairedMac.id)

            let haptic = RecordingAgentTurnCompletionHapticFeedback()
            let client = StubRemotePairingClient(result: pairedMac, sessionScreen: inProgress)
            let model = RemoteClientPairingModel(
                client: client,
                store: store,
                agentTurnCompletionHapticFeedback: haptic
            )

            await model.focusRemoteSession(sessionID: session.id)
            for _ in 0..<20 where model.focusedSessionScreen != inProgress {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            await client.emitObservedScreen(completed)
            for _ in 0..<20 where model.focusedSessionScreen != completed {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            #expect(haptic.successCount == 0)
            #expect(model.focusedSessionIsController == false)
        }
    }

    private final class RecordingAgentTurnCompletionHapticFeedback: AgentTurnCompletionHapticFeedback,
        @unchecked Sendable
    {
        private(set) var successCount = 0

        func playSuccess() {
            successCount += 1
        }
    }
#endif
