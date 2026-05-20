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
            """
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
                let id = try readUUID(column: 0, from: statement)
                let name = try readString(column: 1, from: statement)
                let kindRawValue = try readString(column: 2, from: statement)
                guard let kind = Workspace.Kind(rawValue: kindRawValue) else {
                    throw NexusMetadataStoreError.sqlite("Unknown workspace kind: \(kindRawValue)")
                }
                let folderPath = try readString(column: 3, from: statement)
                let primaryGroupID = try readUUID(column: 4, from: statement)
                workspaces.append(
                    Workspace(
                        id: id,
                        name: name,
                        kind: kind,
                        folderPath: folderPath,
                        primaryGroupID: primaryGroupID
                    )
                )
            }
            return workspaces
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
    case workspaceGroupRequired
    case primaryWorkspaceGroupSelectionRequired
    case workspaceGroupNotFound

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            message
        case .invalidWorkspaceGroupName:
            "Workspace Group name is required"
        case .invalidWorkspaceFolderPath:
            "Workspace folder path is required"
        case .workspaceGroupRequired:
            "Create a Workspace Group before adding a Workspace"
        case .primaryWorkspaceGroupSelectionRequired:
            "Choose a primary Workspace Group for the new Workspace"
        case .workspaceGroupNotFound:
            "The selected Workspace Group no longer exists"
        }
    }
}
