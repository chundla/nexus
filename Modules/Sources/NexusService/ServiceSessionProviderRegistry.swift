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
    static func providerAdapters(
        overrides: [ProviderID: ServiceProviderAdapter]? = nil
    ) -> [ProviderID: ServiceProviderAdapter] {
        let defaults: [ProviderID: ServiceProviderAdapter] = [
            .claude: ServiceProviderAdapter(
                providerID: .claude,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                    await providerHealthEvaluator.healthSummary(for: .claude, workspace: workspace, remoteContext: remoteContext)
                },
                shouldReuseRemoteHealthSnapshot: { snapshot, remoteContext in
                    shouldReuseRemoteCLIHealthSnapshot(snapshot, remoteContext: remoteContext)
                }
            ),
            .codex: ServiceProviderAdapter(
                providerID: .codex,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                    await providerHealthEvaluator.healthSummary(for: .codex, workspace: workspace, remoteContext: remoteContext)
                },
                primarySurfaceEvaluator: { _ in .structuredActivityFeed },
                shouldReuseRemoteHealthSnapshot: { snapshot, remoteContext in
                    shouldReuseRemoteCLIHealthSnapshot(snapshot, remoteContext: remoteContext)
                }
            ),
            .ibmBob: ServiceProviderAdapter(
                providerID: .ibmBob,
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                    await providerHealthEvaluator.healthSummary(for: .ibmBob, workspace: workspace, remoteContext: remoteContext)
                },
                primarySurfaceEvaluator: { _ in .structuredActivityFeed }
            ),
            .pi: ServiceProviderAdapter(
                providerID: .pi,
                supportsDefaultSessionLaunch: false,
                supportsNamedSessions: false,
                healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                    await providerHealthEvaluator.healthSummary(for: .pi, workspace: workspace, remoteContext: remoteContext)
                },
                primarySurfaceEvaluator: { _ in .structuredActivityFeed }
            )
        ]

        guard let overrides else {
            return defaults
        }

        return defaults.merging(overrides) { _, override in override }
    }

    static func providerModules(
        providerAdapters: [ProviderID: ServiceProviderAdapter]
    ) -> ProviderModuleRegistry {
        var modules: [ProviderID: any ProviderModule] = providerAdapters.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }

        if providerAdapters[.pi] != nil {
            modules[.pi] = PiProviderModule()
        }

        return ProviderModuleRegistry(modules: modules)
    }

    static func localProtocolNativeRuntimeFactories(
        piTransportFactory: @escaping PiRPCSessionRuntime.TransportFactory,
        codexTransportFactory: @escaping CodexAppServerRuntime.TransportFactory,
        ibmBobTransportFactory: @escaping IBMBobSessionRuntime.TransportFactory
    ) -> [ProviderID: ProcessSessionRuntimeLauncher.ProtocolNativeRuntimeFactory] {
        [
            .pi: { launchConfiguration, _, _ in
                try await PiRPCSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.piSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder
                )
            },
            .codex: { launchConfiguration, _, _ in
                try await CodexAppServerRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.codexSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    transportFactory: codexTransportFactory
                )
            },
            .ibmBob: { launchConfiguration, _, _ in
                try IBMBobSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.ibmBobSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    transportFactory: ibmBobTransportFactory
                )
            }
        ]
    }

    static func remoteProtocolNativeRuntimeFactories(
        piTransportFactory: @escaping PiRPCSessionRuntime.TransportFactory,
        codexTransportFactory: @escaping CodexAppServerRuntime.TransportFactory,
        ibmBobTransportFactory: @escaping IBMBobSessionRuntime.TransportFactory,
        remoteProtocolSessionCommandBuilder: RemoteProtocolSessionCommandBuilder,
        remoteIBMBobCommandBuilder: RemoteIBMBobCommandBuilder
    ) -> [ProviderID: ProcessSessionRuntimeLauncher.ProtocolNativeRuntimeFactory] {
        [
            .pi: { launchConfiguration, _, _ in
                guard let remoteHost = launchConfiguration.remoteHost,
                      let runtimeIdentifier = launchConfiguration.remoteRuntimeIdentifier else {
                    throw NSError(
                        domain: "ProcessSessionRuntimeLauncher",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Remote Pi launch requires a Host and runtime identifier."]
                    )
                }

                let bridgeArguments = remoteProtocolSessionCommandBuilder.bridgeArguments(
                    host: remoteHost,
                    runtimeIdentifier: runtimeIdentifier,
                    workingDirectory: launchConfiguration.workingDirectory,
                    executable: launchConfiguration.executable,
                    providerArguments: PiRPCSessionRuntime.transportArguments(
                        sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.piSessionLinkage
                    ),
                    launchMode: launchConfiguration.remoteRuntimeLaunchMode
                )

                return try await PiRPCSessionRuntime(
                    executable: "/usr/bin/ssh",
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.piSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    unexpectedTerminationState: .interrupted,
                    unexpectedTerminationMessageBuilder: { _ in
                        "Pi Session stream disconnected. Relaunch to reconnect to the tmux-backed remote runtime."
                    },
                    stopHandler: {
                        try ProcessSessionRuntimeLauncher.runCommand(
                            executable: "/usr/bin/ssh",
                            arguments: remoteProtocolSessionCommandBuilder.stopArguments(
                                runtimeIdentifier: runtimeIdentifier,
                                host: remoteHost
                            )
                        )
                    },
                    transportFactory: { _, _, _ in
                        try piTransportFactory("/usr/bin/ssh", bridgeArguments, nil)
                    }
                )
            },
            .codex: { launchConfiguration, _, _ in
                guard let remoteHost = launchConfiguration.remoteHost,
                      let runtimeIdentifier = launchConfiguration.remoteRuntimeIdentifier else {
                    throw NSError(
                        domain: "ProcessSessionRuntimeLauncher",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Remote Codex launch requires a Host and runtime identifier."]
                    )
                }

                let bridgeArguments = remoteProtocolSessionCommandBuilder.bridgeArguments(
                    host: remoteHost,
                    runtimeIdentifier: runtimeIdentifier,
                    workingDirectory: launchConfiguration.workingDirectory,
                    executable: launchConfiguration.executable,
                    providerArguments: ["app-server"],
                    launchMode: launchConfiguration.remoteRuntimeLaunchMode
                )

                return try await CodexAppServerRuntime(
                    executable: "/usr/bin/ssh",
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.codexSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    unexpectedTerminationState: .interrupted,
                    unexpectedTerminationMessageBuilder: { _ in
                        "Codex Session stream disconnected. Relaunch to reconnect to the tmux-backed remote runtime."
                    },
                    stopHandler: {
                        try ProcessSessionRuntimeLauncher.runCommand(
                            executable: "/usr/bin/ssh",
                            arguments: remoteProtocolSessionCommandBuilder.stopArguments(
                                runtimeIdentifier: runtimeIdentifier,
                                host: remoteHost
                            )
                        )
                    },
                    transportFactory: { _, _, _ in
                        try codexTransportFactory("/usr/bin/ssh", bridgeArguments, nil)
                    }
                )
            },
            .ibmBob: { launchConfiguration, _, _ in
                guard let remoteHost = launchConfiguration.remoteHost,
                      let runtimeIdentifier = launchConfiguration.remoteRuntimeIdentifier else {
                    throw NSError(
                        domain: "ProcessSessionRuntimeLauncher",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Remote IBM Bob launch requires a Host and runtime identifier."]
                    )
                }

                return try IBMBobSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.ibmBobSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    unexpectedTerminationState: .interrupted,
                    unexpectedTerminationStateEvaluator: { status, errorText in
                        let normalized = errorText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if status == 255
                            || normalized.contains("could not resolve hostname")
                            || normalized.contains("operation timed out")
                            || normalized.contains("connection refused")
                            || normalized.contains("no route to host")
                            || normalized.contains("connection closed by remote host")
                            || normalized.contains("broken pipe")
                            || normalized.contains("network is unreachable") {
                            return .interrupted
                        }
                        return .failed
                    },
                    transportFactory: { executable, arguments, workingDirectory in
                        try ibmBobTransportFactory(
                            "/usr/bin/ssh",
                            remoteIBMBobCommandBuilder.bridgeArguments(
                                host: remoteHost,
                                runtimeIdentifier: runtimeIdentifier,
                                workingDirectory: workingDirectory ?? launchConfiguration.workingDirectory,
                                executable: executable,
                                providerArguments: arguments
                            ),
                            nil
                        )
                    }
                )
            }
        ]
    }
}
#endif
