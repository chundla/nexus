#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceSessionLifecycleDelegationTests {
    @Test func launchOrResumeDefaultSessionDelegatesToSessionLifecycleModule() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionLifecycleSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(),
            sessionLifecycle: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let expectedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            isDefault: true,
            state: .ready
        )
        spy.defaultSessionResult = expectedSession

        let session = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .claude)

        #expect(session == expectedSession)
        #expect(spy.defaultSessionCalls == [
            .init(workspaceID: workspace.id, providerID: .claude)
        ])
    }

    @Test func createNamedSessionDelegatesToSessionLifecycleModule() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let spy = SessionLifecycleSpy()
        let service = try NexusService.bootstrapForTests(
            rootURL: rootURL,
            providerHealthEvaluator: ProviderHealthEvaluator(),
            sessionLifecycle: spy
        )
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Claude",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )
        let expectedSession = Session(
            id: UUID(),
            workspaceID: workspace.id,
            providerID: .claude,
            name: "Review",
            isDefault: false,
            state: .ready
        )
        spy.namedSessionResult = expectedSession

        let session = try service.createNamedSession(workspaceID: workspace.id, providerID: .claude, name: "Review")

        #expect(session == expectedSession)
        #expect(spy.namedSessionCalls == [
            .init(workspaceID: workspace.id, providerID: .claude, name: "Review")
        ])
    }
}

private final class SessionLifecycleSpy: SessionLifecycleManaging, @unchecked Sendable {
    struct Call: Equatable {
        let workspaceID: UUID
        let providerID: ProviderID
    }

    struct NamedCall: Equatable {
        let workspaceID: UUID
        let providerID: ProviderID
        let name: String?
    }

    var defaultSessionResult = Session(
        id: UUID(),
        workspaceID: UUID(),
        providerID: .claude,
        isDefault: true,
        state: .ready
    )
    var namedSessionResult = Session(
        id: UUID(),
        workspaceID: UUID(),
        providerID: .claude,
        name: "Review",
        isDefault: false,
        state: .ready
    )
    private(set) var defaultSessionCalls: [Call] = []
    private(set) var namedSessionCalls: [NamedCall] = []

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        defaultSessionCalls.append(.init(workspaceID: workspaceID, providerID: providerID))
        return defaultSessionResult
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        namedSessionCalls.append(.init(workspaceID: workspaceID, providerID: providerID, name: name))
        return namedSessionResult
    }
}
#endif
