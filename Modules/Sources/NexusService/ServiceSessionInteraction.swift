#if os(macOS)
    import Foundation
    import NexusDomain
    import NexusIPC

    protocol SessionInteractionManaging: AnyObject {
        func getSessionScreen(sessionID: UUID) throws -> SessionScreen
        func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen
        func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen
        func respondToApprovalRequest(
            sessionID: UUID,
            approvalRequestID: UUID,
            decision: ApprovalRequestDecision
        ) async throws -> SessionScreen
        func respondToExtensionDialog(
            sessionID: UUID,
            dialogID: String,
            response: SessionExtensionUIDialogResponse
        ) async throws -> SessionScreen
        func observeSessionScreen(
            observationID: UUID,
            sessionID: UUID,
            onUpdate: @escaping @Sendable (SessionScreenObservationUpdate) -> Void
        ) throws -> SessionScreenObservationStart
        func cancelSessionScreenObservation(observationID: UUID)
        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen
        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws
            -> SessionScreen
        func respondToRemoteApprovalRequest(
            sessionID: UUID,
            pairedDeviceID: UUID,
            approvalRequestID: UUID,
            decision: ApprovalRequestDecision
        ) async throws -> SessionScreen
        func respondToRemoteExtensionDialog(
            sessionID: UUID,
            pairedDeviceID: UUID,
            dialogID: String,
            response: SessionExtensionUIDialogResponse
        ) async throws -> SessionScreen
        func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen
        func sendRemoteSessionInputKey(
            sessionID: UUID,
            pairedDeviceID: UUID,
            key: SessionInputKey
        ) async throws -> SessionScreen
    }

    extension SessionInteractionManaging {
        func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
            if prompt.images.isEmpty == false {
                throw NSError(
                    domain: "NexusService",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "This Session interaction does not support image-bearing prompts."
                    ]
                )
            }
            return try await sendSessionInput(sessionID: sessionID, text: prompt.text)
        }

        func respondToExtensionDialog(
            sessionID: UUID,
            dialogID: String,
            response: SessionExtensionUIDialogResponse
        ) async throws -> SessionScreen {
            _ = sessionID
            _ = dialogID
            _ = response
            throw NexusSessionExtensionUIError.extensionDialogsUnavailable
        }

        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws
            -> SessionScreen
        {
            if prompt.images.isEmpty == false {
                throw NSError(
                    domain: "NexusService",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "This remote Session interaction does not support image-bearing prompts."
                    ]
                )
            }
            return try await sendRemoteSessionInput(
                sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: prompt.text)
        }
    }

    struct ServiceSessionInteractionDependencies {
        let sessionRecord: (UUID) throws -> Session?
        let reconcileSessionRuntimeState: (Session) throws -> Session
        let interactiveReadySession: (Session) async throws -> Session
        let hasRuntime: (Session) -> Bool
        let runtimeSessionScreen: (Session) throws -> SessionScreen
        let staticSessionScreen: (Session, String) throws -> SessionScreen
        let normalizedSessionScreen: (SessionScreen) -> SessionScreen
        let addUpdateObserver: (UUID, Session, @escaping @Sendable () -> Void) -> Void
        let removeUpdateObserver: (UUID) -> Void
        let claimMacController: (Session) throws -> SessionScreen
        let isRemoteController: (UUID, UUID) -> Bool
        let sendInput: (SessionPrompt, Session) throws -> SessionScreen
        let sendText: (String, Session) throws -> SessionScreen
        let sendInputKey: (SessionInputKey, Bool, Session) throws -> SessionScreen
        let respondToApprovalRequest: (UUID, ApprovalRequestDecision, Session) throws -> SessionScreen
        let respondToExtensionDialog: (String, SessionExtensionUIDialogResponse, Session) throws -> SessionScreen
        let resetPiSession: (Session) throws -> SessionScreen
        let stabilizedScreenAfterTerminalInput: (Session, SessionScreen, SessionScreen) -> SessionScreen
        let sessionScreenObservationStart: (UUID, SessionScreen) -> SessionScreenObservationStart
        let sessionScreenObservationUpdates: (UUID, Int?) -> [SessionScreenObservationUpdate]
    }

    final class ServiceSessionInteraction: SessionInteractionManaging, @unchecked Sendable {
        private let dependencies: ServiceSessionInteractionDependencies

        init(dependencies: ServiceSessionInteractionDependencies) {
            self.dependencies = dependencies
        }

        func getSessionScreen(sessionID: UUID) throws -> SessionScreen {
            guard let session = try dependencies.sessionRecord(sessionID) else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            let resolvedSession = try dependencies.reconcileSessionRuntimeState(session)

            switch resolvedSession.state {
            case .failed:
                return try dependencies.staticSessionScreen(
                    resolvedSession,
                    resolvedSession.failureMessage ?? "Session launch failed"
                )
            case .interrupted:
                if dependencies.hasRuntime(resolvedSession) {
                    return dependencies.normalizedSessionScreen(try dependencies.runtimeSessionScreen(resolvedSession))
                }
                return try dependencies.staticSessionScreen(
                    resolvedSession,
                    resolvedSession.failureMessage ?? "Session interrupted"
                )
            case .exited:
                if dependencies.hasRuntime(resolvedSession) {
                    return dependencies.normalizedSessionScreen(try dependencies.runtimeSessionScreen(resolvedSession))
                }
                return try dependencies.staticSessionScreen(
                    resolvedSession,
                    resolvedSession.failureMessage ?? "Session exited"
                )
            case .ready:
                if dependencies.hasRuntime(resolvedSession) {
                    return dependencies.normalizedSessionScreen(try dependencies.runtimeSessionScreen(resolvedSession))
                }
                return try dependencies.staticSessionScreen(resolvedSession, "")
            }
        }

        func observeSessionScreen(
            observationID: UUID,
            sessionID: UUID,
            onUpdate: @escaping @Sendable (SessionScreenObservationUpdate) -> Void
        ) throws -> SessionScreenObservationStart {
            let screen = try getSessionScreen(sessionID: sessionID)
            let start = dependencies.sessionScreenObservationStart(observationID, screen)
            let revisionState = StructuredObservationRevisionState(start.structuredSnapshot?.revision)

            dependencies.addUpdateObserver(observationID, screen.session) { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let currentScreen = try self.getSessionScreen(sessionID: sessionID)
                    let updates = self.dependencies.sessionScreenObservationUpdates(
                        currentScreen.session.id,
                        revisionState.value
                    )

                    if updates.isEmpty {
                        onUpdate(.screen(currentScreen))
                        return
                    }

                    for update in updates {
                        switch update {
                        case .structuredDelta(let delta):
                            revisionState.value = delta.revision
                        case .structuredGap(let currentRevision):
                            revisionState.value = currentRevision
                        case .screen:
                            revisionState.value = nil
                        }
                        onUpdate(update)
                    }
                } catch {
                    return
                }
            }

            return start
        }

        func cancelSessionScreenObservation(observationID: UUID) {
            dependencies.removeUpdateObserver(observationID)
        }

        func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
            try await sendSessionInput(sessionID: sessionID, prompt: SessionPrompt(text: text))
        }

        func sendSessionInput(sessionID: UUID, prompt: SessionPrompt) async throws -> SessionScreen {
            let resolvedSession = try await readyMacControlledSession(sessionID: sessionID)
            if isPiSessionResetCommand(prompt, session: resolvedSession) {
                return dependencies.normalizedSessionScreen(try dependencies.resetPiSession(resolvedSession))
            }
            NexusSessionRuntimeDiagnostics.logSessionPromptSubmitted(
                sessionID: resolvedSession.id,
                providerID: resolvedSession.providerID,
                hasRuntime: dependencies.hasRuntime(resolvedSession),
                promptPreview: prompt.text
            )
            return dependencies.normalizedSessionScreen(try dependencies.sendInput(prompt, resolvedSession))
        }

        func respondToApprovalRequest(
            sessionID: UUID,
            approvalRequestID: UUID,
            decision: ApprovalRequestDecision
        ) async throws -> SessionScreen {
            let resolvedSession = try await readyMacControlledSession(sessionID: sessionID)
            return dependencies.normalizedSessionScreen(
                try dependencies.respondToApprovalRequest(approvalRequestID, decision, resolvedSession)
            )
        }

        func respondToExtensionDialog(
            sessionID: UUID,
            dialogID: String,
            response: SessionExtensionUIDialogResponse
        ) async throws -> SessionScreen {
            let resolvedSession = try await readyMacControlledSession(sessionID: sessionID)
            return dependencies.normalizedSessionScreen(
                try dependencies.respondToExtensionDialog(dialogID, response, resolvedSession)
            )
        }

        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
            try await sendRemoteSessionInput(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                prompt: SessionPrompt(text: text)
            )
        }

        func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, prompt: SessionPrompt) async throws
            -> SessionScreen
        {
            let resolvedSession = try await readyRemoteControlledSession(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                controllerError: .remoteSessionInputControllerRequired
            )
            if isPiSessionResetCommand(prompt, session: resolvedSession) {
                return dependencies.normalizedSessionScreen(try dependencies.resetPiSession(resolvedSession))
            }
            return dependencies.normalizedSessionScreen(try dependencies.sendInput(prompt, resolvedSession))
        }

        func respondToRemoteApprovalRequest(
            sessionID: UUID,
            pairedDeviceID: UUID,
            approvalRequestID: UUID,
            decision: ApprovalRequestDecision
        ) async throws -> SessionScreen {
            let resolvedSession = try await readyRemoteControlledSession(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                controllerError: .remoteApprovalRequestControllerRequired
            )
            return dependencies.normalizedSessionScreen(
                try dependencies.respondToApprovalRequest(approvalRequestID, decision, resolvedSession)
            )
        }

        func respondToRemoteExtensionDialog(
            sessionID: UUID,
            pairedDeviceID: UUID,
            dialogID: String,
            response: SessionExtensionUIDialogResponse
        ) async throws -> SessionScreen {
            let resolvedSession = try await readyRemoteControlledSession(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                controllerError: .remoteExtensionDialogControllerRequired
            )
            return dependencies.normalizedSessionScreen(
                try dependencies.respondToExtensionDialog(dialogID, response, resolvedSession)
            )
        }

        func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
            guard let session = try dependencies.sessionRecord(sessionID) else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            let resolvedSession = try dependencies.reconcileSessionRuntimeState(session)
            guard dependencies.isRemoteController(resolvedSession.id, pairedDeviceID) else {
                throw NexusSessionControlError.remoteControllerRequired
            }
            guard dependencies.hasRuntime(resolvedSession) else {
                throw NexusMetadataStoreError.sessionNotReady
            }

            if isPiSessionResetCommand(SessionPrompt(text: text), session: resolvedSession) {
                return dependencies.normalizedSessionScreen(try dependencies.resetPiSession(resolvedSession))
            }
            let screenBeforeInput = dependencies.normalizedSessionScreen(
                try dependencies.runtimeSessionScreen(resolvedSession))
            let responseScreen = dependencies.normalizedSessionScreen(try dependencies.sendText(text, resolvedSession))
            return dependencies.stabilizedScreenAfterTerminalInput(resolvedSession, screenBeforeInput, responseScreen)
        }

        func sendRemoteSessionInputKey(
            sessionID: UUID,
            pairedDeviceID: UUID,
            key: SessionInputKey
        ) async throws -> SessionScreen {
            let resolvedSession = try await readyRemoteControlledSession(
                sessionID: sessionID, pairedDeviceID: pairedDeviceID)
            let currentScreen = dependencies.normalizedSessionScreen(
                try dependencies.runtimeSessionScreen(resolvedSession))
            let renderState = TerminalRenderer.renderState(
                from: currentScreen.transcript,
                terminalColumns: currentScreen.terminalColumns,
                terminalRows: currentScreen.terminalRows
            )
            let responseScreen = dependencies.normalizedSessionScreen(
                try dependencies.sendInputKey(key, renderState.applicationCursorMode, resolvedSession)
            )
            return dependencies.stabilizedScreenAfterTerminalInput(resolvedSession, currentScreen, responseScreen)
        }

        private func readyMacControlledSession(sessionID: UUID) async throws -> Session {
            let resolvedSession = try await readyInteractiveSession(sessionID: sessionID)
            _ = try dependencies.claimMacController(resolvedSession)
            return resolvedSession
        }

        private func readyRemoteControlledSession(
            sessionID: UUID,
            pairedDeviceID: UUID,
            controllerError: NexusSessionControlError = .remoteControllerRequired
        ) async throws -> Session {
            let resolvedSession = try await readyInteractiveSession(sessionID: sessionID)
            guard dependencies.isRemoteController(resolvedSession.id, pairedDeviceID) else {
                throw controllerError
            }
            return resolvedSession
        }

        private func readyInteractiveSession(sessionID: UUID) async throws -> Session {
            guard let session = try dependencies.sessionRecord(sessionID) else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            let resolvedSession = try await dependencies.interactiveReadySession(session)
            guard resolvedSession.state == .ready else {
                throw NexusMetadataStoreError.sessionNotReady
            }
            return resolvedSession
        }

        private func isPiSessionResetCommand(_ prompt: SessionPrompt, session: Session) -> Bool {
            guard session.providerID == .pi,
                prompt.images.isEmpty,
                prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/new"
                    || prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/clear"
            else {
                return false
            }
            return true
        }
    }

    private final class StructuredObservationRevisionState: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: Int?

        init(_ value: Int?) {
            self.storedValue = value
        }

        var value: Int? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedValue
            }
            set {
                lock.lock()
                storedValue = newValue
                lock.unlock()
            }
        }
    }
#endif
