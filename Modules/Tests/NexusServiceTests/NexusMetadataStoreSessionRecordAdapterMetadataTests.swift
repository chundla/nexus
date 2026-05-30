#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import SQLite3
import Testing

struct NexusMetadataStoreSessionRecordAdapterMetadataTests {
    @Test func sessionRecordAdapterMetadataRoundTripsSeparatelyFromLaunchSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusMetadataStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let store = try NexusMetadataStore(storeURL: rootURL.appendingPathComponent("metadata.sqlite"))
        let group = try store.createWorkspaceGroup(name: "Solo Group")
        let workspace = try store.createLocalWorkspace(
            name: "Workspace",
            folderPath: rootURL.appendingPathComponent("workspace", isDirectory: true).path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let session = try store.createDefaultSession(
            workspaceID: workspace.id,
            providerID: .pi,
            state: .ready,
            failureMessage: nil
        )
        let launchSnapshot = try store.ensureLaunchSnapshot(
            sessionID: session.id,
            workspaceID: workspace.id,
            providerID: .pi,
            primarySurface: .structuredActivityFeed,
            resolvedExecutable: "/tmp/fake-pi",
            resolvedWorkingDirectory: workspace.folderPath
        )

        let metadata = try #require(
            SessionRecordAdapterMetadata.pi(
                linkage: PiSessionLinkage(
                    piSessionID: "pi-session-1",
                    sessionFile: "/tmp/pi-session-1.jsonl"
                ),
                activityItems: [
                    SessionActivityItem(kind: .status, text: "Pi shared Session stream connected"),
                    SessionActivityItem(kind: .message, text: "You: deploy")
                ],
                approvalRequests: [
                    SessionApprovalRequest(
                        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                        title: "Approve deploy",
                        text: "Pi wants to deploy.",
                        state: .pending
                    )
                ],
                extensionUIState: SessionExtensionUIState(
                    pendingDialogs: [
                        SessionExtensionUIDialog(
                            id: "deploy-dialog",
                            kind: .confirm,
                            title: "Deploy to production?"
                        )
                    ]
                ),
                providerEvents: [
                    SessionProviderEvent(
                        sequence: 0,
                        providerID: .pi,
                        type: "extension_ui_request",
                        family: .unknown,
                        rawPayload: "{\"type\":\"extension_ui_request\"}"
                    )
                ]
            )
        )
        try store.saveSessionRecordAdapterMetadata(sessionID: session.id, metadata: metadata)

        let storedMetadata = try #require(try store.sessionRecordAdapterMetadata(sessionID: session.id))

        #expect(try store.launchSnapshot(sessionID: session.id) == launchSnapshot)
        #expect(storedMetadata == metadata)
        #expect(storedMetadata.piSessionLinkage?.piSessionID == "pi-session-1")
        #expect(storedMetadata.piPersistedActivityItems?.map(\.text) == ["Pi shared Session stream connected", "You: deploy"])
        #expect(storedMetadata.piPersistedApprovalRequests?.map(\.title) == ["Approve deploy"])
        #expect(storedMetadata.piPersistedExtensionUIState?.pendingDialogs.map(\.title) == ["Deploy to production?"])
        #expect(storedMetadata.piPersistedProviderEvents?.map(\.type) == ["extension_ui_request"])
    }

    @Test func reopeningStoreMigratesLegacyPiSessionLinkageIntoGenericSessionRecordMetadata() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusMetadataStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("metadata.sqlite")
        let session: Session = try {
            let store = try NexusMetadataStore(storeURL: storeURL)
            let group = try store.createWorkspaceGroup(name: "Solo Group")
            let workspace = try store.createLocalWorkspace(
                name: "Workspace",
                folderPath: rootURL.appendingPathComponent("workspace", isDirectory: true).path(percentEncoded: false),
                primaryGroupID: group.id
            )
            return try store.createDefaultSession(
                workspaceID: workspace.id,
                providerID: .pi,
                state: .ready,
                failureMessage: nil
            )
        }()

        var database: OpaquePointer?
        #expect(sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
        guard let database else {
            Issue.record("Expected legacy metadata database to open")
            return
        }
        defer { sqlite3_close(database) }

        #expect(
            sqlite3_exec(
                database,
                """
                CREATE TABLE IF NOT EXISTS pi_session_linkages (
                    session_id TEXT PRIMARY KEY NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                    pi_session_id TEXT,
                    session_file TEXT
                );
                """,
                nil,
                nil,
                nil
            ) == SQLITE_OK
        )
        #expect(
            sqlite3_exec(
                database,
                "INSERT INTO pi_session_linkages (session_id, pi_session_id, session_file) VALUES ('\(session.id.uuidString)', 'pi-session-legacy', '/tmp/pi-session-legacy.jsonl');",
                nil,
                nil,
                nil
            ) == SQLITE_OK
        )

        let reopenedStore = try NexusMetadataStore(storeURL: storeURL)

        #expect(
            try reopenedStore.sessionRecordAdapterMetadata(sessionID: session.id) == SessionRecordAdapterMetadata(
                providerID: .pi,
                values: [
                    "piSessionID": "pi-session-legacy",
                    "sessionFile": "/tmp/pi-session-legacy.jsonl"
                ]
            )
        )
    }
}
#endif
