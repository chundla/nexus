#if os(macOS)
import Foundation
import NexusDomain
@testable import NexusService
import Testing

struct NexusServiceIBMBobSessionLifecycleTests {
    @Test func localIBMBobDefaultSessionLaunchOpensStructuredIdleScreen() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try makeIBMBobService(rootURL: rootURL)
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let prelaunchOverview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let launchedSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let screen = try service.getSessionScreen(sessionID: launchedSession.id)
        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

        let prelaunchProviderCard = try #require(prelaunchOverview.providerCards.first(where: { $0.provider.id == .ibmBob }))
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))

        #expect(launchedSession.providerID == .ibmBob)
        #expect(launchedSession.isDefault)
        #expect(screen.session.state == .ready)
        #expect(screen.primarySurface == .structuredActivityFeed)
        #expect(screen.transcript.isEmpty)
        #expect(screen.activityItems.map(\.kind) == [.status])
        #expect(screen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(prelaunchProviderCard.defaultSession.state == .notCreated)
        #expect(prelaunchProviderCard.defaultSession.actionTitle == "Launch")
        #expect(providerCard.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(providerCard.defaultSession.state == .ready)
        #expect(providerCard.defaultSession.actionTitle == "Resume")
        #expect(providerDetail.prelaunchPrimarySurface == .structuredActivityFeed)
        #expect(providerDetail.defaultSession?.id == launchedSession.id)
    }

    @Test func localIBMBobNamedSessionUsesSharedNamingAndIdleStructuredScreen() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try makeIBMBobService(rootURL: rootURL)
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let firstNamedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: nil)
        let secondNamedSession = try service.createNamedSession(workspaceID: workspace.id, providerID: .ibmBob, name: nil)
        let firstScreen = try service.getSessionScreen(sessionID: firstNamedSession.id)
        let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

        #expect(firstNamedSession.isDefault == false)
        #expect(firstNamedSession.name == "Session 1")
        #expect(secondNamedSession.name == "Session 2")
        #expect(firstScreen.primarySurface == .structuredActivityFeed)
        #expect(firstScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(providerDetail.alternateSessions.map(\.name) == ["Session 1", "Session 2"])
    }

    @Test func localIBMBobIdleReadySessionRejectsStopAndStaysResumable() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try makeIBMBobService(rootURL: rootURL)
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let launchedSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)

        do {
            _ = try service.stopSession(sessionID: launchedSession.id)
            Issue.record("Expected idle ready IBM Bob Session to reject Stop Session")
        } catch let error as IBMBobSessionRuntimeError {
            #expect(error == .noActiveTurnToStop)
        }

        let idleScreen = try service.getSessionScreen(sessionID: launchedSession.id)
        let overview = try service.getWorkspaceOverview(workspaceID: workspace.id)
        let providerCard = try #require(overview.providerCards.first(where: { $0.provider.id == .ibmBob }))

        #expect(idleScreen.session.state == .ready)
        #expect(idleScreen.primarySurface == .structuredActivityFeed)
        #expect(idleScreen.activityItems.map(\.text) == ["IBM Bob Session ready. Send a prompt to start IBM Bob."])
        #expect(providerCard.defaultSession.state == .ready)
        #expect(providerCard.defaultSession.actionTitle == "Resume")
    }

    @Test func localIBMBobIdleReadySessionRecordDeletesWithoutStoredContinuity() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceFolder = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)

        let service = try makeIBMBobService(rootURL: rootURL)
        let group = try service.createWorkspaceGroup(name: "Solo Group")
        let workspace = try service.createLocalWorkspace(
            name: "Local Bob",
            folderPath: workspaceFolder.path(percentEncoded: false),
            primaryGroupID: group.id
        )

        let launchedSession = try service.launchOrResumeDefaultSession(workspaceID: workspace.id, providerID: .ibmBob)
        let deleted = try service.deleteSessionRecord(sessionID: launchedSession.id)
        let providerDetail = try service.getProviderDetail(workspaceID: workspace.id, providerID: .ibmBob)

        #expect(deleted)
        #expect(providerDetail.defaultSession == nil)
        do {
            _ = try service.getSessionRecord(sessionID: launchedSession.id)
            Issue.record("Expected deleted IBM Bob Session Record to be removed")
        } catch let error as NexusMetadataStoreError {
            switch error {
            case .sessionNotFound:
                break
            default:
                Issue.record("Expected sessionNotFound after deleting idle IBM Bob Session Record")
            }
        }
    }
}

private func makeIBMBobService(rootURL: URL) throws -> NexusService {
    try NexusService.bootstrapForTests(
        rootURL: rootURL,
        providerHealthEvaluator: ProviderHealthFacts(
            executableResolver: IBMBobSessionStubExecutableResolver(executables: ["bob": "/tmp/fake-bob"]),
            commandRunner: IBMBobSessionStubCommandRunner(results: [
                .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--version'"]): .success(stdout: "3.4.5\n"),
                .init(executable: "/bin/zsh", arguments: ["-lic", "'/tmp/fake-bob' '--list-sessions'"]): .success(stdout: "[]\n")
            ]),
            localShellCommandBuilder: LocalShellCommandBuilder(environment: ["SHELL": "/bin/zsh"])
        )
    )
}

private struct IBMBobSessionStubExecutableResolver: ProviderExecutableResolving {
    let executables: [String: String]

    func resolveExecutable(named command: String) -> ProviderExecutableResolution {
        ProviderExecutableResolution(
            resolvedExecutable: executables[command],
            searchedDirectories: ["/tmp/bin"],
            homeDirectories: ["/tmp/home"],
            pathEnvironment: "/tmp/bin"
        )
    }
}

private struct IBMBobSessionStubCommandRunner: ProviderCommandRunning {
    struct Invocation: Hashable {
        let executable: String
        let arguments: [String]
    }

    enum StubbedResult {
        case success(stdout: String, stderr: String = "", exitStatus: Int32 = 0)
    }

    let results: [Invocation: StubbedResult]

    func run(executable: String, arguments: [String], currentDirectoryURL: URL?) throws -> ProviderCommandResult {
        guard let result = results[Invocation(executable: executable, arguments: arguments)] else {
            throw NSError(domain: "IBMBobSessionStubCommandRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(executable) \(arguments)"])
        }

        switch result {
        case let .success(stdout, stderr, exitStatus):
            return ProviderCommandResult(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}
#endif
