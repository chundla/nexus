#if os(macOS)
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

            CREATE TABLE IF NOT EXISTS hosts (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                ssh_target TEXT NOT NULL,
                port INTEGER
            );

            CREATE TABLE IF NOT EXISTS remote_workspace_targets (
                workspace_id TEXT PRIMARY KEY NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                host_id TEXT NOT NULL REFERENCES hosts(id),
                remote_path TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_remote_workspace_targets_host_id
            ON remote_workspace_targets(host_id);

            CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_workspace_targets_effective_target
            ON remote_workspace_targets(host_id, remote_path);

            CREATE TABLE IF NOT EXISTS host_validation_snapshots (
                host_id TEXT PRIMARY KEY NOT NULL REFERENCES hosts(id) ON DELETE CASCADE,
                state TEXT NOT NULL,
                summary TEXT NOT NULL,
                checked_at INTEGER NOT NULL,
                diagnostics_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS workspace_availability_snapshots (
                workspace_id TEXT PRIMARY KEY NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                state TEXT NOT NULL,
                summary TEXT NOT NULL,
                checked_at INTEGER NOT NULL,
                diagnostics_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS provider_health_snapshots (
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                provider_id TEXT NOT NULL,
                state TEXT NOT NULL,
                summary TEXT NOT NULL,
                resolved_executable TEXT,
                version TEXT,
                launchability TEXT NOT NULL,
                checked_at INTEGER NOT NULL,
                diagnostics_json TEXT NOT NULL,
                PRIMARY KEY (workspace_id, provider_id)
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
                terminal_rows INTEGER NOT NULL DEFAULT 24,
                remote_runtime_generation INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS launch_snapshots (
                session_id TEXT PRIMARY KEY NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                workspace_id TEXT NOT NULL,
                provider_id TEXT NOT NULL,
                primary_surface TEXT NOT NULL DEFAULT 'terminal',
                resolved_executable TEXT NOT NULL,
                resolved_working_directory TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS session_record_adapter_metadata (
                session_id TEXT PRIMARY KEY NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                provider_id TEXT NOT NULL,
                metadata_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS recent_navigation (
                target_key TEXT PRIMARY KEY NOT NULL,
                target_kind TEXT NOT NULL,
                workspace_id TEXT,
                provider_id TEXT,
                session_id TEXT,
                last_accessed_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS paired_devices (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                paired_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS service_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS remote_client_diagnostic_breadcrumbs (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                operation TEXT NOT NULL,
                message TEXT NOT NULL,
                paired_mac_id TEXT,
                paired_device_id TEXT,
                workspace_id TEXT,
                provider_id TEXT,
                session_id TEXT,
                recorded_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_remote_client_diagnostic_breadcrumbs_recorded_at
            ON remote_client_diagnostic_breadcrumbs(recorded_at DESC);
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
        try ensureColumnExists(
            table: "sessions",
            column: "remote_runtime_generation",
            definition: "INTEGER NOT NULL DEFAULT 0"
        )
        let didAddLaunchSnapshotPrimarySurface = try ensureColumnExists(
            table: "launch_snapshots",
            column: "primary_surface",
            definition: "TEXT NOT NULL DEFAULT 'terminal'"
        )
        if didAddLaunchSnapshotPrimarySurface {
            try migrateLegacyStructuredLaunchSnapshotSurfacesIfNeeded()
        }
        try migrateLegacyPiSessionLinkagesIfNeeded()
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
                """
                SELECT workspaces.id, workspaces.name, workspaces.kind, workspaces.folder_path, workspaces.primary_group_id, remote_workspace_targets.host_id
                FROM workspaces
                LEFT JOIN remote_workspace_targets ON remote_workspace_targets.workspace_id = workspaces.id
                ORDER BY workspaces.rowid ASC;
                """
            )
            defer { sqlite3_finalize(statement) }

            var workspaces: [Workspace] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                workspaces.append(try readWorkspace(from: statement))
            }
            return workspaces
        }
    }

    func listHosts() throws -> [NexusDomain.Host] {
        try withLock {
            let statement = try prepare(
                "SELECT id, name, ssh_target, port FROM hosts ORDER BY rowid ASC;"
            )
            defer { sqlite3_finalize(statement) }

            var hosts: [NexusDomain.Host] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                hosts.append(try readHost(from: statement))
            }
            return hosts
        }
    }

    func remoteAccessEnabled() throws -> Bool {
        try withLock {
            let statement = try prepare(
                "SELECT value FROM service_settings WHERE key = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind("remote_access_enabled", at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return false
            }

            return sqlite3_column_int(statement, 0) != 0
        }
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) throws {
        try withLock {
            let statement = try prepare(
                """
                INSERT INTO service_settings (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind("remote_access_enabled", at: 1, in: statement)
            try bind(Int32(isEnabled ? 1 : 0), at: 2, in: statement)
            try stepDone(statement)
        }
    }

    func listPairedDevices() throws -> [PairedDevice] {
        try withLock {
            let statement = try prepare(
                "SELECT id, name, paired_at FROM paired_devices ORDER BY rowid ASC;"
            )
            defer { sqlite3_finalize(statement) }

            var devices: [PairedDevice] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                devices.append(try readPairedDevice(from: statement))
            }
            return devices
        }
    }

    func createPairedDevice(name: String, pairedAt: Date) throws -> PairedDevice {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw NexusMetadataStoreError.invalidPairedDeviceName
        }

        return try withLock {
            let pairedAtMilliseconds = Int64(pairedAt.timeIntervalSince1970 * 1_000)
            let normalizedPairedAt = Date(timeIntervalSince1970: Double(pairedAtMilliseconds) / 1_000)
            let device = PairedDevice(id: UUID(), name: trimmedName, pairedAt: normalizedPairedAt)
            let statement = try prepare(
                "INSERT INTO paired_devices (id, name, paired_at) VALUES (?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            try bind(device.id.uuidString, at: 1, in: statement)
            try bind(device.name, at: 2, in: statement)
            try bind(pairedAtMilliseconds, at: 3, in: statement)
            try stepDone(statement)
            return device
        }
    }

    func deletePairedDevice(id: UUID) throws -> Bool {
        try withLock {
            let statement = try prepare("DELETE FROM paired_devices WHERE id = ?;")
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
            return sqlite3_changes(database) > 0
        }
    }

    func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) throws {
        try withLock {
            let recordedAtMilliseconds = Int64(breadcrumb.recordedAt.timeIntervalSince1970 * 1_000)
            let statement = try prepare(
                """
                INSERT INTO remote_client_diagnostic_breadcrumbs (
                    id, kind, operation, message, paired_mac_id, paired_device_id, workspace_id, provider_id, session_id, recorded_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(breadcrumb.id.uuidString, at: 1, in: statement)
            try bind(breadcrumb.kind.rawValue, at: 2, in: statement)
            try bind(breadcrumb.operation.rawValue, at: 3, in: statement)
            try bind(breadcrumb.message, at: 4, in: statement)
            try bind(breadcrumb.pairedMacID, at: 5, in: statement)
            try bind(breadcrumb.pairedDeviceID?.uuidString, at: 6, in: statement)
            try bind(breadcrumb.workspaceID?.uuidString, at: 7, in: statement)
            try bind(breadcrumb.providerID?.rawValue, at: 8, in: statement)
            try bind(breadcrumb.sessionID?.uuidString, at: 9, in: statement)
            try bind(recordedAtMilliseconds, at: 10, in: statement)
            try stepDone(statement)

            let trimStatement = try prepare(
                """
                DELETE FROM remote_client_diagnostic_breadcrumbs
                WHERE id NOT IN (
                    SELECT id FROM remote_client_diagnostic_breadcrumbs
                    ORDER BY recorded_at DESC, rowid DESC
                    LIMIT 200
                );
                """
            )
            defer { sqlite3_finalize(trimStatement) }
            try stepDone(trimStatement)
        }
    }

    func listRemoteClientDiagnosticBreadcrumbs(limit: Int) throws -> [RemoteClientDiagnosticBreadcrumb] {
        guard limit > 0 else {
            return []
        }

        return try withLock {
            let statement = try prepare(
                """
                SELECT id, kind, operation, message, paired_mac_id, paired_device_id, workspace_id, provider_id, session_id, recorded_at
                FROM remote_client_diagnostic_breadcrumbs
                ORDER BY recorded_at DESC, rowid DESC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(Int32(limit), at: 1, in: statement)
            var breadcrumbs: [RemoteClientDiagnosticBreadcrumb] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                breadcrumbs.append(try readRemoteClientDiagnosticBreadcrumb(from: statement))
            }
            return breadcrumbs
        }
    }

    func createHost(name: String, sshTarget: String, port: Int?) throws -> NexusDomain.Host {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw NexusMetadataStoreError.invalidHostName
        }

        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTarget.isEmpty == false else {
            throw NexusMetadataStoreError.invalidHostTarget
        }

        if let port, (1...65_535).contains(port) == false {
            throw NexusMetadataStoreError.invalidHostPort
        }

        return try withLock {
            let host = NexusDomain.Host(id: UUID(), name: trimmedName, sshTarget: trimmedTarget, port: port)
            let statement = try prepare(
                "INSERT INTO hosts (id, name, ssh_target, port) VALUES (?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            try bind(host.id.uuidString, at: 1, in: statement)
            try bind(host.name, at: 2, in: statement)
            try bind(host.sshTarget, at: 3, in: statement)
            try bind(host.port.map(Int32.init), at: 4, in: statement)
            try stepDone(statement)
            return host
        }
    }

    func updateHost(id: UUID, name: String, sshTarget: String, port: Int?) throws -> NexusDomain.Host {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw NexusMetadataStoreError.invalidHostName
        }

        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTarget.isEmpty == false else {
            throw NexusMetadataStoreError.invalidHostTarget
        }

        if let port, (1...65_535).contains(port) == false {
            throw NexusMetadataStoreError.invalidHostPort
        }

        return try withLock {
            let statement = try prepare(
                "UPDATE hosts SET name = ?, ssh_target = ?, port = ? WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(trimmedName, at: 1, in: statement)
            try bind(trimmedTarget, at: 2, in: statement)
            try bind(port.map(Int32.init), at: 3, in: statement)
            try bind(id.uuidString, at: 4, in: statement)
            try stepDone(statement)

            guard sqlite3_changes(database) > 0 else {
                throw NexusMetadataStoreError.hostNotFound
            }

            let clearValidationStatement = try prepare("DELETE FROM host_validation_snapshots WHERE host_id = ?;")
            defer { sqlite3_finalize(clearValidationStatement) }
            try bind(id.uuidString, at: 1, in: clearValidationStatement)
            try stepDone(clearValidationStatement)

            return NexusDomain.Host(id: id, name: trimmedName, sshTarget: trimmedTarget, port: port)
        }
    }

    func deleteHost(id: UUID) throws -> Bool {
        try withLock {
            let remoteWorkspaceReferences = try remoteWorkspaceReferenceLabelsWithoutLock(hostID: id)
            guard remoteWorkspaceReferences.isEmpty else {
                throw NexusMetadataStoreError.hostDeletionBlockedByRemoteWorkspaces(remoteWorkspaceReferences)
            }

            let statement = try prepare("DELETE FROM hosts WHERE id = ?;")
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)

            guard sqlite3_changes(database) > 0 else {
                throw NexusMetadataStoreError.hostNotFound
            }

            return true
        }
    }

    func host(id: UUID) throws -> NexusDomain.Host? {
        try withLock {
            let statement = try prepare(
                "SELECT id, name, ssh_target, port FROM hosts WHERE id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try readHost(from: statement)
        }
    }

    func hostValidation(hostID: UUID) throws -> HostValidationSnapshot? {
        try withLock {
            let statement = try prepare(
                "SELECT host_id, state, summary, checked_at, diagnostics_json FROM host_validation_snapshots WHERE host_id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(hostID.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try readHostValidationSnapshot(from: statement)
        }
    }

    func saveHostValidation(hostID: UUID, result: HostValidationResult, checkedAt: Date) throws -> HostValidationSnapshot {
        try withLock {
            let checkedAtMilliseconds = Int64(checkedAt.timeIntervalSince1970 * 1_000)
            let normalizedCheckedAt = Date(timeIntervalSince1970: Double(checkedAtMilliseconds) / 1_000)
            let snapshot = HostValidationSnapshot(
                hostID: hostID,
                state: result.state,
                summary: result.summary,
                checkedAt: normalizedCheckedAt,
                diagnostics: result.diagnostics
            )
            let statement = try prepare(
                """
                INSERT INTO host_validation_snapshots (host_id, state, summary, checked_at, diagnostics_json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(host_id) DO UPDATE SET
                    state = excluded.state,
                    summary = excluded.summary,
                    checked_at = excluded.checked_at,
                    diagnostics_json = excluded.diagnostics_json;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(snapshot.hostID.uuidString, at: 1, in: statement)
            try bind(snapshot.state.rawValue, at: 2, in: statement)
            try bind(snapshot.summary, at: 3, in: statement)
            try bind(checkedAtMilliseconds, at: 4, in: statement)
            try bind(try encodeHostValidationDiagnostics(snapshot.diagnostics), at: 5, in: statement)
            try stepDone(statement)
            return snapshot
        }
    }

    func workspaceAvailability(workspaceID: UUID) throws -> WorkspaceAvailabilitySnapshot? {
        try withLock {
            let statement = try prepare(
                "SELECT workspace_id, state, summary, checked_at, diagnostics_json FROM workspace_availability_snapshots WHERE workspace_id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(workspaceID.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try readWorkspaceAvailabilitySnapshot(from: statement)
        }
    }

    func saveWorkspaceAvailability(workspaceID: UUID, result: WorkspaceAvailabilityResult, checkedAt: Date) throws -> WorkspaceAvailabilitySnapshot {
        try withLock {
            let checkedAtMilliseconds = Int64(checkedAt.timeIntervalSince1970 * 1_000)
            let normalizedCheckedAt = Date(timeIntervalSince1970: Double(checkedAtMilliseconds) / 1_000)
            let snapshot = WorkspaceAvailabilitySnapshot(
                workspaceID: workspaceID,
                state: result.state,
                summary: result.summary,
                checkedAt: normalizedCheckedAt,
                diagnostics: result.diagnostics
            )
            let statement = try prepare(
                """
                INSERT INTO workspace_availability_snapshots (workspace_id, state, summary, checked_at, diagnostics_json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(workspace_id) DO UPDATE SET
                    state = excluded.state,
                    summary = excluded.summary,
                    checked_at = excluded.checked_at,
                    diagnostics_json = excluded.diagnostics_json;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(snapshot.workspaceID.uuidString, at: 1, in: statement)
            try bind(snapshot.state.rawValue, at: 2, in: statement)
            try bind(snapshot.summary, at: 3, in: statement)
            try bind(checkedAtMilliseconds, at: 4, in: statement)
            try bind(try encodeWorkspaceAvailabilityDiagnostics(snapshot.diagnostics), at: 5, in: statement)
            try stepDone(statement)
            return snapshot
        }
    }

    func providerHealth(workspaceID: UUID, providerID: ProviderID) throws -> ProviderHealthSummary? {
        try withLock {
            let statement = try prepare(
                "SELECT state, summary, resolved_executable, version, launchability, checked_at, diagnostics_json FROM provider_health_snapshots WHERE workspace_id = ? AND provider_id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(workspaceID.uuidString, at: 1, in: statement)
            try bind(providerID.rawValue, at: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try readProviderHealthSnapshot(from: statement)
        }
    }

    func saveProviderHealth(workspaceID: UUID, providerID: ProviderID, summary: ProviderHealthSummary, checkedAt: Date) throws -> ProviderHealthSummary {
        try withLock {
            let checkedAtMilliseconds = Int64(checkedAt.timeIntervalSince1970 * 1_000)
            let normalizedCheckedAt = Date(timeIntervalSince1970: Double(checkedAtMilliseconds) / 1_000)
            let snapshot = ProviderHealthSummary(
                state: summary.state,
                summary: summary.summary,
                resolvedExecutable: summary.resolvedExecutable,
                version: summary.version,
                launchability: summary.launchability,
                checkedAt: normalizedCheckedAt,
                diagnostics: summary.diagnostics
            )
            let statement = try prepare(
                """
                INSERT INTO provider_health_snapshots (workspace_id, provider_id, state, summary, resolved_executable, version, launchability, checked_at, diagnostics_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(workspace_id, provider_id) DO UPDATE SET
                    state = excluded.state,
                    summary = excluded.summary,
                    resolved_executable = excluded.resolved_executable,
                    version = excluded.version,
                    launchability = excluded.launchability,
                    checked_at = excluded.checked_at,
                    diagnostics_json = excluded.diagnostics_json;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(workspaceID.uuidString, at: 1, in: statement)
            try bind(providerID.rawValue, at: 2, in: statement)
            try bind(snapshot.state.rawValue, at: 3, in: statement)
            try bind(snapshot.summary, at: 4, in: statement)
            try bind(snapshot.resolvedExecutable, at: 5, in: statement)
            try bind(snapshot.version, at: 6, in: statement)
            try bind(snapshot.launchability.rawValue, at: 7, in: statement)
            try bind(checkedAtMilliseconds, at: 8, in: statement)
            try bind(try encodeProviderHealthDiagnostics(snapshot.diagnostics), at: 9, in: statement)
            try stepDone(statement)
            return snapshot
        }
    }

    func workspace(id: UUID) throws -> Workspace? {
        try withLock {
            let statement = try prepare(
                """
                SELECT workspaces.id, workspaces.name, workspaces.kind, workspaces.folder_path, workspaces.primary_group_id, remote_workspace_targets.host_id
                FROM workspaces
                LEFT JOIN remote_workspace_targets ON remote_workspace_targets.workspace_id = workspaces.id
                WHERE workspaces.id = ?
                LIMIT 1;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(id.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try readWorkspace(from: statement)
        }
    }

    func listRecentNavigation(limit: Int) throws -> [NavigationTarget] {
        try withLock {
            let statement = try prepare(
                "SELECT target_kind, workspace_id, provider_id, session_id FROM recent_navigation ORDER BY last_accessed_at DESC LIMIT ?;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(Int32(max(1, limit)), at: 1, in: statement)
            var targets: [NavigationTarget] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                targets.append(try readNavigationTarget(from: statement))
            }
            return targets
        }
    }

    func recordNavigation(target: NavigationTarget) throws {
        try withLock {
            let statement = try prepare(
                """
                INSERT INTO recent_navigation (target_key, target_kind, workspace_id, provider_id, session_id, last_accessed_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(target_key) DO UPDATE SET
                    target_kind = excluded.target_kind,
                    workspace_id = excluded.workspace_id,
                    provider_id = excluded.provider_id,
                    session_id = excluded.session_id,
                    last_accessed_at = excluded.last_accessed_at;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(navigationTargetKey(target), at: 1, in: statement)
            try bind(target.kind.rawValue, at: 2, in: statement)
            try bind(target.workspaceID?.uuidString, at: 3, in: statement)
            try bind(target.providerID?.rawValue, at: 4, in: statement)
            try bind(target.sessionID?.uuidString, at: 5, in: statement)
            try bind(Int64(Date().timeIntervalSince1970 * 1_000), at: 6, in: statement)
            try stepDone(statement)
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

    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) throws -> Workspace {
        let resolvedRemotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedRemotePath.isEmpty == false, resolvedRemotePath.hasPrefix("/") else {
            throw NexusMetadataStoreError.invalidRemoteWorkspacePath
        }

        return try withLock {
            guard try hostExistsWithoutLock(id: hostID) else {
                throw NexusMetadataStoreError.hostNotFound
            }

            if try remoteWorkspaceTargetExistsWithoutLock(hostID: hostID, remotePath: resolvedRemotePath) {
                throw NexusMetadataStoreError.remoteWorkspaceTargetAlreadyExists(
                    hostName: try hostNameWithoutLock(id: hostID) ?? "Host",
                    remotePath: resolvedRemotePath
                )
            }

            let groups = try listWorkspaceGroupsWithoutLock()
            let resolvedPrimaryGroupID = try resolvePrimaryGroupID(primaryGroupID, groups: groups)
            let resolvedName = resolveWorkspaceName(name: name, folderPath: resolvedRemotePath)
            let workspace = Workspace(
                id: UUID(),
                name: resolvedName,
                kind: .remote,
                folderPath: resolvedRemotePath,
                primaryGroupID: resolvedPrimaryGroupID,
                remoteHostID: hostID
            )

            let workspaceStatement = try prepare(
                "INSERT INTO workspaces (id, name, kind, folder_path, primary_group_id) VALUES (?, ?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(workspaceStatement) }

            try bind(workspace.id.uuidString, at: 1, in: workspaceStatement)
            try bind(workspace.name, at: 2, in: workspaceStatement)
            try bind(workspace.kind.rawValue, at: 3, in: workspaceStatement)
            try bind(workspace.folderPath, at: 4, in: workspaceStatement)
            try bind(workspace.primaryGroupID.uuidString, at: 5, in: workspaceStatement)
            try stepDone(workspaceStatement)

            let targetStatement = try prepare(
                "INSERT INTO remote_workspace_targets (workspace_id, host_id, remote_path) VALUES (?, ?, ?);"
            )
            defer { sqlite3_finalize(targetStatement) }

            try bind(workspace.id.uuidString, at: 1, in: targetStatement)
            try bind(hostID.uuidString, at: 2, in: targetStatement)
            try bind(resolvedRemotePath, at: 3, in: targetStatement)
            try stepDone(targetStatement)
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

    func listAllSessions() throws -> [Session] {
        try withLock {
            let statement = try prepare(
                "SELECT id, workspace_id, provider_id, is_default, name, state, failure_message FROM sessions ORDER BY rowid ASC;"
            )
            defer { sqlite3_finalize(statement) }

            var sessions: [Session] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                sessions.append(try readSession(from: statement))
            }
            return sessions
        }
    }

    func launchSnapshot(sessionID: UUID) throws -> LaunchSnapshot? {
        try withLock {
            try launchSnapshotWithoutLock(sessionID: sessionID)
        }
    }

    func ensureLaunchSnapshot(
        sessionID: UUID,
        workspaceID: UUID,
        providerID: ProviderID,
        primarySurface: SessionSurface = .terminal,
        resolvedExecutable: String,
        resolvedWorkingDirectory: String
    ) throws -> LaunchSnapshot {
        try withLock {
            if let existingSnapshot = try launchSnapshotWithoutLock(sessionID: sessionID) {
                return existingSnapshot
            }

            let snapshot = LaunchSnapshot(
                sessionID: sessionID,
                workspaceID: workspaceID,
                providerID: providerID,
                primarySurface: primarySurface,
                resolvedExecutable: resolvedExecutable,
                resolvedWorkingDirectory: resolvedWorkingDirectory
            )
            let statement = try prepare(
                "INSERT INTO launch_snapshots (session_id, workspace_id, provider_id, primary_surface, resolved_executable, resolved_working_directory) VALUES (?, ?, ?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            try bind(snapshot.sessionID.uuidString, at: 1, in: statement)
            try bind(snapshot.workspaceID.uuidString, at: 2, in: statement)
            try bind(snapshot.providerID.rawValue, at: 3, in: statement)
            try bind(snapshot.primarySurface.rawValue, at: 4, in: statement)
            try bind(snapshot.resolvedExecutable, at: 5, in: statement)
            try bind(snapshot.resolvedWorkingDirectory, at: 6, in: statement)
            try stepDone(statement)
            return snapshot
        }
    }

    func updateLaunchSnapshotPrimarySurface(sessionID: UUID, primarySurface: SessionSurface) throws {
        try withLock {
            let statement = try prepare(
                "UPDATE launch_snapshots SET primary_surface = ? WHERE session_id = ?;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(primarySurface.rawValue, at: 1, in: statement)
            try bind(sessionID.uuidString, at: 2, in: statement)
            try stepDone(statement)
        }
    }

    func sessionRecordAdapterMetadata(sessionID: UUID) throws -> SessionRecordAdapterMetadata? {
        try withLock {
            try sessionRecordAdapterMetadataWithoutLock(sessionID: sessionID)
        }
    }

    func saveSessionRecordAdapterMetadata(sessionID: UUID, metadata: SessionRecordAdapterMetadata) throws {
        guard metadata.isEmpty == false else {
            return
        }

        try withLock {
            try saveSessionRecordAdapterMetadataWithoutLock(sessionID: sessionID, metadata: metadata)
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
            try bind(Int32(session.isDefault ? 1 : 0), at: 4, in: statement)
            try bind(session.name, at: 5, in: statement)
            try bind(session.state.rawValue, at: 6, in: statement)
            try bind(failureMessage, at: 7, in: statement)
            try bind(Int32(80), at: 8, in: statement)
            try bind(Int32(24), at: 9, in: statement)
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
            try bind(Int32(session.isDefault ? 1 : 0), at: 4, in: statement)
            try bind(session.name, at: 5, in: statement)
            try bind(session.state.rawValue, at: 6, in: statement)
            try bind(failureMessage, at: 7, in: statement)
            try bind(Int32(80), at: 8, in: statement)
            try bind(Int32(24), at: 9, in: statement)
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

    private func hostExistsWithoutLock(id: UUID) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM hosts WHERE id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, at: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func hostNameWithoutLock(id: UUID) throws -> String? {
        let statement = try prepare("SELECT name FROM hosts WHERE id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try readString(column: 0, from: statement)
    }

    private func remoteWorkspaceTargetExistsWithoutLock(hostID: UUID, remotePath: String) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM remote_workspace_targets WHERE host_id = ? AND remote_path = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(hostID.uuidString, at: 1, in: statement)
        try bind(remotePath, at: 2, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func remoteWorkspaceReferenceLabelsWithoutLock(hostID: UUID) throws -> [String] {
        let statement = try prepare(
            """
            SELECT workspaces.name, remote_workspace_targets.remote_path
            FROM remote_workspace_targets
            INNER JOIN workspaces ON workspaces.id = remote_workspace_targets.workspace_id
            WHERE remote_workspace_targets.host_id = ?
            ORDER BY workspaces.rowid ASC;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(hostID.uuidString, at: 1, in: statement)

        var labels: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = try readString(column: 0, from: statement)
            let remotePath = try readString(column: 1, from: statement)
            labels.append("\(name) (\(remotePath))")
        }
        return labels
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

    func remoteRuntimeGeneration(sessionID: UUID) throws -> Int {
        try withLock {
            let statement = try prepare(
                "SELECT remote_runtime_generation FROM sessions WHERE id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(sessionID.uuidString, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            return Int(sqlite3_column_int(statement, 0))
        }
    }

    func advanceRemoteRuntimeGeneration(sessionID: UUID) throws -> Int {
        try withLock {
            let statement = try prepare(
                "UPDATE sessions SET remote_runtime_generation = remote_runtime_generation + 1 WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }

            try bind(sessionID.uuidString, at: 1, in: statement)
            try stepDone(statement)

            let query = try prepare(
                "SELECT remote_runtime_generation FROM sessions WHERE id = ? LIMIT 1;"
            )
            defer { sqlite3_finalize(query) }

            try bind(sessionID.uuidString, at: 1, in: query)
            guard sqlite3_step(query) == SQLITE_ROW else {
                throw NexusMetadataStoreError.sessionNotFound
            }

            return Int(sqlite3_column_int(query, 0))
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

    private func launchSnapshotWithoutLock(sessionID: UUID) throws -> LaunchSnapshot? {
        let statement = try prepare(
            "SELECT session_id, workspace_id, provider_id, primary_surface, resolved_executable, resolved_working_directory FROM launch_snapshots WHERE session_id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(sessionID.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try readLaunchSnapshot(from: statement)
    }

    private func sessionRecordAdapterMetadataWithoutLock(sessionID: UUID) throws -> SessionRecordAdapterMetadata? {
        let statement = try prepare(
            "SELECT provider_id, metadata_json FROM session_record_adapter_metadata WHERE session_id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(sessionID.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let providerRawValue = try readString(column: 0, from: statement)
        guard let providerID = ProviderID(rawValue: providerRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown provider ID: \(providerRawValue)")
        }
        let values = try decodeSessionRecordAdapterMetadataValues(from: try readString(column: 1, from: statement))
        let metadata = SessionRecordAdapterMetadata(providerID: providerID, values: values)
        return metadata.isEmpty ? nil : metadata
    }

    private func saveSessionRecordAdapterMetadataWithoutLock(sessionID: UUID, metadata: SessionRecordAdapterMetadata) throws {
        let statement = try prepare(
            """
            INSERT INTO session_record_adapter_metadata (session_id, provider_id, metadata_json)
            VALUES (?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                provider_id = excluded.provider_id,
                metadata_json = excluded.metadata_json;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(sessionID.uuidString, at: 1, in: statement)
        try bind(metadata.providerID.rawValue, at: 2, in: statement)
        try bind(try encodeSessionRecordAdapterMetadataValues(metadata.values), at: 3, in: statement)
        try stepDone(statement)
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

    @discardableResult
    private func ensureColumnExists(table: String, column: String, definition: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if readOptionalString(column: 1, from: statement) == column {
                return false
            }
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
        return true
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

    private func bind(_ value: Int32?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw currentSQLiteError()
            }
            return
        }

        try bind(value, at: index, in: statement)
    }

    private func bind(_ value: Int64, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
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

    private func readOptionalInt(column: Int32, from statement: OpaquePointer?) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int(statement, column))
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
        let remoteHostID = try readOptionalUUID(column: 5, from: statement)
        return Workspace(
            id: id,
            name: name,
            kind: kind,
            folderPath: folderPath,
            primaryGroupID: primaryGroupID,
            remoteHostID: remoteHostID
        )
    }

    private func readHost(from statement: OpaquePointer?) throws -> NexusDomain.Host {
        NexusDomain.Host(
            id: try readUUID(column: 0, from: statement),
            name: try readString(column: 1, from: statement),
            sshTarget: try readString(column: 2, from: statement),
            port: readOptionalInt(column: 3, from: statement)
        )
    }

    private func readPairedDevice(from statement: OpaquePointer?) throws -> PairedDevice {
        PairedDevice(
            id: try readUUID(column: 0, from: statement),
            name: try readString(column: 1, from: statement),
            pairedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1_000)
        )
    }

    private func readRemoteClientDiagnosticBreadcrumb(from statement: OpaquePointer?) throws -> RemoteClientDiagnosticBreadcrumb {
        let kindRawValue = try readString(column: 1, from: statement)
        guard let kind = RemoteClientDiagnosticKind(rawValue: kindRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown remote client diagnostic kind: \(kindRawValue)")
        }
        let operationRawValue = try readString(column: 2, from: statement)
        guard let operation = RemoteClientDiagnosticOperation(rawValue: operationRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown remote client diagnostic operation: \(operationRawValue)")
        }

        return RemoteClientDiagnosticBreadcrumb(
            id: try readUUID(column: 0, from: statement),
            kind: kind,
            operation: operation,
            message: try readString(column: 3, from: statement),
            pairedMacID: readOptionalString(column: 4, from: statement),
            pairedDeviceID: try readOptionalUUID(column: 5, from: statement),
            workspaceID: try readOptionalUUID(column: 6, from: statement),
            providerID: readOptionalString(column: 7, from: statement).flatMap(ProviderID.init(rawValue:)),
            sessionID: try readOptionalUUID(column: 8, from: statement),
            recordedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 9)) / 1_000)
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

    private func readHostValidationSnapshot(from statement: OpaquePointer?) throws -> HostValidationSnapshot {
        let hostID = try readUUID(column: 0, from: statement)
        let stateRawValue = try readString(column: 1, from: statement)
        guard let state = HostValidationSnapshot.State(rawValue: stateRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown host validation state: \(stateRawValue)")
        }
        let summary = try readString(column: 2, from: statement)
        let checkedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1_000)
        let diagnostics = try decodeHostValidationDiagnostics(from: readString(column: 4, from: statement))
        return HostValidationSnapshot(hostID: hostID, state: state, summary: summary, checkedAt: checkedAt, diagnostics: diagnostics)
    }

    private func readWorkspaceAvailabilitySnapshot(from statement: OpaquePointer?) throws -> WorkspaceAvailabilitySnapshot {
        let workspaceID = try readUUID(column: 0, from: statement)
        let stateRawValue = try readString(column: 1, from: statement)
        guard let state = WorkspaceAvailabilitySnapshot.State(rawValue: stateRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown workspace availability state: \(stateRawValue)")
        }
        let summary = try readString(column: 2, from: statement)
        let checkedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1_000)
        let diagnostics = try decodeWorkspaceAvailabilityDiagnostics(from: readString(column: 4, from: statement))
        return WorkspaceAvailabilitySnapshot(workspaceID: workspaceID, state: state, summary: summary, checkedAt: checkedAt, diagnostics: diagnostics)
    }

    private func readProviderHealthSnapshot(from statement: OpaquePointer?) throws -> ProviderHealthSummary {
        let stateRawValue = try readString(column: 0, from: statement)
        guard let state = ProviderHealthSummary.State(rawValue: stateRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown provider health state: \(stateRawValue)")
        }
        let summary = try readString(column: 1, from: statement)
        let resolvedExecutable = readOptionalString(column: 2, from: statement)
        let version = readOptionalString(column: 3, from: statement)
        let launchabilityRawValue = try readString(column: 4, from: statement)
        guard let launchability = ProviderHealthSummary.Launchability(rawValue: launchabilityRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown provider launchability: \(launchabilityRawValue)")
        }
        let checkedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 5)) / 1_000)
        let diagnostics = try decodeProviderHealthDiagnostics(from: readString(column: 6, from: statement))
        return ProviderHealthSummary(
            state: state,
            summary: summary,
            resolvedExecutable: resolvedExecutable,
            version: version,
            launchability: launchability,
            checkedAt: checkedAt,
            diagnostics: diagnostics
        )
    }

    private func readLaunchSnapshot(from statement: OpaquePointer?) throws -> LaunchSnapshot {
        let sessionID = try readUUID(column: 0, from: statement)
        let workspaceID = try readUUID(column: 1, from: statement)
        let providerRawValue = try readString(column: 2, from: statement)
        guard let providerID = ProviderID(rawValue: providerRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown provider id: \(providerRawValue)")
        }
        let primarySurfaceRawValue = try readString(column: 3, from: statement)
        guard let primarySurface = SessionSurface(rawValue: primarySurfaceRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown session surface: \(primarySurfaceRawValue)")
        }
        let resolvedExecutable = try readString(column: 4, from: statement)
        let resolvedWorkingDirectory = try readString(column: 5, from: statement)
        return LaunchSnapshot(
            sessionID: sessionID,
            workspaceID: workspaceID,
            providerID: providerID,
            primarySurface: primarySurface,
            resolvedExecutable: resolvedExecutable,
            resolvedWorkingDirectory: resolvedWorkingDirectory
        )
    }

    private func readNavigationTarget(from statement: OpaquePointer?) throws -> NavigationTarget {
        let kindRawValue = try readString(column: 0, from: statement)
        guard let kind = NavigationTarget.Kind(rawValue: kindRawValue) else {
            throw NexusMetadataStoreError.sqlite("Unknown navigation target kind: \(kindRawValue)")
        }

        let workspaceID = try readOptionalUUID(column: 1, from: statement)
        let providerID = readOptionalString(column: 2, from: statement).flatMap(ProviderID.init(rawValue:))
        let sessionID = try readOptionalUUID(column: 3, from: statement)
        return NavigationTarget(kind: kind, workspaceID: workspaceID, providerID: providerID, sessionID: sessionID)
    }

    private func readOptionalUUID(column: Int32, from statement: OpaquePointer?) throws -> UUID? {
        guard let rawValue = readOptionalString(column: column, from: statement) else {
            return nil
        }

        guard let value = UUID(uuidString: rawValue) else {
            throw NexusMetadataStoreError.sqlite("Invalid UUID: \(rawValue)")
        }
        return value
    }

    private func migrateLegacyStructuredLaunchSnapshotSurfacesIfNeeded() throws {
        let statement = try prepare(
            "UPDATE launch_snapshots SET primary_surface = ? WHERE provider_id = ? AND primary_surface = ?;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(SessionSurface.structuredActivityFeed.rawValue, at: 1, in: statement)
        try bind(ProviderID.pi.rawValue, at: 2, in: statement)
        try bind(SessionSurface.terminal.rawValue, at: 3, in: statement)
        try stepDone(statement)
    }

    private func migrateLegacyPiSessionLinkagesIfNeeded() throws {
        guard try tableExists("pi_session_linkages") else {
            return
        }

        let statement = try prepare("SELECT session_id, pi_session_id, session_file FROM pi_session_linkages;")
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let sessionID = try readUUID(column: 0, from: statement)
            if try sessionRecordAdapterMetadataWithoutLock(sessionID: sessionID) != nil {
                continue
            }

            let metadata = SessionRecordAdapterMetadata(
                providerID: .pi,
                values: [
                    "piSessionID": readOptionalString(column: 1, from: statement) ?? "",
                    "sessionFile": readOptionalString(column: 2, from: statement) ?? ""
                ]
            )
            guard metadata.isEmpty == false else {
                continue
            }

            try saveSessionRecordAdapterMetadataWithoutLock(sessionID: sessionID, metadata: metadata)
        }
    }

    private func tableExists(_ table: String) throws -> Bool {
        let statement = try prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }

        try bind(table, at: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func encodeSessionRecordAdapterMetadataValues(_ values: [String: String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not encode Session Record adapter metadata")
        }
        return json
    }

    private func decodeSessionRecordAdapterMetadataValues(from json: String) throws -> [String: String] {
        guard let data = json.data(using: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not decode Session Record adapter metadata")
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func encodeHostValidationDiagnostics(_ diagnostics: [HostValidationDiagnostic]) throws -> String {
        let data = try JSONEncoder().encode(diagnostics)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not encode host validation diagnostics")
        }
        return json
    }

    private func decodeHostValidationDiagnostics(from json: String) throws -> [HostValidationDiagnostic] {
        guard let data = json.data(using: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not decode host validation diagnostics")
        }
        return try JSONDecoder().decode([HostValidationDiagnostic].self, from: data)
    }

    private func encodeWorkspaceAvailabilityDiagnostics(_ diagnostics: [WorkspaceAvailabilityDiagnostic]) throws -> String {
        let data = try JSONEncoder().encode(diagnostics)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not encode workspace availability diagnostics")
        }
        return json
    }

    private func decodeWorkspaceAvailabilityDiagnostics(from json: String) throws -> [WorkspaceAvailabilityDiagnostic] {
        guard let data = json.data(using: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not decode workspace availability diagnostics")
        }
        return try JSONDecoder().decode([WorkspaceAvailabilityDiagnostic].self, from: data)
    }

    private func encodeProviderHealthDiagnostics(_ diagnostics: [ProviderHealthDiagnostic]) throws -> String {
        let data = try JSONEncoder().encode(diagnostics)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not encode provider health diagnostics")
        }
        return json
    }

    private func decodeProviderHealthDiagnostics(from json: String) throws -> [ProviderHealthDiagnostic] {
        guard let data = json.data(using: .utf8) else {
            throw NexusMetadataStoreError.sqlite("Could not decode provider health diagnostics")
        }
        return try JSONDecoder().decode([ProviderHealthDiagnostic].self, from: data)
    }

    private func navigationTargetKey(_ target: NavigationTarget) -> String {
        switch target.kind {
        case .workspace:
            "workspace:\(target.workspaceID?.uuidString ?? "missing")"
        case .provider:
            "provider:\(target.workspaceID?.uuidString ?? "missing"):\(target.providerID?.rawValue ?? "missing")"
        case .session:
            "session:\(target.sessionID?.uuidString ?? "missing")"
        }
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
    case invalidHostName
    case invalidHostTarget
    case invalidHostPort
    case invalidRemoteWorkspacePath
    case invalidPairedDeviceName
    case invalidSessionName
    case workspaceGroupRequired
    case primaryWorkspaceGroupSelectionRequired
    case workspaceGroupNotFound
    case workspaceNotFound
    case hostNotFound
    case hostDeletionBlockedByRemoteWorkspaces([String])
    case remoteWorkspaceTargetAlreadyExists(hostName: String, remotePath: String)
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
        case .invalidHostName:
            "Host name is required"
        case .invalidHostTarget:
            "SSH target or alias is required"
        case .invalidHostPort:
            "Host port must be between 1 and 65535"
        case .invalidRemoteWorkspacePath:
            "Remote Workspace path must be absolute"
        case .invalidPairedDeviceName:
            "Paired Device name is required"
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
        case .hostNotFound:
            "Host not found"
        case .hostDeletionBlockedByRemoteWorkspaces(let labels):
            "Host is still referenced by Remote Workspaces: \(labels.joined(separator: ", "))"
        case .remoteWorkspaceTargetAlreadyExists(let hostName, let remotePath):
            "A Remote Workspace already exists for \(hostName) at \(remotePath)"
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
#endif
