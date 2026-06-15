#if os(macOS)
    import Foundation
    import NexusDomain

    protocol SessionRecordStore: AnyObject {
        func defaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session?
        func listSessions(workspaceID: UUID, providerID: ProviderID) throws -> [Session]
        func listAllSessions() throws -> [Session]
        func session(id: UUID) throws -> Session?
        func createDefaultSession(
            workspaceID: UUID,
            providerID: ProviderID,
            state: Session.State,
            failureMessage: String?
        ) throws -> Session
        func createNamedSession(
            workspaceID: UUID,
            providerID: ProviderID,
            name: String,
            state: Session.State,
            failureMessage: String?
        ) throws -> Session
        func updateSession(id: UUID, state: Session.State, failureMessage: String?) throws -> Session
        func updateSessionName(id: UUID, name: String?) throws -> Session
        func deleteSessionRecord(id: UUID) throws -> Bool
        func launchSnapshot(sessionID: UUID) throws -> LaunchSnapshot?
        func ensureLaunchSnapshot(
            sessionID: UUID,
            workspaceID: UUID,
            providerID: ProviderID,
            primarySurface: SessionSurface,
            resolvedExecutable: String,
            resolvedWorkingDirectory: String
        ) throws -> LaunchSnapshot
        func updateLaunchSnapshotPrimarySurface(sessionID: UUID, primarySurface: SessionSurface) throws
        func sessionRecordAdapterMetadata(sessionID: UUID) throws -> SessionRecordAdapterMetadata?
        func saveSessionRecordAdapterMetadata(sessionID: UUID, metadata: SessionRecordAdapterMetadata) throws
        func deleteSessionRecordAdapterMetadata(sessionID: UUID) throws
        func updateSessionTerminalSize(id: UUID, columns: Int, rows: Int) throws
        func sessionTerminalSize(id: UUID) throws -> (columns: Int, rows: Int)
        func remoteRuntimeGeneration(sessionID: UUID) throws -> Int
        func advanceRemoteRuntimeGeneration(sessionID: UUID) throws -> Int
    }

    extension SessionRecordStore {
        func deleteSessionRecordAdapterMetadata(sessionID: UUID) throws {
            _ = sessionID
        }
    }

    final class MetadataStoreSessionRecordStore: SessionRecordStore {
        private let metadataStore: NexusMetadataStore

        init(metadataStore: NexusMetadataStore) {
            self.metadataStore = metadataStore
        }

        func defaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session? {
            try metadataStore.defaultSession(workspaceID: workspaceID, providerID: providerID)
        }

        func listSessions(workspaceID: UUID, providerID: ProviderID) throws -> [Session] {
            try metadataStore.listSessions(workspaceID: workspaceID, providerID: providerID)
        }

        func listAllSessions() throws -> [Session] {
            try metadataStore.listAllSessions()
        }

        func session(id: UUID) throws -> Session? {
            try metadataStore.session(id: id)
        }

        func createDefaultSession(
            workspaceID: UUID,
            providerID: ProviderID,
            state: Session.State,
            failureMessage: String?
        ) throws -> Session {
            try metadataStore.createDefaultSession(
                workspaceID: workspaceID,
                providerID: providerID,
                state: state,
                failureMessage: failureMessage
            )
        }

        func createNamedSession(
            workspaceID: UUID,
            providerID: ProviderID,
            name: String,
            state: Session.State,
            failureMessage: String?
        ) throws -> Session {
            try metadataStore.createNamedSession(
                workspaceID: workspaceID,
                providerID: providerID,
                name: name,
                state: state,
                failureMessage: failureMessage
            )
        }

        func updateSession(id: UUID, state: Session.State, failureMessage: String?) throws -> Session {
            try metadataStore.updateSession(id: id, state: state, failureMessage: failureMessage)
        }

        func updateSessionName(id: UUID, name: String?) throws -> Session {
            try metadataStore.updateSessionName(id: id, name: name)
        }

        func deleteSessionRecord(id: UUID) throws -> Bool {
            try metadataStore.deleteSession(id: id)
        }

        func launchSnapshot(sessionID: UUID) throws -> LaunchSnapshot? {
            try metadataStore.launchSnapshot(sessionID: sessionID)
        }

        func ensureLaunchSnapshot(
            sessionID: UUID,
            workspaceID: UUID,
            providerID: ProviderID,
            primarySurface: SessionSurface,
            resolvedExecutable: String,
            resolvedWorkingDirectory: String
        ) throws -> LaunchSnapshot {
            try metadataStore.ensureLaunchSnapshot(
                sessionID: sessionID,
                workspaceID: workspaceID,
                providerID: providerID,
                primarySurface: primarySurface,
                resolvedExecutable: resolvedExecutable,
                resolvedWorkingDirectory: resolvedWorkingDirectory
            )
        }

        func updateLaunchSnapshotPrimarySurface(sessionID: UUID, primarySurface: SessionSurface) throws {
            try metadataStore.updateLaunchSnapshotPrimarySurface(sessionID: sessionID, primarySurface: primarySurface)
        }

        func sessionRecordAdapterMetadata(sessionID: UUID) throws -> SessionRecordAdapterMetadata? {
            try metadataStore.sessionRecordAdapterMetadata(sessionID: sessionID)
        }

        func saveSessionRecordAdapterMetadata(sessionID: UUID, metadata: SessionRecordAdapterMetadata) throws {
            try metadataStore.saveSessionRecordAdapterMetadata(sessionID: sessionID, metadata: metadata)
        }

        func deleteSessionRecordAdapterMetadata(sessionID: UUID) throws {
            try metadataStore.deleteSessionRecordAdapterMetadata(sessionID: sessionID)
        }

        func updateSessionTerminalSize(id: UUID, columns: Int, rows: Int) throws {
            try metadataStore.updateSessionTerminalSize(id: id, columns: columns, rows: rows)
        }

        func sessionTerminalSize(id: UUID) throws -> (columns: Int, rows: Int) {
            try metadataStore.sessionTerminalSize(id: id)
        }

        func remoteRuntimeGeneration(sessionID: UUID) throws -> Int {
            try metadataStore.remoteRuntimeGeneration(sessionID: sessionID)
        }

        func advanceRemoteRuntimeGeneration(sessionID: UUID) throws -> Int {
            try metadataStore.advanceRemoteRuntimeGeneration(sessionID: sessionID)
        }
    }
#endif
