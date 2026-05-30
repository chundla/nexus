#if os(macOS)
import Foundation
import NexusDomain

func shouldReuseRemoteCLIHealthSnapshot(
    _ snapshot: ProviderHealthSummary,
    remoteContext: RemoteWorkspaceHealthContext?
) -> Bool {
    guard snapshot.checkedAt != nil else {
        return false
    }

    let hostValidationAvailable = remoteContext?.hostValidation?.state == .available
    let workspaceAvailabilityAvailable = remoteContext?.workspaceAvailability?.state == .available

    if snapshot.state == .blocked {
        return hostValidationAvailable == false || workspaceAvailabilityAvailable == false
    }

    guard hostValidationAvailable && workspaceAvailabilityAvailable else {
        return false
    }

    switch snapshot.state {
    case .available:
        return true
    case .unavailable, .misconfigured, .notChecked, .blocked:
        return false
    }
}

enum ServiceSessionProviderRegistry {
    static func providerModules(
        overrides: [ProviderID: any ProviderModule] = [:]
    ) -> ProviderModuleRegistry {
        let defaults: [ProviderID: any ProviderModule] = [
            .claude: ClaudeProviderModule(),
            .codex: CodexProviderModule(),
            .ibmBob: IBMBobProviderModule(),
            .pi: PiProviderModule()
        ]

        return ProviderModuleRegistry(
            modules: defaults.merging(overrides) { _, override in override }
        )
    }
}
#endif
