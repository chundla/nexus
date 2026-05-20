import Foundation
import NexusDomain
import NexusIPC
import NexusService
import Observation

@Observable
final class NexusAppModel {
    var serviceStatus: NexusServiceStatus?
    var serviceErrorMessage: String?

    private let client: NexusServiceStatusClient
    private let embeddedService: (any NexusEmbeddedServiceSession)?

    init(client: NexusServiceStatusClient, embeddedService: (any NexusEmbeddedServiceSession)? = nil) {
        self.client = client
        self.embeddedService = embeddedService
    }

    static func live() throws -> NexusAppModel {
        let service = try NexusEmbeddedServiceBootstrap.bootstrap()
        let client = try NexusIPCClient.connect(to: service.listenerEndpoint)
        return NexusAppModel(client: client, embeddedService: service)
    }

    func refreshServiceStatus() async {
        do {
            serviceStatus = try await client.getServiceStatus()
            serviceErrorMessage = nil
        } catch {
            serviceStatus = nil
            serviceErrorMessage = error.localizedDescription
        }
    }
}
