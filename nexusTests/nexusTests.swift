//
//  nexusTests.swift
//  nexusTests
//
//  Created by Chandler on 5/18/26.
//

import Foundation
import Testing
@testable import nexus

struct nexusTests {

    @Test func embeddedServiceBootstrapStartsBackgroundServiceReachableOverIPC() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let status = try await client.getServiceStatus()

        #expect(status.state == .running)
        #expect(status.store.kind == .sqlite)
        #expect(status.store.owner == .backgroundService)
        #expect(status.store.location.path(percentEncoded: false).hasSuffix("Nexus.sqlite"))
    }

    @MainActor
    @Test func appModelLoadsServiceStatusFromIPCClient() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        let model = NexusAppModel(client: client)

        await model.refreshServiceStatus()

        #expect(model.serviceStatus?.state == .running)
        #expect(model.serviceStatus?.store.owner == .backgroundService)
    }

    @Test func embeddedServiceBootstrapCreatesAndOwnsMetadataStoreFile() async throws {
        let service = try NexusEmbeddedServiceBootstrap.bootstrapForTests()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)

        let status = try await client.getServiceStatus()

        #expect(FileManager.default.fileExists(atPath: service.storeURL.path(percentEncoded: false)))
        #expect(status.store.location == service.storeURL)
        #expect(status.store.owner == .backgroundService)
    }

    @MainActor
    @Test func appModelReportsUnavailableServiceWhenStatusRefreshFails() async {
        let model = NexusAppModel(client: FailingServiceStatusClient())

        await model.refreshServiceStatus()

        #expect(model.serviceStatus == nil)
        #expect(model.serviceErrorMessage == "Background Service unavailable")
    }

    @MainActor
    @Test func liveAppModelBootstrapsEmbeddedBackgroundServiceAndLoadsStatus() async throws {
        let model = try NexusAppModel.live()

        await model.refreshServiceStatus()

        let status = try #require(model.serviceStatus)
        #expect(status.state == .running)
        #expect(status.store.kind == .sqlite)
        #expect(status.store.owner == .backgroundService)
        #expect(status.store.location.path(percentEncoded: false).contains("Application Support"))
        #expect(status.store.location.lastPathComponent == "Nexus.sqlite")
        #expect(model.serviceErrorMessage == nil)
    }

}

private struct FailingServiceStatusClient: NexusServiceStatusClient {
    func getServiceStatus() async throws -> NexusServiceStatus {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background Service unavailable"])
    }
}
