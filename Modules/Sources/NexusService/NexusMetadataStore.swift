import Foundation
import NexusDomain
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NexusMetadataStore {
    private let database: OpaquePointer?
    private let lock = NSLock()

    init(storeURL: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Could not open metadata store"
            sqlite3_close(database)
            throw NexusMetadataStoreError.sqlite(message)
        }

        self.database = database
        try execute(
            """
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS workspace_groups (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                folder_path TEXT NOT NULL,
                primary_group_id TEXT NOT NULL REFERENCES workspace_groups(id)
            );

            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY NOT NULL,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id),
                provider_id TEXT NOT NULL,
                is_default INTEGER NOT NULL,
                name TEXT,
                state TEXT NOT NULL,
                failure_message TEXT,
                terminal_columns INTEGER NOT NULL DEFAULT 80,
                terminal_rows INTEGER NOT NULL DEFAULT 24
            );
            """
        )
        try ensureColumnExists(
            table: "sessions",
            column: "name",
            definition: "TEXT"
        )
        try ensureColumnExists(
            table: "sessions",
            column: "terminal_columns",
            definition: "INTEGER NOT NULL DEFAULT 80"
        )
        try ensureColumnExists(
            table: "sessions",
            column: "terminal_rows",
            definition: "INTEGER NOT NULL DEFAULT 24"
        )
    }

    deinit {
        sqlite3_close(database)
    }

    func listWorkspaceGroups() throws -> [WorkspaceGroup] {
        try withLock {
            let statement = try prepare("SELECT id, name FROM workspace_groups ORDER BY rowid ASC;")
            defer { sqlite3_finalize(statement) }

            var groups: [WorkspaceGroup] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = try readUUID(column: 0, from: statement)
                let name = try readString(column: 1, from: statement)
                groups.append(WorkspaceGroup(id: id, name: name))
            }
            return groups
        }
    }

    func createWorkspaceGroup(name: String) throws -> WorkspaceGroup {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw NexusMetadataStoreError.invalidWorkspaceGroupName
        }

        return try withLock {
            let group = WorkspaceGroup(id: UUID(), name: trimmedName)
            let statement = try prepare("INSERT INTO workspace_groups (id, name) VALUES (?, ?);")
            defer { sqlite3_finalize(statement) }

            try bind(group.id.uuidString, at: 1, in: statement)
            try bind(group.name, at: 2, in: statement)
            try stepDone(statement)
            return group
        }
    }

    func listWorkspaces() throws -> [Workspace] {
        try withLock {
            let statement = try prepare(
                "SELECT id, name, kind, folder_path, primary_group_id FROM workspaces ORDER BY rowid ASC;"
            )
            defer { sqlite3_finalize(statement) }

            var workspaces: [Workspace] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                workspaces.append(try readWorkspace(from: statement))
            }
            return workspaces
        }
    }

    func workspace(id: UUID) throws -> Workspace? {
        try withLock {
            let statement = try prepare(
                "SELECT id, name, kind, folder_path, primary_group_id FROM workspaces WHERE id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try readWorkspace(from: statement)
        }
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) throws -> Workspace {
        let resolvedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedFolderPath.isEmpty == false else {
            throw NexusMetadataStoreError.invalidWorkspaceFolderPath
        }

        return try withLock {
            let groups = try listWorkspaceGroupsWithoutLock()
            let resolvedPrimaryGroupID = try resolvePrimaryGroupID(primaryGroupID, groups: groups)
            let resolvedName = resolveWorkspaceName(name: name, folderPath: resolvedFolderPath)
            let workspace = Workspace(
                id: UUID(),
                name: resolvedName,
                kind: .local,
                folderPath: resolvedFolderPath,
                primaryGroupID: resolvedPrimaryGroupID
            )

            let statement = try prepare(
                "INSERT INTO workspaces (id, name, kind, folder_path, primary_group_id) VALUES (?, ?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            try bind(workspace.id.uuidString, at: 1, in: statement)
            try bind(workspace.name, at: 2, in: statement)
            try bind(workspace.kind.rawValue, at: 3, in: statement)
            try bind(workspace.folderPath, at: 4, in: statement)
            try bind(workspace.primaryGroupID.uuidString, at: 5, in: statement)
            try stepDone(statement)
            return workspace
        }
    }

    func defaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session? {
        try withLock {
            try defaultSessionWithoutLock(workspaceID: workspaceID, providerID: providerID)
        }
    }

    func listSessions(workspaceID: UUID, providerID: ProviderID) throws -> [Session] {
        try withLock {
            let statement = try prepare(
                "SELECT id, workspace_id, provider_id, is_default, name, state, failure_message FROM sessions WHERE workspace_id = ? AND provider_id = ? ORDER BY is_default DESC, rowid ASC;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(workspaceID.uuidString, at: 1, in: statement)
            try bind(providerID.rawValue, at: 2, in: statement)

            var sessions: [Session] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                sessions.append(try readSession(from: statement))
            }
            return sessions
        }
    }

    func createDefaultSession(
        workspaceID: UUID,
        providerID: ProviderID,
        state: Session.State,
        failureMessage: String?
    ) throws -> Session {
        try withLock {
            let session = Session(
                id: UUID(),
                workspaceID: workspaceID,
                providerID: providerID,
                isDefault: true,
                state: state,
                failureMessage: failureMessage
            )

            let statement = try prepare(
                "INSERT INTO sessions (id, workspace_id, provider_id, is_default, name, state, failure_message, terminal_columns, terminal_rows) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            try bind(session.id.uuidString, at: 1, in: statement)
            try bind(session.workspaceID.uuidString, at: 2, in: statement)
            try bind(session.providerID.rawValue, at: 3, in: statement)
            try bind(session.isDefault ? 1 : 0, at: 4, in: statement)
            try bind(session.name, at: 5, in: statement)
            try bind(session.state.rawValue, at: 6, in: statement)
            try bind(failureMessage, at: 7, in: statement)
            try bind(80, at: 8, in: statement)
            try bind(24, at: 9, in: statement)
            try stepDone(statement)
            return session
        }
    }

    func createNamedSession(
        workspaceID: UUID,
        providerID: ProviderID,
        name: String,
        state: Session.State,
        failureMessage: String?
    ) throws -> Session {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw NexusMetadataStoreError.invalidSessionName
        }

        return try withLock {
            let session = Session(
                id: UUID(),
                workspaceID: workspaceID,
                providerID: providerID,
                name: trimmedName,
                isDefault: false,
                state: state,
                failureMessage: failureMessage
            )

            let statement = try prepare(
                "INSERT INTO sessions (id, workspace_id, provider_id, is_default, name, state, failure_message, terminal_columns, terminal_rows) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            try bind(session.id.uuidString, at: 1, in: statement)
            try bind(session.workspaceID.uuidString, at: 2, in: statement)
            try bind(session.providerID.rawValue, at: 3, in: statement)
            try bind(session.isDefault ? 1 : 0, at: 4, in: statement)
            try bind(session.name, at: 5, in: statement)
            try bind(session.state.rawValue, at: 6, in: statement)
            try bind(failureMessage, at: 7, in: statement)
            try bind(80, at: 8, in: statement)
            try bind(24, at: 9, in: statement)
            try stepDone(statement)
            return session
        }
    }

    func updateSession(id: UUID, state: Session.State, failureMessage: String?) throws -> Session {
        try withLock {
            let statement = try prepare(
                "UPDATE sessions SET state = ?, failure_message = ? WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(state.rawValue, at: 1, in: statement)
            try bind(failureMessage, at: 2, in: statement)
            try bind(id.uuidString, at: 3, in: statement)
            try stepDone(statement)

            guard let session = try sessionWithoutLock(id: id) else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            return session
        }
    }

    func deleteSession(id: UUID) throws -> Bool {
        try withLock {
            let statement = try prepare("DELETE FROM sessions WHERE id = ?;")
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
            return sqlite3_changes(database) > 0
        }
    }

    private func resolvePrimaryGroupID(_ primaryGroupID: UUID?, groups: [WorkspaceGroup]) throws -> UUID {
        if let primaryGroupID {
            guard groups.contains(where: { $0.id == primaryGroupID }) else {
                throw NexusMetadataStoreError.workspaceGroupNotFound
            }
            return primaryGroupID
        }

        guard groups.isEmpty == false else {
            throw NexusMetadataStoreError.workspaceGroupRequired
        }

        guard groups.count == 1, let group = groups.first else {
            throw NexusMetadataStoreError.primaryWorkspaceGroupSelectionRequired
        }

        return group.id
    }

    private func resolveWorkspaceName(name: String?, folderPath: String) -> String {
        if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false {
            return trimmed
        }

        let candidate = URL(fileURLWithPath: folderPath).lastPathComponent
        return candidate.isEmpty ? folderPath : candidate
    }

    func updateSessionTerminalSize(id: UUID, columns: Int, rows: Int) throws {
        try withLock {
            let statement = try prepare(
                "UPDATE sessions SET terminal_columns = ?, terminal_rows = ? WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(Int32(max(1, columns)), at: 1, in: statement)
            try bind(Int32(max(1, rows)), at: 2, in: statement)
            try bind(id.uuidString, at: 3, in: statement)
            try stepDone(statement)
        }
    }

    func sessionTerminalSize(id: UUID) throws -> (columns: Int, rows: Int) {
        try withLock {
            let statement = try prepare(
                "SELECT terminal_columns, terminal_rows FROM sessions WHERE id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            return (
                columns: Int(sqlite3_column_int(statement, 0)),
                rows: Int(sqlite3_column_int(statement, 1))
            )
        }
    }

    private func defaultSessionWithoutLock(workspaceID: UUID, providerID: ProviderID) throws -> Session? {
        let statement = try prepare(
            "SELECT id, workspace_id, provider_id, is_default, name, state, failure_message FROM sessions WHERE workspace_id = ? AND provider_id = ? AND is_default = 1 LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(workspaceID.uuidString, at: 1, in: statement)
        try bind(providerID.rawValue, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try readSession(from: statement)
    }

    func session(id: UUID) throws -> Session? {
        try withLock {
            try sessionWithoutLock(id: id)
        }
    }

    private func sessionWithoutLock(id: UUID) throws -> Session? {
        let statement = try prepare(
            "SELECT id, workspace_id, provider_id, is_default, name, state, failure_message FROM sessions WHERE id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try readSession(from: statement)
    }

    private func listWorkspaceGroupsWithoutLock() throws -> [WorkspaceGroup] {
        let statement = try prepare("SELECT id, name FROM workspace_groups ORDER BY rowid ASC;")
        defer { sqlite3_finalize(statement) }

        var groups: [WorkspaceGroup] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = try readUUID(column: 0, from: statement)
            let name = try readString(column: 1, from: statement)
            groups.append(WorkspaceGroup(id: id, name: name))
        }
        return groups
    }

    private func ensureColumnExists(table: String, column: String, definition: String) throws {
        let statement = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if readOptionalString(column: 1, from: statement) == column {
                return
            }
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw currentSQLiteError()
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentSQLiteError()
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw currentSQLiteError()
        }
    }

    private func bind(_ value: Int32, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_int(statement, index, value) == SQLITE_OK else {
            throw currentSQLiteError()
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw currentSQLiteError()
            }
            return
        }

        try bind(value, at: index, in: statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw currentSQLiteError()
        }
    }

    private func readString(column: Int32, from statement: OpaquePointer?) throws -> String {
        guard let pointer = sqlite3_column_text(statement, column) else {
            throw NexusMetadataStoreError.sqlite("Missing text at column \(column)")
        }
        return String(cString: pointer)
    }

    private func readUUID(column: Int32, from statement: OpaquePointer?) throws -> UUID {
        let rawValue = try readString(column: column, from: statement)
        guard let value = UUID(uuidString: rawValue) else {
            throw NexusMetadataStoreError.sqlite("Invalid UUID: \(rawValue)")
        }
        return value
    }

    private func readOptionalString(column: Int32, from statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func readWorkspace(from statement: OpaquePointer?) throws -> Workspace {
        let id = try readUUID(column: 0, from: statement)
        let name = try readString(column: 1, from: statement)
        let kindRawValue = try readString(column: 2, from: statement)
        guard let kind = Workspace.Kind(rawValue: kindRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown workspace kind: \(kindRawValue)")
        }
        let folderPath = try readString(column: 3, from: statement)
        let primaryGroupID = try readUUID(column: 4, from: statement)
        return Workspace(
            id: id,
            name: name,
            kind: kind,
            folderPath: folderPath,
            primaryGroupID: primaryGroupID
        )
    }

    private func readSession(from statement: OpaquePointer?) throws -> Session {
        let id = try readUUID(column: 0, from: statement)
        let workspaceID = try readUUID(column: 1, from: statement)
        let providerRawValue = try readString(column: 2, from: statement)
        guard let providerID = ProviderID(rawValue: providerRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown provider id: \(providerRawValue)")
        }
        let isDefault = sqlite3_column_int(statement, 3) != 0
        let name = readOptionalString(column: 4, from: statement)
        let stateRawValue = try readString(column: 5, from: statement)
        guard let state = Session.State(rawValue: stateRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown session state: \(stateRawValue)")
        }
        let failureMessage = readOptionalString(column: 6, from: statement)
        return Session(
            id: id,
            workspaceID: workspaceID,
            providerID: providerID,
            name: name,
            isDefault: isDefault,
            state: state,
            failureMessage: failureMessage
        )
    }

    private func currentSQLiteError() -> Error {
        NexusMetadataStoreError.sqlite(
            database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
        )
    }
}

enum NexusMetadataStoreError: LocalizedError {
    case sqlite(String)
    case invalidWorkspaceGroupName
    case invalidWorkspaceFolderPath
    case invalidSessionName
    case workspaceGroupRequired
    case primaryWorkspaceGroupSelectionRequired
    case workspaceGroupNotFound
    case workspaceNotFound
    case sessionNotFound
    case providerNotSupported
    case sessionNotReady
    case sessionRecordDeletionRequiresStoppedSession

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            message
        case .invalidWorkspaceGroupName:
            "Workspace Group name is required"
        case .invalidWorkspaceFolderPath:
            "Workspace folder path is required"
        case .invalidSessionName:
            "Session name is required"
        case .workspaceGroupRequired:
            "Create a Workspace Group before adding a Workspace"
        case .primaryWorkspaceGroupSelectionRequired:
            "Choose a primary Workspace Group for the new Workspace"
        case .workspaceGroupNotFound:
            "The selected Workspace Group no longer exists"
        case .workspaceNotFound:
            "Workspace not found"
        case .sessionNotFound:
            "Session not found"
        case .providerNotSupported:
            "Provider launch is not implemented yet"
        case .sessionNotReady:
            "Session is not ready for input"
        case .sessionRecordDeletionRequiresStoppedSession:
            "Stop the session before deleting its record"
        }
    }
}
